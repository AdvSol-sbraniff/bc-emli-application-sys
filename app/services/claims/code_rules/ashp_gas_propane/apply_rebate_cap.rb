# frozen_string_literal: true

module Claims
  module CodeRules
    module AshpGasPropane
      class ApplyRebateCap
        GAS_PROPANE_UPGRADE_TYPE_KEY = "air_source_heat_pump_gas_propane"
        ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY = "ashp_upgrade_line_amount"
        REBATE_FIELD_KEY = "upgrade_specific_rebate_line_amount"
        EQUIPMENT_TYPE_FIELD_KEY = "hp_new_equipment_type"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"

        BASE_CAPS_BY_CATEGORY = {
          single_head_minisplit: {
            1 => BigDecimal("7500"),
            2 => BigDecimal("5500"),
            3 => BigDecimal("4000")
          },
          two_head_or_two_single_head: {
            1 => BigDecimal("14000"),
            2 => BigDecimal("10500"),
            3 => BigDecimal("8000")
          },
          central_ducted_or_three_head: {
            1 => BigDecimal("16000"),
            2 => BigDecimal("12000"),
            3 => BigDecimal("10500")
          }
        }.freeze

        RULE = { key: "ashp_gas_propane_rebate_math_within_cap" }.freeze

        def self.call(invoice_version_id:, invoice_upgrade_type_id:)
          new(
            invoice_version_id: invoice_version_id,
            invoice_upgrade_type_id: invoice_upgrade_type_id
          ).call
        end

        def self.implemented_rule_keys
          [RULE.fetch(:key)]
        end

        def initialize(invoice_version_id:, invoice_upgrade_type_id:)
          @invoice_version_id = invoice_version_id
          @invoice_upgrade_type_id = invoice_upgrade_type_id
        end

        def call
          @invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)
          @upgrade_type =
            ::Claims::InvoiceUpgradeType.find(@invoice_upgrade_type_id)

          return { ok: true, skipped: true } unless enabled_for_upgrade_type?

          row = rulecheck_row
          replace_rulechecks!([row])

          { ok: true, skipped: false, rule_result: row.fetch(:rule_result) }
        rescue => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_for_upgrade_type?
          unless upgrade_type.upgrade_type_key == GAS_PROPANE_UPGRADE_TYPE_KEY
            return false
          end

          ::Claims::CodeRules::Registry.enabled_for?(
            code_rule_key: RULE.fetch(:key),
            invoice_upgrade_type_id: upgrade_type.id,
            fallback: false
          )
        end

        def rulecheck_row
          now = Time.current
          rule_result, confidence, calculation, evidence_text, reason_text =
            rebate_cap_evaluation

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULE.fetch(:key),
            rule_result: rule_result,
            confidence: confidence,
            expected_text:
              "For ASHP convert-from-natural-gas/propane, the claimed base rebate must be no more than 100% of the eligible ASHP upgrade cost and no more than the equipment-category maximum for the matched income level.",
            calculation: calculation,
            evidence_text: evidence_text,
            reason_and_likely_causes:
              append_admin_message(
                rule_result: rule_result,
                reason_text: reason_text
              ),
            created_at: now,
            updated_at: now
          }
        end

        def rebate_cap_evaluation
          rebate_amount = decimal_from_field(rebate_field)
          upgrade_amount = decimal_from_field(ashp_upgrade_line_amount_field)
          income_level = parsed_income_level
          category = equipment_category
          cap = category_cap(category, income_level)
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
          if category == :unknown
            warnings << "#{EQUIPMENT_TYPE_FIELD_KEY} does not clearly classify the base rebate category"
          end

          if rebate_amount && cap && rebate_amount > cap
            failures << "rebate #{money(rebate_amount)} exceeds #{category_label(category)} cap #{money(cap)}"
          end

          if rebate_amount && upgrade_amount && rebate_amount > upgrade_amount
            failures << "rebate #{money(rebate_amount)} exceeds ASHP upgrade amount #{money(upgrade_amount)}"
          end

          result =
            if failures.any?
              "fail"
            elsif warnings.any?
              "warn"
            else
              "pass"
            end

          [
            result,
            result == "warn" ? 0 : 100,
            [
              "#{REBATE_FIELD_KEY}=#{money(rebate_amount) || "(missing)"}",
              "#{ASHP_UPGRADE_LINE_AMOUNT_FIELD_KEY}=#{money(upgrade_amount) || "(missing)"}",
              "income_level=#{income_level || "(missing)"}",
              "equipment_category=#{category_label(category)}",
              "cap=#{money(cap) || "(missing)"}",
              "northern_top_up_excluded=true"
            ].join("; "),
            field_evidence(
              rebate_field,
              ashp_upgrade_line_amount_field,
              equipment_type_field,
              income_level_field
            ),
            rebate_cap_reason_text(
              result: result,
              failures: failures,
              warnings: warnings
            )
          ]
        end

        def equipment_category
          text = field_text(equipment_type_field)
          return :unknown if text.blank?

          if text.match?(
               /\b(central\s+ducted|central\s+system|3[- ]?head|three[- ]?head|3\s+or\s+more\s+zones?|three\s+or\s+more\s+zones?|3\s+or\s+more\s+supply\s+outlets?|three\s+or\s+more\s+supply\s+outlets?|mixed\s+ducted\s+and\s+ductless)\b/i
             )
            return :central_ducted_or_three_head
          end

          if text.match?(
               /\b(2[- ]?head|two[- ]?head|2\s+single[- ]head|two\s+single[- ]head|low\s+static(?:\s+pressure)?\s+ducted\s+mini(?:[- ]split)?(?:[^.;]*\btwo\s+supply\s+outlets?)?)\b/i
             )
            return :two_head_or_two_single_head
          end

          if text.match?(/\b(single[- ]head|one[- ]head|1[- ]head)\b/i)
            return :single_head_minisplit
          end

          :unknown
        end

        def category_cap(category, income_level)
          return nil unless income_level

          BASE_CAPS_BY_CATEGORY.fetch(category, {})[income_level]
        end

        def category_label(category)
          case category
          when :single_head_minisplit
            "single-head mini-split"
          when :two_head_or_two_single_head
            "2-head multi-split or 2 single-head mini-split"
          when :central_ducted_or_three_head
            "central ducted or 3-head multi-split"
          else
            "unknown"
          end
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

        def field_text(field)
          [field&.value_text, field&.evidence_text].compact.join(" ")
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

        def rebate_cap_reason_text(result:, failures:, warnings:)
          case result
          when "pass"
            "The named rebate, ASHP upgrade amount, equipment category, and income-level cap are all present, and the rebate is no greater than the eligible ASHP upgrade amount or the base rebate cap. Northern top-up is intentionally excluded and checked by ashp_fossil_northern_top_up_within_cap."
          when "fail"
            "The deterministic gas/propane ASHP base rebate comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the gas/propane ASHP base rebate comparison because #{warnings.join("; ")}. Admin should verify the invoice rebate line, ASHP line amount, equipment category, and matched eligibility code."
          end
        end

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.transaction do
            ::Claims::InvoiceVersionRulecheck.where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "code",
              rule_key: RULE.fetch(:key)
            ).delete_all

            ::Claims::InvoiceVersionRulecheck.insert_all!(rows)
          end
        end

        def append_admin_message(rule_result:, reason_text:)
          message =
            ::Claims::CodeRules::Registry.admin_message(
              code_rule_key: RULE.fetch(:key),
              rule_result: rule_result
            )
          return reason_text if message.blank?

          "#{reason_text}\n\nAdmin guidance: #{message}"
        end

        def money(value)
          return nil if value.nil?

          "$#{format_decimal(value)}"
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
