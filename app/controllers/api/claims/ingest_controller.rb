# app/controllers/api/claims/ingest_controller.rb

# ============================================================
# SECTION 00 — FILE OVERVIEW
# PURPOSE: Claims ingest endpoints
# NOTES:
# - Exposes package/fix upload entry points plus run tracker endpoints.
# - Logs via Rails.logger (docker compose logs -f app)
# ============================================================

# ============================================================
# SECTION 01 — CONTROLLER: Api::Claims::IngestController
# ============================================================

require "json"
require "net/http"
require "securerandom"

module Api
  module Claims
    class IngestController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.test_tools"
      include Api::Claims::Concerns::UploadErrorRendering

      # ============================================================
      # SECTION 01.01 — AUTH / POLICY BYPASSES
      # ============================================================

      skip_before_action :authenticate_user!,
                         only: %i[
                           runs_index
                           steps_index
                           steps_by_session_index
                           run_ocr
                           run_show
                           run_invoices_index
                           steps_by_invoice_index
                           admin_submit_batch
                           upload_fix_package
                         ]
      skip_before_action :require_claims_admin!, only: %i[upload_fix_package]
      before_action :require_upload_fix_actor!, only: %i[upload_fix_package]
      skip_before_action :require_confirmation,
                         only: %i[
                           runs_index
                           steps_index
                           steps_by_session_index
                           run_ocr
                           run_show
                           run_invoices_index
                           steps_by_invoice_index
                           admin_submit_batch
                           upload_fix_package
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          upload_fix_package
                          runs_index
                          steps_index
                          steps_by_session_index
                          run_ocr
                          run_show
                          run_invoices_index
                          steps_by_invoice_index
                          admin_submit_batch
                        ]
      skip_forgery_protection only: %i[
                                upload_fix_package
                                runs_index
                                steps_index
                                steps_by_session_index
                                run_ocr
                                run_show
                                run_invoices_index
                                steps_by_invoice_index
                                admin_submit_batch
                              ]

      # ============================================================
      # SECTION 01.50 — ACTION: runs_index
      # ROUTE: GET /api/claims/ingest/runs
      # PURPOSE:
      # - Returns recent claims.ingest_runs rows for the Run Tracker grid
      # - Optional filter: ?session_id=<uuid>
      # - Optional limit:  ?limit=25 (max 100)
      # ============================================================

      def runs_index
        session_id = params[:session_id].to_s.strip
        session_id = nil if session_id.empty?

        limit = params[:limit].to_i
        limit = 25 if limit <= 0
        limit = 100 if limit > 100

        scope = ::Claims::IngestRun.order(created_at: :desc)
        scope = scope.where(session_id: session_id) if session_id

        rows =
          scope
            .limit(limit)
            .map do |r|
              {
                id: r.id,
                session_id: r.session_id,
                status: r.status,
                total_files: r.total_files,
                completed_files: r.completed_files,
                failed_files: r.failed_files,
                created_at: r.created_at,
                updated_at: r.updated_at,
                completed_at: r.completed_at
              }
            end

        render json: { runs: rows }, status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][runs_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 runs: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 01.60 — ACTION: steps_index
      # ROUTE: GET /api/claims/ingest/runs/:ingest_run_id/steps
      # PURPOSE:
      # - Returns step rows (upload/di/genai) for a single ingest_run
      # ============================================================

      def steps_index
        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id in route." if ingest_run_id.empty?

        limit = params[:limit].to_i
        limit = 50 if limit <= 0
        limit = 200 if limit > 200

        scope =
          ::Claims::IngestStepRun.where(ingest_run_id: ingest_run_id).order(
            created_at: :desc
          )

        rows =
          scope
            .limit(limit)
            .map do |r|
              {
                id: r.id,
                ingest_run_id: r.ingest_run_id,
                invoice_version_id: r.invoice_version_id,
                step_type: r.step_type,
                status: r.status,
                error_text: r.error_text,
                **step_diagnostic_payload(r),
                created_at: r.created_at,
                updated_at: r.updated_at
              }
            end

        render json: { steps: rows }, status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][steps_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 steps: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 01.61 — ACTION: steps_by_session_index
      # ROUTE: GET /api/claims/ingest/steps?session_id=<uuid>
      # PURPOSE:
      # - Returns ingest_step_runs filtered by session_id
      # - Useful for seeing all pipeline runs in one session
      # ============================================================

      def steps_by_session_index
        session_id = params[:session_id].to_s.strip
        raise "Missing session_id in querystring." if session_id.empty?

        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        scope =
          ::Claims::IngestStepRun.where(session_id: session_id).order(
            created_at: :desc
          )

        rows =
          scope
            .limit(limit)
            .map do |r|
              {
                id: r.id,
                ingest_run_id: r.ingest_run_id,
                session_id: r.session_id,
                invoice_version_id: r.invoice_version_id,
                step_type: r.step_type,
                status: r.status,
                error_text: r.error_text,
                **step_diagnostic_payload(r),
                created_at: r.created_at,
                updated_at: r.updated_at
              }
            end

        render json: { steps: rows }, status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][steps_by_session_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 steps: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      def upload_fix_package
        invoice_id = params[:invoice_id].to_s
        files =
          Array(params[:"files[]"]) + Array(params[:files]) +
            Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:file])
        files = files.flatten.compact

        result =
          ::Claims::Ingest::UploadFixPackage.call(
            invoice_id: invoice_id,
            clone_invoice_version_id: params[:clone_invoice_version_id],
            clone_supporting_document_ids:
              Array(params[:"clone_supporting_document_ids[]"]) +
                Array(params[:clone_supporting_document_ids]),
            clone_all_current_supporting_documents:
              ActiveModel::Type::Boolean.new.cast(
                params[:clone_all_current_supporting_documents]
              ),
            files: files
          )

        response_status =
          if result.ok
            :accepted
          elsif result.failure_category == "technical_failure"
            :internal_server_error
          else
            :unprocessable_entity
          end
        render json: result.to_h, status: response_status
      rescue StandardError => e
        render_claims_upload_error(e, log_prefix: "ingest][upload_fix_package")
      end

      # ============================================================
      # SECTION 02.10 — ACTION: run_ocr
      # ROUTE: POST /api/claims/ingest/run_ocr
      # BODY: { invoice_version_id: "uuid", ingest_run_id: "uuid" }
      # PURPOSE:
      # - enqueue Sidekiq job that calls Node /inv/ocr
      # - creates ingest_step_runs row inside the job
      # ============================================================
      def run_ocr
        invoice_version_id = params[:invoice_version_id].to_s.strip
        raise "Missing invoice_version_id" if invoice_version_id.empty?

        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id" if ingest_run_id.empty?

        ::Claims::IngestRun.find(ingest_run_id)

        jid =
          ::Claims::RunOcrJob.perform_async(invoice_version_id, ingest_run_id)

        render json: {
                 ok: true,
                 enqueued: true,
                 job_id: jid,
                 invoice_version_id: invoice_version_id,
                 ingest_run_id: ingest_run_id
               },
               status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][run_ocr] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.30 — ACTION: run_show
      # ROUTE: GET /api/claims/ingest/runs/:ingest_run_id
      # PURPOSE:
      # - Returns ingest run header details for run context strip
      # ============================================================
      def run_show
        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id." if ingest_run_id.empty?

        run = ::Claims::IngestRun.find(ingest_run_id)
        diagnostics =
          ::Claims::Ingest::AttemptDiagnostics.call(
            steps:
              ::Claims::IngestStepRun.where(ingest_run_id: run.id).order(
                :created_at,
                :id
              ),
            run_status: run.status
          )
        terminal_failure =
          terminal_failure_payload(diagnostics.terminal_failure_step)
        render json: {
                 id: run.id,
                 run_kind: run.run_kind,
                 session_id: run.session_id,
                 invoice_id: run.invoice_id,
                 resolved_invoice_version_id: run.resolved_invoice_version_id,
                 status: run.status,
                 pipeline_error_code: run.pipeline_error_code,
                 pipeline_error_description: run.pipeline_error_description,
                 failure_category: run.failure_category,
                 failure_code: run.failure_code,
                 attempt_summary: diagnostics.summary,
                 terminal_failure: terminal_failure,
                 primary_failure: terminal_failure,
                 total_files: run.total_files,
                 completed_files: run.completed_files,
                 failed_files: run.failed_files,
                 created_at: run.created_at,
                 updated_at: run.updated_at,
                 completed_at: run.completed_at
               },
               status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][run_show] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.40 — ACTION: run_invoices_index
      # ROUTE: GET /api/claims/ingest/runs/:ingest_run_id/invoices
      # PURPOSE:
      # - Returns one row per invoice version touched in the ingest run
      # ============================================================
      def run_invoices_index
        ingest_run_id = params[:ingest_run_id].to_s.strip
        raise "Missing ingest_run_id." if ingest_run_id.empty?

        rows = ingest_run_invoice_rows(ingest_run_id: ingest_run_id)

        render json: { rows: rows }, status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][run_invoices_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.50 — ACTION: steps_by_invoice_index
      # ROUTE: GET /api/claims/ingest/invoices/:invoice_id/steps
      # PURPOSE:
      # - Returns all step history for an invoice (optional run filter)
      # ============================================================
      def steps_by_invoice_index
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id." if invoice_id.empty?

        ingest_run_id = params[:ingest_run_id].to_s.strip
        ingest_run_id = nil if ingest_run_id.empty?

        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        rows =
          ingest_invoice_step_rows(
            invoice_id: invoice_id,
            ingest_run_id: ingest_run_id,
            limit: limit
          )
        classifier_results =
          ingest_invoice_classifier_results(
            invoice_id: invoice_id,
            ingest_run_id: ingest_run_id
          )

        render json: {
                 rows: rows,
                 classifier_results: classifier_results
               },
               status: :ok
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][steps_by_invoice_index] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # ============================================================
      # SECTION 02.60 — ACTION: admin_submit_batch
      # ROUTE: POST /api/claims/ingest/admin_submit_batch
      # PURPOSE:
      # - Simulates contractor draft creation for multiple files:
      #   create session, upload each file, enqueue OCR->GenAI chain.
      # - Does not submit to admin; submitter_id/submitted_at stay blank.
      # ============================================================
      def admin_submit_batch
        contractor_id = params[:contractor_id].to_s.strip

        if contractor_id.empty?
          raise ::Claims::Ingest::UploadErrors::ValidationError.new(
                  "Select a contractor before uploading files."
                )
        end

        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        files = files.flatten.compact
        if files.empty?
          raise ::Claims::Ingest::UploadErrors::ValidationError.new(
                  "Select at least one invoice or supporting document to upload."
                )
        end

        result =
          ::Claims::Ingest::CreateDraftBatch.call(
            contractor_id: contractor_id,
            files: files,
            log_prefix: "admin_submit_batch"
          )

        render json: result, status: :ok
      rescue StandardError => e
        render_claims_upload_error(e, log_prefix: "ingest][admin_submit_batch")
      end

      private

      def require_upload_fix_actor!
        return if ::Claims::Rbac.allowed?(current_user, "claims.test_tools")

        unless ::Claims::Rbac.allowed?(current_user, "claims.contractor_portal")
          render json: {
                   error: "Invoice upload-fix access denied."
                 },
                 status: :forbidden
          return
        end

        invoice = ::Claims::Invoice.find_by(id: params[:invoice_id].to_s)
        allowed =
          invoice.present? &&
            ::Contractor
              .left_joins(:contractor_employees)
              .where(id: invoice.contractor_id)
              .where(
                "contractors.contact_id = :user_id OR contractor_employees.employee_id = :user_id",
                user_id: current_user&.id
              )
              .exists?

        return if allowed

        render json: {
                 error: "Invoice upload-fix access denied."
               },
               status: :forbidden
      end

      def ingest_run_invoice_rows(ingest_run_id:)
        run = ::Claims::IngestRun.includes(:invoice).find(ingest_run_id)
        invoice = run.invoice
        return [] unless invoice

        invoice_version =
          ::Claims::InvoiceVersion.find_by(id: run.resolved_invoice_version_id)
        invoice_version ||=
          ::Claims::InvoiceVersion
            .where(invoice_id: invoice.id)
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .first

        [
          {
            invoice_id: invoice.id,
            invoice_status: invoice.status,
            invoice_status_updated_at: invoice.status_updated_at,
            invoice_version_id: invoice_version&.id,
            invoice_versionno: invoice_version&.invoice_versionno,
            original_filename: invoice_version&.original_filename,
            storage_key: invoice_version&.storage_key,
            created_at: invoice.created_at,
            updated_at: invoice.updated_at
          }
        ]
      end

      def ingest_invoice_step_rows(invoice_id:, ingest_run_id:, limit:)
        invoice = ::Claims::Invoice.find(invoice_id)
        document_scope =
          ::Claims::IngestDocument.where(
            "invoice_id = :invoice_id OR resolved_invoice_id = :invoice_id",
            invoice_id: invoice.id
          )
        if ingest_run_id
          document_scope = document_scope.where(ingest_run_id: ingest_run_id)
        end
        documents = document_scope.order(created_at: :asc).to_a
        documents_by_id = documents.index_by(&:id)

        document_steps =
          if documents_by_id.empty?
            []
          else
            scope =
              ::Claims::IngestStepRun.where(
                ingest_document_id: documents_by_id.keys
              )
            scope = scope.where(ingest_run_id: ingest_run_id) if ingest_run_id
            scope.to_a
          end

        invoice_step_scope =
          ::Claims::IngestStepRun
            .joins(
              "JOIN claims.invoice_versions iv ON iv.id = claims.ingest_step_runs.invoice_version_id"
            )
            .where("iv.invoice_id = ?", invoice.id)
            .where(supporting_document_type_id: nil)
        if ingest_run_id
          invoice_step_scope =
            invoice_step_scope.where(ingest_run_id: ingest_run_id)
        end
        invoice_steps = invoice_step_scope.to_a
        invoice_versions_by_id =
          ::Claims::InvoiceVersion.where(invoice_id: invoice.id).index_by(&:id)

        supporting_documents =
          ::Claims::SupportingDocument
            .where(invoice_version_id: invoice_versions_by_id.keys)
            .includes(:supporting_document_type)
            .where.not(supporting_document_type_id: nil)
            .order(:created_at, :id)
            .to_a
        supporting_documents_by_type_id =
          supporting_documents.group_by do |doc|
            doc.supporting_document_type_id.to_s
          end
        supporting_documents_by_version_and_type_id =
          supporting_documents.group_by do |doc|
            [doc.invoice_version_id.to_s, doc.supporting_document_type_id.to_s]
          end
        type_ids = supporting_documents_by_type_id.keys
        type_steps =
          if type_ids.empty?
            []
          else
            scope =
              ::Claims::IngestStepRun
                .where(
                  invoice_version_id: invoice_versions_by_id.keys,
                  supporting_document_type_id: type_ids,
                  step_type: %w[
                    extract_supporting_document
                    extract_supporting_document
                  ]
                )
                .where.not(supporting_document_type_id: nil)
            scope = scope.where(ingest_run_id: ingest_run_id) if ingest_run_id
            scope.to_a
          end

        run_ids =
          (
            documents.map(&:ingest_run_id) +
              invoice_steps.map(&:ingest_run_id) +
              type_steps.map(&:ingest_run_id)
          ).compact.uniq
        run_level_steps =
          if run_ids.empty?
            []
          else
            scope =
              ::Claims::IngestStepRun.where(ingest_run_id: run_ids).where(
                ingest_document_id: nil,
                invoice_version_id: nil,
                supporting_document_type_id: nil
              )
            scope = scope.where(ingest_run_id: ingest_run_id) if ingest_run_id
            scope.to_a
          end

        rows =
          document_steps.map do |step|
            document = documents_by_id[step.ingest_document_id]
            {
              id: step.id,
              ingest_run_id: step.ingest_run_id,
              session_id: step.session_id,
              invoice_id: invoice.id,
              ingest_document_id: step.ingest_document_id,
              invoice_version_id: document&.resolved_invoice_version_id,
              invoice_versionno: nil,
              original_filename: document&.original_filename,
              document_kind: document&.document_kind,
              invoice_status: invoice.status,
              step_type: step.step_type,
              status: step.status,
              state_label: nil,
              step_note: nil,
              error_text: step.error_text,
              **step_diagnostic_payload(step),
              created_at: step.created_at,
              updated_at: step.updated_at
            }
          end

        rows.concat(
          run_level_steps.map do |step|
            {
              id: step.id,
              ingest_run_id: step.ingest_run_id,
              session_id: step.session_id,
              invoice_id: invoice.id,
              ingest_document_id: nil,
              invoice_version_id: nil,
              invoice_versionno: nil,
              original_filename: nil,
              document_kind: "package",
              invoice_status: invoice.status,
              step_type: step.step_type,
              status: step.status,
              state_label: nil,
              step_note: nil,
              error_text: step.error_text,
              **step_diagnostic_payload(step),
              created_at: step.created_at,
              updated_at: step.updated_at
            }
          end
        )

        rows.concat(
          type_steps.map do |step|
            documents_for_type =
              supporting_documents_by_version_and_type_id[
                [
                  step.invoice_version_id.to_s,
                  step.supporting_document_type_id.to_s
                ]
              ] ||
                supporting_documents_by_type_id[
                  step.supporting_document_type_id.to_s
                ] || []
            invoice_version = invoice_versions_by_id[step.invoice_version_id]
            {
              id: step.id,
              ingest_run_id: step.ingest_run_id,
              session_id: step.session_id,
              invoice_id: invoice.id,
              ingest_document_id: nil,
              invoice_version_id: step.invoice_version_id,
              invoice_versionno: invoice_version&.invoice_versionno,
              original_filename:
                supporting_document_type_step_label(documents_for_type),
              document_kind: "supporting_document_type",
              invoice_status: invoice.status,
              step_type: step.step_type,
              status: step.status,
              state_label: nil,
              step_note: nil,
              error_text: step.error_text,
              **step_diagnostic_payload(step),
              created_at: step.created_at,
              updated_at: step.updated_at
            }
          end
        )

        rows.concat(
          invoice_steps.map do |step|
            invoice_version = invoice_versions_by_id[step.invoice_version_id]
            {
              id: step.id,
              ingest_run_id: step.ingest_run_id,
              session_id: step.session_id,
              invoice_id: invoice.id,
              ingest_document_id: nil,
              invoice_version_id: step.invoice_version_id,
              invoice_versionno: invoice_version&.invoice_versionno,
              original_filename: invoice_version&.original_filename,
              document_kind: "invoice",
              invoice_status: invoice.status,
              step_type: step.step_type,
              status: step.status,
              state_label: nil,
              step_note: nil,
              error_text: step.error_text,
              **step_diagnostic_payload(step),
              created_at: step.created_at,
              updated_at: step.updated_at
            }
          end
        )

        rows
          .sort_by { |row| row[:created_at] || Time.at(0) }
          .reverse
          .first(limit)
      end

      def supporting_document_type_step_label(documents)
        documents = Array(documents)
        type = documents.first&.supporting_document_type
        type_label = type&.description.presence || type&.type_key.to_s.humanize
        filenames =
          documents
            .sort_by { |doc| [doc.created_at || Time.at(0), doc.id] }
            .filter_map { |doc| doc.original_filename.to_s.presence }

        return type_label if filenames.empty?
        return filenames.join(", ") if type_label.blank?

        "#{type_label}: #{filenames.join(", ")}"
      end

      def ingest_invoice_classifier_results(invoice_id:, ingest_run_id:)
        invoice_version_ids =
          classifier_invoice_version_ids(
            invoice_id: invoice_id,
            ingest_run_id: ingest_run_id
          )

        if invoice_version_ids.any?
          scope =
            ::Claims::InvoiceVersionUpgradeType
              .joins(
                "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
              )
              .select(
                "claims.invoice_version_upgrade_types.*",
                "iut.upgrade_type_key AS upgrade_type_key",
                "iut.description AS upgrade_type_description"
              )
              .where(invoice_version_id: invoice_version_ids)

          rows =
            scope
              .order(updated_at: :desc)
              .map do |row|
                {
                  id: row.id,
                  invoice_version_id: row.invoice_version_id,
                  invoice_upgrade_type_id: row.invoice_upgrade_type_id,
                  upgrade_type_key: row.read_attribute("upgrade_type_key"),
                  upgrade_type_description:
                    row.read_attribute("upgrade_type_description"),
                  confidence: row.confidence,
                  evidence_text: row.evidence_text,
                  classifier_notes: row.classification_explanation,
                  updated_at: row.updated_at
                }
              end
          return rows if rows.any?
        end

        []
      end

      def classifier_invoice_version_ids(invoice_id:, ingest_run_id:)
        invoice_id = invoice_id.to_s.strip
        ingest_run_id = ingest_run_id.to_s.strip
        ingest_run_id = nil if ingest_run_id.empty?

        if ingest_run_id
          step_invoice_version_ids =
            ::Claims::IngestStepRun
              .joins(
                "JOIN claims.invoice_versions iv ON iv.id = claims.ingest_step_runs.invoice_version_id"
              )
              .where(ingest_run_id: ingest_run_id)
              .where("iv.invoice_id = ?", invoice_id)
              .where.not(invoice_version_id: nil)
              .distinct
              .pluck(:invoice_version_id)

          document_invoice_version_ids =
            ::Claims::IngestDocument
              .where(ingest_run_id: ingest_run_id)
              .where(
                "invoice_id = :invoice_id OR resolved_invoice_id = :invoice_id",
                invoice_id: invoice_id
              )
              .where.not(resolved_invoice_version_id: nil)
              .distinct
              .pluck(:resolved_invoice_version_id)

          run_invoice_version_ids =
            (
              step_invoice_version_ids + document_invoice_version_ids
            ).compact.uniq

          return run_invoice_version_ids if run_invoice_version_ids.any?
        end

        ::Claims::InvoiceVersion
          .where(invoice_id: invoice_id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .limit(1)
          .pluck(:id)
      end

      def file_safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)

        obj.public_send(method_name)
      rescue StandardError
        nil
      end

      def ingest_node_upload_pdf!(session_id:, invoice_version_id:, file:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        base = base.sub(%r{/\z}, "")
        uri = URI("#{base}/inv/upload-pdf")

        req = Net::HTTP::Post.new(uri)

        io = File.open(file.path, "rb")
        filename =
          file_safe_call(file, :original_filename) || File.basename(file.path)
        content_type = file_safe_call(file, :content_type) || "application/pdf"

        form = [
          ["sessionId", session_id.to_s],
          ["invoiceVersionId", invoice_version_id.to_s],
          ["file", io, { filename: filename, content_type: content_type }]
        ]

        req.set_form(form, "multipart/form-data")

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node upload failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      ensure
        io&.close
      end

      def ingest_extract_storage_key(node_resp)
        node_resp.fetch("storage_key")
      end

      def terminal_failure_payload(step)
        return if step.nil?

        {
          step_id: step.id,
          step_type: step.step_type,
          error_text: step.error_text,
          **step_diagnostic_payload(step)
        }
      end

      def step_diagnostic_payload(step)
        {
          failure_category: step.failure_category,
          failure_code: step.failure_code,
          error_code: step.error_code,
          error_category: step.error_category,
          error_phase: step.error_phase,
          retryable: step.retryable,
          diagnostic_id: step.diagnostic_id,
          provider_status: step.provider_status,
          provider_code: step.provider_code,
          provider_attempt_count: step.provider_attempt_count
        }
      end
    end
  end
end
