# frozen_string_literal: true

module Claims
  module CodeRules
    module Esu
      class ApplyTiming
        ESU_UPGRADE_TYPE_KEY = "electrical_service_upgrade"
        HP_INSTALL_DATE_FIELD_KEY = "esu_heat_pump_installation_date_reference"
        ASSOCIATED_HP_FIELD_KEY = "esu_associated_heat_pump_or_hpwh_reference"
        SERVICE_DATE_FIELD_KEY = "service_completion_or_invoice_date"
        SERVICE_DOCUMENT_TYPE_KEYS = %w[
          electrical_utility_upgrade_document
          utility_bill
        ].freeze

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
        rescue => e
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
          service_date_values = service_date_candidates
          hp_install_date_values = date_values_from_field(hp_install_date_field)
          service_date = service_date_values.first
          hp_install_date = hp_install_date_values.first

          if service_date && hp_install_date
            return(
              actual_date_comparison(
                service_date: service_date,
                hp_install_date: hp_install_date
              )
            )
          end

          if same_invoice_association_available?
            invoice_date = invoice_version.di_ocr_invoice_date
            if service_date && hp_install_date.blank?
              return(
                actual_date_comparison(
                  service_date: service_date,
                  hp_install_date: invoice_date,
                  hp_install_date_source: "invoice_date_proxy"
                )
              )
            end

            if service_date.blank? && hp_install_date
              return(
                actual_date_comparison(
                  service_date: invoice_date,
                  hp_install_date: hp_install_date,
                  service_date_source: "invoice_date_proxy"
                )
              )
            end

            return(
              same_invoice_proxy_result(
                missing_service_date: service_date.blank?,
                missing_hp_install_date: hp_install_date.blank?
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
          service_date_source: "located_field",
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
                "The ESU service date and associated heat pump installation date are both present and within six months."
              else
                "The ESU service date is outside the six-month window around the associated heat pump installation date."
              end
            )
          ]
        end

        def same_invoice_proxy_result(
          missing_service_date:,
          missing_hp_install_date:
        )
          invoice_date = invoice_version.di_ocr_invoice_date

          [
            "pass",
            80,
            [
              "same_invoice_proxy=true",
              "invoice_date=#{invoice_date.iso8601}",
              "esu_associated_heat_pump_or_hpwh_reference=present",
              "missing_service_date=#{missing_service_date}",
              "missing_heat_pump_installation_date=#{missing_hp_install_date}"
            ].join("; "),
            evidence_text,
            "The invoice visibly associates the ESU with a heat pump or heat pump water heater on the same invoice, so the invoice date is used as the shared timing proxy."
          ]
        end

        def warning_result(service_date:, hp_install_date:)
          missing = []
          missing << "ESU service upgrade date" if service_date.blank?
          missing << "heat pump installation date" if hp_install_date.blank?

          [
            "warn",
            0,
            [
              "esu_service_upgrade_date=#{service_date&.iso8601 || "(missing)"}",
              "heat_pump_installation_date=#{hp_install_date&.iso8601 || "(missing)"}",
              "same_invoice_proxy_available=false"
            ].join("; "),
            evidence_text,
            "Code could not confidently compare ESU timing because #{missing.join(" and ")} is missing or not parseable."
          ]
        end

        def service_date_candidates
          supporting_service_date_fields
            .flat_map do |field|
              date_values_from_text(field.value_text) +
                date_values_from_text(field.evidence_text)
            end
            .uniq
        end

        def supporting_service_date_fields
          ::Claims::SupportingDocumentLocatedField
            .joins(supporting_document: :supporting_document_type)
            .where(
              ::Claims::SupportingDocument.table_name => {
                invoice_version_id: invoice_version.id
              },
              ::Claims::SupportingDocumentType.table_name => {
                type_key: SERVICE_DOCUMENT_TYPE_KEYS
              },
              :field_key => SERVICE_DATE_FIELD_KEY
            )
            .where.not(value_text: [nil, ""])
            .where(
              "#{::Claims::SupportingDocument.table_name}.supporting_document_routing_quality IS NULL OR " \
                "#{::Claims::SupportingDocument.table_name}.supporting_document_routing_quality <> ?",
              "unusable"
            )
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def hp_install_date_field
          @hp_install_date_field ||= best_genai_field(HP_INSTALL_DATE_FIELD_KEY)
        end

        def associated_hp_field
          @associated_hp_field ||= best_genai_field(ASSOCIATED_HP_FIELD_KEY)
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

        def same_invoice_association_available?
          invoice_version.di_ocr_invoice_date.present? &&
            associated_hp_field.present? &&
            associated_hp_field.value_text.present?
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
              /
              \b\d{4}[-\/]\d{1,2}[-\/]\d{1,2}\b |
              \b\d{1,2}[-\/]\d{1,2}[-\/]\d{2,4}\b |
              \b(?:#{month_names})\.?\s+\d{1,2},?\s+\d{4}\b |
              \b\d{1,2}\s+(?:#{month_names})\.?,?\s+\d{4}\b
            /ix
            )
          ).flatten.compact.presence || []
        end

        def parse_date(fragment)
          Date.parse(fragment)
        rescue ArgumentError, TypeError
          nil
        end

        def evidence_text
          (
            supporting_service_date_fields +
              [hp_install_date_field, associated_hp_field].compact
          )
            .filter_map do |field|
              text = field.evidence_text.presence || field.value_text.presence
              next if text.blank?

              "#{field.field_key}: #{text}"
            end
            .uniq
            .join("; ")
            .presence
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
