require "net/http"
require "json"

module Api
  module Claims
    class InvoiceVersionsAdminController < Api::ApplicationController
      skip_before_action :authenticate_user!,   only: %i[index_by_invoice show read_by_version read_genai_by_version pdf_url_by_version]
      skip_before_action :require_confirmation, only: %i[index_by_invoice show read_by_version read_genai_by_version pdf_url_by_version]
      skip_after_action  :verify_authorized,    only: %i[index_by_invoice show read_by_version read_genai_by_version pdf_url_by_version]
      skip_forgery_protection                   only: %i[index_by_invoice show read_by_version read_genai_by_version pdf_url_by_version]

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
        invoice_grid = ::Claims::InvoiceGrid.where(invoice_id: invoice_id).limit(1).first

        invoice_json = invoice&.as_json(only: [:id, :status, :created_at, :updated_at, :status_updated_at]) || {}
        invoice_json["session_created_at"] = invoice_grid&.session_created_at
        invoice_json["contractor_business_name"] = invoice_grid&.contractor_business_name

        render json: {
          invoice_id: invoice_id,
          invoice: invoice_json,
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

      # GET /api/claims/admin/invoice_versions/:id/read
      # PURPOSE: Read-screen payload for one specific invoice_version (no current-version resolution)
      def read_by_version
        id = params[:id].to_s.strip
        raise "Missing id" if id.empty?

        iv = ::Claims::InvoiceVersion.find_by(id: id)
        if iv.nil?
          render json: { error: "Not found", id: id }, status: :not_found
          return
        end

        invoice = ::Claims::Invoice.find_by(id: iv.invoice_id)

        lineitems = ::Claims::Lineitem
          .where(invoice_version_id: iv.id)
          .order(:lineitem_seqno)
          .as_json(
            only: [
              :id, :invoice_version_id, :lineitem_seqno,
              :ocr_description, :ocr_description_page, :ocr_description_polygon,
              :ocr_quantity, :ocr_quantity_page, :ocr_quantity_polygon,
              :ocr_unit_price, :ocr_unit_price_page, :ocr_unit_price_polygon,
              :ocr_amount, :ocr_amount_page, :ocr_amount_polygon,
              :created_at, :updated_at
            ]
          )

        render json: {
          read: iv.as_json,
          invoice: invoice&.as_json(only: [:id, :session_id, :status, :status_updated_at, :created_at, :updated_at]),
          lineitems: lineitems
        }, status: :ok
      rescue => e
        Rails.logger.error("[claims][invoice_versions_admin][read_by_version] ERROR: #{e.class}: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoice_versions/:id/read_genai
      # PURPOSE: GenAI located fields + rulechecks for one specific invoice_version
      def read_genai_by_version
        id = params[:id].to_s.strip
        raise "Missing id" if id.empty?

        iv = ::Claims::InvoiceVersion.find_by(id: id)
        if iv.nil?
          render json: { error: "Not found", id: id }, status: :not_found
          return
        end

        located_rows = ::Claims::InvoiceVersionLocatedField
          .where(invoice_version_id: iv.id, source_engine: "genai")
          .order(:field_key, :line_number, :created_at)

        code_located_rows = ::Claims::InvoiceVersionLocatedField
          .where(invoice_version_id: iv.id, source_engine: "code")
          .order(:field_key, :line_number, :created_at)

        rule_rows = ::Claims::InvoiceVersionRulecheck
          .where(invoice_version_id: iv.id, source_engine: "genai")
          .order(:rule_number, :created_at)

        render json: {
          invoice_version_id: iv.id,
          located_fields: located_rows.as_json(
            only: [
              :id, :field_key, :line_number,
              :value_type, :value_text, :value_json, :normalized_value,
              :confidence, :page, :polygon,
              :evidence_text, :evidence_hint, :notes,
              :created_at, :updated_at
            ]
          ),
          code_located_fields: code_located_rows.as_json(
            only: [
              :id, :field_key, :line_number,
              :value_type, :value_text, :value_json, :normalized_value,
              :confidence, :page, :polygon,
              :evidence_text, :evidence_hint, :notes,
              :created_at, :updated_at
            ]
          ),
          rulechecks: rule_rows.as_json(
            only: [
              :id,
              :rule_number, :rule_name,
              :rule_pass_flag,
              :confidence,
              :expected_text, :observed_text,
              :calculation,
              :tolerance_notes,
              :evidence_text, :evidence_hint,
              :reason_and_likely_causes,
              :created_at, :updated_at
            ]
          )
        }, status: :ok
      rescue => e
        Rails.logger.error("[claims][invoice_versions_admin][read_genai_by_version] ERROR: #{e.class}: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoice_versions/:id/pdf_url
      # PURPOSE: Mint signed URL for one specific invoice_version PDF
      def pdf_url_by_version
        id = params[:id].to_s.strip
        raise "Missing id" if id.empty?

        iv = ::Claims::InvoiceVersion.find_by(id: id)
        if iv.nil?
          render json: { error: "Not found", id: id }, status: :not_found
          return
        end

        node_resp = node_mint_sas!(storage_key: iv.storage_key, container: ENV["AZURE_BLOB_CONTAINER"])
        render json: { sas_url: node_resp["sas_url"] }, status: :ok
      rescue => e
        Rails.logger.error("[claims][invoice_versions_admin][pdf_url_by_version] ERROR: #{e.class}: #{e.message}")
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def node_mint_sas!(storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?
        base = base.sub(%r{/\z}, "")

        uri = URI("#{base}/inv/mint-sas")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = { storageKey: storage_key, container: container }.compact.to_json

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == "https"), read_timeout: 60) { |http| http.request(req) }
        body = res.body.to_s
        raise "Node mint-sas failed HTTP=#{res.code} body=#{body}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(body)
      end
    end
  end
end