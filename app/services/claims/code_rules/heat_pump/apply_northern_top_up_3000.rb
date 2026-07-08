# frozen_string_literal: true

module Claims
  module CodeRules
    module HeatPump
      class ApplyNorthernTopUp3000
        RELEVANT_UPGRADE_TYPE_KEYS = %w[
          dual_fuel_ducted_heat_pump
          air_to_water_heat_pump
          combined_space_water_heat_pump
        ].freeze

        TOP_UP_FIELD_KEY = "hp_northern_top_up_evidence"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"
        TOP_UP_CAP = BigDecimal("3000")

        RULE = {
          number: 7,
          key: "heat_pump_northern_top_up_3000_within_cap"
        }.freeze

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
          unless RELEVANT_UPGRADE_TYPE_KEYS.include?(
                   upgrade_type.upgrade_type_key
                 )
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
            top_up_evaluation

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_number: RULE.fetch(:number),
            rule_key: RULE.fetch(:key),
            rule_result: rule_result,
            confidence: confidence,
            expected_text:
              "A separately claimed northern top-up must be for an eligible Income Level 1 or 2 home, no more than $3,000, north of and including the District of 100 Mile House, and connected to BC Hydro electric service.",
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

        def top_up_evaluation
          top_up_text = field_text(top_up_field)

          unless top_up_claimed?(top_up_text)
            return [
              "pass",
              100,
              "hp_northern_top_up_evidence=(missing or no separate northern top-up visible); top_up_claimed=false.",
              field_evidence(top_up_field),
              "No separate northern top-up is visible in the named northern-top-up field, so there is no top-up amount to compare against the $3,000 northern top-up cap."
            ]
          end

          amount = top_up_amount(top_up_text)
          income_level = parsed_income_level
          location_supported = northern_location_supported?(top_up_text)
          bc_hydro_supported = bc_hydro_service_supported?(top_up_text)
          failures = []
          warnings = []

          if amount.nil?
            warnings << "#{TOP_UP_FIELD_KEY} does not contain a parseable separate dollar amount"
          end
          if income_level.nil?
            warnings << "income level is missing or not ESP1/ESP2/ESP3"
          end
          unless location_supported
            warnings << "#{TOP_UP_FIELD_KEY} does not clearly support location north of and including the District of 100 Mile House"
          end
          unless bc_hydro_supported
            warnings << "#{TOP_UP_FIELD_KEY} does not clearly support BC Hydro electric service"
          end

          if income_level == 3 && amount&.positive?
            failures << "income level 3 has no northern top-up"
          end
          if amount && amount > TOP_UP_CAP
            failures << "northern top-up #{money(amount)} exceeds cap #{money(TOP_UP_CAP)}"
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
              "#{TOP_UP_FIELD_KEY}=#{money(amount) || "(missing)"}",
              "income_level=#{income_level || "(missing)"}",
              "cap=#{money(TOP_UP_CAP)}",
              "northern_location_supported=#{location_supported}",
              "bc_hydro_service_supported=#{bc_hydro_supported}"
            ].join("; "),
            field_evidence(top_up_field, income_level_field),
            top_up_reason_text(
              result: result,
              failures: failures,
              warnings: warnings
            )
          ]
        end

        def top_up_claimed?(text)
          return false if text.blank?
          if text.match?(/\b(no|none|not visible|not shown|missing|null)\b/i)
            return false
          end

          text.match?(
            /\b(northern|north(?:ern)?\s+top[- ]?up|top[- ]?up)\b/i
          ) || top_up_amount(text).present?
        end

        def top_up_amount(text)
          dollar_values = text.to_s.scan(/\$\s*(\d[\d,]*(?:\.\d+)?)/).flatten
          values =
            dollar_values.filter_map do |value|
              BigDecimal(value.delete(","))
            rescue ArgumentError
              nil
            end

          values.max
        end

        def northern_location_supported?(text)
          text.match?(
            /\b(north\s+of|including\s+the\s+District\s+of\s+100\s+Mile\s+House|100\s+Mile\s+House|51\.628|location[^.;]*(north|eligible))\b/i
          )
        end

        def bc_hydro_service_supported?(text)
          text.match?(/\b(BC\s*Hydro|hydro\s+electric\s+service)\b/i)
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

        def top_up_field
          @top_up_field ||= best_genai_field(TOP_UP_FIELD_KEY)
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
            .order(confidence: :desc, created_at: :desc)
            .first
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

        def top_up_reason_text(result:, failures:, warnings:)
          case result
          when "pass"
            "The named northern-top-up, income-level, northern-location, and BC Hydro evidence satisfy the deterministic $3,000 northern top-up check."
          when "fail"
            "The deterministic $3,000 northern top-up comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the $3,000 northern top-up comparison because #{warnings.join("; ")}. Admin should verify the top-up line, location, BC Hydro service, and matched eligibility code."
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
