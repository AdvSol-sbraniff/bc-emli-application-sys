module Api
  module Claims
    class ContractorPortalController < Api::ApplicationController
      skip_after_action :verify_authorized,
                        only: %i[index revision_requests submit_to_admin]
      skip_after_action :verify_policy_scoped, only: %i[index]
      skip_forgery_protection only: %i[submit_to_admin]

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

        rows =
          invoices.map do |invoice|
            {
              invoice_id: invoice.invoice_id,
              session_id: invoice.session_id,
              status: invoice.invoice_status,
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
                       status: row.revision_request_status,
                       request_text: row.revision_request_text,
                       response_text: row.revision_request_response_text,
                       created_at: row.revision_request_created_at,
                       updated_at: row.revision_request_updated_at,
                       closed_at: row.revision_request_closed_at
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

      # POST /api/claims/contractor/invoices/:invoice_id/submit_to_admin
      def submit_to_admin
        invoice = contractor_invoice!

        unless invoice.status == "genai_complete"
          render json: {
                   error: "Invoice is not ready to submit",
                   status: invoice.status,
                   expected_status: "genai_complete"
                 },
                 status: :unprocessable_entity
          return
        end

        now = Time.current
        invoice.update!(
          status: "admin_review_inbox",
          submitted_at: invoice.submitted_at || now,
          status_updated_at: now,
          updated_at: now
        )

        render json: {
                 ok: true,
                 invoice:
                   invoice.as_json(
                     only: %i[
                       id
                       session_id
                       status
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

      private

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
    end
  end
end
