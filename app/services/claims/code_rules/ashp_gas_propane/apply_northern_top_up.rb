# frozen_string_literal: true

module Claims
  module CodeRules
    module AshpGasPropane
      class ApplyNorthernTopUp
        GAS_PROPANE_UPGRADE_TYPE_KEY = "air_source_heat_pump_gas_propane"
        TOP_UP_FIELD_KEY = "hp_northern_top_up_evidence"
        EQUIPMENT_TYPE_FIELD_KEY = "hp_new_equipment_type"
        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"

        SINGLE_HEAD_CAP = BigDecimal("1500")
        MULTI_OR_DUCTED_CAP = BigDecimal("3000")

        RULE = {
          number: 7,
          key: "ashp_gas_propane_northern_top_up_within_cap"
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
              "A separately claimed gas/propane ASHP northern top-up should be for an eligible Income Level 1 or 2 home, within the equipment-category cap, north of and including the District of 100 Mile House, and connected to BC Hydro electric service.",
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
              "No separate northern top-up is visible in the named northern-top-up field, so there is no top-up amount to compare against the northern top-up caps."
            ]
          end

          amount = top_up_amount(top_up_text)
          income_level = parsed_income_level
          category = equipment_category
          cap = category_cap(category)
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
          if category == :unknown
            warnings << "#{EQUIPMENT_TYPE_FIELD_KEY} does not clearly classify the equipment for the northern top-up cap"
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
          if amount && cap && amount > cap
            failures << "northern top-up #{money(amount)} exceeds #{category_label(category)} cap #{money(cap)}"
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
              "equipment_category=#{category_label(category)}",
              "cap=#{money(cap) || "(missing)"}",
              "northern_location_supported=#{location_supported}",
              "bc_hydro_service_supported=#{bc_hydro_supported}"
            ].join("; "),
            field_evidence(
              top_up_field,
              equipment_type_field,
              income_level_field
            ),
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

        def equipment_category
          text = field_text(equipment_type_field)
          return :unknown if text.blank?

          if text.match?(
               /\b(central\s+ducted|3[- ]?head|three[- ]?head|multi[- ]?split|multiple[- ]split|multi[- ]?head|2[- ]?head|two[- ]?head|2\s+single[- ]head|two\s+single[- ]head|low\s+static|two\s+supply\s+outlets?|3\s+or\s+more\s+zones?|three\s+or\s+more\s+zones?)\b/i
             )
            return :multi_or_ducted
          end

          if text.match?(/\b(single[- ]head|one[- ]head|1[- ]head)\b/i)
            return :single_head
          end

          :unknown
        end

        def category_cap(category)
          case category
          when :single_head
            SINGLE_HEAD_CAP
          when :multi_or_ducted
            MULTI_OR_DUCTED_CAP
          end
        end

        def category_label(category)
          case category
          when :single_head
            "single-head mini-split"
          when :multi_or_ducted
            "central ducted, multi-split, or 2 single-head mini-split"
          else
            "unknown"
          end
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
            "The named northern-top-up, equipment, income-level, northern-location, and BC Hydro evidence satisfy the deterministic gas/propane northern top-up check."
          when "fail"
            "The deterministic gas/propane northern top-up comparison failed: #{failures.join("; ")}."
          else
            "Code could not confidently complete the gas/propane northern top-up comparison because #{warnings.join("; ")}. Admin should verify the top-up line, equipment category, location, BC Hydro service, and eligibility code."
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
