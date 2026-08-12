# app/controllers/api/claims/invoice_versions_controller.rb
module Api
  module Claims
    class InvoiceVersionsController < Api::ApplicationController
      # For the POC: don’t require login + don’t require policy checks

      before_action :require_claims_invoice_reader!,
                    only: %i[
                      current_invoices
                      read
                      read_genai
                      pdf_url
                      pdf
                      supporting_document_pdf_url
                    ]
      skip_after_action :verify_authorized,
                        only: %i[
                          current_invoices
                          read
                          read_genai
                          pdf_url
                          pdf
                          supporting_document_pdf_url
                        ]

      # ============================================================
      # GET /api/claims/sessions/:session_id/current_invoices
      # PURPOSE: Nav bar list for a session (returns invoice_ids in display order)
      # ============================================================
      def current_invoices
        session_id = params[:session_id]

        sql = <<~SQL
          SELECT invoice_id
          FROM claims.v_current_invoice_versions
          WHERE session_id = ?
          ORDER BY created_at DESC
        SQL

        sanitized =
          ActiveRecord::Base.send(:sanitize_sql_array, [sql, session_id])
        rows =
          ActiveRecord::Base.connection.exec_query(
            sanitized,
            "current_invoices"
          )
        invoice_ids = rows.rows.flatten

        render json: { invoice_ids: invoice_ids }
      end

      # ============================================================
      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/read
      # PURPOSE: Read-screen payload for one invoice (resolves to *current* invoice_version)
      # ============================================================
      def read
        row =
          ::Claims::CurrentInvoiceVersion.find_by(
            session_id: params[:session_id],
            invoice_id: params[:invoice_id]
          )

        if row.nil?
          render json: {
                   error: "Not found",
                   session_id: params[:session_id],
                   invoice_id: params[:invoice_id]
                 },
                 status: :not_found
          return
        end

        civ_id = row.id # current invoice_version_id

        lineitems = serialize_lineitems(civ_id)

        read_hash =
          ::Claims::CurrentInvoiceVersionBlueprint.render_as_hash(
            row,
            view: :read_screen
          )
        invoice_version = ::Claims::InvoiceVersion.find_by(id: civ_id)
        reference_number, submitted_at =
          ::Claims::Invoice.where(id: row.invoice_id).pick(
            :reference_number,
            :submitted_at
          )

        render json: {
                 read:
                   read_hash.merge(
                     reference_number: reference_number,
                     submitted_at: submitted_at,
                     ahri_product_match:
                       serialize_ahri_product_match(invoice_version),
                     neea_product_match:
                       serialize_neea_product_match(invoice_version),
                     awhp_product_match:
                       serialize_awhp_product_match(invoice_version),
                     ohpa_product_match:
                       serialize_ohpa_product_match(invoice_version),
                     herv_product_match:
                       serialize_herv_product_match(invoice_version),
                     vent_fan_product_match:
                       serialize_vent_fan_product_match(invoice_version),
                     supporting_document_types_by_upgrade_type:
                       serialize_supporting_document_types_by_upgrade_type(
                         invoice_version&.id
                       ),
                     uploaded_supporting_documents:
                       serialize_uploaded_supporting_documents(
                         invoice_version&.id
                       )
                   ),
                 lineitems: lineitems
               }
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

      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/pdf_url
      def pdf_url
        civ =
          ::Claims::CurrentInvoiceVersion.find_by(
            session_id: params[:session_id],
            invoice_id: params[:invoice_id]
          )

        if civ.nil?
          render json: { error: "Not found" }, status: :not_found
          return
        end

        render json: {
                 sas_url:
                   node_mint_sas!(
                     storage_key: civ.storage_key,
                     container: ENV["AZURE_BLOB_CONTAINER"].presence
                   ).fetch("sas_url")
               }
      end

      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/supporting_documents/:id/pdf_url
      def supporting_document_pdf_url
        civ =
          ::Claims::CurrentInvoiceVersion.find_by(
            session_id: params[:session_id],
            invoice_id: params[:invoice_id]
          )

        if civ.nil?
          render json: { error: "Not found" }, status: :not_found
          return
        end

        doc =
          ::Claims::SupportingDocument.find_by(
            id: params[:id],
            invoice_version_id: civ.id
          )

        if doc.nil?
          render json: {
                   error: "Supporting document not found"
                 },
                 status: :not_found
          return
        end

        render json: {
                 sas_url:
                   node_mint_sas!(
                     storage_key: doc.storage_key,
                     container: ENV["AZURE_BLOB_CONTAINER"].presence
                   ).fetch("sas_url")
               }
      end

      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/pdf
      def pdf
        civ =
          ::Claims::CurrentInvoiceVersion.find_by(
            session_id: params[:session_id],
            invoice_id: params[:invoice_id]
          )

        if civ.nil?
          render json: { error: "Not found" }, status: :not_found
          return
        end

        stream_blob_pdf!(storage_key: civ.storage_key)
      end

      # ============================================================
      # GET /api/claims/sessions/:session_id/invoices/:invoice_id/read_genai
      # PURPOSE: GenAI located fields for the *current* invoice_version of an invoice
      # ============================================================

      def read_genai
        civ =
          ::Claims::CurrentInvoiceVersion.find_by(
            session_id: params[:session_id],
            invoice_id: params[:invoice_id]
          )

        if civ.nil?
          render json: {
                   error: "Not found",
                   session_id: params[:session_id],
                   invoice_id: params[:invoice_id]
                 },
                 status: :not_found
          return
        end

        located_rows = located_fields_for(civ.id, "genai")
        classifier_located_rows = located_fields_for(civ.id, "classifier")
        code_located_rows = located_fields_for(civ.id, "code")
        rule_rows = rulechecks_for(civ.id, "genai")
        code_rule_rows = rulechecks_for(civ.id, "code")
        upgrade_type_results = upgrade_type_results_for(civ.id)

        render json: {
                 invoice_version_id: civ.id,
                 upgrade_type_results:
                   serialize_upgrade_type_results(upgrade_type_results),
                 located_fields: serialize_located_fields(located_rows),
                 classifier_located_fields:
                   serialize_located_fields(classifier_located_rows),
                 code_located_fields:
                   serialize_located_fields(code_located_rows),
                 rulechecks: serialize_rulechecks(rule_rows),
                 code_rulechecks: serialize_rulechecks(code_rule_rows)
               }
      end

      private

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

      def require_claims_invoice_reader!
        if current_user&.admin? || current_user&.admin_manager? ||
             current_user&.system_admin?
          return
        end

        invoice =
          if params[:invoice_id].present?
            ::Claims::Invoice.find_by(
              id: params[:invoice_id].to_s,
              session_id: params[:session_id].to_s
            )
          elsif params[:session_id].present?
            ::Claims::Invoice.where(session_id: params[:session_id].to_s).first
          end

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

        render json: { error: "Invoice access denied." }, status: :forbidden
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
            *upgrade_type_select_sql("claims.invoice_version_located_fields"),
            "COALESCE(glf.contractor_display_name, clf.contractor_display_name, CASE WHEN claims.invoice_version_located_fields.source_engine = 'classifier' AND claims.invoice_version_located_fields.field_key = 'classifier.eligibility_code' THEN 'Eligibility code' END) AS contractor_display_name"
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
            *upgrade_type_select_sql("claims.invoice_version_rulechecks"),
            "COALESCE(gr.source_quote, cr.source_quote) AS source_quote",
            "COALESCE(gr.contractor_action, cr.contractor_action) AS contractor_action",
            "COALESCE(gr.contractor_visibility, cr.contractor_visibility, 'hidden') AS effective_contractor_visibility",
            "COALESCE(gr.contractor_blocking_policy, cr.contractor_blocking_policy, 'non_blocking') AS effective_contractor_blocking_policy"
          )
          .order(:source_engine, :rule_key, :created_at)
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
              row.read_attribute("upgrade_type_description"),
            "source_quote" => row.read_attribute("source_quote"),
            "contractor_action" => row.read_attribute("contractor_action"),
            "contractor_visibility" =>
              row.read_attribute("effective_contractor_visibility"),
            "contractor_blocking_policy" =>
              row.read_attribute("effective_contractor_blocking_policy")
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
              admin_advice
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
        return [] if invoice_version_id.blank?

        rows = upgrade_type_results_for(invoice_version_id).to_a
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
        return [] if invoice_version_id.blank?

        ::Claims::SupportingDocument
          .where(invoice_version_id: invoice_version_id)
          .includes(
            :supporting_document_type,
            :supporting_document_located_fields,
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
              classification_status: row.classification_status,
              classification_confidence: row.classification_confidence,
              classification_reason: row.classification_reason,
              supporting_document_routing_quality:
                row.supporting_document_routing_quality,
              supporting_document_routing_quality_reason:
                row.supporting_document_routing_quality_reason,
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

      def serialize_supporting_document_visual_findings(row)
        row
          .supporting_document_visual_findings
          .sort_by do |finding|
            [finding.finding_seqno.to_i, finding.created_at]
          end
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
          .sort_by { |field| [field.field_key.to_s, field.created_at] }
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
        return nil unless invoice_version

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
        return nil unless invoice_version

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
        return nil unless invoice_version

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
        return nil unless invoice_version

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
        return nil unless invoice_version

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
        return nil unless invoice_version

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
