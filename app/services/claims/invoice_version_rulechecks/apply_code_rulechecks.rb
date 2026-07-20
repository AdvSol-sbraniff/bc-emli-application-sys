# frozen_string_literal: true

module Claims
  module InvoiceVersionRulechecks
    class ApplyCodeRulechecks
      COMMON_RULE_FALLBACK_ENABLED = false
      PRIOR_REBATE_RULE_KEY = "prior_same_upgrade_type_rebate_payment_found"
      MULTIPLE_SPACE_SYSTEMS_RULE_KEY =
        "current_invoice_cannot_contain_multiple_space_systems"
      PRIMARY_SPACE_HEATING_UPGRADE_TYPE_KEYS = %w[
        air_source_heat_pump_electric
        air_source_heat_pump_wood
        air_source_heat_pump_gas_propane
        air_source_heat_pump_oil
        dual_fuel_ducted_heat_pump
        air_to_water_heat_pump
        combined_space_water_heat_pump
      ].freeze
      HEAT_PUMP_WATER_HEATER_UPGRADE_TYPE_KEY = "heat_pump_water_heater"
      INSULATION_UPGRADE_TYPE_KEY = "insulation"
      WINDOWS_DOORS_UPGRADE_TYPE_KEY = "windows_doors"
      ELECTRICAL_SERVICE_UPGRADE_TYPE_KEY = "electrical_service_upgrade"
      PRIOR_REBATE_EXCLUDED_INVOICE_STATUS = "ineligible"
      COMMON_RULE_KEYS = %w[
        first_class_invoice_fields_present
        submission_within_six_months
        eligibility_code_valid_for_invoice_date
        eligibility_code_found_in_database
        current_invoice_cannot_contain_multiple_space_systems
        prior_same_upgrade_type_rebate_payment_found
      ].freeze
      COMMON_RULE_BUILDERS = {
        "first_class_invoice_fields_present" =>
          :first_class_invoice_fields_present,
        "submission_within_six_months" => :submission_within_six_months,
        "eligibility_code_valid_for_invoice_date" =>
          :eligibility_code_valid_for_invoice_date,
        "eligibility_code_found_in_database" =>
          :eligibility_code_found_in_database,
        MULTIPLE_SPACE_SYSTEMS_RULE_KEY =>
          :current_invoice_cannot_contain_multiple_space_systems,
        PRIOR_REBATE_RULE_KEY => :prior_same_upgrade_type_rebate_payment_found
      }.freeze

      def self.call(invoice_version_id:)
        new(invoice_version_id: invoice_version_id).call
      end

      def initialize(invoice_version_id:)
        @invoice_version_id = invoice_version_id
      end

      def call
        @invoice_version = Claims::InvoiceVersion.find(@invoice_version_id)
        @invoice = Claims::Invoice.find(@invoice_version.invoice_id)
        @session = Claims::Session.find_by(id: @invoice.session_id)
        @code_fields = load_fields("code")
        validate_common_rule_coverage!

        rows =
          COMMON_RULE_BUILDERS.filter_map do |rule_key, builder_method|
            next unless enabled_common_rule?(rule_key)

            send(builder_method)
          end

        Claims::InvoiceVersionRulecheck.transaction do
          Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: @invoice_version_id,
            invoice_upgrade_type_id: common_upgrade_type_id,
            source_engine: "code",
            rule_key: COMMON_RULE_KEYS
          ).delete_all

          Claims::InvoiceVersionRulecheck.insert_all!(rows) if rows.any?
        end

        { ok: true, replaced: rows.size }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      attr_reader :invoice_version, :invoice, :session, :code_fields

      def first_class_invoice_fields_present
        unless enabled_common_rule?("first_class_invoice_fields_present")
          return nil
        end

        required = {
          "Invoice number" => invoice_version.di_ocr_invoice_id,
          "Invoice date" => invoice_version.di_ocr_invoice_date,
          "Vendor name" => invoice_version.di_ocr_vendor_name,
          "Customer name" => invoice_version.di_ocr_customer_name,
          "Subtotal" => invoice_version.di_ocr_sub_total,
          "Total tax" => invoice_version.di_ocr_total_tax,
          "Invoice total" => invoice_version.di_ocr_invoice_total,
          "Amount due" => invoice_version.di_ocr_amount_due
        }

        missing = required.select { |_label, value| value.blank? }.keys
        pass = missing.empty?

        row(
          rule_key: "first_class_invoice_fields_present",
          rule_result: pass ? "pass" : "warn",
          confidence: 100,
          expected_text: "OCR first-class invoice fields are present.",
          detail_text:
            (
              if pass
                "All tracked first-class fields are present."
              else
                "Missing: #{missing.join(", ")}."
              end
            ),
          calculation:
            (
              unless pass
                "Missing tracked invoice fields: #{missing.join(", ")}."
              end
            ),
          evidence_text: "invoice_versions DI first-class columns",
          reason_and_likely_causes:
            (
              if pass
                nil
              else
                "Admin should verify the missing first-class invoice fields in the PDF. This is a warning because OCR may have missed fields that are still visible on the invoice."
              end
            )
        )
      end

      def submission_within_six_months
        return nil unless enabled_common_rule?("submission_within_six_months")

        invoice_date = invoice_version.di_ocr_invoice_date
        program_received_at = invoice.created_at

        if invoice_date.blank?
          return(
            warn_row(
              rule_key: "submission_within_six_months",
              expected_text: "invoices.created_at <= invoice_date + 6 months.",
              detail_text:
                "Missing invoice date, so the six-month program receipt deadline cannot be calculated."
            )
          )
        end

        deadline = invoice_date.advance(months: 6)
        program_received_date = program_received_at.to_date
        pass = program_received_date <= deadline

        row(
          rule_key: "submission_within_six_months",
          rule_result: pass ? "pass" : "fail",
          confidence: 100,
          expected_text: "invoices.created_at <= invoice_date + 6 months.",
          detail_text:
            "invoice_date=#{invoice_date.iso8601}; program_received_date=#{program_received_date.iso8601}.",
          calculation:
            "#{invoice_date.iso8601} + 6 months = #{deadline.iso8601}; #{program_received_date.iso8601} <= #{deadline.iso8601} => #{pass}",
          evidence_text:
            "invoice_versions.di_ocr_invoice_date + claims.invoices.created_at"
        )
      end

      def eligibility_code_valid_for_invoice_date
        unless enabled_common_rule?("eligibility_code_valid_for_invoice_date")
          return nil
        end

        invoice_date = invoice_version.di_ocr_invoice_date
        eligibility_code_record = matched_eligibility_code_record
        approved_at = eligibility_code_record&.approved_at
        eligibility_code = eligibility_code_record&.eligibility_code

        missing = []
        missing << "invoice date" if invoice_date.blank?
        if eligibility_code_record.blank?
          missing << "matched eligibility code record"
        end
        missing << "eligibility code approval date" if approved_at.blank?

        if missing.any?
          return(
            warn_row(
              rule_key: "eligibility_code_valid_for_invoice_date",
              expected_text:
                "Invoice date is within six months of the eligibility-code approval date.",
              detail_text: "Missing #{missing.join(" and ")}."
            )
          )
        end

        approved_date = parse_date(approved_at)
        deadline = approved_date.advance(months: 6)
        pass = invoice_date >= approved_date && invoice_date <= deadline

        row(
          rule_key: "eligibility_code_valid_for_invoice_date",
          rule_result: pass ? "pass" : "fail",
          confidence: 100,
          expected_text:
            "Invoice date is on or after eligibility-code approval and on or before six months after approval.",
          detail_text:
            "eligibility_code=#{eligibility_code.presence || "missing"}; users_eligibilitycode_id=#{invoice_version.users_eligibilitycode_id.presence || "missing"}; approved_at=#{approved_date.iso8601}; six_month_deadline=#{deadline.iso8601}; invoice_date=#{invoice_date.iso8601}.",
          calculation:
            "#{approved_date.iso8601} <= #{invoice_date.iso8601} <= #{deadline.iso8601} => #{pass}",
          evidence_text:
            "invoice_versions.users_eligibilitycode_id + claims.users_eligibilitycodes + invoice_versions.di_ocr_invoice_date"
        )
      rescue ArgumentError
        warn_row(
          rule_key: "eligibility_code_valid_for_invoice_date",
          expected_text: "Eligibility approval date is a parseable date.",
          detail_text: "Could not parse eligibility-code approval date."
        )
      end

      def eligibility_code_found_in_database
        unless enabled_common_rule?("eligibility_code_found_in_database")
          return nil
        end

        eligibility_code_record = matched_eligibility_code_record
        db_code =
          eligibility_code_record&.eligibility_code.presence ||
            first_field_value(
              code_fields,
              "users_eligibilitycodes.eligibility_code"
            ).to_s.strip
        classifier_code =
          first_field_value(classifier_fields, "classifier.eligibility_code") ||
            first_field_value(classifier_fields, "eligibility_code")

        if eligibility_code_record.present?
          return(
            row(
              rule_key: "eligibility_code_found_in_database",
              rule_result: "pass",
              confidence: 100,
              expected_text:
                "The classifier-located eligibility code resolves to a populated claims.users_eligibilitycodes record.",
              detail_text:
                "classifier eligibility code=#{classifier_code.presence || "missing"}; matched users_eligibilitycode_id=#{eligibility_code_record.id}; matched eligibility_code=#{db_code}.",
              calculation:
                "invoice_versions.users_eligibilitycode_id is populated => true",
              evidence_text:
                "invoice_versions.users_eligibilitycode_id + claims.users_eligibilitycodes"
            )
          )
        end

        row(
          rule_key: "eligibility_code_found_in_database",
          rule_result: "fail",
          confidence: 100,
          expected_text:
            "The classifier-located eligibility code resolves to a populated claims.users_eligibilitycodes record.",
          detail_text:
            "classifier eligibility code=#{classifier_code.presence || "missing"}; invoice_versions.users_eligibilitycode_id is missing.",
          calculation:
            "invoice_versions.users_eligibilitycode_id is populated => false",
          evidence_text: "invoice_versions.users_eligibilitycode_id",
          reason_and_likely_causes:
            "The deterministic enrichment step did not populate invoice_versions.users_eligibilitycode_id, so the classifier-located eligibility code did not resolve to a usable users_eligibilitycodes record."
        )
      end

      def current_invoice_cannot_contain_multiple_space_systems
        return nil unless enabled_common_rule?(MULTIPLE_SPACE_SYSTEMS_RULE_KEY)

        space_heating_keys =
          current_upgrade_type_keys & PRIMARY_SPACE_HEATING_UPGRADE_TYPE_KEYS
        pass = space_heating_keys.size <= 1

        row(
          rule_key: MULTIPLE_SPACE_SYSTEMS_RULE_KEY,
          rule_result: pass ? "pass" : "fail",
          confidence: 100,
          expected_text:
            "Current invoice contains no more than one primary space heating system upgrade type.",
          detail_text:
            "current_space_heating_upgrade_types=#{space_heating_keys.join(",").presence || "none"}; count=#{space_heating_keys.size}.",
          calculation:
            "current_space_heating_upgrade_type_count=#{space_heating_keys.size}; #{space_heating_keys.size} <= 1 => #{pass}",
          evidence_text:
            "claims.invoice_version_upgrade_types + claims.invoice_upgrade_types",
          reason_and_likely_causes:
            (
              unless pass
                "The classifier detected multiple primary space heating upgrade types on the same invoice version. The invoice should only contain one primary space heating system."
              end
            )
        )
      end

      def prior_same_upgrade_type_rebate_payment_found
        return nil unless enabled_common_rule?(PRIOR_REBATE_RULE_KEY)

        if invoice_version.participant_user_id.blank?
          classifier_code =
            first_field_value(
              classifier_fields,
              "classifier.eligibility_code"
            ) || first_field_value(classifier_fields, "eligibility_code")
          return(
            row(
              rule_key: PRIOR_REBATE_RULE_KEY,
              rule_result: "warn",
              confidence: 0,
              expected_text:
                "Matched participant is available before checking prior rebate payments.",
              detail_text:
                "No matched participant was available, so duplicate-payment history was not checked.",
              calculation:
                "classifier.eligibility_code=#{classifier_code.presence || "missing"}; users_eligibilitycode_id=#{invoice_version.users_eligibilitycode_id.presence || "missing"}; participant_user_id=#{invoice_version.participant_user_id.presence || "missing"}; prior rebate history check not run.",
              evidence_text:
                "classifier.eligibility_code + invoice_versions.users_eligibilitycode_id + invoice_versions.participant_user_id",
              reason_and_likely_causes:
                "Could not check prior rebate history because the invoice eligibility code did not match a participant eligibility record in the database. Confirm the eligibility code record, then rerun validation before approving."
            )
          )
        end

        current_keys = current_upgrade_type_keys
        prior_keys = prior_current_invoice_upgrade_type_keys
        current_has_space_heating =
          (current_keys & PRIMARY_SPACE_HEATING_UPGRADE_TYPE_KEYS).any?
        prior_has_space_heating =
          (prior_keys & PRIMARY_SPACE_HEATING_UPGRADE_TYPE_KEYS).any?
        failed_checks = []
        if current_has_space_heating && prior_has_space_heating
          failed_checks << "primary_space_heating"
        end
        if current_keys.include?(HEAT_PUMP_WATER_HEATER_UPGRADE_TYPE_KEY) &&
             prior_keys.include?(HEAT_PUMP_WATER_HEATER_UPGRADE_TYPE_KEY)
          failed_checks << HEAT_PUMP_WATER_HEATER_UPGRADE_TYPE_KEY
        end
        if current_keys.include?(INSULATION_UPGRADE_TYPE_KEY) &&
             prior_keys.include?(INSULATION_UPGRADE_TYPE_KEY)
          failed_checks << INSULATION_UPGRADE_TYPE_KEY
        end
        if current_keys.include?(WINDOWS_DOORS_UPGRADE_TYPE_KEY) &&
             prior_keys.include?(WINDOWS_DOORS_UPGRADE_TYPE_KEY)
          failed_checks << WINDOWS_DOORS_UPGRADE_TYPE_KEY
        end
        if current_keys.include?(ELECTRICAL_SERVICE_UPGRADE_TYPE_KEY) &&
             prior_keys.include?(ELECTRICAL_SERVICE_UPGRADE_TYPE_KEY)
          failed_checks << ELECTRICAL_SERVICE_UPGRADE_TYPE_KEY
        end
        rule_result = failed_checks.any? ? "fail" : "pass"

        row(
          rule_key: PRIOR_REBATE_RULE_KEY,
          rule_result: rule_result,
          confidence: 100,
          expected_text:
            "Participant has no prior non-ineligible current invoice for the same one-rebate-limited upgrade area.",
          detail_text:
            "participant_user_id=#{invoice_version.participant_user_id}; current_upgrade_types=#{current_keys.join(",").presence || "none"}; prior_current_upgrade_types=#{prior_keys.join(",").presence || "none"}; failed_checks=#{failed_checks.join(",").presence || "none"}.",
          calculation:
            prior_rebate_calculation(
              current_keys: current_keys,
              prior_keys: prior_keys,
              current_has_space_heating: current_has_space_heating,
              prior_has_space_heating: prior_has_space_heating,
              failed_checks: failed_checks,
              rule_result: rule_result
            ),
          evidence_text:
            "invoice_versions.participant_user_id + current invoice_versions per invoice_id + claims.invoice_version_upgrade_types + claims.invoices.status",
          reason_and_likely_causes:
            prior_rebate_reason(
              rule_result: rule_result,
              failed_checks: failed_checks
            )
        )
      end

      def load_fields(source_engine)
        Claims::InvoiceVersionLocatedField.where(
          invoice_version_id: invoice_version.id,
          source_engine: source_engine
        ).to_a
      end

      def classifier_fields
        @classifier_fields ||= load_fields("classifier")
      end

      def matched_eligibility_code_record
        @matched_eligibility_code_record ||=
          invoice_version.users_eligibilitycode
      end

      def current_upgrade_type_keys
        @current_upgrade_type_keys ||=
          ::Claims::InvoiceUpgradeType
            .joins(
              "INNER JOIN claims.invoice_version_upgrade_types ivut " \
                "ON ivut.invoice_upgrade_type_id = " \
                "#{::Claims::InvoiceUpgradeType.table_name}.id"
            )
            .where("ivut.invoice_version_id = ?", invoice_version.id)
            .distinct
            .order(:upgrade_type_key)
            .pluck(:upgrade_type_key)
      end

      def prior_current_invoice_upgrade_type_keys
        @prior_current_invoice_upgrade_type_keys ||=
          ::Claims::InvoiceUpgradeType
            .joins(
              "INNER JOIN claims.invoice_version_upgrade_types prior_ivut " \
                "ON prior_ivut.invoice_upgrade_type_id = " \
                "#{::Claims::InvoiceUpgradeType.table_name}.id"
            )
            .joins(
              "INNER JOIN claims.v_current_invoice_versions prior_current_versions " \
                "ON prior_current_versions.id = prior_ivut.invoice_version_id"
            )
            .where(
              "prior_current_versions.participant_user_id = ?",
              invoice_version.participant_user_id
            )
            .where.not("prior_current_versions.invoice_id = ?", invoice.id)
            .where.not(
              "prior_current_versions.invoice_status = ?",
              PRIOR_REBATE_EXCLUDED_INVOICE_STATUS
            )
            .distinct
            .order(:upgrade_type_key)
            .pluck(:upgrade_type_key)
      end

      def prior_rebate_calculation(
        current_keys:,
        prior_keys:,
        current_has_space_heating:,
        prior_has_space_heating:,
        failed_checks:,
        rule_result:
      )
        [
          "current_has_space_heating=#{current_has_space_heating}",
          "prior_has_space_heating=#{prior_has_space_heating}",
          "current_has_heat_pump_water_heater=#{current_keys.include?(HEAT_PUMP_WATER_HEATER_UPGRADE_TYPE_KEY)}",
          "prior_has_heat_pump_water_heater=#{prior_keys.include?(HEAT_PUMP_WATER_HEATER_UPGRADE_TYPE_KEY)}",
          "current_has_insulation=#{current_keys.include?(INSULATION_UPGRADE_TYPE_KEY)}",
          "prior_has_insulation=#{prior_keys.include?(INSULATION_UPGRADE_TYPE_KEY)}",
          "current_has_windows_doors=#{current_keys.include?(WINDOWS_DOORS_UPGRADE_TYPE_KEY)}",
          "prior_has_windows_doors=#{prior_keys.include?(WINDOWS_DOORS_UPGRADE_TYPE_KEY)}",
          "current_has_electrical_service_upgrade=#{current_keys.include?(ELECTRICAL_SERVICE_UPGRADE_TYPE_KEY)}",
          "prior_has_electrical_service_upgrade=#{prior_keys.include?(ELECTRICAL_SERVICE_UPGRADE_TYPE_KEY)}",
          "failed_checks=#{failed_checks.join(",").presence || "none"}",
          "result=#{rule_result}"
        ].join("; ")
      end

      def prior_rebate_reason(rule_result:, failed_checks:)
        return nil unless rule_result == "fail"

        "A current non-ineligible invoice for this participant already contains one of the same one-rebate-limited upgrade areas: #{failed_checks.join(", ")}."
      end

      def first_field_value(fields, key)
        field_values(fields, key).first
      end

      def field_values(fields, key)
        fields
          .select { |f| f.field_key == key }
          .map { |f| f.value_text.presence }
          .compact
      end

      def parse_date(value)
        return value if value.is_a?(Date)
        return value.to_date if value.respond_to?(:to_date)

        Date.iso8601(value.to_s)
      end

      def enabled_common_rule?(rule_key)
        ::Claims::CodeRules::Registry.enabled_for?(
          code_rule_key: rule_key,
          invoice_upgrade_type_id: common_upgrade_type_id,
          fallback: COMMON_RULE_FALLBACK_ENABLED
        )
      end

      def enabled_common_rule_keys
        @enabled_common_rule_keys ||=
          ::Claims::CodeRule
            .joins(:code_rule_upgrade_types)
            .where(enabled: true)
            .where(
              ::Claims::CodeRuleUpgradeType.table_name => {
                invoice_upgrade_type_id: common_upgrade_type_id
              }
            )
            .order(:code_rule_key)
            .pluck(:code_rule_key)
      end

      def validate_common_rule_coverage!
        missing_keys = enabled_common_rule_keys - COMMON_RULE_BUILDERS.keys
        return if missing_keys.empty?

        raise(
          "Enabled common code rules have no executor implementation: #{missing_keys.join(", ")}"
        )
      end

      def common_upgrade_type_id
        @common_upgrade_type_id ||=
          ::Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common").id
      end

      def append_admin_message(rule_key:, rule_result:, reason_text:)
        message =
          ::Claims::CodeRules::Registry.admin_message(
            code_rule_key: rule_key,
            rule_result: rule_result
          )

        return reason_text if message.blank?
        return message if reason_text.blank?
        return reason_text if reason_text.include?(message)
        return reason_text if message.include?(reason_text)

        [reason_text, message].join(" ")
      end

      def warn_row(rule_key:, expected_text:, detail_text:)
        row(
          rule_key: rule_key,
          rule_result: "warn",
          confidence: 0,
          expected_text: expected_text,
          detail_text: detail_text,
          evidence_text: nil,
          reason_and_likely_causes:
            "Required evidence was not available for deterministic validation. Admin should verify this specific missing context before treating it as a material failure."
        )
      end

      def row(
        rule_key:,
        rule_result:,
        confidence:,
        expected_text:,
        detail_text:,
        calculation: nil,
        evidence_text: nil,
        reason_and_likely_causes: nil
      )
        now = Time.current

        {
          invoice_version_id: invoice_version.id,
          invoice_upgrade_type_id: common_upgrade_type_id,
          source_engine: "code",
          rule_key: rule_key,
          rule_result: rule_result,
          confidence: confidence,
          expected_text: expected_text,
          calculation: calculation,
          evidence_text: evidence_text.presence || detail_text,
          reason_and_likely_causes:
            append_admin_message(
              rule_key: rule_key,
              rule_result: rule_result,
              reason_text: reason_and_likely_causes
            ),
          created_at: now,
          updated_at: now
        }
      end
    end
  end
end
