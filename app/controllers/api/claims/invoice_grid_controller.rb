# frozen_string_literal: true

module Api
  module Claims
    class InvoiceGridController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      # POC: no auth/policy for now (match your SessionsController approach)
      skip_before_action :authenticate_user!,
                         only: %i[
                           index
                           destroy
                           status_transition
                           reanalyze_advice
                         ]
      skip_before_action :require_claims_admin!,
                         only: %i[
                           index
                           destroy
                           status_transition
                           reanalyze_advice
                         ]
      skip_before_action :require_confirmation,
                         only: %i[
                           index
                           destroy
                           status_transition
                           reanalyze_advice
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          index
                          destroy
                          status_transition
                          reanalyze_advice
                        ]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[
                                index
                                destroy
                                status_transition
                                reanalyze_advice
                              ]

      # GET /api/claims/admin/invoices
      # Query:
      # - session_id=uuid (optional)
      # - invoice_status=string (optional)
      # - q=string (optional, ILIKE across whitelisted columns)
      # - sort=field:dir  (dir = asc|desc)
      # - page=int (default 1)
      # - per=int  (default 25, max 200)
      def index
        rel = ::Claims::InvoiceGrid.all

        # Filters
        if params[:session_id].present?
          rel = rel.where(session_id: params[:session_id].to_s.strip)
        end

        if params[:invoice_status].present?
          invoice_status = params[:invoice_status].to_s.strip
          invoice_statuses =
            invoice_status
              .split(",")
              .map { |status| status.to_s.strip }
              .select(&:present?)
          rel =
            if invoice_status == "failed"
              rel.where(
                invoice_status: %w[
                  upload_failed
                  ocr_failed
                  genai_failed
                  package_needs_correction
                  technical_failure
                ]
              )
            elsif invoice_status == "processing"
              rel.where(
                invoice_status: %w[
                  upload_queued
                  upload_in_progress
                  ocr_queued
                  ocr_in_progress
                  genai_queued
                  genai_in_progress
                ]
              )
            elsif invoice_statuses.many?
              rel.where(invoice_status: invoice_statuses)
            else
              rel.where(invoice_status: invoice_status)
            end
        end

        upgrade_type_keys = parse_upgrade_type_keys(params[:upgrade_type_keys])
        if upgrade_type_keys.any?
          placeholders =
            upgrade_type_keys
              .each_index
              .map { |idx| ":upgrade_type_key_#{idx}" }
              .join(", ")
          binds =
            upgrade_type_keys.each_with_index.to_h do |key, idx|
              ["upgrade_type_key_#{idx}".to_sym, key]
            end

          rel =
            rel.where(
              "COALESCE(latest_detected_upgrade_type_keys, ARRAY[]::varchar[]) && ARRAY[#{placeholders}]::varchar[]",
              binds
            )
        end

        # Text search (safe against missing columns)
        rel = apply_text_search(rel, params[:q])

        # Sort (safe against missing columns)
        sort_field, sort_dir = parse_sort(params[:sort])
        rel = rel.order(Arel.sql("#{sort_field} #{sort_dir}"))

        # Pagination
        page = to_int(params[:page], 1)
        per = clamp(to_int(params[:per], 25), 1, 200)
        offset = (page - 1) * per

        total = rel.count
        rows = rel.offset(offset).limit(per)

        render json: {
                 rows: rows.as_json,
                 meta: {
                   total: total,
                   page: page,
                   per: per,
                   sort: "#{sort_field}:#{sort_dir}",
                   filters: {
                     session_id: params[:session_id].presence,
                     invoice_status: params[:invoice_status].presence,
                     upgrade_type_keys: upgrade_type_keys,
                     q: params[:q].presence
                   }
                 }
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[CLAIMS][INVOICE_GRID] ERROR: #{e.class}: #{e.message}"
        )
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :internal_server_error
      end

      # DELETE /api/claims/admin/invoices/:id
      # Deletes one invoice and all child claim artifacts in FK-safe order.
      def destroy
        deleted =
          ::Claims::Invoices::DestroyPackage.call(invoice_id: params[:id])

        render json: { deleted: true, counts: deleted }, status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[CLAIMS][INVOICE_GRID] destroy failed id=#{params[:id]}: #{e.class}: #{e.message}"
        )
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/claims/admin/invoices/:id/status_transition
      # Body: { transition: "screen_in|approve_pending|mark_ineligible|mark_paid" }
      def status_transition
        transition_key = params[:transition].to_s.strip
        spec = status_transition_spec(transition_key)

        if spec.nil?
          render json: {
                   error: "Unknown transition",
                   transition: transition_key,
                   allowed_transitions: status_transition_specs.keys
                 },
                 status: :unprocessable_entity
          return
        end

        invoice = nil
        previous_status = nil

        ::Claims::Invoice.transaction do
          invoice = ::Claims::Invoice.lock.find(params[:id])
          previous_status = invoice.status.to_s

          unless spec.fetch(:from).include?(previous_status)
            render json: {
                     error: "Transition not allowed from current status",
                     transition: transition_key,
                     current_status: previous_status,
                     allowed_from: spec.fetch(:from),
                     target_status: spec.fetch(:to)
                   },
                   status: :unprocessable_entity
            raise ActiveRecord::Rollback
          end

          if transition_key.in?(%w[screen_in approve_pending])
            gate = ::Claims::RevisionIssues::ApprovalGate.call(invoice: invoice)
            unless gate.allowed
              render json: {
                       error: gate.error,
                       error_code: "revision_review_incomplete",
                       issue_ids: gate.issue_ids,
                       missing_rulecheck_ids: gate.missing_rulecheck_ids
                     },
                     status: :unprocessable_entity
              raise ActiveRecord::Rollback
            end
          end

          latest_version_id =
            invoice
              .invoice_versions
              .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
              .limit(1)
              .pick(:id)
          invoice.set_workflow_status!(
            spec.fetch(:to),
            actor_user_id: current_user&.id,
            invoice_version_id: latest_version_id
          )
        end

        return if performed?

        render json: {
                 ok: true,
                 transition: transition_key,
                 invoice:
                   invoice.as_json(
                     only: %i[
                       id
                       session_id
                       status
                       status_subtype
                       status_updated_at
                       updated_at
                     ]
                   ),
                 previous_status: previous_status,
                 status: invoice.status
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[CLAIMS][INVOICE_GRID] status_transition failed id=#{params[:id]} transition=#{params[:transition]}: #{e.class}: #{e.message}"
        )
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/claims/admin/invoices/:id/reanalyze_advice
      # Clones current evidence into a new invoice version and reruns advice with
      # the current prompts/rules/configuration.
      def reanalyze_advice
        result =
          ::Claims::Ingest::CreateRuleChangeRun.call(invoice_id: params[:id])

        render json: result.to_h, status: :accepted
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[CLAIMS][INVOICE_GRID] reanalyze_advice failed id=#{params[:id]}: #{e.class}: #{e.message}"
        )
        Rails.logger.error(e.backtrace.join("\n"))
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def status_transition_specs
        {
          "screen_in" => {
            from: %w[admin_review_inbox],
            to: "in_review"
          },
          "approve_pending" => {
            from: %w[in_review],
            to: "approved_pending"
          },
          "mark_ineligible" => {
            from: %w[admin_review_inbox in_review],
            to: "ineligible"
          },
          "mark_paid" => {
            from: %w[approved_pending],
            to: "approved_paid"
          }
        }
      end

      def status_transition_spec(key)
        status_transition_specs[key]
      end

      def to_int(v, default)
        Integer(v)
      rescue StandardError
        default
      end

      def clamp(n, lo, hi)
        [[n, lo].max, hi].min
      end

      def apply_text_search(rel, q)
        q = q.to_s.strip
        return rel if q.blank?

        cols = ::Claims::InvoiceGrid.column_names

        # keep this small + useful
        candidates = %w[
          contractor_business_name
          contractor_number
          contractor_email
          submitter_email
          submitter_name
          latest_di_ocr_invoice_id
          latest_di_ocr_vendor_name
          latest_original_filename
        ]

        fields = candidates.select { |c| cols.include?(c) }
        return rel if fields.empty?

        escape_char = "!"
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(q, escape_char)}%"

        clauses =
          fields
            .map { |f| "#{f} ILIKE :p ESCAPE '#{escape_char}'" }
            .join(" OR ")
        rel.where(clauses, p: pattern)
      end

      def parse_sort(raw)
        cols = ::Claims::InvoiceGrid.column_names

        default_field =
          (
            if cols.include?("latest_invoice_version_updated_at")
              "latest_invoice_version_updated_at"
            else
              "invoice_updated_at"
            end
          )
        default_dir = "desc"

        return default_field, default_dir if raw.blank?

        field, dir = raw.to_s.split(":", 2)
        field = field.to_s.strip
        dir = dir.to_s.strip.downcase

        field = default_field unless cols.include?(field)
        dir = %w[asc desc].include?(dir) ? dir : default_dir

        [field, dir]
      end

      def parse_upgrade_type_keys(raw)
        raw
          .to_s
          .split(",")
          .map { |value| value.to_s.strip }
          .reject(&:blank?)
          .uniq
      end
    end
  end
end
