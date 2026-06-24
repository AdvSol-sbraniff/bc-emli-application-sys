module Api
  module Claims
    class ContractorPortalController < Api::ApplicationController
      skip_after_action :verify_authorized,
                        only: %i[
                          index
                          upload_batch
                          revision_requests
                          create_revision_request
                          update_revision_request
                          submit_to_admin
                          ingest_run_show
                          ingest_run_invoices
                          ingest_invoice_steps
                        ]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[
                                upload_batch
                                create_revision_request
                                update_revision_request
                                submit_to_admin
                              ]

      # GET /api/claims/contractor/invoices
      def index
        contractor = current_contractor
        if contractor.nil?
          render json: {
                   error: "Contractor not found for current user."
                 },
                 status: :not_found
          return
        end

        invoices =
          ::Claims::InvoiceGrid.where(contractor_id: contractor.id).order(
            Arel.sql(
              "COALESCE(invoice_status_updated_at, latest_invoice_version_updated_at, invoice_updated_at, invoice_created_at) DESC, invoice_created_at DESC"
            )
          )

        latest_version_ids =
          invoices
            .map do |invoice|
              if invoice.respond_to?(:latest_invoice_version_id)
                invoice.latest_invoice_version_id
              end
            end
            .compact

        customer_by_version =
          ::Claims::InvoiceVersion
            .where(id: latest_version_ids)
            .pluck(:id, :di_ocr_customer_name)
            .to_h

        rows =
          invoices.map do |invoice|
            {
              invoice_id: invoice.invoice_id,
              session_id: invoice.session_id,
              status: invoice.invoice_status,
              status_subtype:
                (
                  if invoice.respond_to?(:invoice_status_subtype)
                    invoice.invoice_status_subtype
                  end
                ),
              status_updated_at: invoice.invoice_status_updated_at,
              system_help_notes: invoice.system_help_notes,
              invoice_created_at: invoice.invoice_created_at,
              invoice_updated_at: invoice.invoice_updated_at,
              invoice_submitted_at:
                (
                  if invoice.respond_to?(:invoice_submitted_at)
                    invoice.invoice_submitted_at
                  else
                    nil
                  end
                ),
              submitted:
                invoice.respond_to?(:invoice_submitted_at) &&
                  invoice.invoice_submitted_at.present?,
              latest_invoice_version_id: invoice.latest_invoice_version_id,
              latest_invoice_versionno: invoice.latest_invoice_versionno,
              latest_original_filename: invoice.latest_original_filename,
              latest_invoice_version_updated_at:
                invoice.latest_invoice_version_updated_at,
              latest_di_ocr_invoice_id: invoice.latest_di_ocr_invoice_id,
              latest_di_ocr_invoice_date: invoice.latest_di_ocr_invoice_date,
              latest_di_ocr_invoice_total: invoice.latest_di_ocr_invoice_total,
              latest_di_ocr_vendor_name: invoice.latest_di_ocr_vendor_name,
              latest_di_ocr_customer_name:
                customer_by_version[invoice.latest_invoice_version_id],
              latest_detected_upgrade_type_keys:
                (
                  if invoice.respond_to?(:latest_detected_upgrade_type_keys)
                    invoice.latest_detected_upgrade_type_keys
                  else
                    []
                  end
                )
            }
          end

        render json: {
                 contractor: {
                   id: contractor.id,
                   business_name: contractor.business_name,
                   number: contractor.number
                 },
                 rows: rows
               },
               status: :ok
      end

      # POST /api/claims/contractor/invoices/upload_batch
      def upload_batch
        contractor = current_contractor
        if contractor.nil?
          render json: {
                   error: "Contractor not found for current user."
                 },
                 status: :not_found
          return
        end

        files =
          Array(params[:"pdfs[]"]) + Array(params[:pdfs]) +
            Array(params[:files]) + Array(params[:file])

        result =
          ::Claims::Ingest::CreateDraftBatch.call(
            contractor_id: contractor.id,
            files: files,
            log_prefix: "contractor_upload_batch",
            cleanup_failed_invoice_artifacts: true
          )

        render json: result, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][contractor_portal][upload_batch] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 ok: false,
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # GET /api/claims/contractor/invoices/:invoice_id/revision_requests
      def revision_requests
        invoice = contractor_invoice!

        rows =
          ::Claims::RevisionRequestGrid.where(invoice_id: invoice.id).order(
            Arel.sql(
              "claims.v_revision_request_grid.invoice_versionno DESC NULLS LAST, claims.v_revision_request_grid.revision_request_seqno ASC"
            )
          )

        render json: {
                 rows:
                   rows.map do |row|
                     {
                       id: row.revision_request_id,
                       invoice_version_id: row.invoice_version_id,
                       invoice_versionno: row.invoice_versionno,
                       revreq_seqno: row.revision_request_seqno,
                       message_type: row.revision_request_message_type,
                       request_text: row.revision_request_text,
                       created_at: row.revision_request_created_at,
                       updated_at: row.revision_request_updated_at
                     }
                   end
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][contractor_portal][revision_requests] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/claims/contractor/invoices/:invoice_id/revision_requests
      def create_revision_request
        invoice = contractor_invoice!
        invoice_version = latest_invoice_version!(invoice)
        text = params[:request_text].to_s.strip

        if text.empty?
          render json: {
                   error: "Message text is required."
                 },
                 status: :unprocessable_entity
          return
        end

        record =
          ::Claims::AdminRevisionRequest.create!(
            invoice_id: invoice.id,
            invoice_version_id: invoice_version.id,
            requester_id: current_user.id,
            message_type: "contractor_note",
            request_text: text
          )

        render json: serialize_revision_request(record), status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue => e
        Rails.logger.error(
          "[claims][contractor_portal][create_revision_request] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # PATCH /api/claims/contractor/invoices/:invoice_id/revision_requests/:id
      def update_revision_request
        invoice = contractor_invoice!
        record =
          ::Claims::AdminRevisionRequest
            .includes(:invoice)
            .where(
              id: params[:id].to_s,
              message_type: "contractor_note",
              requester_id: current_user.id
            )
            .first!
        unless record.invoice_id == invoice.id
          raise ActiveRecord::RecordNotFound
        end

        text = params[:request_text].to_s.strip
        if text.empty?
          render json: {
                   error: "Message text is required."
                 },
                 status: :unprocessable_entity
          return
        end

        record.update!(request_text: text)

        render json: serialize_revision_request(record), status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Message not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: {
                 error: e.record.errors.full_messages.join(", ")
               },
               status: :unprocessable_entity
      rescue => e
        Rails.logger.error(
          "[claims][contractor_portal][update_revision_request] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # POST /api/claims/contractor/invoices/:invoice_id/submit_to_admin
      def submit_to_admin
        invoice = contractor_invoice!

        allowed_submit_statuses = %w[genai_complete contractor_revision_inbox]
        unless allowed_submit_statuses.include?(invoice.status)
          render json: {
                   error: "Invoice is not ready to submit",
                   status: invoice.status,
                   expected_statuses: allowed_submit_statuses
                 },
                 status: :unprocessable_entity
          return
        end

        invoice.set_workflow_status!(
          "admin_review_inbox",
          submitter_id: invoice.submitter_id || current_user.id,
          submitted_at: invoice.submitted_at || Time.current
        )

        render json: {
                 ok: true,
                 invoice:
                   invoice.as_json(
                     only: %i[
                       id
                       session_id
                       status
                       status_subtype
                       submitted_at
                       status_updated_at
                       updated_at
                     ]
                   )
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Invoice not found" }, status: :not_found
      rescue => e
        Rails.logger.error(
          "[claims][contractor_portal][submit_to_admin] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/contractor/ingest/runs/:ingest_run_id
      def ingest_run_show
        run = contractor_ingest_run!
        failure_payload = contractor_ingest_run_failure_payload(run)

        render json: {
                 id: run.id,
                 session_id: run.session_id,
                 resolved_invoice_version_id: run.resolved_invoice_version_id,
                 status: run.status,
                 pipeline_error_code: run.pipeline_error_code,
                 pipeline_error_description: run.pipeline_error_description,
                 failure_status: failure_payload[:failure_status],
                 failure_status_subtype:
                   failure_payload[:failure_status_subtype],
                 failure_message: failure_payload[:failure_message],
                 retry_guidance: failure_payload[:retry_guidance],
                 total_files: run.total_files,
                 completed_files: run.completed_files,
                 failed_files: run.failed_files,
                 messages: run.messages,
                 created_at: run.created_at,
                 updated_at: run.updated_at,
                 completed_at: run.completed_at
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Ingest run not found" }, status: :not_found
      rescue => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/contractor/ingest/runs/:ingest_run_id/invoices
      def ingest_run_invoices
        run = contractor_ingest_run!
        rows =
          contractor_ingest_run_invoice_rows(
            ingest_run_id: run.id,
            contractor_id: current_contractor.id
          )
        failure_payload = contractor_ingest_run_failure_payload(run)

        render json: {
                 rows: rows,
                 failure_status: failure_payload[:failure_status],
                 failure_status_subtype:
                   failure_payload[:failure_status_subtype],
                 failure_message: failure_payload[:failure_message],
                 retry_guidance: failure_payload[:retry_guidance]
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 rows: [],
                 error: "Ingest run not found"
               },
               status: :not_found
      rescue => e
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # GET /api/claims/contractor/ingest/invoices/:invoice_id/steps
      def ingest_invoice_steps
        invoice = contractor_invoice!
        ingest_run_id = params[:ingest_run_id].to_s.strip.presence
        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        rows =
          contractor_ingest_invoice_step_rows(
            invoice_id: invoice.id,
            ingest_run_id: ingest_run_id,
            limit: limit
          )
        classifier_results =
          contractor_ingest_invoice_classifier_results(
            invoice_id: invoice.id,
            ingest_run_id: ingest_run_id
          )

        render json: {
                 rows: rows,
                 classifier_results: classifier_results
               },
               status: :ok
      rescue ActiveRecord::RecordNotFound
        render json: {
                 rows: [],
                 error: "Invoice not found"
               },
               status: :not_found
      rescue => e
        render json: {
                 rows: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      private

      def contractor_ingest_run_invoice_rows(ingest_run_id:, contractor_id:)
        rows_by_invoice_id = {}

        documents =
          ::Claims::IngestDocument
            .where(ingest_run_id: ingest_run_id, contractor_id: contractor_id)
            .where.not(resolved_invoice_id: nil)
            .order(created_at: :asc)
            .to_a

        documents
          .group_by(&:resolved_invoice_id)
          .each do |invoice_id, docs|
            invoice =
              ::Claims::Invoice.find_by(
                id: invoice_id,
                contractor_id: contractor_id
              )
            next if invoice.nil?

            primary_doc =
              docs.find { |doc| doc.document_kind == "invoice" } || docs.first
            invoice_version =
              ::Claims::InvoiceVersion.find_by(
                id:
                  primary_doc&.resolved_invoice_version_id ||
                    docs.map(&:resolved_invoice_version_id).compact.first
              )

            rows_by_invoice_id[invoice.id] = {
              invoice_id: invoice.id,
              invoice_status: invoice.status,
              invoice_status_subtype: invoice.status_subtype,
              invoice_status_updated_at: invoice.status_updated_at,
              invoice_version_id: invoice_version&.id,
              invoice_versionno: invoice_version&.invoice_versionno,
              original_filename:
                primary_doc&.original_filename ||
                  invoice_version&.original_filename,
              created_at: invoice.created_at,
              updated_at: invoice.updated_at
            }.merge(invoice_status_subtype_copy(invoice))
          end

        invoice_version_ids =
          ::Claims::IngestStepRun
            .where(ingest_run_id: ingest_run_id)
            .where.not(invoice_version_id: nil)
            .distinct
            .pluck(:invoice_version_id)

        ::Claims::InvoiceVersion
          .joins(:invoice)
          .where(id: invoice_version_ids)
          .where("claims.invoices.contractor_id = ?", contractor_id)
          .order(created_at: :asc)
          .each do |invoice_version|
            invoice = invoice_version.invoice
            rows_by_invoice_id[invoice.id] ||= {
              invoice_id: invoice.id,
              invoice_status: invoice.status,
              invoice_status_subtype: invoice.status_subtype,
              invoice_status_updated_at: invoice.status_updated_at,
              invoice_version_id: invoice_version.id,
              invoice_versionno: invoice_version.invoice_versionno,
              original_filename: invoice_version.original_filename,
              created_at: invoice.created_at,
              updated_at: invoice.updated_at
            }.merge(invoice_status_subtype_copy(invoice))
          end

        rows_by_invoice_id.values.sort_by do |row|
          row[:created_at] || Time.at(0)
        end
      end

      def invoice_status_subtype_copy(invoice)
        ::Claims::Invoices::StatusSubtypes.invoice_row_copy(
          invoice.status,
          invoice.status_subtype
        )
      end

      def contractor_ingest_invoice_step_rows(
        invoice_id:,
        ingest_run_id:,
        limit:
      )
        invoice = contractor_invoice!
        document_scope =
          ::Claims::IngestDocument.where(resolved_invoice_id: invoice.id)
        document_scope =
          document_scope.where(ingest_run_id: ingest_run_id) if ingest_run_id
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
        invoice_step_scope =
          invoice_step_scope.where(
            ingest_run_id: ingest_run_id
          ) if ingest_run_id
        invoice_steps = invoice_step_scope.to_a
        invoice_versions_by_id =
          ::Claims::InvoiceVersion.where(
            id: invoice_steps.map(&:invoice_version_id).compact.uniq
          ).index_by(&:id)

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
              invoice_status_subtype: invoice.status_subtype,
              step_type: step.step_type,
              status: step.status,
              error_text: step.error_text,
              created_at: step.created_at,
              updated_at: step.updated_at
            }
          end

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
              invoice_status_subtype: invoice.status_subtype,
              step_type: step.step_type,
              status: step.status,
              error_text: step.error_text,
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

      def contractor_ingest_invoice_classifier_results(
        invoice_id:,
        ingest_run_id:
      )
        invoice_version_ids =
          ::Claims::InvoiceVersion.where(invoice_id: invoice_id).pluck(:id)

        if invoice_version_ids.any?
          rows =
            ::Claims::InvoiceVersionUpgradeType
              .joins(
                "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
              )
              .select(
                "claims.invoice_version_upgrade_types.*",
                "iut.upgrade_type_key AS upgrade_type_key",
                "iut.description AS upgrade_type_description"
              )
              .where(
                invoice_version_id: invoice_version_ids,
                source_engine: "classifier"
              )
              .order(updated_at: :desc)
              .map do |row|
                {
                  id: row.id,
                  invoice_version_id: row.invoice_version_id,
                  invoice_upgrade_type_id: row.invoice_upgrade_type_id,
                  upgrade_type_key: row.read_attribute("upgrade_type_key"),
                  upgrade_type_description:
                    row.read_attribute("upgrade_type_description"),
                  call_status: row.call_status,
                  confidence: row.confidence,
                  evidence_text: row.raw_json&.dig("evidence_text"),
                  classifier_notes:
                    row.raw_json&.dig("classification_explanation"),
                  updated_at: row.updated_at
                }
              end
          return rows if rows.any?
        end

        []
      end

      def serialize_revision_request(record)
        {
          id: record.id,
          invoice_id: record.invoice_id,
          invoice_version_id: record.invoice_version_id,
          invoice_versionno: record.invoice_version&.invoice_versionno,
          revreq_seqno: record.revreq_seqno,
          message_type: record.message_type,
          request_text: record.request_text,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      end

      def latest_invoice_version!(invoice)
        ::Claims::InvoiceVersion
          .where(invoice_id: invoice.id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .first!
      end

      def current_contractor
        ::Contractor
          .left_joins(:contractor_employees)
          .where(
            "contractors.contact_id = :user_id OR contractor_employees.employee_id = :user_id",
            user_id: current_user.id
          )
          .distinct
          .first
      end

      def contractor_invoice!
        contractor = current_contractor
        raise ActiveRecord::RecordNotFound if contractor.nil?

        ::Claims::Invoice.find_by!(
          id: params[:invoice_id].to_s.strip,
          contractor_id: contractor.id
        )
      end

      def contractor_ingest_run!
        contractor = current_contractor
        raise ActiveRecord::RecordNotFound if contractor.nil?

        run = ::Claims::IngestRun.find(params[:ingest_run_id].to_s.strip)
        if run.contractor_id.present? &&
             run.contractor_id.to_s == contractor.id.to_s
          return run
        end

        has_owned_invoice =
          ::Claims::Invoice.where(
            session_id: run.session_id,
            contractor_id: contractor.id
          ).exists?

        raise ActiveRecord::RecordNotFound unless has_owned_invoice

        run
      end

      def contractor_ingest_run_failure_payload(run)
        messages = parse_messages(run.messages)
        message_payload =
          messages.reverse.find do |message|
            message["contractor_message"].present?
          end

        if message_payload
          return(
            {
              failure_status: message_payload["status"],
              failure_status_subtype:
                message_payload["status_subtype"] || message_payload["code"],
              failure_message: message_payload["contractor_message"],
              retry_guidance: nil
            }
          )
        end

        invoice =
          ::Claims::Invoice
            .where(
              session_id: run.session_id,
              contractor_id: run.contractor_id,
              status: %w[package_needs_correction technical_failure]
            )
            .order(updated_at: :desc)
            .first

        return {} unless invoice

        {
          failure_status: invoice.status,
          failure_status_subtype: invoice.status_subtype,
          failure_message:
            ::Claims::Invoices::StatusSubtypes.contractor_failure_message(
              invoice.status,
              invoice.status_subtype
            ),
          retry_guidance:
            ::Claims::Invoices::StatusSubtypes.retry_guidance(
              invoice.status,
              invoice.status_subtype
            )
        }
      end

      def parse_messages(messages)
        return messages if messages.is_a?(Array)

        JSON.parse(messages.to_s)
      rescue JSON::ParserError, TypeError
        []
      end
    end
  end
end
