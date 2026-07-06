# frozen_string_literal: true

module Claims
  module CodeRules
    module AshpElectric
      class ApplyProductRequirements
        ELECTRIC_UPGRADE_TYPE_KEY = "air_source_heat_pump_electric"
        ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY = "ashp_upgrade_line_amount"
        REBATE_FIELD_KEY = "upgrade_specific_rebate_line_amount"
        EQUIPMENT_TYPE_FIELD_KEY = "hp_new_equipment_type"
        EFFICIENCY_AND_CAPACITY_FIELD_KEY = "hp_efficiency_and_capacity"
        INVOICE_AHRI_FIELD_KEY = "classifier.ahri_reference"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"

        ESP_CAP_BY_INCOME_LEVEL = {
          1 => BigDecimal("5000"),
          2 => BigDecimal("4000")
        }.freeze

        MIN_CAPACITY_BTU = BigDecimal("12000")
        MIN_SEER = BigDecimal("16.0")
        MIN_HSPF = BigDecimal("10.0")
        MIN_SEER2 = BigDecimal("15.2")
        MIN_HSPF2 = BigDecimal("8.5")
        MIN_MULTISPLIT_HEADS = 2

        RULES = {
          rebate_cap: {
            number: 4,
            key: "ashp_electric_rebate_math_within_cap"
          },
          product_specs: {
            number: 5,
            key: "ashp_electric_product_specs_meet_requirements"
          },
          multisplit_heads: {
            number: 6,
            key: "ashp_electric_multisplit_minimum_two_indoor_heads"
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

          product = matched_ahri_product
          rows = rulecheck_rows(enabled_rules: enabled_rules, product: product)
          replace_rulechecks!(rows)

          {
            ok: true,
            skipped: false,
            matched: product.present?,
            rulechecks: rows.size
          }
        rescue => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_rules_for_upgrade_type
          unless upgrade_type.upgrade_type_key == ELECTRIC_UPGRADE_TYPE_KEY
            return {}
          end

          RULES.select do |_rule_type, rule|
            ::Claims::CodeRules::Registry.enabled_for?(
              code_rule_key: rule.fetch(:key),
              invoice_upgrade_type_id: upgrade_type.id,
              fallback: false
            )
          end
        end

        def rulecheck_rows(enabled_rules:, product:)
          [
            (rebate_cap_row if enabled_rules.key?(:rebate_cap)),
            (
              if enabled_rules.key?(:product_specs)
                product_specs_row(product: product)
              end
            ),
            (
              if enabled_rules.key?(:multisplit_heads)
                multisplit_heads_row(product: product)
              end
            )
          ].compact
        end

        def rebate_cap_row
          rebate_amount = decimal_from_field(rebate_field)
          upgrade_amount = decimal_from_field(ashp_upgrade_line_amount_field)
          income_level = parsed_income_level
          cap = income_level && ESP_CAP_BY_INCOME_LEVEL[income_level]
          failures = []
          warnings = []

          if rebate_amount.nil?
            warnings << "#{REBATE_FIELD_KEY} is missing or not numeric"
          end
          if upgrade_amount.nil?
            warnings << "#{ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY} is missing or not numeric"
          end
          if income_level.nil?
            warnings << "income level is missing or not ESP1/ESP2/ESP3"
          end
          if income_level == 3
            warnings << "income level #{income_level} has no electric ASHP rebate cap"
          end

          if rebate_amount && cap && rebate_amount > cap
            failures << "rebate #{money(rebate_amount)} exceeds cap #{money(cap)}"
          end

          if rebate_amount && upgrade_amount && rebate_amount > upgrade_amount
            failures << "rebate #{money(rebate_amount)} exceeds ASHP upgrade amount #{money(upgrade_amount)}"
          end

          if rebate_amount&.positive? && income_level == 3
            failures << "income level 3 has no electric-to-ASHP rebate cap"
          end

          result =
            if failures.any?
              "fail"
            elsif warnings.any?
              "warn"
            else
              "pass"
            end

          base_rulecheck_row(
            rule: RULES.fetch(:rebate_cap),
            rule_result: result,
            confidence: result == "pass" || result == "fail" ? 100 : 0,
            expected_text:
              "For ASHP convert-from-electric, the claimed rebate must be no more than 100% of the eligible ASHP upgrade cost and no more than the Income Level 1/2 maximum shown in the requirements table.",
            calculation: [
              "#{REBATE_FIELD_KEY}=#{money(rebate_amount) || "(missing)"}",
              "#{ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY}=#{money(upgrade_amount) || "(missing)"}",
              "income_level=#{income_level || "(missing)"}",
              "cap=#{money(cap) || "(none)"}"
            ].join("; "),
            evidence_text:
              field_evidence(
                rebate_field,
                ashp_upgrade_line_amount_field,
                income_level_field
              ),
            reason_and_likely_causes:
              rebate_cap_reason_text(
                result: result,
                failures: failures,
                warnings: warnings
              )
          )
        end

        def product_specs_row(product:)
          unless product
            return(
              dependent_info_row(
                rule: RULES.fetch(:product_specs),
                expected_text:
                  "The matched AHRI product row should show capacity of at least 12,000 BTU, qualifying SEER/HSPF or SEER2/HSPF2 values, and variable-speed compressor evidence."
              )
            )
          end

          capacity_result = capacity_evaluation(product)
          efficiency_result = efficiency_evaluation(product)
          variable_speed_result = variable_speed_evaluation(product)
          evaluations = [
            capacity_result,
            efficiency_result,
            variable_speed_result
          ]
          result = combined_result(evaluations)

          base_rulecheck_row(
            rule: RULES.fetch(:product_specs),
            rule_result: result,
            confidence: result == "pass" || result == "fail" ? 100 : 0,
            expected_text:
              "Ductless mini-split, ductless multi-split, and central ducted heat pumps in the ASHP convert-from-electric table must meet the SEER/HSPF or SEER2/HSPF2 threshold, use a variable speed compressor, and have minimum capacity of 12,000 BTU.",
            calculation:
              evaluations
                .map { |evaluation| evaluation.fetch(:calculation) }
                .join("; "),
            evidence_text: [
              product_evidence(product),
              field_evidence(efficiency_and_capacity_field)
            ].compact_blank.join("; "),
            reason_and_likely_causes:
              product_specs_reason_text(
                result: result,
                evaluations: evaluations
              )
          )
        end

        def multisplit_heads_row(product:)
          equipment_text = equipment_context_text(product)
          multisplit = multisplit_evidence?(equipment_text)
          head_count = indoor_head_count(equipment_text)

          if !multisplit
            return(
              base_rulecheck_row(
                rule: RULES.fetch(:multisplit_heads),
                rule_result: "pass",
                confidence: 100,
                expected_text:
                  "Ductless multi-split heat pumps in the ASHP convert-from-electric table must install a minimum of two indoor head units.",
                calculation:
                  "hp_new_equipment_type/product source does not identify this ASHP as a ductless multi-split.",
                evidence_text:
                  field_evidence(equipment_type_field) ||
                    product_evidence(product),
                reason_and_likely_causes:
                  "The multi-split-specific indoor-head requirement does not apply because the named equipment evidence does not identify a ductless multi-split heat pump."
              )
            )
          end

          if head_count && head_count < MIN_MULTISPLIT_HEADS
            return(
              base_rulecheck_row(
                rule: RULES.fetch(:multisplit_heads),
                rule_result: "fail",
                confidence: 100,
                expected_text:
                  "Ductless multi-split heat pumps in the ASHP convert-from-electric table must install a minimum of two indoor head units.",
                calculation:
                  "identified_as_multisplit=true; indoor_head_count=#{head_count}; required_minimum=#{MIN_MULTISPLIT_HEADS}.",
                evidence_text:
                  field_evidence(equipment_type_field) ||
                    product_evidence(product),
                reason_and_likely_causes:
                  "The invoice/product evidence identifies a ductless multi-split heat pump, but the visible indoor-head count is below the two-head minimum."
              )
            )
          end

          if head_count && head_count >= MIN_MULTISPLIT_HEADS
            return(
              base_rulecheck_row(
                rule: RULES.fetch(:multisplit_heads),
                rule_result: "pass",
                confidence: 100,
                expected_text:
                  "Ductless multi-split heat pumps in the ASHP convert-from-electric table must install a minimum of two indoor head units.",
                calculation:
                  "identified_as_multisplit=true; indoor_head_count=#{head_count}; required_minimum=#{MIN_MULTISPLIT_HEADS}.",
                evidence_text:
                  field_evidence(equipment_type_field) ||
                    product_evidence(product),
                reason_and_likely_causes:
                  "The named equipment evidence identifies a ductless multi-split heat pump and shows at least two indoor head units."
              )
            )
          end

          base_rulecheck_row(
            rule: RULES.fetch(:multisplit_heads),
            rule_result: product_multisplit_source?(product) ? "pass" : "warn",
            confidence: product_multisplit_source?(product) ? 100 : 0,
            expected_text:
              "Ductless multi-split heat pumps in the ASHP convert-from-electric table must install a minimum of two indoor head units.",
            calculation:
              "identified_as_multisplit=true; indoor_head_count=(not explicitly visible); product_source=#{product_source_description(product).presence || "(missing)"}",
            evidence_text:
              field_evidence(equipment_type_field) || product_evidence(product),
            reason_and_likely_causes:
              if product_multisplit_source?(product)
                "The matched AHRI product-list source is the ductless multi-split list, so code treats the product-list bucket as satisfying the multi-split indoor-head requirement."
              else
                "The invoice evidence identifies a multi-split heat pump, but code could not find a named field value with the number of indoor head units. Admin should verify the invoice equipment section."
              end
          )
        end

        def capacity_evaluation(product)
          capacity = product.rated_capacity_btu_at_minus_5c

          if !metric_present?(capacity)
            return(
              {
                result: "warn",
                calculation:
                  "capacity=#{format_decimal(capacity) || "(missing)"}; required_minimum=12000 BTU",
                reason:
                  "The AHRI product row does not provide a usable capacity value."
              }
            )
          end

          passed = BigDecimal(capacity.to_s) >= MIN_CAPACITY_BTU
          {
            result: passed ? "pass" : "fail",
            calculation:
              "capacity=#{format_decimal(capacity)} BTU; required_minimum=12000 BTU",
            reason:
              if passed
                "The AHRI product row meets the 12,000 BTU minimum capacity requirement."
              else
                "The AHRI product row is below the 12,000 BTU minimum capacity requirement."
              end
          }
        end

        def efficiency_evaluation(product)
          legacy_complete =
            metric_present?(product.seer) && metric_present?(product.hspf)
          current_complete =
            metric_present?(product.seer2) && metric_present?(product.hspf2)
          legacy_pass =
            legacy_complete && product.seer >= MIN_SEER &&
              product.hspf >= MIN_HSPF
          current_pass =
            current_complete && product.seer2 >= MIN_SEER2 &&
              product.hspf2 >= MIN_HSPF2

          if !legacy_complete && !current_complete
            return(
              {
                result: "warn",
                calculation:
                  "SEER/HSPF pair=(incomplete); SEER2/HSPF2 pair=(incomplete)",
                reason:
                  "The AHRI product row does not provide one complete efficiency pair for threshold comparison."
              }
            )
          end

          {
            result: legacy_pass || current_pass ? "pass" : "fail",
            calculation: efficiency_calculation_text(product),
            reason:
              if legacy_pass || current_pass
                "The AHRI product row meets one allowed efficiency threshold path."
              else
                "The AHRI product row does not meet either allowed efficiency threshold path."
              end
          }
        end

        def variable_speed_evaluation(product)
          text = variable_speed_context_text(product)

          if text.match?(/\b(single[- ]stage|fixed[- ]speed|not variable)\b/i)
            return(
              {
                result: "fail",
                calculation: "variable_speed_evidence=contradicted",
                reason:
                  "The named evidence appears to contradict the variable-speed compressor requirement."
              }
            )
          end

          if text.match?(
               /\b(variable[- ]speed|variable[- ]capacity|inverter)\b/i
             )
            return(
              {
                result: "pass",
                calculation: "variable_speed_evidence=present",
                reason:
                  "The named evidence supports a variable-speed compressor."
              }
            )
          end

          {
            result: "warn",
            calculation: "variable_speed_evidence=(missing)",
            reason:
              "Code could not find variable-speed compressor wording in the named field evidence or matched product row."
          }
        end

        def combined_result(evaluations)
          if evaluations.any? { |evaluation|
               evaluation.fetch(:result) == "fail"
             }
            return "fail"
          end
          if evaluations.any? { |evaluation|
               evaluation.fetch(:result) == "warn"
             }
            return "warn"
          end

          "pass"
        end

        def matched_ahri_product
          if invoice_version.ahri_product.present?
            return invoice_version.ahri_product
          end

          invoice_ahri = normalized_ahri(invoice_ahri_field&.value_text)
          return nil if invoice_ahri.blank?

          current_match =
            ::Claims::CurrentAhriProduct
              .where(ahri_reference_number: invoice_ahri)
              .order(:source_description, :id)
              .first

          ::Claims::AhriProduct.find_by(id: current_match.id) if current_match
        end

        def ashp_upgrade_line_amount_field
          @ashp_upgrade_line_amount_field ||=
            best_genai_field(ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY)
        end

        def rebate_field
          @rebate_field ||= best_genai_field(REBATE_FIELD_KEY)
        end

        def equipment_type_field
          @equipment_type_field ||= best_genai_field(EQUIPMENT_TYPE_FIELD_KEY)
        end

        def efficiency_and_capacity_field
          @efficiency_and_capacity_field ||=
            best_genai_field(EFFICIENCY_AND_CAPACITY_FIELD_KEY)
        end

        def income_level_field
          @income_level_field ||= best_code_field(INCOME_LEVEL_FIELD_KEY)
        end

        def invoice_ahri_field
          @invoice_ahri_field ||=
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

        def best_genai_field(field_key)
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "genai",
              field_key: field_key
            )
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .first
        end

        def best_code_field(field_key)
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              source_engine: "code",
              field_key: field_key
            )
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .first
        end

        def parsed_income_level
          record_level = invoice_version.users_eligibilitycode&.income_level
          return record_level if [1, 2, 3].include?(record_level)

          field_level = income_level_field&.value_text.to_s.strip
          parsed = Integer(field_level, 10) if field_level.present?
          return parsed if [1, 2, 3].include?(parsed)

          nil
        rescue ArgumentError
          nil
        end

        def decimal_from_field(field)
          decimal_from_text(field&.value_text)
        end

        def decimal_from_text(value)
          text = value.to_s.strip
          return nil if text.blank?

          match = text.match(/-?\$?\s*\d[\d,]*(?:\.\d+)?/)
          return nil unless match

          BigDecimal(match[0].delete("$, "))
        rescue ArgumentError
          nil
        end

        def indoor_head_count(text)
          candidates = []
          text
            .to_s
            .scan(
              /\b(\d+)\s*(?:indoor\s*)?(?:head|heads|zone|zones|supply\s*outlets?)\b/i
            ) { |match| candidates << match.first.to_i }
          text
            .to_s
            .scan(
              /\b(two|three|four|five|six)\s*(?:indoor\s*)?(?:head|heads|zone|zones|supply\s*outlets?)\b/i
            ) { |match| candidates << word_number(match.first) }
          text
            .to_s
            .scan(/\b(\d+)[- ](?:head|zone)\b/i) do |match|
              candidates << match.first.to_i
            end

          candidates.compact.max
        end

        def word_number(value)
          { "two" => 2, "three" => 3, "four" => 4, "five" => 5, "six" => 6 }[
            value.to_s.downcase
          ]
        end

        def multisplit_evidence?(text)
          text.match?(
            /\b(multi[- ]split|multiple[- ]split|multi[- ]head)\b/i
          ) || text.match?(/\bductless\s+multi\b/i)
        end

        def product_multisplit_source?(product)
          product_source_description(product).match?(
            /\bductless\s+multi[- ]split\b/i
          )
        end

        def equipment_context_text(product)
          [
            equipment_type_field&.value_text,
            equipment_type_field&.evidence_text,
            product_source_description(product),
            product&.heat_pump_type,
            product&.indoor_model_or_air_handler
          ].compact.join(" ")
        end

        def variable_speed_context_text(product)
          [
            efficiency_and_capacity_field&.value_text,
            efficiency_and_capacity_field&.evidence_text,
            equipment_type_field&.value_text,
            product&.heat_pump_type,
            product&.eligibility_notes,
            product&.raw_row_json
          ].compact.join(" ")
        end

        def product_source_description(product)
          product&.import_run&.ahri_source&.description.to_s
        end

        def rebate_cap_reason_text(result:, failures:, warnings:)
          case result
          when "pass"
            "The named rebate, ASHP upgrade amount, and income-level cap are all present, and the rebate is no greater than the eligible ASHP upgrade amount or the Income Level cap."
          when "fail"
            "The deterministic ASHP electric rebate comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the ASHP electric rebate comparison because #{warnings.join("; ")}. Admin should verify the invoice line amount, rebate line, and matched eligibility code."
          end
        end

        def product_specs_reason_text(result:, evaluations:)
          details =
            evaluations.map { |evaluation| evaluation.fetch(:reason) }.join(" ")
          case result
          when "pass"
            "The matched AHRI product row and named field evidence satisfy the ASHP electric product specification checks. #{details}"
          when "fail"
            "One or more ASHP electric product specification checks failed. #{details}"
          else
            "One or more ASHP electric product specification checks could not be completed from the named fields/product row. #{details}"
          end
        end

        def dependent_info_row(rule:, expected_text:)
          base_rulecheck_row(
            rule: rule,
            rule_result: "info",
            confidence: 0,
            expected_text: expected_text,
            calculation:
              "No matched AHRI product row was available from invoice_versions.ahri_product_id or classifier.ahri_reference.",
            evidence_text: field_evidence(invoice_ahri_field),
            reason_and_likely_causes:
              "This ASHP electric product-spec rule depends on the AHRI product-list match. The AHRI product-list rule records whether the invoice AHRI reference was missing, not found, or matched; this dependent metric check is informational until that match exists."
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

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.transaction do
            ::Claims::InvoiceVersionRulecheck.where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "code",
              rule_key: RULES.values.map { |rule| rule.fetch(:key) }
            ).delete_all

            ::Claims::InvoiceVersionRulecheck.insert_all!(rows) if rows.any?
          end
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

        def field_evidence(*fields)
          fields
            .compact
            .map do |field|
              text = field.evidence_text.presence || field.value_text.presence
              next if text.blank?

              "#{field.field_key}: #{text}"
            end
            .compact
            .uniq
            .join("; ")
            .presence
        end

        def product_evidence(product)
          return nil unless product

          [
            "AHRI #{product.ahri_reference_number}",
            product_source_description(product),
            product.make,
            product.outdoor_model,
            product.indoor_model_or_air_handler,
            product.furnace_model,
            "capacity #{format_decimal(product.rated_capacity_btu_at_minus_5c)} BTU",
            efficiency_metric_summary(product)
          ].compact_blank.join("; ")
        end

        def efficiency_metric_summary(product)
          [
            (
              if metric_present?(product.seer)
                "SEER #{format_decimal(product.seer)}"
              end
            ),
            (
              if metric_present?(product.hspf)
                "HSPF #{format_decimal(product.hspf)}"
              end
            ),
            (
              if metric_present?(product.seer2)
                "SEER2 #{format_decimal(product.seer2)}"
              end
            ),
            (
              if metric_present?(product.hspf2)
                "HSPF2 #{format_decimal(product.hspf2)}"
              end
            )
          ].compact.join(", ")
        end

        def efficiency_calculation_text(product)
          legacy =
            if metric_present?(product.seer) || metric_present?(product.hspf)
              "SEER #{format_decimal(product.seer)} / HSPF #{format_decimal(product.hspf)} versus SEER >= 16.0 and HSPF >= 10.0"
            else
              "SEER/HSPF pair not provided"
            end

          current =
            if metric_present?(product.seer2) || metric_present?(product.hspf2)
              "SEER2 #{format_decimal(product.seer2)} / HSPF2 #{format_decimal(product.hspf2)} versus SEER2 >= 15.2 and HSPF2 >= 8.5"
            else
              "SEER2/HSPF2 pair not provided"
            end

          "#{legacy}; #{current}"
        end

        def metric_present?(value)
          value.present? && BigDecimal(value.to_s).positive?
        rescue ArgumentError
          false
        end

        def format_decimal(value)
          return nil if value.blank?

          decimal = BigDecimal(value.to_s)
          decimal.frac.zero? ? decimal.to_i.to_s : decimal.to_s("F")
        rescue ArgumentError
          nil
        end

        def money(value)
          return nil if value.nil?

          "$#{format_decimal(value)}"
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
