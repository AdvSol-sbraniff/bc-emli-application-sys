# frozen_string_literal: true

module Claims
  module InvoiceVersionRulechecks
    class ApplyCodeRulechecks
      SOURCE_VINTAGE_DATE = Date.new(2026, 4, 1)
      COMMON_RULE_FALLBACK_ENABLED = false
      COMMON_RULE_KEYS = %w[
        source_vintage_applies
        first_class_invoice_fields_present
        submission_within_six_months
        eligibility_code_valid_for_invoice_date
        eligibility_code_found_in_database
      ].freeze
      COMMON_RULE_BUILDERS = {
        "source_vintage_applies" => :source_vintage_applies,
        "first_class_invoice_fields_present" =>
          :first_class_invoice_fields_present,
        "submission_within_six_months" => :submission_within_six_months,
        "eligibility_code_valid_for_invoice_date" =>
          :eligibility_code_valid_for_invoice_date,
        "eligibility_code_found_in_database" =>
          :eligibility_code_found_in_database
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

      def source_vintage_applies
        return nil unless enabled_common_rule?("source_vintage_applies")

        invoice_date = invoice_version.di_ocr_invoice_date

        if invoice_date.blank?
          return(
            warn_row(
              rule_number: 1,
              rule_key: "source_vintage_applies",
              expected_text:
                "Invoice date determines which RER vintage applies.",
              detail_text:
                "Invoice date was not found, so the correct requirements vintage needs admin confirmation."
            )
          )
        end

        pass = invoice_date >= SOURCE_VINTAGE_DATE
        result = pass ? "pass" : "warn"

        row(
          rule_number: 1,
          rule_key: "source_vintage_applies",
          rule_result: result,
          confidence: 100,
          expected_text:
            "Invoice date determines whether the current #{SOURCE_VINTAGE_DATE.iso8601} RER vintage applies or prior requirements may apply.",
          detail_text: "Invoice date=#{invoice_date.iso8601}.",
          calculation:
            "#{invoice_date.iso8601} >= #{SOURCE_VINTAGE_DATE.iso8601} => #{pass}; result=#{result}",
          evidence_text: "invoice_versions.di_ocr_invoice_date"
        )
      end

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
          rule_number: 2,
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
        submitted_at = invoice.submitted_at

        missing = []
        missing << "invoice date" if invoice_date.blank?
        missing << "invoice submitted_at" if submitted_at.blank?

        if missing.any?
          return(
            warn_row(
              rule_number: 3,
              rule_key: "submission_within_six_months",
              expected_text:
                "invoices.submitted_at <= invoice_date + 6 months.",
              detail_text: "Missing #{missing.join(" and ")}."
            )
          )
        end

        deadline = invoice_date.advance(months: 6)
        submitted_date = submitted_at.to_date
        pass = submitted_date <= deadline

        row(
          rule_number: 3,
          rule_key: "submission_within_six_months",
          rule_result: pass ? "pass" : "fail",
          confidence: 100,
          expected_text: "invoices.submitted_at <= invoice_date + 6 months.",
          detail_text:
            "invoice_date=#{invoice_date.iso8601}; invoices.submitted_at=#{submitted_date.iso8601}.",
          calculation:
            "#{invoice_date.iso8601} + 6 months = #{deadline.iso8601}; #{submitted_date.iso8601} <= #{deadline.iso8601} => #{pass}",
          evidence_text:
            "invoice_versions.di_ocr_invoice_date + claims.invoices.submitted_at"
        )
      end

      def eligibility_code_valid_for_invoice_date
        unless enabled_common_rule?("eligibility_code_valid_for_invoice_date")
          return nil
        end

        invoice_date = invoice_version.di_ocr_invoice_date
        approved_at =
          first_field_value(code_fields, "users_eligibilitycodes.approved_at")
        expires_at =
          first_field_value(code_fields, "users_eligibilitycodes.expires_at")
        eligibility_code =
          first_field_value(
            code_fields,
            "users_eligibilitycodes.eligibility_code"
          )

        missing = []
        missing << "invoice date" if invoice_date.blank?
        missing << "eligibility code approval date" if approved_at.blank?

        if missing.any?
          return(
            warn_row(
              rule_number: 4,
              rule_key: "eligibility_code_valid_for_invoice_date",
              expected_text:
                "Invoice date is within the eligibility-code validity window.",
              detail_text: "Missing #{missing.join(" and ")}."
            )
          )
        end

        approved_date = parse_date(approved_at)
        expiry_date = parse_date(expires_at)
        deadline = expiry_date || approved_date.advance(months: 6)
        pass = invoice_date >= approved_date && invoice_date <= deadline

        row(
          rule_number: 4,
          rule_key: "eligibility_code_valid_for_invoice_date",
          rule_result: pass ? "pass" : "fail",
          confidence: 100,
          expected_text:
            "Invoice date is on or after eligibility-code approval and on or before eligibility-code expiry.",
          detail_text:
            "eligibility_code=#{eligibility_code.presence || "missing"}; approved_at=#{approved_date.iso8601}; expiry=#{deadline.iso8601}; invoice_date=#{invoice_date.iso8601}.",
          calculation:
            "#{approved_date.iso8601} <= #{invoice_date.iso8601} <= #{deadline.iso8601} => #{pass}",
          evidence_text:
            "claims.users_eligibilitycodes + invoice_versions.di_ocr_invoice_date"
        )
      rescue ArgumentError
        warn_row(
          rule_number: 4,
          rule_key: "eligibility_code_valid_for_invoice_date",
          expected_text:
            "Eligibility approval/expiry dates are parseable dates.",
          detail_text: "Could not parse eligibility-code dates."
        )
      end

      def eligibility_code_found_in_database
        unless enabled_common_rule?("eligibility_code_found_in_database")
          return nil
        end

        db_code =
          first_field_value(
            code_fields,
            "users_eligibilitycodes.eligibility_code"
          ).to_s.strip

        if db_code.present?
          return(
            row(
              rule_number: 5,
              rule_key: "eligibility_code_found_in_database",
              rule_result: "pass",
              confidence: 100,
              expected_text:
                "The classifier-located eligibility code resolves to a populated claims.users_eligibilitycodes record.",
              detail_text:
                "Code-located users_eligibilitycodes.eligibility_code=#{db_code}.",
              calculation:
                "claims.invoice_version_located_fields[source_engine=code, field_key=users_eligibilitycodes.eligibility_code] is populated => true",
              evidence_text:
                "claims.invoice_version_located_fields source_engine=code field_key=users_eligibilitycodes.eligibility_code"
            )
          )
        end

        row(
          rule_number: 5,
          rule_key: "eligibility_code_found_in_database",
          rule_result: "fail",
          confidence: 100,
          expected_text:
            "The classifier-located eligibility code resolves to a populated claims.users_eligibilitycodes record.",
          detail_text:
            "No code-located users_eligibilitycodes.eligibility_code value was populated for this invoice version.",
          calculation:
            "claims.invoice_version_located_fields[source_engine=code, field_key=users_eligibilitycodes.eligibility_code] is populated => false",
          evidence_text:
            "claims.invoice_version_located_fields source_engine=code field_key=users_eligibilitycodes.eligibility_code",
          reason_and_likely_causes:
            "The case-facts build did not populate the matched database eligibility code, so the classifier-located eligibility code did not resolve to a usable users_eligibilitycodes record."
        )
      end

      def load_fields(source_engine)
        Claims::InvoiceVersionLocatedField.where(
          invoice_version_id: invoice_version.id,
          source_engine: source_engine
        ).to_a
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

        [reason_text, message].join(" ")
      end

      def warn_row(rule_number:, rule_key:, expected_text:, detail_text:)
        row(
          rule_number: rule_number,
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
        rule_number:,
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

        attrs = {
          invoice_version_id: invoice_version.id,
          invoice_upgrade_type_id: common_upgrade_type_id,
          source_engine: "code",
          rule_number: rule_number,
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

        optional_metadata = { rule_key: rule_key }

        optional_metadata.each do |key, value|
          attrs[
            key
          ] = value if Claims::InvoiceVersionRulecheck.column_names.include?(
            key.to_s
          )
        end

        attrs
      end
    end
  end
end
