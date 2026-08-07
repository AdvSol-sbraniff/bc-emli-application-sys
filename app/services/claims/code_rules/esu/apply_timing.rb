# frozen_string_literal: true

module Claims
  module CodeRules
    module Esu
      class ApplyTiming
        ESU_UPGRADE_TYPE_KEY = "electrical_service_upgrade"
        HP_INSTALL_DATE_FIELD_KEY = "esu_heat_pump_installation_date_reference"

        RULE = {
          key: "esu_timing_within_six_months_of_heat_pump_installation"
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
        rescue StandardError => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_for_upgrade_type?
          upgrade_type.upgrade_type_key == ESU_UPGRADE_TYPE_KEY &&
            ::Claims::CodeRules::Registry.enabled_for?(
              code_rule_key: RULE.fetch(:key),
              invoice_upgrade_type_id: upgrade_type.id,
              fallback: false
            )
        end

        def rulecheck_row
          now = Time.current
          result, confidence, calculation, evidence_text, reason_text =
            timing_evaluation

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULE.fetch(:key),
            rule_result: result,
            confidence: confidence,
            expected_text:
              "The electrical service upgrade must be installed within six months of the associated heat pump or heat pump water heater installation.",
            calculation: calculation,
            evidence_text: evidence_text,
            reason_and_likely_causes:
              append_admin_message(
                rule_result: result,
                reason_text: reason_text
              ),
            created_at: now,
            updated_at: now
          }
        end

        def timing_evaluation
          service_date = invoice_version.di_ocr_invoice_date
          hp_install_date_values = date_values_from_field(hp_install_date_field)
          hp_install_date = hp_install_date_values.first

          if service_date && hp_install_date
            return(
              actual_date_comparison(
                service_date: service_date,
                hp_install_date: hp_install_date,
                service_date_source: "invoice_date_proxy"
              )
            )
          end

          warning_result(
            service_date: service_date,
            hp_install_date: hp_install_date
          )
        end

        def actual_date_comparison(
          service_date:,
          hp_install_date:,
          service_date_source:,
          hp_install_date_source: "located_field"
        )
          window_start = hp_install_date.advance(months: -6)
          window_end = hp_install_date.advance(months: 6)
          pass = service_date >= window_start && service_date <= window_end
          result = pass ? "pass" : "fail"

          [
            result,
            100,
            [
              "esu_service_upgrade_date=#{service_date.iso8601}",
              "esu_service_upgrade_date_source=#{service_date_source}",
              "heat_pump_installation_date=#{hp_install_date.iso8601}",
              "heat_pump_installation_date_source=#{hp_install_date_source}",
              "allowed_window=#{window_start.iso8601}..#{window_end.iso8601}",
              "within_window=#{pass}"
            ].join("; "),
            evidence_text,
            (
              if pass
                "The invoice date used as the ESU installation-date proxy is within six months of the associated heat pump installation date."
              else
                "The invoice date used as the ESU installation-date proxy is outside the six-month window around the associated heat pump installation date."
              end
            )
          ]
        end

        def warning_result(service_date:, hp_install_date:)
          missing = []
          if service_date.blank?
            missing << "invoice date used as the ESU installation-date proxy"
          end
          missing << "heat pump installation date" if hp_install_date.blank?
          service_date_value = service_date&.iso8601 || "(missing)"
          service_date_source =
            service_date.present? ? "invoice_date_proxy" : "(missing)"
          hp_install_date_value = hp_install_date&.iso8601 || "(missing)"
          hp_install_date_source =
            hp_install_date.present? ? "located_field" : "(missing)"
          missing_description = missing.join(" and ")

          [
            "warn",
            0,
            [
              "esu_service_upgrade_date=#{service_date_value}",
              "esu_service_upgrade_date_source=#{service_date_source}",
              "heat_pump_installation_date=#{hp_install_date_value}",
              "heat_pump_installation_date_source=#{hp_install_date_source}"
            ].join("; "),
            evidence_text,
            "Code could not compare ESU timing because #{missing_description} is missing or not parseable."
          ]
        end

        def hp_install_date_field
          @hp_install_date_field ||= best_genai_field(HP_INSTALL_DATE_FIELD_KEY)
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

        def date_values_from_field(field)
          return [] if field.blank?

          (
            date_values_from_text(field.value_text) +
              date_values_from_text(field.evidence_text)
          ).uniq
        end

        def date_values_from_text(value)
          text = value.to_s
          return [] if text.blank?

          date_fragments(text).filter_map { |fragment| parse_date(fragment) }
        end

        def date_fragments(text)
          month_names =
            "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|" \
              "jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|" \
              "nov(?:ember)?|dec(?:ember)?"

          Array(
            text.scan(
              %r{
              \b\d{4}[-/]\d{1,2}[-/]\d{1,2}\b |
              \b\d{1,2}[-/]\d{1,2}[-/]\d{2,4}\b |
              \b(?:#{month_names})\.?\s+\d{1,2},?\s+\d{4}\b |
              \b\d{1,2}\s+(?:#{month_names})\.?,?\s+\d{4}\b
            }ix
            )
          ).flatten.compact.presence || []
        end

        def parse_date(fragment)
          Date.parse(fragment)
        rescue ArgumentError, TypeError
          nil
        end

        def evidence_text
          evidence = []
          if invoice_version.di_ocr_invoice_date.present?
            evidence << "invoice_date_proxy: #{invoice_version.di_ocr_invoice_date.iso8601}"
          end

          evidence.concat(
            [hp_install_date_field].compact.filter_map do |field|
              text = field.evidence_text.presence || field.value_text.presence
              next if text.blank?

              "#{field.field_key}: #{text}"
            end
          )

          evidence.uniq.join("; ").presence
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
