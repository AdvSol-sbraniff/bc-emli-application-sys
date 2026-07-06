# frozen_string_literal: true

module Claims
  module CodeRules
    module OilHeatPumpOhpa
      class ApplyProductListMatch
        OIL_UPGRADE_TYPE_KEY = "air_source_heat_pump_oil"
        INVOICE_AHRI_FIELD_KEY = "classifier.ahri_reference"
        SUPPORTING_AHRI_FIELD_KEY = "ahri_reference"

        RULES = {
          product_list_match: {
            number: 1,
            key: "ashp_oil_ohpa_bc_product_found_in_list"
          }
        }.freeze

        def self.call(invoice_version_id:, invoice_upgrade_type_id:)
          new(
            invoice_version_id: invoice_version_id,
            invoice_upgrade_type_id: invoice_upgrade_type_id
          ).call
        end

        def self.implemented_rule_keys
          RULES.values.map { |rule| rule.fetch(:key) }
        end

        def initialize(invoice_version_id:, invoice_upgrade_type_id:)
          @invoice_version_id = invoice_version_id
          @invoice_upgrade_type_id = invoice_upgrade_type_id
        end

        def call
          @invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)
          @upgrade_type =
            ::Claims::InvoiceUpgradeType.find(@invoice_upgrade_type_id)

          enabled_rules = enabled_rules_for_upgrade_type
          return { ok: true, skipped: true } if enabled_rules.empty?

          ahri_evidence = ahri_evidence_bundle
          product = product_for_ahri_evidence(ahri_evidence)
          rule_rows =
            rulecheck_rows(
              ahri_evidence: ahri_evidence,
              product: product,
              enabled_rules: enabled_rules
            )

          replace_rulechecks!(rule_rows)

          {
            ok: true,
            skipped: false,
            matched: product.present?,
            rulechecks: rule_rows.size
          }
        rescue StandardError => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_rules_for_upgrade_type
          RULES.select do |_rule_type, rule|
            ::Claims::CodeRules::Registry.enabled_for?(
              code_rule_key: rule.fetch(:key),
              invoice_upgrade_type_id: upgrade_type.id,
              fallback: oil_upgrade_type?
            )
          end
        end

        def oil_upgrade_type?
          upgrade_type.upgrade_type_key == OIL_UPGRADE_TYPE_KEY
        end

        def ahri_evidence_bundle
          invoice_field = best_invoice_ahri_located_field
          supporting_fields = supporting_document_ahri_located_fields
          invoice_ahri = normalized_ahri(invoice_field&.value_text)
          supporting_ahris =
            supporting_fields
              .map { |field| normalized_ahri(field.value_text) }
              .reject(&:blank?)
              .uniq

          {
            invoice_field: invoice_field,
            supporting_fields: supporting_fields,
            invoice_ahri: invoice_ahri.presence,
            supporting_ahris: supporting_ahris
          }
        end

        def best_invoice_ahri_located_field
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "classifier",
              field_key: INVOICE_AHRI_FIELD_KEY
            )
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .first
        end

        def supporting_document_ahri_located_fields
          ::Claims::SupportingDocumentLocatedField
            .joins(:supporting_document)
            .where(
              ::Claims::SupportingDocument.table_name => {
                invoice_version_id: invoice_version.id
              }
            )
            .where(field_key: SUPPORTING_AHRI_FIELD_KEY)
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def product_for_ahri_evidence(ahri_evidence)
          return nil unless ahri_evidence_matchable?(ahri_evidence)

          product_for(ahri_evidence.fetch(:invoice_ahri))
        end

        def ahri_evidence_matchable?(ahri_evidence)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          supporting_ahris = ahri_evidence.fetch(:supporting_ahris)

          invoice_ahri.present? && supporting_ahris.size == 1 &&
            supporting_ahris.first == invoice_ahri
        end

        def product_for(raw_ahri)
          ahri = normalized_ahri(raw_ahri)
          return nil if ahri.blank?

          current_match =
            ::Claims::CurrentOhpaProduct
              .where(ahri_reference_number: ahri)
              .order(:source_description, :id)
              .first

          return nil unless current_match

          ::Claims::OhpaProduct.find_by(id: current_match.id)
        end

        def current_ohpa_products_available?
          ::Claims::CurrentOhpaProduct.exists?
        end

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULES.values.map { |rule| rule.fetch(:key) }
          ).delete_all

          ::Claims::InvoiceVersionRulecheck.insert_all!(rows) if rows.any?
        end

        def rulecheck_rows(ahri_evidence:, product:, enabled_rules:)
          [
            (
              if enabled_rules.key?(:product_list_match)
                product_list_match_row(
                  ahri_evidence: ahri_evidence,
                  product: product
                )
              end
            )
          ].compact
        end

        def product_list_match_row(ahri_evidence:, product:)
          matched = product.present?
          status =
            ahri_evidence_status(ahri_evidence: ahri_evidence, product: product)

          base_rulecheck_row(
            rule: RULES.fetch(:product_list_match),
            rule_result: product_list_rule_result(status),
            confidence: matched ? 100 : 0,
            expected_text:
              "The invoice and supporting document should both show the same AHRI reference, and that AHRI should match a row in the imported NRCan Oil to Heat Pump Affordability BC qualified product list.",
            calculation:
              product_list_calculation_text(
                ahri_evidence: ahri_evidence,
                status: status,
                product: product
              ),
            evidence_text: ahri_evidence_text(ahri_evidence),
            reason_and_likely_causes:
              product_list_reason_text(
                ahri_evidence: ahri_evidence,
                status: status,
                product: product
              )
          )
        end

        def base_rulecheck_row(
          rule:,
          rule_result:,
          confidence:,
          expected_text:,
          calculation:,
          evidence_text:,
          reason_and_likely_causes:
        )
          now = Time.current

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_number: rule.fetch(:number),
            rule_key: rule.fetch(:key),
            rule_result: rule_result,
            confidence: confidence,
            expected_text: expected_text,
            calculation: calculation,
            evidence_text: evidence_text,
            reason_and_likely_causes:
              append_admin_message(
                rule: rule,
                rule_result: rule_result,
                reason_text: reason_and_likely_causes
              ),
            created_at: now,
            updated_at: now
          }
        end

        def append_admin_message(rule:, rule_result:, reason_text:)
          message =
            ::Claims::CodeRules::Registry.admin_message(
              code_rule_key: rule.fetch(:key),
              rule_result: rule_result
            )
          return reason_text if message.blank?

          "#{reason_text}\n\nAdmin guidance: #{message}"
        end

        def product_list_rule_result(status)
          if status == :source_unavailable
            "warn"
          else
            (status == :matched ? "pass" : "fail")
          end
        end

        def ahri_evidence_status(ahri_evidence:, product:)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          supporting_ahris = ahri_evidence.fetch(:supporting_ahris)

          return :missing_invoice if invoice_ahri.blank?
          return :missing_supporting if supporting_ahris.empty?
          unless supporting_ahris.size == 1 &&
                   supporting_ahris.first == invoice_ahri
            return :conflict
          end
          return :source_unavailable unless current_ohpa_products_available?

          product.present? ? :matched : :not_found
        end

        def product_list_calculation_text(ahri_evidence:, status:, product:)
          case status
          when :missing_invoice
            "No AHRI reference was stored in invoice located fields. Supporting-document AHRI evidence: #{supporting_ahri_text(ahri_evidence)}."
          when :missing_supporting
            "Invoice AHRI was stored as #{ahri_evidence.fetch(:invoice_ahri)}, but no AHRI reference was stored in processed supporting-document located fields."
          when :conflict
            "Invoice AHRI #{ahri_evidence.fetch(:invoice_ahri)} does not match the supporting-document AHRI evidence #{supporting_ahri_text(ahri_evidence)}."
          when :source_unavailable
            "Invoice and supporting-document AHRI evidence both show #{ahri_evidence.fetch(:invoice_ahri)}, but no current imported NRCan OHPA BC product-list rows were available to search."
          when :matched
            "Invoice and supporting-document AHRI evidence both matched ohpa_products.id=#{product.id} from source=#{product.import_run&.ohpa_source&.description}. #{product_evidence(product)}."
          else
            "Invoice and supporting-document AHRI evidence both show #{ahri_evidence.fetch(:invoice_ahri)}, but that AHRI was not found in the current imported NRCan OHPA BC qualified product list."
          end
        end

        def product_list_reason_text(ahri_evidence:, status:, product:)
          case status
          when :missing_invoice
            "The oil-to-heat-pump product-list rule requires AHRI evidence in both the invoice and a supporting product document. " \
              "The processed supporting documents may include AHRI evidence, but the invoice located fields did not include a usable AHRI reference. " \
              "Because the invoice does not independently identify the installed AHRI combination, code cannot confirm the billed equipment is on the NRCan OHPA BC list."
          when :missing_supporting
            "The invoice includes AHRI evidence, but the processed supporting documents did not include usable AHRI evidence. " \
              "This rule requires the invoice AHRI to be corroborated by supporting product evidence such as a product specification sheet or manufacturer label/photo."
          when :conflict
            "The invoice AHRI does not match the AHRI evidence extracted from supporting documents. " \
              "Invoice evidence is #{ahri_evidence.fetch(:invoice_ahri)}; supporting-document evidence is #{supporting_ahri_text(ahri_evidence)}. " \
              "Admin should verify whether the wrong supporting document was uploaded, the invoice references a different system, or extraction needs correction."
          when :source_unavailable
            "The invoice and supporting documents agree on AHRI #{ahri_evidence.fetch(:invoice_ahri)}, but there are no current imported NRCan OHPA BC product-list rows available for code to search. " \
              "This is an information-on-record problem, not a product failure. Admin should refresh the OHPA download and rerun GenAI/code checks."
          when :matched
            "The invoice and supporting document both identify AHRI #{ahri_evidence.fetch(:invoice_ahri)}, and that AHRI was found in the current imported NRCan OHPA BC qualified product list. " \
              "The stored invoice version now points to the exact imported OHPA product-list row used for this check. " \
              "This is a code-owned pass because the match was made against local imported reference data, not by model judgment."
          else
            "The invoice and supporting document both include the same AHRI evidence, but code could not find that AHRI in the current imported NRCan OHPA BC qualified product list. " \
              "Admin should verify whether the AHRI was read correctly, confirm the OHPA import is current, and ask the contractor for corrected qualifying-product evidence if needed."
          end
        end

        def supporting_ahri_text(ahri_evidence)
          ahri_evidence.fetch(:supporting_ahris).presence&.join(" / ") ||
            "(none)"
        end

        def ahri_evidence_text(ahri_evidence)
          invoice_field = ahri_evidence.fetch(:invoice_field)
          supporting_fields = ahri_evidence.fetch(:supporting_fields)
          parts = []

          if invoice_field
            parts << "invoice: #{invoice_field.evidence_text.presence || invoice_field.value_text}"
          end

          supporting_fields.each do |field|
            label =
              field.supporting_document&.original_filename.presence ||
                "supporting document"
            parts << "#{label}: #{field.evidence_text.presence || field.value_text}"
          end

          parts.uniq.join("; ").presence
        end

        def product_evidence(product)
          [
            "AHRI #{product.ahri_reference_number}",
            product.brand,
            product.model_number,
            product.indoor_model_numbers,
            product.furnace_model_number,
            product.product_group,
            product.model_status
          ].compact_blank.join("; ")
        end

        def normalized_ahri(raw_ahri)
          text = raw_ahri.to_s.strip
          return "" if text.blank?

          digits = text.gsub(/\D/, "")
          digits.presence || text
        end
      end
    end
  end
end
