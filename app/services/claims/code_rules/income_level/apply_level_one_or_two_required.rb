# frozen_string_literal: true

module Claims
  module CodeRules
    module IncomeLevel
      class ApplyLevelOneOrTwoRequired
        RULE = { number: 90, key: "income_level_1_or_2_required" }.freeze

        INCOME_LEVEL_FIELD_KEY = "users_eligibilitycodes.income_level"
        ELIGIBILITY_CODE_FIELD_KEY = "users_eligibilitycodes.eligibility_code"

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

          {
            ok: true,
            skipped: false,
            income_level: parsed_income_level,
            rule_result: row.fetch(:rule_result)
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
            fallback: false
          )
        end

        def rulecheck_row
          now = Time.current
          rule_result, confidence, calculation, evidence_text, reason_text =
            income_level_evaluation

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_number: RULE.fetch(:number),
            rule_key: RULE.fetch(:key),
            rule_result: rule_result,
            confidence: confidence,
            expected_text:
              "Participant must be registered and approved as Income Level 1 or 2 for this upgrade type.",
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

        def income_level_evaluation
          raw_income_level = income_level_field&.value_text
          income_level = parsed_income_level
          eligibility_code = eligibility_code_field&.value_text.to_s.strip
          evidence_text =
            evidence_text_for(
              income_level: raw_income_level,
              eligibility_code: eligibility_code
            )

          if raw_income_level.blank?
            return [
              "warn",
              0,
              "No stored users_eligibilitycodes.income_level code-located field was available for this invoice version.",
              evidence_text,
              "The matched eligibility-code record did not produce a stored income_level fact for deterministic validation. Code cannot safely decide the Income Level 1/2 requirement without that database fact. Admin should confirm the eligibility-code match and rerun case-fact generation if the record exists."
            ]
          end

          unless income_level
            return [
              "warn",
              0,
              "Stored users_eligibilitycodes.income_level value could not be parsed as 1, 2, or 3: #{raw_income_level}.",
              evidence_text,
              "The stored income_level value is present but not parseable as a supported ESP income level. Admin should correct the eligibility-code record or investigate why the code-located field contains an unexpected value."
            ]
          end

          if [1, 2].include?(income_level)
            return [
              "pass",
              100,
              "income_level=#{income_level}; income_level IN (1, 2) => true.",
              evidence_text,
              "The matched eligibility-code record shows Income Level #{income_level}, which satisfies the program requirement that this upgrade type is limited to participants registered and approved as Income Level 1 or 2."
            ]
          end

          [
            "fail",
            100,
            "income_level=#{income_level}; income_level IN (1, 2) => false.",
            evidence_text,
            "The matched eligibility-code record shows Income Level 3. The current ESP requirements limit this upgrade type to participants registered and approved as Income Level 1 or 2, so this deterministic check fails unless the eligibility-code record is incorrect."
          ]
        end

        def parsed_income_level
          @parsed_income_level ||=
            begin
              value = income_level_field&.value_text.to_s.strip
              if value.blank?
                nil
              else
                parsed = Integer(value, 10)
                [1, 2, 3].include?(parsed) ? parsed : nil
              end
            rescue ArgumentError
              nil
            end
        end

        def income_level_field
          @income_level_field ||= best_code_field(INCOME_LEVEL_FIELD_KEY)
        end

        def eligibility_code_field
          @eligibility_code_field ||=
            best_code_field(ELIGIBILITY_CODE_FIELD_KEY)
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

        def evidence_text_for(income_level:, eligibility_code:)
          values = []
          if eligibility_code.present?
            values << "eligibility_code=#{eligibility_code}"
          end
          values << "income_level=#{income_level}" if income_level.present?
          values.presence&.join("; ") || "claims.users_eligibilitycodes"
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
      end
    end
  end
end
