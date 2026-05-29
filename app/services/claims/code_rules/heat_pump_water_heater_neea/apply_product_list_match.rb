# frozen_string_literal: true

module Claims
  module CodeRules
    module HeatPumpWaterHeaterNeea
      class ApplyProductListMatch
        HPWH_UPGRADE_TYPE_KEY = "heat_pump_water_heater"

        MANUFACTURER_FIELD_KEY = "hpwh_manufacturer"
        MODEL_NUMBER_FIELD_KEY = "hpwh_model_number"
        MODEL_COMPONENTS_FIELD_KEY = "hpwh_model_components"
        MAKE_MODEL_FIELD_KEY = "hpwh_make_model"

        RULES = {
          product_list_match: {
            number: 1,
            key: "hpwh_neea_found_in_product_list",
            name: "NEEA HPWH Found In Product List",
            source_requirement_id: "ESP-2026-HPWH-NEEA-001"
          },
          tier_two_or_higher: {
            number: 2,
            key: "hpwh_neea_tier_2_or_higher",
            name: "NEEA HPWH Tier 2 Or Higher",
            source_requirement_id: "ESP-2026-HPWH-NEEA-002"
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
          product = product_for(field_bundle)
          rule_rows =
            rulecheck_rows(
              field_bundle: field_bundle,
              product: product,
              enabled_rules: enabled_rules
            )

          ::Claims::InvoiceVersion.transaction do
            @invoice_version.update!(neea_product_id: product&.id)
            replace_rulechecks!(rule_rows)
          end

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
          RULES.select do |_rule_name, rule|
            ::Claims::CodeRules::Registry.enabled_for?(
              code_rule_key: rule.fetch(:key),
              invoice_upgrade_type_id: upgrade_type.id,
              fallback: legacy_hpwh_relevant_upgrade_type?
            )
          end
        end

        def legacy_hpwh_relevant_upgrade_type?
          upgrade_type.upgrade_type_key == HPWH_UPGRADE_TYPE_KEY
        end

        def located_field_bundle
          fields = {
            manufacturer: located_fields(MANUFACTURER_FIELD_KEY),
            model_number: located_fields(MODEL_NUMBER_FIELD_KEY),
            model_components: located_fields(MODEL_COMPONENTS_FIELD_KEY),
            make_model: located_fields(MAKE_MODEL_FIELD_KEY)
          }

          {
            fields: fields,
            manufacturer_values: values_for(fields.fetch(:manufacturer)),
            model_values:
              values_for(fields.fetch(:model_number)) +
                values_for(fields.fetch(:model_components)) +
                values_for(fields.fetch(:make_model))
          }
        end

        def located_fields(field_key)
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "genai",
              field_key: field_key
            )
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

        def split_field_value(value)
          value.to_s.split(/\s*(?:\||,|;|\n|\r|&)\s*/).reject(&:blank?)
        end

        def product_for(field_bundle)
          model_values = field_bundle.fetch(:model_values)
          return nil if model_values.empty?

          manufacturers =
            field_bundle
              .fetch(:manufacturer_values)
              .map { |value| normalize_text(value) }
              .compact

          matches =
            candidate_products(
              field_bundle: field_bundle
            ).filter_map do |product|
              model_score =
                model_match_score(product: product, model_values: model_values)
              next if model_score.zero?

              manufacturer_score =
                manufacturer_match_score(
                  product: product,
                  manufacturers: manufacturers
                )

              [manufacturer_score + model_score, product]
            end

          match =
            matches.max_by do |score, product|
              [score, effective_tier(product).to_i, product.id]
            end
          ::Claims::NeeaProduct.find_by(id: match.last.id) if match
        end

        def candidate_products(field_bundle:)
          manufacturers =
            field_bundle
              .fetch(:manufacturer_values)
              .map { |value| normalize_text(value) }
              .compact

          scope = ::Claims::CurrentNeeaProduct.all
          return scope.to_a if manufacturers.empty?

          brand_matches = scope.where(brand_normalized: manufacturers).to_a
          brand_matches.presence || scope.to_a
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
          product_loose = loose_model_key(product_model)
          product_components =
            Array(product.model_components)
              .map { |component| loose_model_key(component) }
              .reject(&:blank?)

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
            if product_loose.present? && loose_value.include?(product_loose)
              return 80
            end
            if all_components_match?(
                 product_components: product_components,
                 loose_value: loose_value
               )
              return 70
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

        def all_components_match?(product_components:, loose_value:)
          return false if product_components.empty? || loose_value.blank?

          product_components.all? do |component|
            loose_value.include?(component)
          end
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

        def rulecheck_rows(field_bundle:, product:, enabled_rules:)
          [
            (
              if enabled_rules.key?(:product_list_match)
                product_list_match_row(
                  field_bundle: field_bundle,
                  product: product
                )
              end
            ),
            (
              if enabled_rules.key?(:tier_two_or_higher)
                tier_two_or_higher_row(
                  field_bundle: field_bundle,
                  product: product
                )
              end
            )
          ].compact
        end

        def product_list_match_row(field_bundle:, product:)
          matched = product.present?

          base_rulecheck_row(
            rule: RULES.fetch(:product_list_match),
            rule_result: matched ? "pass" : "warn",
            confidence: matched ? 100 : 0,
            expected_text:
              "The heat pump water heater manufacturer/model found on the invoice should match a row in the imported NEEA Residential HPWH Qualified Products List.",
            calculation:
              product_list_calculation_text(
                field_bundle: field_bundle,
                product: product
              ),
            evidence_text: field_evidence(field_bundle),
            reason_and_likely_causes:
              product_list_reason_text(
                field_bundle: field_bundle,
                product: product
              )
          )
        end

        def tier_two_or_higher_row(field_bundle:, product:)
          if product.nil?
            return(
              dependent_info_row(
                field_bundle: field_bundle,
                rule: RULES.fetch(:tier_two_or_higher),
                expected_text:
                  "The matched NEEA product-list row should show Tier 2 or higher."
              )
            )
          end

          tier = effective_tier(product)

          if tier.nil?
            return(
              base_rulecheck_row(
                rule: RULES.fetch(:tier_two_or_higher),
                rule_result: "warn",
                confidence: 0,
                expected_text:
                  "The matched NEEA product-list row should show Tier 2 or higher.",
                calculation:
                  "Matched neea_products.id=#{product.id}, but indoor_tier and outdoor_tier were both blank in the imported NEEA row.",
                evidence_text: product_evidence(product),
                reason_and_likely_causes:
                  "The product-list match succeeded, but the imported NEEA row did not provide a usable tier value. " \
                    "The Energy Savings Program requirement is that the heat pump water heater be listed as a qualifying product, and the NEEA list expresses qualification through product-list tier data. " \
                    "Because code cannot see a tier value, it cannot prove the Tier 2 or higher threshold. " \
                    "Admin should inspect the source NEEA PDF row and confirm whether the list import missed the tier. " \
                    "If the source PDF is correct but the imported row is incomplete, refresh or repair the NEEA import before relying on this code rule."
              )
            )
          end

          passed = tier >= 2
          base_rulecheck_row(
            rule: RULES.fetch(:tier_two_or_higher),
            rule_result: passed ? "pass" : "fail",
            confidence: 100,
            expected_text:
              "The matched NEEA product-list row should show Tier 2 or higher.",
            calculation:
              "Effective NEEA tier = #{tier}; required minimum = Tier 2.",
            evidence_text: product_evidence(product),
            reason_and_likely_causes:
              tier_reason_text(product: product, tier: tier, passed: passed)
          )
        end

        def dependent_info_row(field_bundle:, rule:, expected_text:)
          base_rulecheck_row(
            rule: rule,
            rule_result: "info",
            confidence: 0,
            expected_text: expected_text,
            calculation:
              "The NEEA tier check was not run because no matching NEEA product-list row was available for #{field_summary(field_bundle).presence || "(missing model evidence)"}.",
            evidence_text: field_evidence(field_bundle),
            reason_and_likely_causes:
              "This code rule depends on a successful NEEA product-list match before it can inspect product-list tier values. " \
                "Code Rule 1 records whether the manufacturer/model evidence was missing, not found, or matched. " \
                "Until a product row is matched, this dependent tier check cannot make a meaningful pass or fail decision. " \
                "This is shown as information rather than a second warning so the admin is not asked to resolve the same root issue twice. " \
                "After the NEEA match is corrected, rerun GenAI/code checks to evaluate the product-list tier."
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
            source_requirement_id: rule.fetch(:source_requirement_id),
            evidence_source: "invoice_pdf|external_list",
            rule_name: rule.fetch(:name),
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

        def product_list_calculation_text(field_bundle:, product:)
          if field_bundle.fetch(:model_values).empty?
            return(
              "No HPWH manufacturer/model located fields were stored for this heat pump water heater upgrade call."
            )
          end

          unless current_neea_products_available?
            return(
              "No current imported NEEA Residential HPWH Qualified Products List rows were available to search."
            )
          end

          if product
            "Invoice model evidence #{field_summary(field_bundle)} matched neea_products.id=#{product.id} from source=#{product.import_run&.neea_source&.description}."
          else
            "Invoice model evidence #{field_summary(field_bundle)} was searched across the current imported NEEA Residential HPWH Qualified Products List, but no matching row was found."
          end
        end

        def product_list_reason_text(field_bundle:, product:)
          if field_bundle.fetch(:model_values).empty?
            return(
              "The invoice was classified as a heat pump water heater upgrade, but the GenAI located fields did not include a usable model number or model-component value. " \
                "This warning means the code rule could not perform the NEEA product-list lookup. " \
                "Admin should check the invoice and supporting documents for the heat pump water heater manufacturer and model number. " \
                "If the model is present but was missed, rerun GenAI after improving the source document or ruleset prompt. " \
                "If no model evidence is available, the contractor may need to provide product-list support."
            )
          end

          unless current_neea_products_available?
            return(
              "The invoice provided heat pump water heater model evidence, but there are no current imported NEEA product-list rows available for code to search. " \
                "This is an information-on-record problem, not a model judgment about the invoice. " \
                "Admin should refresh the NEEA product-list download and confirm the import succeeds. " \
                "After a successful import, rerun GenAI/code checks for this invoice version. " \
                "Until the source list is loaded, code cannot confirm the NEEA product-list requirement."
            )
          end

          if product
            return(
              "The invoice heat pump water heater model evidence was found in the current imported NEEA Residential HPWH Qualified Products List. " \
                "The stored invoice version now points to the exact imported NEEA product-list row used for this check. " \
                "This is a code-owned pass because the match was made against local information on record, not by model judgment. " \
                "Admins can inspect the matched row values, including brand, model, configuration, volume, tier, and qualification date. " \
                "No follow-up is required for the basic NEEA product-list match unless the visible invoice equipment appears inconsistent with the matched row."
            )
          end

          "The invoice provided heat pump water heater model evidence, but code did not find a matching row in the current imported NEEA Residential HPWH Qualified Products List. " \
            "This warning does not prove the product is ineligible; it means the local imported list could not confirm the match. " \
            "Admin should verify whether the manufacturer and model were read correctly and whether the current NEEA PDF has been imported. " \
            "If the list is stale or missing, refresh the NEEA product-list configuration and rerun GenAI/code checks. " \
            "If the list is current and the model still does not match, ask the contractor for corrected product evidence or NEEA listing support."
        end

        def tier_reason_text(product:, tier:, passed:)
          if passed
            return(
              "The matched NEEA product-list row shows an effective tier of #{tier}, which satisfies the Tier 2 or higher threshold. " \
                "The effective tier is calculated from the available indoor/outdoor tier values on the imported product-list row. " \
                "The imported row evidence is #{product_evidence(product)}. " \
                "This is a code-owned pass because the comparison is simple numeric threshold logic against the matched NEEA row. " \
                "No follow-up is required for the NEEA tier threshold if the product-list match is correct."
            )
          end

          "The matched NEEA product-list row shows an effective tier of #{tier}, which is below the Tier 2 or higher threshold. " \
            "The effective tier is calculated from the available indoor/outdoor tier values on the imported product-list row. " \
            "The imported row evidence is #{product_evidence(product)}. " \
            "Because a product row was matched and the tier value is available, code can make a deterministic fail decision. " \
            "Admin should confirm the invoice model and matched NEEA row are the correct installed equipment before asking the contractor for corrected product evidence."
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
              if field_bundle.fetch(:manufacturer_values).any?
                "manufacturer=#{field_bundle.fetch(:manufacturer_values).join(" / ")}"
              end
            ),
            (
              if field_bundle.fetch(:model_values).any?
                "model=#{field_bundle.fetch(:model_values).join(" / ")}"
              end
            )
          ].compact.join("; ")
        end

        def product_evidence(product)
          [
            product.brand,
            product.model_number,
            (
              if product.storage_volume_gallons.present?
                "#{format_decimal(product.storage_volume_gallons)} gallons"
              end
            ),
            (
              if product.configuration.present?
                "configuration #{product.configuration}"
              end
            ),
            (
              if product.indoor_tier.present?
                "indoor tier #{product.indoor_tier}"
              end
            ),
            (
              if product.outdoor_tier.present?
                "outdoor tier #{product.outdoor_tier}"
              end
            ),
            (
              if product.qualified_date.present?
                "qualified #{product.qualified_date}"
              end
            ),
            (
              if product.import_run&.neea_source&.description.present?
                "source #{product.import_run&.neea_source&.description}"
              end
            )
          ].compact_blank.join("; ")
        end

        def current_neea_products_available?
          ::Claims::CurrentNeeaProduct.exists?
        end

        def effective_tier(product)
          [product.indoor_tier, product.outdoor_tier].compact.max
        end

        def normalize_text(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]+/, " ").squish.presence
        end

        def strict_model_key(value)
          value.to_s.upcase.gsub(/\s+/, "").presence
        end

        def loose_model_key(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]/, "").presence
        end

        def format_decimal(value)
          return nil if value.blank?

          decimal = BigDecimal(value.to_s)
          decimal.frac.zero? ? decimal.to_i.to_s : decimal.to_s("F")
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
