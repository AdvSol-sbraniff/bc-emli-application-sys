# frozen_string_literal: true

module Claims
  module CodeRules
    module WindowsDoorsUFactor
      class ApplyThresholdCheck
        WINDOWS_DOORS_UPGRADE_TYPE_KEY = "windows_doors"
        U_FACTOR_FIELD_KEY = "metric_u_factor"
        MAX_U_FACTOR = BigDecimal("1.22")

        RULE = { key: "wd_u_factor_threshold" }.freeze

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

          fields = u_factor_fields
          values = parsed_u_factor_values(fields)
          row = u_factor_row(fields: fields, values: values)

          replace_rulechecks!([row])

          {
            ok: true,
            skipped: false,
            parsed_value_count: values.size,
            highest_u_factor: values.max&.to_s("F")
          }
        rescue => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_for_upgrade_type?
          ::Claims::CodeRules::Registry.enabled_for?(
            code_rule_key: RULE.fetch(:key),
            invoice_upgrade_type_id: upgrade_type.id,
            fallback:
              upgrade_type.upgrade_type_key == WINDOWS_DOORS_UPGRADE_TYPE_KEY
          )
        end

        def u_factor_fields
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "genai",
              field_key: U_FACTOR_FIELD_KEY
            )
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def parsed_u_factor_values(fields)
          fields.flat_map { |field| extract_decimals(field.value_text) }.uniq
        end

        def extract_decimals(text)
          text
            .to_s
            .scan(/(?<![A-Za-z])\d+(?:[.,]\d+)?(?![A-Za-z])/)
            .filter_map do |token|
              normalized = token.tr(",", ".")
              BigDecimal(normalized)
            rescue ArgumentError
              nil
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

        def u_factor_row(fields:, values:)
          now = Time.current
          rule_result, calculation, evidence_text, reason_text =
            u_factor_evaluation(fields: fields, values: values)

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULE.fetch(:key),
            rule_result: rule_result,
            expected_text:
              "Each claimed window or door should show a metric U-factor of 1.22 W/m2-K or less.",
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

        def u_factor_evaluation(fields:, values:)
          if fields.empty?
            return [
              "warn",
              "No metric_u_factor located field was stored for the windows/doors upgrade call.",
              nil,
              "The windows and doors ruleset did not produce any structured U-factor value for this invoice version. The program requirement is that installed windows and doors show a U-factor of 1.22 W/m2-K or less, but code cannot compare that threshold when no value is available. This is a warning rather than a failure because the value may still be visible in supporting product documents, label photos, or certification sheets that are not yet structured into this invoice field. Admin should inspect the invoice and any product/certification support to confirm whether a compliant U-factor is visible. If the value is present in the source documents but missing from the located fields, improve the extraction/ruleset path and rerun validation."
            ]
          end

          if values.empty?
            raw_text = unique_field_text(fields)
            return [
              "warn",
              "metric_u_factor field text was present but no numeric U-factor could be parsed from: #{raw_text.presence || "(blank)"}.",
              raw_text.presence,
              "The windows and doors ruleset captured text for the U-factor field, but code could not safely parse a numeric metric U-factor from it. This means the source wording may be incomplete, mixed with unrelated identifiers, or formatted in a way that the deterministic parser cannot rely on. Because the threshold comparison cannot be performed safely, this is a warning instead of a failure. Admin should inspect the source invoice or supporting product/certification material and confirm the visible U-factor values manually. If the source clearly shows U-factor values, the extraction path should be tightened so code can compare them deterministically on rerun."
            ]
          end

          highest_value = values.max
          values_text = values.map { |value| value.to_s("F") }.join(", ")
          evidence_text = unique_field_text(fields).presence || values_text

          if highest_value <= MAX_U_FACTOR
            return [
              "pass",
              "Parsed metric U-factor values = [#{values_text}]; highest parsed value = #{highest_value.to_s("F")}; threshold = 1.22; all parsed values <= 1.22 => true.",
              evidence_text,
              "The structured windows and doors located fields produced one or more metric U-factor values, and every parsed value is at or below the program threshold of 1.22 W/m2-K. Because the comparison is purely numeric once the values are extracted, code can make a deterministic pass decision here. The highest parsed value is still within threshold, so there is no visible contradiction that needs manual resolution. Admin can rely on this check unless the underlying extracted field is clearly tied to the wrong product or supporting document. No follow-up is required for the U-factor threshold based on the currently extracted evidence."
            ]
          end

          [
            "fail",
            "Parsed metric U-factor values = [#{values_text}]; highest parsed value = #{highest_value.to_s("F")}; threshold = 1.22; highest parsed value > 1.22 => true.",
            evidence_text,
            "The structured windows and doors located fields produced one or more metric U-factor values, and at least one parsed value exceeds the program threshold of 1.22 W/m2-K. Because this comparison is deterministic once the values are extracted, code can make a fail decision without asking GenAI to reinterpret the threshold. The fail assumes the extracted U-factor belongs to the claimed installed window or door product evidence rather than an unrelated reference, so admin should still confirm the cited source if the product context looks mixed. If the extracted field is tied to the correct product, the installed unit does not satisfy the U-factor requirement as currently documented. The likely next step is corrected product evidence, a different supporting certification source, or a manual override only if the extracted value is demonstrably tied to the wrong item."
          ]
        end

        def unique_field_text(fields)
          fields
            .map { |field| field.value_text.to_s.strip }
            .reject(&:empty?)
            .uniq
            .join(" | ")
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
      end
    end
  end
end
