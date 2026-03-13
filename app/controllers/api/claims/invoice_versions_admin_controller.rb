module Api
  module Claims
    class InvoiceVersionsAdminController < Api::ApplicationController
      skip_before_action :authenticate_user!,   only: %i[index_by_invoice show]
      skip_before_action :require_confirmation, only: %i[index_by_invoice show]
      skip_after_action  :verify_authorized,    only: %i[index_by_invoice show]
      skip_forgery_protection                   only: %i[index_by_invoice show]

      def index_by_invoice
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id" if invoice_id.empty?

        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        rows = ::Claims::InvoiceVersion
          .where(invoice_id: invoice_id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .limit(limit)

        invoice = ::Claims::Invoice.find_by(id: invoice_id)

        render json: {
          invoice_id: invoice_id,
          invoice: invoice&.as_json(only: [:id, :status, :created_at, :updated_at, :status_updated_at]),
          invoice_versions: rows.as_json(
            only: [
              :id, :invoice_id, :invoice_versionno,
              :storage_provider, :storage_key, :original_filename,
              :content_type, :byte_size, :sha256,
              :di_ocr_invoice_id, :di_ocr_invoice_date, :di_ocr_vendor_name, :di_ocr_invoice_total,
              :created_at, :updated_at
            ]
          )
        }, status: :ok
      rescue => e
        Rails.logger.error("[claims][invoice_versions_admin][index_by_invoice] ERROR: #{e.class}: #{e.message}")
        render json: { invoice_versions: [], error: e.message }, status: :unprocessable_entity
      end

      def show
        id = params[:id].to_s.strip
        raise "Missing id" if id.empty?

        row = ::Claims::InvoiceVersion.find_by(id: id)
        if row.nil?
          render json: { error: "Not found", id: id }, status: :not_found
          return
        end

        render json: {
          invoice_version: row.as_json
        }, status: :ok
      rescue => e
        Rails.logger.error("[claims][invoice_versions_admin][show] ERROR: #{e.class}: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end
    end
  end
end