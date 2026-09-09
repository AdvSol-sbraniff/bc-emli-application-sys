require "net/http"
require "json"

module Api
  module Claims
    class InvoiceVersionsAdminController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      skip_before_action :authenticate_user!,
                         only: %i[
                           index_by_invoice
                           read_current_by_invoice
                           read_genai_current_by_invoice
                           pdf_url_current_by_invoice
                           pdf_current_by_invoice
                           show
                           read_by_version
                           read_genai_by_version
                           pdf_url_by_version
                           pdf_by_version
                         ]
      skip_before_action :require_confirmation,
                         only: %i[
                           index_by_invoice
                           read_current_by_invoice
                           read_genai_current_by_invoice
                           pdf_url_current_by_invoice
                           pdf_current_by_invoice
                           show
                           read_by_version
                           read_genai_by_version
                           pdf_url_by_version
                           pdf_by_version
                         ]
      skip_after_action :verify_authorized,
                        only: %i[
                          index_by_invoice
                          read_current_by_invoice
                          read_genai_current_by_invoice
                          pdf_url_current_by_invoice
                          pdf_current_by_invoice
                          show
                          read_by_version
                          read_genai_by_version
                          pdf_url_by_version
                          pdf_by_version
                        ]
      skip_forgery_protection only: %i[
                                index_by_invoice
                                read_current_by_invoice
                                read_genai_current_by_invoice
                                pdf_url_current_by_invoice
                                pdf_current_by_invoice
                                show
                                read_by_version
                                read_genai_by_version
                                pdf_url_by_version
                                pdf_by_version
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
                 invoice_version_count:
                   ::Claims::InvoiceVersion.where(invoice_id: invoice_id).count,
                 read:
                   invoice_version_read_json(iv).merge(
                     "ahri_product_match" => serialize_ahri_product_match(iv),
                     "neea_product_match" => serialize_neea_product_match(iv),
                     "awhp_product_match" => serialize_awhp_product_match(iv),
                     "ohpa_product_match" => serialize_ohpa_product_match(iv),
                     "herv_product_match" => serialize_herv_product_match(iv),
                     "vent_fan_product_match" =>
                       serialize_vent_fan_product_match(iv),
                     "supporting_document_types_by_upgrade_type" =>
                       serialize_supporting_document_types_by_upgrade_type(
                         iv.id
                       ),
                     "uploaded_supporting_documents" =>
                       serialize_uploaded_supporting_documents(iv.id)
                   ),
                 invoice: invoice_header_json(invoice),
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
        classifier_located_rows = located_fields_for(iv.id, "classifier")
        rule_rows = rulechecks_for(iv.id, "genai")
        code_rule_rows = rulechecks_for(iv.id, "code")
        detected_upgrade_types = detected_upgrade_types_for(iv.id)

        render json: {
                 review_mode: "invoice_current",
                 is_current_invoice_version: true,
                 invoice_version_id: iv.id,
                 validation_result: iv.validation_result,
                 detected_upgrade_types:
                   serialize_detected_upgrade_types(detected_upgrade_types),
                 located_fields: serialize_located_fields(located_rows),
                 code_located_fields:
                   serialize_located_fields(code_located_rows),
                 classifier_located_fields:
                   serialize_located_fields(classifier_located_rows),
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

        render json: {
                 sas_url: request.path.delete_suffix("_url")
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][pdf_url_current_by_invoice] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoices/:invoice_id/current_version/pdf
      def pdf_current_by_invoice
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

        stream_blob_pdf!(storage_key: iv.storage_key)
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][pdf_current_by_invoice] ERROR: #{e.class}: #{e.message}"
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

        render json: {
                 invoice_version: invoice_version_read_json(row)
               },
               status: :ok
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
                 invoice_version_count:
                   ::Claims::InvoiceVersion.where(
                     invoice_id: iv.invoice_id
                   ).count,
                 read:
                   invoice_version_read_json(iv).merge(
                     "ahri_product_match" => serialize_ahri_product_match(iv),
                     "neea_product_match" => serialize_neea_product_match(iv),
                     "awhp_product_match" => serialize_awhp_product_match(iv),
                     "ohpa_product_match" => serialize_ohpa_product_match(iv),
                     "herv_product_match" => serialize_herv_product_match(iv),
                     "vent_fan_product_match" =>
                       serialize_vent_fan_product_match(iv),
                     "supporting_document_types_by_upgrade_type" =>
                       serialize_supporting_document_types_by_upgrade_type(
                         iv.id
                       ),
                     "uploaded_supporting_documents" =>
                       serialize_uploaded_supporting_documents(iv.id)
                   ),
                 invoice: invoice_header_json(invoice),
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
        classifier_located_rows = located_fields_for(iv.id, "classifier")
        rule_rows = rulechecks_for(iv.id, "genai")
        code_rule_rows = rulechecks_for(iv.id, "code")
        detected_upgrade_types = detected_upgrade_types_for(iv.id)

        render json: {
                 review_mode: "invoice_version_snapshot",
                 is_current_invoice_version:
                   current_invoice_version_for(iv.invoice_id)&.id == iv.id,
                 invoice_version_id: iv.id,
                 validation_result: iv.validation_result,
                 detected_upgrade_types:
                   serialize_detected_upgrade_types(detected_upgrade_types),
                 located_fields: serialize_located_fields(located_rows),
                 code_located_fields:
                   serialize_located_fields(code_located_rows),
                 classifier_located_fields:
                   serialize_located_fields(classifier_located_rows),
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

        render json: {
                 sas_url: request.path.delete_suffix("_url")
               },
               status: :ok
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][pdf_url_by_version] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      # GET /api/claims/admin/invoice_versions/:id/pdf
      def pdf_by_version
        id = params[:id].to_s.strip
        raise "Missing id" if id.empty?

        iv = ::Claims::InvoiceVersion.find_by(id: id)
        if iv.nil?
          render json: { error: "Not found", id: id }, status: :not_found
          return
        end

        stream_blob_pdf!(storage_key: iv.storage_key)
      rescue => e
        Rails.logger.error(
          "[claims][invoice_versions_admin][pdf_by_version] ERROR: #{e.class}: #{e.message}"
        )
        render json: { error: e.message }, status: :unprocessable_entity
      end

      private

      def invoice_header_json(invoice)
        return nil if invoice.nil?

        invoice_grid =
          ::Claims::InvoiceGrid.where(invoice_id: invoice.id).limit(1).first

        invoice.as_json(
          only: %i[
            id
            reference_number
            session_id
            status
            status_updated_at
            created_at
            updated_at
          ]
        ).merge(
          "contractor_business_name" => invoice_grid&.contractor_business_name
        )
      end

      def invoice_version_read_json(invoice_version)
        viewer_config =
          ::Claims::ValidationgenaiConfig.order(:created_at).pick(
            :show_admin_field_revision_plus,
            :admin_pdf_viewer_ux_mode
          )

        invoice_version.as_json.merge(
          "personal_information_type" =>
            serialize_personal_information_type(
              invoice_version.personal_information_type
            ),
          "contractor_advice" =>
            ::Claims::InvoiceVersions::BuildContractorAdvice.call(
              invoice_version_id: invoice_version.id
            ),
          "show_admin_field_revision_plus" => viewer_config&.first != false,
          "admin_pdf_viewer_ux_mode" =>
            (viewer_config&.second == "enterprise" ? "enterprise" : "simple")
        )
      end

      def stream_blob_pdf!(storage_key:, container: ENV["AZURE_BLOB_CONTAINER"])
        res =
          node_download_blob!(storage_key: storage_key, container: container)
        send_data res.body,
                  type: res["content-type"].presence || "application/pdf",
                  disposition: "inline",
                  filename:
                    File.basename(storage_key.to_s.presence || "document.pdf")
      end

      def node_download_blob!(storage_key:, container: nil)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?
        base = base.sub(%r{/\z}, "")

        uri = URI("#{base}/inv/download-blob")
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

        unless res.is_a?(Net::HTTPSuccess)
          raise "Node download-blob failed HTTP=#{res.code} body=#{res.body}"
        end

        res
      end

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
        ].join(", ")
      end

      def serialize_lineitems(invoice_version_id)
        ::Claims::Lineitem
          .where(invoice_version_id: invoice_version_id)
          .order(:lineitem_seqno)
          .map do |row|
            row.as_json(
              only: %i[
                id
                invoice_version_id
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
            )
          end
      end

      def located_fields_for(invoice_version_id, source_engine)
        ::Claims::InvoiceVersionLocatedField
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_located_fields.invoice_upgrade_type_id"
          )
          .joins(
            "LEFT JOIN claims.genai_located_fields glf ON claims.invoice_version_located_fields.source_engine = 'genai' AND glf.genai_field_key = claims.invoice_version_located_fields.field_key"
          )
          .joins(
            "LEFT JOIN claims.code_located_fields clf ON claims.invoice_version_located_fields.source_engine = 'code' AND clf.code_field_key = claims.invoice_version_located_fields.field_key"
          )
          .where(
            invoice_version_id: invoice_version_id,
            source_engine: source_engine
          )
          .select(
            [
              upgrade_type_select_sql("claims.invoice_version_located_fields"),
              "COALESCE(glf.contractor_display_name, clf.contractor_display_name, CASE WHEN claims.invoice_version_located_fields.source_engine = 'classifier' AND claims.invoice_version_located_fields.field_key = 'classifier.eligibility_code' THEN 'Eligibility code' END) AS contractor_display_name"
            ].join(", ")
          )
          .order(:field_key, :created_at)
      end

      def rulechecks_for(invoice_version_id, source_engine)
        ::Claims::InvoiceVersionRulecheck
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_rulechecks.invoice_upgrade_type_id"
          )
          .joins(
            "LEFT JOIN claims.genai_rules gr ON claims.invoice_version_rulechecks.source_engine = 'genai' AND gr.genai_rule_key = claims.invoice_version_rulechecks.rule_key"
          )
          .joins(
            "LEFT JOIN claims.code_rules cr ON claims.invoice_version_rulechecks.source_engine = 'code' AND cr.code_rule_key = claims.invoice_version_rulechecks.rule_key"
          )
          .where(
            invoice_version_id: invoice_version_id,
            source_engine: source_engine
          )
          .select(
            [
              upgrade_type_select_sql("claims.invoice_version_rulechecks"),
              "COALESCE(gr.source_quote, cr.source_quote) AS source_quote",
              "COALESCE(gr.contractor_action, cr.contractor_action) AS contractor_action",
              "COALESCE(gr.contractor_visibility, cr.contractor_visibility, 'hidden') AS effective_contractor_visibility",
              "COALESCE(gr.contractor_blocking_policy, cr.contractor_blocking_policy, 'non_blocking') AS effective_contractor_blocking_policy",
              "COALESCE(gr.admin_workflow_policy, cr.admin_workflow_policy, 'fail_only') AS effective_admin_workflow_policy",
              "CASE WHEN claims.invoice_version_rulechecks.source_engine = 'genai' THEN gr.prompt_text ELSE cr.description END AS rule_definition_text"
            ].join(", ")
          )
          .order(:source_engine, :rule_key, :created_at)
      end

      def detected_upgrade_types_for(invoice_version_id)
        ::Claims::InvoiceVersionUpgradeType
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
          )
          .where(invoice_version_id: invoice_version_id)
          .select(
            upgrade_type_select_sql("claims.invoice_version_upgrade_types")
          )
          .order(
            Arel.sql(
              "CASE WHEN iut.upgrade_type_key = 'common' THEN 0 ELSE 1 END, iut.upgrade_type_key"
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
              row.read_attribute("upgrade_type_description"),
            "contractor_display_name" =>
              row.read_attribute("contractor_display_name")
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
              contractor_display_name
              rule_result
              compliance_score
              expected_text
              calculation
              evidence_text
              reason_and_likely_causes
              reason_complaint_code
              reason_complaint_text
              created_at
              updated_at
            ]
          ).merge(
            "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
            "upgrade_type_description" =>
              row.read_attribute("upgrade_type_description"),
            "source_quote" => row.read_attribute("source_quote"),
            "contractor_action" => row.read_attribute("contractor_action"),
            "contractor_visibility" =>
              row.read_attribute("effective_contractor_visibility"),
            "contractor_blocking_policy" =>
              row.read_attribute("effective_contractor_blocking_policy"),
            "admin_workflow_policy" =>
              row.read_attribute("effective_admin_workflow_policy"),
            "rule_definition_text" => row.read_attribute("rule_definition_text")
          )
        end
      end

      def serialize_detected_upgrade_types(rows)
        rows.map do |row|
          row.as_json(
            only: %i[
              id
              invoice_version_id
              invoice_upgrade_type_id
              confidence
              evidence_text
              classification_explanation
              page
              polygon
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

      def serialize_supporting_document_types_by_upgrade_type(
        invoice_version_id
      )
        rows = detected_upgrade_types_for(invoice_version_id).to_a
        upgrade_types = []
        seen_upgrade_type_ids = {}

        rows.each do |row|
          upgrade_type_id = row.invoice_upgrade_type_id
          if upgrade_type_id.blank? || seen_upgrade_type_ids[upgrade_type_id]
            next
          end

          seen_upgrade_type_ids[upgrade_type_id] = true
          upgrade_types << {
            invoice_upgrade_type_id: upgrade_type_id,
            upgrade_type_key: row.read_attribute("upgrade_type_key"),
            upgrade_type_description:
              row.read_attribute("upgrade_type_description")
          }
        end

        return [] if upgrade_types.empty?

        mappings =
          ::Claims::SupportingDocumentTypeUpgradeType
            .includes(:supporting_document_type)
            .where(
              invoice_upgrade_type_id:
                upgrade_types.map { |row| row[:invoice_upgrade_type_id] }
            )
            .references(:supporting_document_type)
            .merge(::Claims::SupportingDocumentType.where(enabled: true))
            .order("claims.supporting_document_types.type_key ASC")
            .to_a
            .group_by(&:invoice_upgrade_type_id)

        upgrade_types.map do |row|
          type_rows = Array(mappings[row[:invoice_upgrade_type_id]])

          row.merge(
            supporting_document_types:
              type_rows.map do |mapping|
                type = mapping.supporting_document_type
                {
                  supporting_document_type_id: type.id,
                  type_key: type.type_key,
                  description: type.description
                }
              end
          )
        end
      end

      def serialize_uploaded_supporting_documents(invoice_version_id)
        ::Claims::SupportingDocument
          .where(invoice_version_id: invoice_version_id)
          .includes(
            :supporting_document_type,
            :personal_information_type,
            :supporting_document_visual_findings
          )
          .order(created_at: :desc, id: :desc)
          .map do |row|
            display_type =
              row.supporting_document_type&.description ||
                row.supporting_document_type&.type_key || row.content_type

            {
              id: row.id,
              invoice_version_id: row.invoice_version_id,
              supporting_document_type_id: row.supporting_document_type_id,
              supporting_document_type_key:
                row.supporting_document_type&.type_key,
              supporting_document_type_description:
                row.supporting_document_type&.description,
              classification_confidence: row.classification_confidence,
              classification_reason: row.classification_reason,
              supporting_document_routing_quality:
                row.supporting_document_routing_quality,
              supporting_document_routing_quality_reason:
                row.supporting_document_routing_quality_reason,
              personal_information_review_status:
                row.personal_information_review_status,
              personal_information_type:
                serialize_personal_information_type(
                  row.personal_information_type
                ),
              personal_information_review_reason:
                row.personal_information_review_reason,
              located_fields: serialize_supporting_document_located_fields(row),
              visual_findings:
                serialize_supporting_document_visual_findings(row),
              classified_at: row.classified_at,
              original_filename: row.original_filename,
              content_type: display_type,
              mime_content_type: row.content_type,
              byte_size: row.byte_size,
              created_at: row.created_at,
              updated_at: row.updated_at
            }
          end
      end

      def serialize_personal_information_type(type)
        return nil if type.nil?

        { type_key: type.type_key, display_name: type.display_name }
      end

      def serialize_supporting_document_visual_findings(row)
        row
          .supporting_document_visual_findings
          .order(:finding_seqno, :created_at)
          .map do |finding|
            finding.as_json(
              only: %i[
                id
                supporting_document_id
                finding_seqno
                source_engine
                finding_type
                page
                summary
                legibility
                confidence
                raw_json
                created_at
                updated_at
              ]
            )
          end
      end

      def serialize_supporting_document_located_fields(row)
        row
          .supporting_document_located_fields
          .includes(:supporting_document_type_located_field)
          .order(:field_key, :created_at)
          .map do |field|
            definition = field.supporting_document_type_located_field
            field.as_json(
              only: %i[
                id
                supporting_document_id
                supporting_document_type_located_field_id
                source_engine
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
              "field_number" => definition&.field_number,
              "contractor_display_name" => definition&.contractor_display_name,
              "prompt_text" => definition&.prompt_text
            )
          end
      end

      def serialize_ahri_product_match(invoice_version)
        product = invoice_version.ahri_product
        return nil unless product

        import_run = product.import_run
        source = import_run&.ahri_source

        {
          product: {
            id: product.id,
            ahri_reference_number: product.ahri_reference_number,
            heat_pump_type: product.heat_pump_type,
            make: product.make,
            outdoor_model: product.outdoor_model,
            indoor_model_or_air_handler: product.indoor_model_or_air_handler,
            furnace_model: product.furnace_model,
            rated_capacity_btu_at_minus_5c:
              product.rated_capacity_btu_at_minus_5c,
            seer: product.seer,
            seer2: product.seer2,
            hspf: product.hspf,
            hspf2: product.hspf2,
            cop: product.cop,
            capacity_maintenance_percent: product.capacity_maintenance_percent,
            cold_climate_rated: product.cold_climate_rated,
            eligibility_notes: product.eligibility_notes
          },
          source: {
            ahri_import_run_id: import_run&.id,
            ahri_source_id: source&.id,
            source_url: source&.source_url,
            source_description: source&.description,
            publishing_notes: import_run&.publishing_notes,
            publishing_date: import_run&.publishing_date,
            completed_at: import_run&.completed_at,
            records_imported: import_run&.records_imported
          }
        }
      end

      def serialize_neea_product_match(invoice_version)
        product = invoice_version.neea_product
        return nil unless product

        import_run = product.import_run
        source = import_run&.neea_source

        {
          product: {
            id: product.id,
            brand: product.brand,
            model_number: product.model_number,
            storage_volume_gallons: product.storage_volume_gallons,
            indoor_tier: product.indoor_tier,
            indoor_cce: product.indoor_cce,
            outdoor_tier: product.outdoor_tier,
            outdoor_scop: product.outdoor_scop,
            configuration: product.configuration,
            flex_load_connectivity: product.flex_load_connectivity,
            plug_in_endorsement: product.plug_in_endorsement,
            qualified_date: product.qualified_date,
            specification_version: product.specification_version,
            eligibility_notes: product.eligibility_notes
          },
          source: {
            neea_import_run_id: import_run&.id,
            neea_source_id: source&.id,
            source_url: source&.source_url,
            source_description: source&.description,
            publishing_notes: import_run&.publishing_notes,
            publishing_date: import_run&.publishing_date,
            completed_at: import_run&.completed_at,
            records_imported: import_run&.records_imported
          }
        }
      end

      def serialize_awhp_product_match(invoice_version)
        product = invoice_version.awhp_product
        return nil unless product

        import_run = product.import_run
        source = import_run&.awhp_source

        {
          product: {
            id: product.id,
            brand: product.brand,
            model_number: product.model_number,
            model_number_regex: product.model_number_regex,
            model_components: product.model_components,
            system_type: product.system_type,
            eligibility_notes: product.eligibility_notes
          },
          source: {
            awhp_import_run_id: import_run&.id,
            awhp_source_id: source&.id,
            source_url: source&.source_url,
            source_description: source&.description,
            publishing_notes: import_run&.publishing_notes,
            publishing_date: import_run&.publishing_date,
            completed_at: import_run&.completed_at,
            records_imported: import_run&.records_imported
          }
        }
      end

      def serialize_ohpa_product_match(invoice_version)
        product = invoice_version.ohpa_product
        return nil unless product

        import_run = product.import_run
        source = import_run&.ohpa_source

        {
          product: {
            id: product.id,
            ahri_reference_number: product.ahri_reference_number,
            brand: product.brand,
            model_number: product.model_number,
            indoor_model_numbers: product.indoor_model_numbers,
            furnace_model_number: product.furnace_model_number,
            product_group: product.product_group,
            ahri_type: product.ahri_type,
            ducting_configuration: product.ducting_configuration,
            model_status: product.model_status,
            series_name: product.series_name,
            rated_capacity_47f: product.rated_capacity_47f,
            rated_capacity_95f: product.rated_capacity_95f,
            capacity_maintenance_percent: product.capacity_maintenance_percent,
            cop_5f: product.cop_5f,
            hspf2_region_iv: product.hspf2_region_iv,
            hspf2_region_v: product.hspf2_region_v,
            seer2: product.seer2,
            eligibility_notes: product.eligibility_notes
          },
          source: {
            ohpa_import_run_id: import_run&.id,
            ohpa_source_id: source&.id,
            source_url: source&.source_url,
            source_description: source&.description,
            publishing_notes: import_run&.publishing_notes,
            publishing_date: import_run&.publishing_date,
            completed_at: import_run&.completed_at,
            records_imported: import_run&.records_imported
          }
        }
      end

      def serialize_herv_product_match(invoice_version)
        product = invoice_version.herv_product
        return nil unless product

        import_run = product.import_run
        source = import_run&.herv_source

        {
          product: {
            id: product.id,
            brand: product.brand,
            model_number: product.model_number,
            model_type: product.model_type,
            sensible_heat_recovery_efficiency_sre_at_0c:
              product.sensible_heat_recovery_efficiency_sre_at_0c,
            sensible_heat_recovery_efficiency_sre_at_minus_25c:
              product.sensible_heat_recovery_efficiency_sre_at_minus_25c,
            associated_net_supply_airflow_at_0c_cfm:
              product.associated_net_supply_airflow_at_0c_cfm,
            associated_net_supply_airflow_at_minus_25c_cfm:
              product.associated_net_supply_airflow_at_minus_25c_cfm,
            associated_power_consumption_at_0c_w:
              product.associated_power_consumption_at_0c_w,
            associated_power_consumption_at_minus_25c_w:
              product.associated_power_consumption_at_minus_25c_w,
            max_rated_airflow_at_0c_cfm: product.max_rated_airflow_at_0c_cfm,
            power_consumption_at_0c_w: product.power_consumption_at_0c_w,
            eligibility_notes: product.eligibility_notes
          },
          source: {
            herv_import_run_id: import_run&.id,
            herv_source_id: source&.id,
            source_url: source&.source_url,
            source_description: source&.description,
            publishing_notes: import_run&.publishing_notes,
            publishing_date: import_run&.publishing_date,
            completed_at: import_run&.completed_at,
            records_imported: import_run&.records_imported
          }
        }
      end

      def serialize_vent_fan_product_match(invoice_version)
        product = invoice_version.vent_fan_product
        return nil unless product

        import_run = product.import_run
        source = import_run&.vent_fan_source

        {
          product: {
            id: product.id,
            energy_star_unique_id: product.energy_star_unique_id,
            energy_star_partner: product.energy_star_partner,
            brand: product.brand,
            product_model_name: product.product_model_name,
            model_number: product.model_number,
            fan_type: product.fan_type,
            number_of_speeds: product.number_of_speeds,
            duct_size: product.duct_size,
            sound_level_sones: product.sound_level_sones,
            bathroom_utility_airflow_at_0_25_in_wg:
              product.bathroom_utility_airflow_at_0_25_in_wg,
            airflow_1_cfm: product.airflow_1_cfm,
            airflow_2_cfm: product.airflow_2_cfm,
            airflow_3_cfm: product.airflow_3_cfm,
            efficacy_1_cfm_watt: product.efficacy_1_cfm_watt,
            efficacy_2_cfm_watt: product.efficacy_2_cfm_watt,
            efficacy_3_cfm_watt: product.efficacy_3_cfm_watt,
            markets: product.markets,
            cb_model_identifier: product.cb_model_identifier,
            meets_most_efficient_criteria: product.meets_most_efficient_criteria
          },
          source: {
            vent_fan_import_run_id: import_run&.id,
            vent_fan_source_id: source&.id,
            source_url: source&.source_url,
            source_description: source&.description,
            publishing_notes: import_run&.publishing_notes,
            publishing_date: import_run&.publishing_date,
            completed_at: import_run&.completed_at,
            records_imported: import_run&.records_imported
          }
        }
      end
    end
  end
end
