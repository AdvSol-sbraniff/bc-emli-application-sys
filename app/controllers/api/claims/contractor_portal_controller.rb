module Api
  module Claims
    class ContractorPortalController < Api::ApplicationController
      skip_after_action :verify_authorized, only: %i[index]
      skip_after_action :verify_policy_scoped, only: %i[index]

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
    end
  end
end
