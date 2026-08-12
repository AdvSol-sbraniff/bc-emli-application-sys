# frozen_string_literal: true

module Claims
  module CodeRules
    module Hpwh
      class ApplyRebateCap
        HPWH_UPGRADE_TYPE_KEY = "heat_pump_water_heater"
        HPWH_LINE_AMOUNT_FIELD_KEY = "hpwh_line_amount"
        REBATE_FIELD_KEY = "upgrade_specific_rebate_line_amount"
        SOURCE_FIELD_KEY = "hpwh_existing_fuel_type"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"

        BASE_CAPS_BY_SOURCE_PATH = {
          fossil: {
            1 => BigDecimal("3500"),
            2 => BigDecimal("3500"),
            3 => BigDecimal("3500")
          },
          electric_or_wood: {
            1 => BigDecimal("3500"),
            2 => BigDecimal("2800"),
            3 => nil
          }
        }.freeze

        RULE = { key: "hpwh_rebate_math_within_cap" }.freeze

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
          unless upgrade_type.upgrade_type_key == HPWH_UPGRADE_TYPE_KEY
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
          rule_result, calculation, evidence_text, reason_text =
            rebate_cap_evaluation

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULE.fetch(:key),
            rule_result: rule_result,
            expected_text:
              "For a heat pump water heater, the claimed rebate must be no more than 100% of the eligible HPWH upgrade cost and no more than the source-fuel maximum for the matched income level.",
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
          upgrade_amount = decimal_from_field(line_amount_field)
          income_level = parsed_income_level
          source_path = source_fuel_path
          cap = source_path_cap(source_path, income_level)
          failures = []
          warnings = []

          if rebate_amount.nil?
            warnings << "#{REBATE_FIELD_KEY} is missing or not numeric"
          end
          if upgrade_amount.nil?
            warnings << "#{HPWH_LINE_AMOUNT_FIELD_KEY} is missing or not numeric"
          end
          if income_level.nil?
            warnings << "income level is missing or not ESP1/ESP2/ESP3"
          end
          if source_path == :unknown
            warnings << "#{SOURCE_FIELD_KEY} does not clearly classify the prior water-heater source path"
          end
          if source_path != :unknown && income_level && cap.nil?
            failures << "#{source_path_label(source_path)} has no rebate for income level #{income_level}"
          end

          if rebate_amount && cap && rebate_amount > cap
            failures << "rebate #{money(rebate_amount)} exceeds #{source_path_label(source_path)} cap #{money(cap)}"
          end

          if rebate_amount && upgrade_amount && rebate_amount > upgrade_amount
            failures << "rebate #{money(rebate_amount)} exceeds HPWH upgrade amount #{money(upgrade_amount)}"
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
            [
              "#{REBATE_FIELD_KEY}=#{money(rebate_amount) || "(missing)"}",
              "#{HPWH_LINE_AMOUNT_FIELD_KEY}=#{money(upgrade_amount) || "(missing)"}",
              "income_level=#{income_level || "(missing)"}",
              "source_fuel_path=#{source_path_label(source_path)}",
              "cap=#{money(cap) || "(none)"}"
            ].join("; "),
            field_evidence(
              rebate_field,
              line_amount_field,
              source_field,
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
          text = field_text(source_field)
          return :unknown if text.blank?

          if text.match?(
               /\b(fossil|gas|natural\s+gas|propane|oil|fuel\s+oil)\b/i
             )
            return :fossil
          end
          if text.match?(/\b(electric|electricity|wood|solid\s+fuel|pellet)\b/i)
            return :electric_or_wood
          end

          :unknown
        end

        def source_path_cap(source_path, income_level)
          return nil unless income_level

          BASE_CAPS_BY_SOURCE_PATH.fetch(source_path, {})[income_level]
        end

        def source_path_label(source_path)
          case source_path
          when :fossil
            "fossil fuel"
          when :electric_or_wood
            "electricity or wood"
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

        def line_amount_field
          @line_amount_field ||= best_genai_field(HPWH_LINE_AMOUNT_FIELD_KEY)
        end

        def rebate_field
          @rebate_field ||= best_genai_field(REBATE_FIELD_KEY)
        end

        def source_field
          @source_field ||= best_genai_field(SOURCE_FIELD_KEY)
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
            "The named rebate, HPWH upgrade amount, prior water-heater source path, and income-level cap are all present, and the rebate is no greater than the eligible upgrade amount or the base rebate cap."
          when "fail"
            "The deterministic HPWH rebate comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the HPWH rebate comparison because #{warnings.join("; ")}. Admin should verify the invoice rebate line, HPWH line amount, prior water-heater source path, and matched eligibility code."
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
