# frozen_string_literal: true

module Claims
  module CodeRules
    module Ventilation
      class ApplyRebateCap
        UPGRADE_TYPE_KEY = "ventilation"
        VENT_LINE_AMOUNT_FIELD_KEY = "vent_line_amount"
        REBATE_FIELD_KEY = "upgrade_specific_rebate_line_amount"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"
        VENT_SYSTEM_TYPE_FIELD_KEY = "vent_system_type"
        SUPPORTING_SYSTEM_TYPE_FIELD_KEY = "product_category_or_system_type"

        CAPS_BY_SUBTYPE_AND_INCOME_LEVEL = {
          bathroom_fan: {
            1 => {
              percent: BigDecimal("0.95"),
              dollar_cap: BigDecimal("300")
            },
            2 => {
              percent: BigDecimal("0.60"),
              dollar_cap: BigDecimal("300")
            },
            3 => nil
          },
          herv: {
            1 => {
              percent: BigDecimal("0.95"),
              dollar_cap: BigDecimal("1600")
            },
            2 => {
              percent: BigDecimal("0.60"),
              dollar_cap: BigDecimal("1600")
            },
            3 => nil
          }
        }.freeze

        RULE = { key: "vent_rebate_math_within_cap" }.freeze

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
          return false unless upgrade_type.upgrade_type_key == UPGRADE_TYPE_KEY

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
              "For ventilation, the claimed rebate must be no more than the eligible ventilation cost and no more than the income-level percentage/cap maximum.",
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
          ventilation_amount = decimal_from_field(line_amount_field)
          income_level = parsed_income_level
          subtype = ventilation_subtype
          cap_config =
            (
              if income_level && subtype.fetch(:key)
                CAPS_BY_SUBTYPE_AND_INCOME_LEVEL.fetch(subtype.fetch(:key))[
                  income_level
                ]
              else
                nil
              end
            )
          calculated_cap = calculated_cap(ventilation_amount, cap_config)
          failures = []
          warnings = []

          if rebate_amount.nil?
            warnings << "#{REBATE_FIELD_KEY} is missing or not numeric"
          end
          if ventilation_amount.nil?
            warnings << "#{VENT_LINE_AMOUNT_FIELD_KEY} is missing or not numeric"
          end
          if income_level.nil?
            warnings << "income level is missing or not ESP1/ESP2/ESP3"
          end
          warnings << subtype.fetch(:warning) if subtype.fetch(:key).nil?

          if income_level == 3 && rebate_amount&.positive?
            failures << "income level 3 has no ventilation rebate"
          end

          if rebate_amount && calculated_cap && rebate_amount > calculated_cap
            failures << "rebate #{money(rebate_amount)} exceeds calculated cap #{money(calculated_cap)}"
          end

          if rebate_amount && ventilation_amount &&
               rebate_amount > ventilation_amount
            failures << "rebate #{money(rebate_amount)} exceeds ventilation amount #{money(ventilation_amount)}"
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
              "#{VENT_LINE_AMOUNT_FIELD_KEY}=#{money(ventilation_amount) || "(missing)"}",
              "ventilation_subtype=#{subtype.fetch(:label)}",
              "subtype_evidence=#{subtype.fetch(:evidence)}",
              "income_level=#{income_level || "(missing)"}",
              "percentage=#{percentage_label(cap_config)}",
              "dollar_cap=#{money(cap_config&.fetch(:dollar_cap)) || "(none)"}",
              "calculated_cap=#{money(calculated_cap) || "(none)"}"
            ].join("; "),
            field_evidence(
              rebate_field,
              line_amount_field,
              system_type_field,
              income_level_field,
              *supporting_system_type_fields
            ),
            rebate_cap_reason_text(
              result: result,
              failures: failures,
              warnings: warnings
            )
          ]
        end

        def calculated_cap(ventilation_amount, cap_config)
          return nil unless ventilation_amount && cap_config

          percentage_cap = ventilation_amount * cap_config.fetch(:percent)
          [percentage_cap, cap_config.fetch(:dollar_cap)].min
        end

        def percentage_label(cap_config)
          return "(none)" unless cap_config

          "#{(cap_config.fetch(:percent) * 100).to_i}%"
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
          @line_amount_field ||= best_genai_field(VENT_LINE_AMOUNT_FIELD_KEY)
        end

        def rebate_field
          @rebate_field ||= best_genai_field(REBATE_FIELD_KEY)
        end

        def income_level_field
          @income_level_field ||= best_code_field(INCOME_LEVEL_FIELD_KEY)
        end

        def system_type_field
          @system_type_field ||= best_genai_field(VENT_SYSTEM_TYPE_FIELD_KEY)
        end

        def supporting_system_type_fields
          @supporting_system_type_fields ||=
            ::Claims::SupportingDocumentLocatedField
              .joins(:supporting_document)
              .where(
                ::Claims::SupportingDocument.table_name => {
                  invoice_version_id: invoice_version.id
                },
                :field_key => SUPPORTING_SYSTEM_TYPE_FIELD_KEY
              )
              .where.not(value_text: [nil, ""])
              .order(confidence: :desc, created_at: :desc)
              .to_a
        end

        def ventilation_subtype
          matched_subtypes = []
          matched_subtypes << :herv if invoice_version.herv_product_id.present?
          if invoice_version.vent_fan_product_id.present?
            matched_subtypes << :bathroom_fan
          end
          matched_subtypes.uniq!

          if matched_subtypes.size > 1
            return(
              subtype_result(
                key: nil,
                label: "conflicting",
                evidence:
                  "herv_product_id and vent_fan_product_id are both populated",
                warning:
                  "ventilation subtype is conflicting because both HERV and fan product matches are populated"
              )
            )
          end

          if matched_subtypes.one?
            key = matched_subtypes.first
            return(
              subtype_result(
                key: key,
                label: subtype_label(key),
                evidence: product_match_subtype_evidence(key)
              )
            )
          end

          subtype_from_text
        end

        def subtype_from_text
          text = subtype_text
          if text.blank?
            return unknown_subtype("ventilation subtype is missing")
          end

          hrv_or_erv =
            text.match?(/\b(hrv|erv)\b|heat\s+recovery|energy\s+recovery/i)
          fan =
            text.match?(
              /bathroom\s+fan|bath\s+fan|utility\s+fan|exhaust\s+fan|ventilating\s+fan|fan\s+system/i
            )

          if hrv_or_erv && fan
            return(
              subtype_result(
                key: nil,
                label: "conflicting",
                evidence: text.squish,
                warning:
                  "ventilation subtype is conflicting because named evidence includes both HRV/ERV and bathroom/exhaust fan wording"
              )
            )
          end

          if hrv_or_erv
            return(
              subtype_result(
                key: :herv,
                label: "HRV/ERV",
                evidence: text.squish
              )
            )
          end

          if fan
            return(
              subtype_result(
                key: :bathroom_fan,
                label: "bathroom fan",
                evidence: text.squish
              )
            )
          end

          unknown_subtype(
            "ventilation subtype is missing or does not clearly classify as bathroom fan or HRV/ERV"
          )
        end

        def subtype_text
          ([system_type_field] + supporting_system_type_fields)
            .compact
            .flat_map { |field| [field.value_text, field.evidence_text] }
            .compact
            .join(" ")
        end

        def unknown_subtype(warning)
          subtype_result(
            key: nil,
            label: "unknown",
            evidence: subtype_text.squish.presence || "(missing)",
            warning: warning
          )
        end

        def subtype_result(key:, label:, evidence:, warning: nil)
          { key: key, label: label, evidence: evidence, warning: warning }
        end

        def subtype_label(key)
          case key
          when :herv
            "HRV/ERV"
          when :bathroom_fan
            "bathroom fan"
          else
            "unknown"
          end
        end

        def product_match_subtype_evidence(key)
          case key
          when :herv
            "invoice_versions.herv_product_id=#{invoice_version.herv_product_id}"
          when :bathroom_fan
            "invoice_versions.vent_fan_product_id=#{invoice_version.vent_fan_product_id}"
          else
            "(missing)"
          end
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
            "The named rebate, ventilation amount, ventilation subtype, and income-level cap are all present, and the rebate is no greater than the eligible ventilation amount or subtype-specific calculated cap."
          when "fail"
            "The deterministic ventilation rebate comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the ventilation rebate comparison because #{warnings.join("; ")}. Admin should verify the invoice rebate line, ventilation line amount, ventilation subtype, and matched eligibility code."
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
