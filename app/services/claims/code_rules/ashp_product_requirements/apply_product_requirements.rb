# frozen_string_literal: true

module Claims
  module CodeRules
    module AshpProductRequirements
      class ApplyProductRequirements
        ELECTRIC_UPGRADE_TYPE_KEY = "air_source_heat_pump_electric"
        WOOD_UPGRADE_TYPE_KEY = "air_source_heat_pump_wood"
        GAS_PROPANE_UPGRADE_TYPE_KEY = "air_source_heat_pump_gas_propane"
        OIL_UPGRADE_TYPE_KEY = "air_source_heat_pump_oil"
        ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY = "ashp_upgrade_line_amount"
        REBATE_FIELD_KEY = "upgrade_specific_rebate_line_amount"
        EQUIPMENT_TYPE_FIELD_KEY = "hp_new_equipment_type"
        EFFICIENCY_AND_CAPACITY_FIELD_KEY = "hp_efficiency_and_capacity"
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

        REBATE_CAP_UPGRADE_TYPE_KEYS = [
          ELECTRIC_UPGRADE_TYPE_KEY,
          WOOD_UPGRADE_TYPE_KEY
        ].freeze
        AHRI_PRODUCT_UPGRADE_TYPE_KEYS = [
          ELECTRIC_UPGRADE_TYPE_KEY,
          WOOD_UPGRADE_TYPE_KEY,
          GAS_PROPANE_UPGRADE_TYPE_KEY
        ].freeze
        OHPA_PRODUCT_UPGRADE_TYPE_KEYS = [OIL_UPGRADE_TYPE_KEY].freeze
        PRODUCT_SPEC_UPGRADE_TYPE_KEYS =
          (
            AHRI_PRODUCT_UPGRADE_TYPE_KEYS + OHPA_PRODUCT_UPGRADE_TYPE_KEYS
          ).freeze
        MULTISPLIT_UPGRADE_TYPE_KEYS = PRODUCT_SPEC_UPGRADE_TYPE_KEYS

        RULES = {
          rebate_cap: {
            key: "ashp_electric_wood_rebate_math_within_cap"
          },
          product_specs: {
            key: "ashp_product_specs_meet_requirements"
          },
          multisplit_heads: {
            key: "ashp_multisplit_minimum_two_indoor_heads"
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

          product = matched_product
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
          RULES.select do |_rule_type, rule|
            applicable_rule_for_upgrade_type?(_rule_type) &&
              ::Claims::CodeRules::Registry.enabled_for?(
                code_rule_key: rule.fetch(:key),
                invoice_upgrade_type_id: upgrade_type.id,
                fallback: false
              )
          end
        end

        def applicable_rule_for_upgrade_type?(rule_type)
          case rule_type
          when :rebate_cap
            REBATE_CAP_UPGRADE_TYPE_KEYS.include?(upgrade_type.upgrade_type_key)
          when :product_specs
            PRODUCT_SPEC_UPGRADE_TYPE_KEYS.include?(
              upgrade_type.upgrade_type_key
            )
          when :multisplit_heads
            MULTISPLIT_UPGRADE_TYPE_KEYS.include?(upgrade_type.upgrade_type_key)
          else
            false
          end
        end

        def ahri_backed_upgrade_type?
          AHRI_PRODUCT_UPGRADE_TYPE_KEYS.include?(upgrade_type.upgrade_type_key)
        end

        def ohpa_backed_upgrade_type?
          OHPA_PRODUCT_UPGRADE_TYPE_KEYS.include?(upgrade_type.upgrade_type_key)
        end

        def matched_product
          return matched_ahri_product if ahri_backed_upgrade_type?
          return matched_ohpa_product if ohpa_backed_upgrade_type?

          nil
        end

        def matched_ahri_product
          invoice_version.ahri_product
        end

        def matched_ohpa_product
          invoice_version.ohpa_product
        end

        def source_product_label(product)
          case product
          when ::Claims::OhpaProduct
            "OHPA product row"
          else
            "AHRI product row"
          end
        end

        def source_product_pointer
          if ohpa_backed_upgrade_type?
            "invoice_versions.ohpa_product_id"
          else
            "invoice_versions.ahri_product_id"
          end
        end

        def capacity_value(product)
          if product.respond_to?(:rated_capacity_btu_at_minus_5c)
            return product.rated_capacity_btu_at_minus_5c
          end
          if product.respond_to?(:rated_capacity_47f)
            return product.rated_capacity_47f
          end

          nil
        end

        def legacy_seer_value(product)
          product.seer if product.respond_to?(:seer)
        end

        def legacy_hspf_value(product)
          product.hspf if product.respond_to?(:hspf)
        end

        def current_seer2_value(product)
          product.seer2 if product.respond_to?(:seer2)
        end

        def current_hspf2_value(product)
          if product.respond_to?(:hspf2)
            product.hspf2
          elsif product.respond_to?(:hspf2_region_iv)
            product.hspf2_region_iv
          end
        end

        def product_value(product, method_name)
          product.public_send(method_name) if product.respond_to?(method_name)
        end

        def source_product_description(product)
          if product.respond_to?(:import_run) &&
               product.import_run.respond_to?(:ahri_source)
            return product.import_run.ahri_source&.description.to_s
          end
          if product.respond_to?(:import_run) &&
               product.import_run.respond_to?(:ohpa_source)
            return product.import_run.ohpa_source&.description.to_s
          end

          ""
        end

        def source_product_reference(product)
          table_name =
            case product
            when ::Claims::OhpaProduct
              "ohpa_products"
            else
              "ahri_products"
            end
          "#{table_name}.id=#{product.id}"
        end

        def product_list_name(product)
          case product
          when ::Claims::OhpaProduct
            "NRCan Oil to Heat Pump Affordability BC qualified product list"
          else
            "BC Hydro heat-pump product list"
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
            warnings << "income level #{income_level} has no electric/wood ASHP rebate cap"
          end

          if rebate_amount && cap && rebate_amount > cap
            failures << "rebate #{money(rebate_amount)} exceeds cap #{money(cap)}"
          end

          if rebate_amount && upgrade_amount && rebate_amount > upgrade_amount
            failures << "rebate #{money(rebate_amount)} exceeds ASHP upgrade amount #{money(upgrade_amount)}"
          end

          if rebate_amount&.positive? && income_level == 3
            failures << "income level 3 has no electric/wood ASHP rebate cap"
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
              "For ASHP convert-from-electric/wood, the claimed rebate must be no more than 100% of the eligible ASHP upgrade cost and no more than the Income Level 1/2 maximum shown in the requirements table.",
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
                  "The matched AHRI/OHPA product row should show capacity of at least 12,000 BTU, qualifying SEER/HSPF or SEER2/HSPF2 values, and variable-speed compressor evidence."
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
              "Ductless mini-split, ductless multi-split, and central ducted ASHPs must meet the SEER/HSPF or SEER2/HSPF2 threshold, use a variable speed compressor, and have minimum capacity of 12,000 BTU.",
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
                  "Ductless multi-split ASHPs must install a minimum of two indoor head units.",
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
                  "Ductless multi-split ASHPs must install a minimum of two indoor head units.",
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
                  "Ductless multi-split ASHPs must install a minimum of two indoor head units.",
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
              "Ductless multi-split ASHPs must install a minimum of two indoor head units.",
            calculation:
              "identified_as_multisplit=true; indoor_head_count=(not explicitly visible); product_source=#{source_product_description(product).presence || "(missing)"}",
            evidence_text:
              field_evidence(equipment_type_field) || product_evidence(product),
            reason_and_likely_causes:
              if product_multisplit_source?(product)
                "The matched product-list source is the ductless multi-split list, so code treats the product-list bucket as satisfying the multi-split indoor-head requirement."
              else
                "The invoice evidence identifies a multi-split heat pump, but code could not find a named field value with the number of indoor head units. Admin should verify the invoice equipment section."
              end
          )
        end

        def capacity_evaluation(product)
          capacity = capacity_value(product)

          if !metric_present?(capacity)
            return(
              {
                result: "warn",
                calculation:
                  "capacity=#{format_decimal(capacity) || "(missing)"}; required_minimum=12000 BTU",
                reason:
                  "The #{source_product_label(product)} does not provide a usable capacity value."
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
                "The #{source_product_label(product)} meets the 12,000 BTU minimum capacity requirement."
              else
                "The #{source_product_label(product)} is below the 12,000 BTU minimum capacity requirement."
              end
          }
        end

        def efficiency_evaluation(product)
          legacy_complete =
            metric_present?(legacy_seer_value(product)) &&
              metric_present?(legacy_hspf_value(product))
          current_complete =
            metric_present?(current_seer2_value(product)) &&
              metric_present?(current_hspf2_value(product))
          legacy_pass =
            legacy_complete && legacy_seer_value(product) >= MIN_SEER &&
              legacy_hspf_value(product) >= MIN_HSPF
          current_pass =
            current_complete && current_seer2_value(product) >= MIN_SEER2 &&
              current_hspf2_value(product) >= MIN_HSPF2

          if !legacy_complete && !current_complete
            return(
              {
                result: "warn",
                calculation:
                  "SEER/HSPF pair=(incomplete); SEER2/HSPF2 pair=(incomplete)",
                reason:
                  "The #{source_product_label(product)} does not provide one complete efficiency pair for threshold comparison."
              }
            )
          end

          {
            result: legacy_pass || current_pass ? "pass" : "fail",
            calculation: efficiency_calculation_text(product),
            reason:
              if legacy_pass || current_pass
                "The #{source_product_label(product)} meets one allowed efficiency threshold path."
              else
                "The #{source_product_label(product)} does not meet either allowed efficiency threshold path."
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
          source_product_description(product).match?(
            /\bductless\s+multi[- ]split\b/i
          )
        end

        def equipment_context_text(product)
          [
            equipment_type_field&.value_text,
            equipment_type_field&.evidence_text,
            source_product_description(product),
            product_value(product, :heat_pump_type),
            product_value(product, :indoor_model_or_air_handler),
            product_value(product, :indoor_model_numbers),
            product_value(product, :ducting_configuration),
            product_value(product, :product_group),
            product_value(product, :ahri_type)
          ].compact.join(" ")
        end

        def variable_speed_context_text(product)
          [
            efficiency_and_capacity_field&.value_text,
            efficiency_and_capacity_field&.evidence_text,
            equipment_type_field&.value_text,
            product_value(product, :heat_pump_type),
            product_value(product, :ducting_configuration),
            product_value(product, :product_group),
            product_value(product, :ahri_type),
            product_value(product, :eligibility_notes),
            product_value(product, :raw_row_json)
          ].compact.join(" ")
        end

        def rebate_cap_reason_text(result:, failures:, warnings:)
          case result
          when "pass"
            "The named rebate, ASHP upgrade amount, and income-level cap are all present, and the rebate is no greater than the eligible ASHP upgrade amount or the Income Level cap."
          when "fail"
            "The deterministic ASHP electric/wood rebate comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the ASHP electric/wood rebate comparison because #{warnings.join("; ")}. Admin should verify the invoice line amount, rebate line, and matched eligibility code."
          end
        end

        def product_specs_reason_text(result:, evaluations:)
          details =
            evaluations.map { |evaluation| evaluation.fetch(:reason) }.join(" ")
          case result
          when "pass"
            "The matched product row and named field evidence satisfy the ASHP product specification checks. #{details}"
          when "fail"
            "One or more ASHP product specification checks failed. #{details}"
          else
            "One or more ASHP product specification checks could not be completed from the named fields/product row. #{details}"
          end
        end

        def dependent_info_row(rule:, expected_text:)
          base_rulecheck_row(
            rule: rule,
            rule_result: "info",
            confidence: 0,
            expected_text: expected_text,
            calculation:
              "No matched product row was available from #{source_product_pointer}.",
            evidence_text: nil,
            reason_and_likely_causes:
              "This ASHP product-spec rule depends on the product-list match. The product-list rule records whether the invoice AHRI reference was missing, not found, or matched; this dependent metric check is informational until that match exists."
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
            source_product_reference(product),
            product_list_name(product),
            source_product_description(product),
            product_value(product, :make),
            product_value(product, :brand),
            product_value(product, :outdoor_model),
            product_value(product, :model_number),
            product_value(product, :indoor_model_or_air_handler),
            product_value(product, :indoor_model_numbers),
            product_value(product, :furnace_model),
            product_value(product, :furnace_model_number),
            "capacity #{format_decimal(capacity_value(product))} BTU",
            efficiency_metric_summary(product)
          ].compact_blank.join("; ")
        end

        def efficiency_metric_summary(product)
          [
            (
              if metric_present?(legacy_seer_value(product))
                "SEER #{format_decimal(legacy_seer_value(product))}"
              end
            ),
            (
              if metric_present?(legacy_hspf_value(product))
                "HSPF #{format_decimal(legacy_hspf_value(product))}"
              end
            ),
            (
              if metric_present?(current_seer2_value(product))
                "SEER2 #{format_decimal(current_seer2_value(product))}"
              end
            ),
            (
              if metric_present?(current_hspf2_value(product))
                "HSPF2 #{format_decimal(current_hspf2_value(product))}"
              end
            )
          ].compact.join(", ")
        end

        def efficiency_calculation_text(product)
          legacy =
            if metric_present?(legacy_seer_value(product)) ||
                 metric_present?(legacy_hspf_value(product))
              "SEER #{format_decimal(legacy_seer_value(product))} / HSPF #{format_decimal(legacy_hspf_value(product))} versus SEER >= 16.0 and HSPF >= 10.0"
            else
              "SEER/HSPF pair not provided"
            end

          current =
            if metric_present?(current_seer2_value(product)) ||
                 metric_present?(current_hspf2_value(product))
              "SEER2 #{format_decimal(current_seer2_value(product))} / HSPF2 #{format_decimal(current_hspf2_value(product))} versus SEER2 >= 15.2 and HSPF2 >= 8.5"
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
      end
    end
  end
end
