# frozen_string_literal: true

module Claims
  module CodeRules
    module Dfhp
      class ApplyRebateCap
        DFHP_UPGRADE_TYPE_KEY = "dual_fuel_ducted_heat_pump"
        DFHP_LINE_AMOUNT_FIELD_KEY = "dfhp_line_amount"
        REBATE_FIELD_KEY = "upgrade_specific_rebate_line_amount"
        SOURCE_FUEL_PATH_FIELD_KEY = "dfhp_source_fuel_path"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"

        BASE_CAPS_BY_SOURCE_PATH = {
          png_natural_gas_or_propane: {
            1 => BigDecimal("11500"),
            2 => BigDecimal("6500"),
            3 => BigDecimal("6500")
          },
          tank_propane: {
            1 => BigDecimal("15000"),
            2 => BigDecimal("10000"),
            3 => BigDecimal("10000")
          }
        }.freeze

        RULE = { key: "dfhp_rebate_math_within_cap" }.freeze

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
          unless upgrade_type.upgrade_type_key == DFHP_UPGRADE_TYPE_KEY
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
              "For a dual-fuel ducted heat pump, the claimed base rebate must be no more than 100% of the eligible DFHP upgrade cost and no more than the source-fuel-path maximum for the matched income level.",
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
          upgrade_amount = decimal_from_field(dfhp_line_amount_field)
          income_level = parsed_income_level
          source_path = source_fuel_path
          cap = source_path_cap(source_path, income_level)
          failures = []
          warnings = []

          if rebate_amount.nil?
            warnings << "#{REBATE_FIELD_KEY} is missing or not numeric"
          end
          if upgrade_amount.nil?
            warnings << "#{DFHP_LINE_AMOUNT_FIELD_KEY} is missing or not numeric"
          end
          if income_level.nil?
            warnings << "income level is missing or not ESP1/ESP2/ESP3"
          end
          if source_path == :unknown
            warnings << "#{SOURCE_FUEL_PATH_FIELD_KEY} does not clearly classify the DFHP source-fuel path"
          end

          if rebate_amount && cap && rebate_amount > cap
            failures << "rebate #{money(rebate_amount)} exceeds #{source_path_label(source_path)} cap #{money(cap)}"
          end

          if rebate_amount && upgrade_amount && rebate_amount > upgrade_amount
            failures << "rebate #{money(rebate_amount)} exceeds DFHP upgrade amount #{money(upgrade_amount)}"
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
              "#{DFHP_LINE_AMOUNT_FIELD_KEY}=#{money(upgrade_amount) || "(missing)"}",
              "income_level=#{income_level || "(missing)"}",
              "source_fuel_path=#{source_path_label(source_path)}",
              "cap=#{money(cap) || "(missing)"}",
              "northern_top_up_excluded=true"
            ].join("; "),
            field_evidence(
              rebate_field,
              dfhp_line_amount_field,
              source_fuel_path_field,
              income_level_field
            ),
            rebate_cap_reason_text(
              result: result,
              failures: failures,
              warnings: warnings
            )
          ]
        end

        def source_fuel_path
          text = field_text(source_fuel_path_field)
          return :unknown if text.blank?

          if text.match?(
               /\b(tank(?:ed)?\s+propane|propane\s+tank|tank\s+lp|lp\s+tank)\b/i
             )
            return :tank_propane
          end

          if text.match?(/\b(PNG|Pacific\s+Northern\s+Gas)\b/i) &&
               text.match?(/\b(natural\s+gas|propane|gas)\b/i)
            return :png_natural_gas_or_propane
          end

          :unknown
        end

        def source_path_cap(source_path, income_level)
          return nil unless income_level

          BASE_CAPS_BY_SOURCE_PATH.fetch(source_path, {})[income_level]
        end

        def source_path_label(source_path)
          case source_path
          when :png_natural_gas_or_propane
            "PNG natural gas or PNG propane"
          when :tank_propane
            "tank propane"
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

        def dfhp_line_amount_field
          @dfhp_line_amount_field ||=
            best_genai_field(DFHP_LINE_AMOUNT_FIELD_KEY)
        end

        def rebate_field
          @rebate_field ||= best_genai_field(REBATE_FIELD_KEY)
        end

        def source_fuel_path_field
          @source_fuel_path_field ||=
            best_genai_field(SOURCE_FUEL_PATH_FIELD_KEY)
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
            "The named rebate, DFHP upgrade amount, source-fuel path, and income-level cap are all present, and the rebate is no greater than the eligible DFHP upgrade amount or the base rebate cap. Northern top-up is intentionally excluded and checked by heat_pump_northern_top_up_3000_within_cap."
          when "fail"
            "The deterministic DFHP base rebate comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the DFHP base rebate comparison because #{warnings.join("; ")}. Admin should verify the invoice DFHP line amount, rebate line, source-fuel path, and matched eligibility code."
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
