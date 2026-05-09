require "net/http"
require "json"

module Api
  module Claims
    class InvoiceVersionsAdminController < Api::ApplicationController
      skip_before_action :authenticate_user!,
                         only: %i[
                           index_by_invoice
                           read_current_by_invoice
                           read_genai_current_by_invoice
                           pdf_url_current_by_invoice
                           show
                           read_by_version
                           read_genai_by_version
                           pdf_url_by_version
                         ]
      skip_before_action :require_confirmation,
                         only: %i[
                           index_by_invoice
                           read_current_by_invoice
                           read_genai_current_by_invoice
                           pdf_url_current_by_invoice
                           show
                           read_by_version
                           read_genai_by_version
                           pdf_url_by_version
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          index_by_invoice
                          read_current_by_invoice
                          read_genai_current_by_invoice
                          pdf_url_current_by_invoice
                          show
                          read_by_version
                          read_genai_by_version
                          pdf_url_by_version
                        ]
      skip_forgery_protection only: %i[
                                index_by_invoice
                                read_current_by_invoice
                                read_genai_current_by_invoice
                                pdf_url_current_by_invoice
                                show
                                read_by_version
                                read_genai_by_version
                                pdf_url_by_version
                              ]

      def index_by_invoice
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id" if invoice_id.empty?

        limit = params[:limit].to_i
        limit = 200 if limit <= 0
        limit = 500 if limit > 500

        rows =
          ::Claims::InvoiceVersion
            .where(invoice_id: invoice_id)
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .limit(limit)

        invoice = ::Claims::Invoice.find_by(id: invoice_id)
        invoice_grid =
          ::Claims::InvoiceGrid.where(invoice_id: invoice_id).limit(1).first

        invoice_json =
          invoice&.as_json(
            only: %i[id status created_at updated_at status_updated_at]
          ) || {}
        invoice_json["session_created_at"] = invoice_grid&.session_created_at
        invoice_json[
          "contractor_business_name"
        ] = invoice_grid&.contractor_business_name

        render json: {
                 invoice_id: invoice_id,
                 invoice: invoice_json,
                 invoice_versions:
                   rows.as_json(
                     only: %i[
                       id
                       invoice_id
                       invoice_versionno
                       storage_provider
                       storage_key
                       original_filename
                       content_type
                       byte_size
                       sha256
                       di_ocr_invoice_id
                       di_ocr_invoice_date
                       di_ocr_vendor_name
                       di_ocr_invoice_total
                       created_at
                       updated_at
                     ]
                   )
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][index_by_invoice] ERROR: #{e.class}: #{e.message}"
        )
        render json: {
                 invoice_versions: [],
                 error: e.message
               },
               status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoices/:invoice_id/current_version/read
      # PURPOSE: Read-screen payload for the latest/current version of one invoice.
      # Bookmarks to this route follow future uploaded fixes.
      def read_current_by_invoice
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id" if invoice_id.empty?

        invoice = ::Claims::Invoice.find_by(id: invoice_id)
        if invoice.nil?
          render json: {
                   error: "Invoice not found",
                   invoice_id: invoice_id
                 },
                 status: :not_found
          return
        end

        iv = current_invoice_version_for(invoice_id)
        if iv.nil?
          render json: {
                   error: "Current invoice version not found",
                   invoice_id: invoice_id
                 },
                 status: :not_found
          return
        end

        render json: {
                 review_mode: "invoice_current",
                 is_current_invoice_version: true,
                 read: iv.as_json,
                 invoice:
                   invoice.as_json(
                     only: %i[
                       id
                       session_id
                       status
                       status_updated_at
                       created_at
                       updated_at
                     ]
                   ),
                 lineitems: serialize_lineitems(iv.id)
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][read_current_by_invoice] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoices/:invoice_id/current_version/read_genai
      def read_genai_current_by_invoice
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id" if invoice_id.empty?

        iv = current_invoice_version_for(invoice_id)
        if iv.nil?
          render json: {
                   error: "Current invoice version not found",
                   invoice_id: invoice_id
                 },
                 status: :not_found
          return
        end

        located_rows = located_fields_for(iv.id, "genai")
        code_located_rows = located_fields_for(iv.id, "code")
        rule_rows = rulechecks_for(iv.id, "genai")
        code_rule_rows = rulechecks_for(iv.id, "code")
        upgrade_type_results = upgrade_type_results_for(iv.id)

        render json: {
                 review_mode: "invoice_current",
                 is_current_invoice_version: true,
                 invoice_version_id: iv.id,
                 upgrade_type_results:
                   serialize_upgrade_type_results(upgrade_type_results),
                 located_fields: serialize_located_fields(located_rows),
                 code_located_fields:
                   serialize_located_fields(code_located_rows),
                 rulechecks: serialize_rulechecks(rule_rows),
                 code_rulechecks: serialize_rulechecks(code_rule_rows)
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][read_genai_current_by_invoice] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoices/:invoice_id/current_version/pdf_url
      def pdf_url_current_by_invoice
        invoice_id = params[:invoice_id].to_s.strip
        raise "Missing invoice_id" if invoice_id.empty?

        iv = current_invoice_version_for(invoice_id)
        if iv.nil?
          render json: {
                   error: "Current invoice version not found",
                   invoice_id: invoice_id
                 },
                 status: :not_found
          return
        end

        node_resp =
          node_mint_sas!(
            storage_key: iv.storage_key,
            container: ENV["AZURE_BLOB_CONTAINER"]
          )
        render json: { sas_url: node_resp["sas_url"] }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][pdf_url_current_by_invoice] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def show
        id = params[:id].to_s.strip
        raise "Missing id" if id.empty?

        row = ::Claims::InvoiceVersion.find_by(id: id)
        if row.nil?
          render json: { error: "Not found", id: id }, status: :not_found
          return
        end

        render json: { invoice_version: row.as_json }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][show] ERROR: #{e.class}: #{e.message}"
        )
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

        lineitems = serialize_lineitems(iv.id)

        render json: {
                 review_mode: "invoice_version_snapshot",
                 is_current_invoice_version:
                   current_invoice_version_for(iv.invoice_id)&.id == iv.id,
                 read: iv.as_json,
                 invoice:
                   invoice&.as_json(
                     only: %i[
                       id
                       session_id
                       status
                       status_updated_at
                       created_at
                       updated_at
                     ]
                   ),
                 lineitems: lineitems
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][read_by_version] ERROR: #{e.class}: #{e.message}"
        )
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

        located_rows = located_fields_for(iv.id, "genai")
        code_located_rows = located_fields_for(iv.id, "code")
        rule_rows = rulechecks_for(iv.id, "genai")
        code_rule_rows = rulechecks_for(iv.id, "code")
        upgrade_type_results = upgrade_type_results_for(iv.id)

        render json: {
                 review_mode: "invoice_version_snapshot",
                 is_current_invoice_version:
                   current_invoice_version_for(iv.invoice_id)&.id == iv.id,
                 invoice_version_id: iv.id,
                 upgrade_type_results:
                   serialize_upgrade_type_results(upgrade_type_results),
                 located_fields: serialize_located_fields(located_rows),
                 code_located_fields:
                   serialize_located_fields(code_located_rows),
                 rulechecks: serialize_rulechecks(rule_rows),
                 code_rulechecks: serialize_rulechecks(code_rule_rows)
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][read_genai_by_version] ERROR: #{e.class}: #{e.message}"
        )
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

        node_resp =
          node_mint_sas!(
            storage_key: iv.storage_key,
            container: ENV["AZURE_BLOB_CONTAINER"]
          )
        render json: { sas_url: node_resp["sas_url"] }, status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][pdf_url_by_version] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def current_invoice_version_for(invoice_id)
        ::Claims::InvoiceVersion
          .where(invoice_id: invoice_id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .first
      end

      def upgrade_type_select_sql(table_name)
        [
          "#{table_name}.*",
          "iut.upgrade_type_key AS upgrade_type_key",
          "iut.description AS upgrade_type_description"
        ]
      end

      def serialize_lineitems(invoice_version_id)
        ::Claims::Lineitem
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.lineitems.invoice_upgrade_type_id"
          )
          .where(invoice_version_id: invoice_version_id)
          .select(*upgrade_type_select_sql("claims.lineitems"))
          .order(:lineitem_seqno)
          .map do |row|
            row.as_json(
              only: %i[
                id
                invoice_version_id
                invoice_upgrade_type_id
                lineitem_seqno
                ocr_description
                ocr_description_page
                ocr_description_polygon
                ocr_quantity
                ocr_quantity_page
                ocr_quantity_polygon
                ocr_unit_price
                ocr_unit_price_page
                ocr_unit_price_polygon
                ocr_amount
                ocr_amount_page
                ocr_amount_polygon
                created_at
                updated_at
              ]
            ).merge(
              "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
              "upgrade_type_description" =>
                row.read_attribute("upgrade_type_description")
            )
          end
      end

      def located_fields_for(invoice_version_id, source_engine)
        ::Claims::InvoiceVersionLocatedField
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_located_fields.invoice_upgrade_type_id"
          )
          .where(
            invoice_version_id: invoice_version_id,
            source_engine: source_engine
          )
          .select(
            *upgrade_type_select_sql("claims.invoice_version_located_fields")
          )
          .order(:field_key, :created_at)
      end

      def rulechecks_for(invoice_version_id, source_engine)
        ::Claims::InvoiceVersionRulecheck
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_rulechecks.invoice_upgrade_type_id"
          )
          .where(
            invoice_version_id: invoice_version_id,
            source_engine: source_engine
          )
          .select(*upgrade_type_select_sql("claims.invoice_version_rulechecks"))
          .order(:rule_number, :created_at)
      end

      def upgrade_type_results_for(invoice_version_id)
        ::Claims::InvoiceVersionUpgradeType
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
          )
          .where(invoice_version_id: invoice_version_id)
          .select(
            *upgrade_type_select_sql("claims.invoice_version_upgrade_types")
          )
          .order(
            Arel.sql(
              "CASE WHEN iut.upgrade_type_key = 'common' THEN 0 ELSE 1 END, iut.upgrade_type_key, claims.invoice_version_upgrade_types.source_engine"
            )
          )
      end

      def serialize_located_fields(rows)
        rows.map do |row|
          row.as_json(
            only: %i[
              id
              invoice_version_id
              invoice_upgrade_type_id
              field_key
              value_type
              value_text
              value_json
              confidence
              page
              polygon
              evidence_text
              created_at
              updated_at
            ]
          ).merge(
            "source_engine" => row.source_engine,
            "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
            "upgrade_type_description" =>
              row.read_attribute("upgrade_type_description")
          )
        end
      end

      def serialize_rulechecks(rows)
        rows.map do |row|
          row.as_json(
            only: %i[
              id
              invoice_version_id
              invoice_upgrade_type_id
              source_engine
              rule_key
              source_requirement_id
              evidence_source
              rule_number
              rule_name
              rule_result
              confidence
              expected_text
              calculation
              evidence_text
              reason_and_likely_causes
              created_at
              updated_at
            ]
          ).merge(
            "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
            "upgrade_type_description" =>
              row.read_attribute("upgrade_type_description")
          )
        end
      end

      def serialize_upgrade_type_results(rows)
        rows.map do |row|
          row.as_json(
            only: %i[
              id
              invoice_version_id
              invoice_upgrade_type_id
              source_engine
              call_status
              confidence
              result
              validationgenai_ruleset_id
              raw_json
              created_at
              updated_at
            ]
          ).merge(
            "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
            "upgrade_type_description" =>
              row.read_attribute("upgrade_type_description")
          )
        end
      end

      def node_mint_sas!(storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?
        base = base.sub(%r{/\z}, "")

        uri = URI("#{base}/inv/mint-sas")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req.body = {
          storageKey: storage_key,
          container: container
        }.compact.to_json

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 60
          ) { |http| http.request(req) }
        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node mint-sas failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      end
    end
  end
end
