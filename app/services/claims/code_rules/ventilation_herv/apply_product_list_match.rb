# frozen_string_literal: true

module Claims
  module CodeRules
    module VentilationHerv
      class ApplyProductListMatch
        VENTILATION_UPGRADE_TYPE_KEY = "ventilation"

        INVOICE_FIELD_KEYS = %w[
          classifier.product_model_number
          classifier.product_manufacturer
          vent_system_type
          vent_manufacturer
          vent_model_number
          vent_make_model
          vent_energy_star_reference
          vent_nrcan_or_product_list_reference
        ].freeze

        SUPPORTING_DOCUMENT_FIELD_KEYS = %w[
          brand_and_model
          model_number
          product_category_or_system_type
          energy_star_reference
          nrcan_reference
          product_list_reference
        ].freeze

        RULES = {
          product_list_match: {
            number: 4,
            key: "vent_herv_nrcan_energy_star_product_list_match"
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

          field_bundle = located_field_bundle
          status = product_list_status(field_bundle)
          product =
            status == :matched ? product_for_field_bundle(field_bundle) : nil

          invoice_version.update!(herv_product_id: product&.id)

          rule_rows =
            rulecheck_rows(
              field_bundle: field_bundle,
              product: product,
              status: status,
              enabled_rules: enabled_rules
            )

          replace_rulechecks!(rule_rows)

          {
            ok: true,
            skipped: false,
            matched: product.present?,
            status: status,
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
              fallback: legacy_ventilation_relevant_upgrade_type?
            )
          end
        end

        def legacy_ventilation_relevant_upgrade_type?
          upgrade_type.upgrade_type_key == VENTILATION_UPGRADE_TYPE_KEY
        end

        def located_field_bundle
          invoice_fields = invoice_located_fields
          supporting_fields = supporting_document_located_fields
          all_fields = invoice_fields + supporting_fields

          {
            fields: {
              invoice: invoice_fields,
              supporting_document: supporting_fields
            },
            all_text: values_for(all_fields).join(" "),
            invoice_model_values: model_values_for(invoice_fields),
            supporting_model_values: model_values_for(supporting_fields),
            invoice_manufacturer_values:
              manufacturer_values_for(invoice_fields),
            supporting_manufacturer_values:
              manufacturer_values_for(supporting_fields)
          }
        end

        def invoice_located_fields
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: %w[classifier genai],
              field_key: INVOICE_FIELD_KEYS
            )
            .where.not(value_text: [nil, ""])
            .order(
              Arel.sql(
                "CASE source_engine WHEN 'classifier' THEN 0 ELSE 1 END"
              ),
              confidence: :desc,
              created_at: :desc
            )
            .to_a
        end

        def supporting_document_located_fields
          ::Claims::SupportingDocumentLocatedField
            .joins(:supporting_document)
            .where(
              ::Claims::SupportingDocument.table_name => {
                invoice_version_id: invoice_version.id
              }
            )
            .where(field_key: SUPPORTING_DOCUMENT_FIELD_KEYS)
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def values_for(fields)
          fields
            .flat_map { |field| split_field_value(field.value_text) }
            .map(&:squish)
            .reject(&:blank?)
            .uniq
        end

        def model_values_for(fields)
          values_for(fields).select { |value| model_like?(value) }
        end

        def manufacturer_values_for(fields)
          values_for(fields).map { |value| normalize_text(value) }.compact.uniq
        end

        def split_field_value(value)
          value.to_s.split(/\s*(?:\||,|;|\n|\r)\s*/).reject(&:blank?)
        end

        def model_like?(value)
          text = value.to_s
          loose = loose_model_key(text)
          loose.present? && loose.length >= 4 && text.match?(/[0-9]/)
        end

        def product_list_status(field_bundle)
          return :bathroom_fan if bathroom_fan_only?(field_bundle)
          if hrv_or_erv_evidence?(field_bundle) == false
            return :unclear_system_type
          end
          if field_bundle.fetch(:invoice_model_values).empty?
            return :missing_invoice
          end
          if field_bundle.fetch(:supporting_model_values).empty?
            return :missing_supporting
          end
          return :source_unavailable unless current_herv_products_available?

          invoice_product =
            product_for_values(
              model_values: field_bundle.fetch(:invoice_model_values),
              manufacturer_values:
                field_bundle.fetch(:invoice_manufacturer_values)
            )
          supporting_product =
            product_for_values(
              model_values: field_bundle.fetch(:supporting_model_values),
              manufacturer_values:
                field_bundle.fetch(:supporting_manufacturer_values)
            )

          if invoice_product.blank? || supporting_product.blank?
            return :not_found
          end
          return :conflict unless invoice_product.id == supporting_product.id

          :matched
        end

        def bathroom_fan_only?(field_bundle)
          text = normalized_bundle_text(field_bundle)
          return false if text.blank?
          if text.match?(/\b(hrv|erv)\b|heat recovery|energy recovery/)
            return false
          end

          text.match?(/bathroom fan|bath fan|exhaust fan|fan system/)
        end

        def hrv_or_erv_evidence?(field_bundle)
          text = normalized_bundle_text(field_bundle)
          return nil if text.blank?

          text.match?(/\b(hrv|erv)\b|heat recovery|energy recovery/)
        end

        def normalized_bundle_text(field_bundle)
          normalize_text(field_bundle.fetch(:all_text)).to_s.downcase
        end

        def product_for_field_bundle(field_bundle)
          invoice_product =
            product_for_values(
              model_values: field_bundle.fetch(:invoice_model_values),
              manufacturer_values:
                field_bundle.fetch(:invoice_manufacturer_values)
            )
          supporting_product =
            product_for_values(
              model_values: field_bundle.fetch(:supporting_model_values),
              manufacturer_values:
                field_bundle.fetch(:supporting_manufacturer_values)
            )

          return nil if invoice_product.blank? || supporting_product.blank?
          return nil unless invoice_product.id == supporting_product.id

          invoice_product
        end

        def product_for_values(model_values:, manufacturer_values:)
          return nil if model_values.empty?

          matches =
            current_herv_products.filter_map do |product|
              model_score =
                model_match_score(product: product, model_values: model_values)
              next if model_score.zero?

              manufacturer_score =
                manufacturer_match_score(
                  product: product,
                  manufacturers: manufacturer_values
                )

              [manufacturer_score + model_score, product]
            end

          match =
            matches.max_by do |score, product|
              [score, product.brand.to_s, product.model_number.to_s, product.id]
            end

          ::Claims::HervProduct.find_by(id: match.last.id) if match
        end

        def current_herv_products
          ::Claims::CurrentHervProduct.all.to_a
        end

        def current_herv_products_available?
          ::Claims::CurrentHervProduct.exists?
        end

        def manufacturer_match_score(product:, manufacturers:)
          return 0 if manufacturers.empty?

          product_brand = normalize_text(product.brand)
          return 0 if product_brand.blank?

          matched =
            manufacturers.any? do |manufacturer|
              manufacturer == product_brand ||
                manufacturer.include?(product_brand) ||
                product_brand.include?(manufacturer)
            end

          matched ? 20 : 0
        end

        def model_match_score(product:, model_values:)
          product_model = product.model_number.to_s
          product_strict = strict_model_key(product_model)
          product_loose = loose_model_key(product_model)

          model_values.each do |value|
            strict_value = strict_model_key(value)
            loose_value = loose_model_key(value)

            if strict_model_matches_regex?(
                 product.model_number_regex,
                 strict_value
               )
              return 100
            end

            if product.model_number_normalized.present? &&
                 product.model_number_normalized == strict_value
              return 95
            end

            return 90 if product_loose.present? && loose_value == product_loose

            if product_loose.present? && product_loose.length >= 5 &&
                 loose_value.to_s.include?(product_loose)
              return 85
            end

            if loose_value.present? && loose_value.length >= 5 &&
                 product_loose.to_s.include?(loose_value)
              return 75
            end

            next unless product_strict.present? && strict_value.present?
            if strict_value.include?(product_strict) ||
                 product_strict.include?(strict_value)
              return 60
            end
          end

          0
        end

        def strict_model_matches_regex?(regex_text, value)
          return false if regex_text.blank? || value.blank?

          Regexp.new(regex_text).match?(value)
        rescue RegexpError
          false
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

        def rulecheck_rows(field_bundle:, product:, status:, enabled_rules:)
          [
            (
              if enabled_rules.key?(:product_list_match)
                product_list_match_row(
                  field_bundle: field_bundle,
                  product: product,
                  status: status
                )
              end
            )
          ].compact
        end

        def product_list_match_row(field_bundle:, product:, status:)
          base_rulecheck_row(
            rule: RULES.fetch(:product_list_match),
            rule_result: product_list_rule_result(status),
            confidence: product.present? ? 100 : 0,
            expected_text:
              "For HRV/ERV ventilation upgrades, the invoice and supporting document should both identify the same product, and that product should match a row in the imported NRCan ENERGY STAR heat/energy recovery ventilator product list.",
            calculation:
              product_list_calculation_text(
                field_bundle: field_bundle,
                status: status,
                product: product
              ),
            evidence_text: field_evidence(field_bundle),
            reason_and_likely_causes:
              product_list_reason_text(
                field_bundle: field_bundle,
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
          case status
          when :matched
            "pass"
          when :bathroom_fan
            "info"
          when :unclear_system_type, :source_unavailable
            "warn"
          else
            "fail"
          end
        end

        def product_list_calculation_text(field_bundle:, status:, product:)
          case status
          when :bathroom_fan
            "Named ventilation evidence indicates a bathroom/exhaust fan rather than an HRV/ERV. HERV NRCan product-list lookup was not applicable."
          when :unclear_system_type
            "Named ventilation evidence did not clearly show HRV/ERV wording. Invoice model evidence=#{field_bundle.fetch(:invoice_model_values).presence&.join(" / ") || "(none)"}; supporting-document model evidence=#{field_bundle.fetch(:supporting_model_values).presence&.join(" / ") || "(none)"}."
          when :missing_invoice
            "No usable HRV/ERV model evidence was stored in invoice fields. Supporting-document model evidence=#{field_bundle.fetch(:supporting_model_values).presence&.join(" / ") || "(none)"}."
          when :missing_supporting
            "Invoice model evidence=#{field_bundle.fetch(:invoice_model_values).join(" / ")}; no usable HRV/ERV model evidence was stored from supporting documents."
          when :source_unavailable
            "Invoice and supporting-document HRV/ERV product evidence are present, but no current imported NRCan ENERGY STAR HERV product-list rows were available to search."
          when :conflict
            "Invoice product evidence #{field_bundle.fetch(:invoice_model_values).join(" / ")} did not resolve to the same imported HERV product as supporting-document product evidence #{field_bundle.fetch(:supporting_model_values).join(" / ")}."
          when :matched
            "Invoice and supporting-document product evidence both matched herv_products.id=#{product.id} from source=#{product.import_run&.herv_source&.description}. #{field_summary(field_bundle)}."
          else
            "Invoice model evidence #{field_bundle.fetch(:invoice_model_values).join(" / ")} and supporting-document model evidence #{field_bundle.fetch(:supporting_model_values).join(" / ")} were searched against the current imported NRCan ENERGY STAR HERV product list, but code could not confirm a shared matching row."
          end
        end

        def product_list_reason_text(field_bundle:, status:, product:)
          case status
          when :bathroom_fan
            "This ventilation upgrade evidence appears to describe a bathroom or exhaust fan, not an HRV/ERV. The NRCan ENERGY STAR HERV product-list requirement applies to heat/energy recovery ventilators, so this code rule records information only and leaves bathroom-fan feature review to the configured ventilation GenAI rules."
          when :unclear_system_type
            "The ventilation evidence did not clearly identify the equipment as an HRV or ERV. Code should not force a product-list failure when the triggering equipment type is unclear. Admin should review vent_system_type and supporting product evidence, then rerun extraction if the HRV/ERV wording is visible but was missed."
          when :missing_invoice
            "The supporting documents may include HRV/ERV product evidence, but the invoice located fields did not include a usable model number. Because the invoice does not independently identify the installed HRV/ERV product, code cannot confirm that the billed equipment matches the supporting product evidence."
          when :missing_supporting
            "The invoice includes HRV/ERV model evidence, but processed supporting documents did not include usable product evidence. The code-owned lookup requires supporting product evidence such as a product specification sheet, ENERGY STAR label, or manufacturer label/photo."
          when :source_unavailable
            "The invoice and supporting documents both include HRV/ERV product evidence, but there are no current imported NRCan ENERGY STAR HERV product-list rows available for code to search. Refresh the HERV product-list download and rerun GenAI/code checks."
          when :conflict
            "The invoice product evidence does not match the product evidence extracted from supporting documents. Invoice evidence is #{field_bundle.fetch(:invoice_model_values).join(" / ")}; supporting-document evidence is #{field_bundle.fetch(:supporting_model_values).join(" / ")}. Admin should verify whether the wrong supporting document was uploaded, the invoice references a different product, or extraction needs correction."
          when :matched
            "The invoice and supporting document both identify the same HRV/ERV product, and that product was found in the current imported NRCan ENERGY STAR heat/energy recovery ventilator product list. The stored invoice version points to the exact imported product-list row used for this check."
          else
            "The invoice and supporting document both include HRV/ERV model evidence, but code could not confirm a shared matching row in the current imported NRCan ENERGY STAR HERV product list. Admin should verify the model read, refresh the HERV import if needed, or ask the contractor for corrected product evidence."
          end
        end

        def field_evidence(field_bundle)
          field_bundle
            .fetch(:fields)
            .values
            .flatten
            .filter_map do |field|
              field.evidence_text.presence || field.value_text.presence
            end
            .uniq
            .join("; ")
            .presence
        end

        def field_summary(field_bundle)
          [
            (
              if field_bundle.fetch(:invoice_model_values).any?
                "invoice model=#{field_bundle.fetch(:invoice_model_values).join(" / ")}"
              end
            ),
            (
              if field_bundle.fetch(:supporting_model_values).any?
                "supporting model=#{field_bundle.fetch(:supporting_model_values).join(" / ")}"
              end
            )
          ].compact.join("; ")
        end

        def normalize_text(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]+/, " ").squish.presence
        end

        def strict_model_key(value)
          model_match_text(value).upcase.gsub(/\s+/, "").presence
        end

        def loose_model_key(value)
          model_match_text(value).upcase.gsub(/[^A-Z0-9]/, "").presence
        end

        def model_match_text(value)
          value.to_s.gsub(/\([^)]*=\s*all sizes[^)]*\)/i, "").squish
        end
      end
    end
  end
end
