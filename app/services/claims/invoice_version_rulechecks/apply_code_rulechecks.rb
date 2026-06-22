# frozen_string_literal: true

module Claims
  module InvoiceVersionRulechecks
    class ApplyCodeRulechecks
      SOURCE_VINTAGE_DATE = Date.new(2026, 4, 1)
      COMMON_RULE_FALLBACK_ENABLED = false
      PRIOR_REBATE_RULE_KEY = "prior_same_upgrade_type_rebate_payment_found"
      PAID_PRIOR_REBATE_STATUSES = %w[approved_paid].freeze
      ACTIVE_PRIOR_REBATE_STATUSES = %w[
        genai_complete
        admin_review_inbox
        contractor_revision_inbox
        in_review
        approved_pending
      ].freeze
      EXCLUDED_DUPLICATE_REBATE_UPGRADE_TYPE_KEYS = %w[common].freeze
      COMMON_RULE_KEYS = %w[
        source_vintage_applies
        first_class_invoice_fields_present
        submission_within_six_months
        eligibility_code_valid_for_invoice_date
        eligibility_code_found_in_database
        prior_same_upgrade_type_rebate_payment_found
      ].freeze
      COMMON_RULE_BUILDERS = {
        "source_vintage_applies" => :source_vintage_applies,
        "first_class_invoice_fields_present" =>
          :first_class_invoice_fields_present,
        "submission_within_six_months" => :submission_within_six_months,
        "eligibility_code_valid_for_invoice_date" =>
          :eligibility_code_valid_for_invoice_date,
        "eligibility_code_found_in_database" =>
          :eligibility_code_found_in_database,
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
        eligibility_code_record = matched_eligibility_code_record
        approved_at =
          eligibility_code_record&.approved_at ||
            first_field_value(code_fields, "users_eligibilitycodes.approved_at")
        expires_at =
          eligibility_code_record&.expires_at ||
            first_field_value(code_fields, "users_eligibilitycodes.expires_at")
        eligibility_code =
          eligibility_code_record&.eligibility_code ||
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
            "eligibility_code=#{eligibility_code.presence || "missing"}; users_eligibilitycode_id=#{invoice_version.users_eligibilitycode_id.presence || "missing"}; approved_at=#{approved_date.iso8601}; expiry=#{deadline.iso8601}; invoice_date=#{invoice_date.iso8601}.",
          calculation:
            "#{approved_date.iso8601} <= #{invoice_date.iso8601} <= #{deadline.iso8601} => #{pass}",
          evidence_text:
            "invoice_versions.users_eligibilitycode_id + claims.users_eligibilitycodes + invoice_versions.di_ocr_invoice_date"
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
              rule_number: 5,
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
          rule_number: 5,
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

      def prior_same_upgrade_type_rebate_payment_found
        return nil unless enabled_common_rule?(PRIOR_REBATE_RULE_KEY)

        if invoice_version.participant_user_id.blank?
          return(
            row(
              rule_number: 6,
              rule_key: PRIOR_REBATE_RULE_KEY,
              rule_result: "warn",
              confidence: 0,
              expected_text:
                "Matched participant is available before checking prior same-upgrade rebate payments.",
              detail_text:
                "invoice_versions.participant_user_id is missing; duplicate-payment history cannot be checked.",
              calculation: "participant_user_id is populated => false",
              evidence_text: "invoice_versions.participant_user_id",
              reason_and_likely_causes:
                "The deterministic enrichment step did not populate participant_user_id, so code cannot safely compare this invoice against the participant's prior invoices."
            )
          )
        end

        current_upgrade_types = distinct_current_duplicate_rebate_upgrade_types

        if current_upgrade_types.empty?
          return(
            row(
              rule_number: 6,
              rule_key: PRIOR_REBATE_RULE_KEY,
              rule_result: "warn",
              confidence: 0,
              expected_text:
                "At least one detected upgrade type is available for duplicate-payment comparison.",
              detail_text:
                "No non-common detected upgrade types were found for this invoice version.",
              calculation:
                "distinct non-common invoice_version_upgrade_types count = 0",
              evidence_text: "claims.invoice_version_upgrade_types",
              reason_and_likely_causes:
                "The classifier did not leave a non-common detected upgrade type for this invoice version, so code cannot compare prior rebate payments."
            )
          )
        end

        evaluations =
          current_upgrade_types.map do |upgrade_type|
            prior_matches =
              latest_prior_same_upgrade_type_matches(
                invoice_upgrade_type_id: upgrade_type.id
              )
            failed_matches =
              prior_matches.select do |match|
                PAID_PRIOR_REBATE_STATUSES.include?(match.status)
              end
            warning_matches =
              prior_matches.select do |match|
                ACTIVE_PRIOR_REBATE_STATUSES.include?(match.status)
              end
            ignored_matches = prior_matches - failed_matches - warning_matches
            result =
              if failed_matches.any?
                "fail"
              elsif warning_matches.any?
                "warn"
              else
                "pass"
              end

            {
              upgrade_type: upgrade_type,
              prior_matches: prior_matches,
              failed_matches: failed_matches,
              warning_matches: warning_matches,
              ignored_matches: ignored_matches,
              result: result
            }
          end

        rule_result =
          if evaluations.any? { |evaluation| evaluation[:result] == "fail" }
            "fail"
          elsif evaluations.any? { |evaluation| evaluation[:result] == "warn" }
            "warn"
          else
            "pass"
          end

        row(
          rule_number: 6,
          rule_key: PRIOR_REBATE_RULE_KEY,
          rule_result: rule_result,
          confidence: 100,
          expected_text:
            "Participant has no prior paid or active claim for the same exact detected upgrade type.",
          detail_text: prior_rebate_detail_text(evaluations),
          calculation: prior_rebate_calculation(evaluations),
          evidence_text:
            "invoice_versions.participant_user_id + latest invoice_versions per invoice_id + claims.invoice_version_upgrade_types + claims.invoices.status",
          reason_and_likely_causes: prior_rebate_reason(rule_result)
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

      def distinct_current_duplicate_rebate_upgrade_types
        @distinct_current_duplicate_rebate_upgrade_types ||=
          ::Claims::InvoiceUpgradeType
            .joins(
              "INNER JOIN claims.invoice_version_upgrade_types ivut " \
                "ON ivut.invoice_upgrade_type_id = " \
                "#{::Claims::InvoiceUpgradeType.table_name}.id"
            )
            .where(ivut: { invoice_version_id: invoice_version.id })
            .where.not(
              upgrade_type_key: EXCLUDED_DUPLICATE_REBATE_UPGRADE_TYPE_KEYS
            )
            .distinct
            .order(:upgrade_type_key)
            .to_a
      end

      def latest_prior_same_upgrade_type_matches(invoice_upgrade_type_id:)
        latest_versions_sql =
          ::Claims::InvoiceVersion
            .select(
              "DISTINCT ON (invoice_id) " \
                "id, invoice_id, invoice_versionno, participant_user_id, " \
                "users_eligibilitycode_id"
            )
            .where(participant_user_id: invoice_version.participant_user_id)
            .where.not(invoice_id: invoice.id)
            .order(:invoice_id, invoice_versionno: :desc)
            .to_sql

        ::Claims::Invoice
          .from("claims.invoices AS prior_invoices")
          .joins(
            "INNER JOIN (#{latest_versions_sql}) latest_versions " \
              "ON latest_versions.invoice_id = prior_invoices.id"
          )
          .joins(
            "INNER JOIN claims.invoice_version_upgrade_types prior_ivut " \
              "ON prior_ivut.invoice_version_id = latest_versions.id"
          )
          .where(
            prior_ivut: {
              invoice_upgrade_type_id: invoice_upgrade_type_id
            }
          )
          .select(
            "prior_invoices.id AS invoice_id",
            "prior_invoices.status AS status",
            "prior_invoices.submitted_at AS submitted_at",
            "latest_versions.id AS invoice_version_id",
            "latest_versions.invoice_versionno AS invoice_versionno"
          )
          .order(
            Arel.sql(
              "CASE prior_invoices.status " \
                "WHEN 'approved_paid' THEN 0 " \
                "WHEN 'approved_pending' THEN 1 " \
                "WHEN 'in_review' THEN 2 " \
                "WHEN 'admin_review_inbox' THEN 3 " \
                "WHEN 'contractor_revision_inbox' THEN 4 " \
                "WHEN 'genai_complete' THEN 5 " \
                "ELSE 6 END"
            ),
            Arel.sql("prior_invoices.created_at DESC")
          )
          .to_a
          .uniq { |match| match.invoice_version_id }
      end

      def prior_rebate_detail_text(evaluations)
        [
          "participant_user_id=#{invoice_version.participant_user_id}",
          "users_eligibilitycode_id=#{invoice_version.users_eligibilitycode_id.presence || "missing"}",
          "current_invoice_id=#{invoice.id}",
          "current_invoice_version_id=#{invoice_version.id}",
          "upgrade checks: #{prior_rebate_upgrade_summaries(evaluations).join(" | ")}"
        ].join("; ")
      end

      def prior_rebate_upgrade_summaries(evaluations)
        evaluations.map do |evaluation|
          upgrade_type = evaluation[:upgrade_type]
          parts = ["#{upgrade_type.upgrade_type_key}=#{evaluation[:result]}"]
          if evaluation[:failed_matches].any?
            parts << "paid prior #{prior_rebate_match_list(evaluation[:failed_matches])}"
          end
          if evaluation[:warning_matches].any?
            parts << "active prior #{prior_rebate_match_list(evaluation[:warning_matches])}"
          end
          if evaluation[:ignored_matches].any?
            parts << "ignored prior #{prior_rebate_match_list(evaluation[:ignored_matches])}"
          end

          if parts.size == 1
            parts.first
          else
            "#{parts.first} (#{parts.drop(1).join("; ")})"
          end
        end
      end

      def prior_rebate_match_list(matches)
        matches
          .map do |match|
            "#{match.status}:invoice_id=#{match.invoice_id}," \
              "invoice_version_id=#{match.invoice_version_id}," \
              "version=#{match.invoice_versionno}"
          end
          .join(", ")
      end

      def prior_rebate_calculation(evaluations)
        evaluations
          .map do |evaluation|
            "#{evaluation[:upgrade_type].upgrade_type_key}: " \
              "paid_matches=#{evaluation[:failed_matches].size}, " \
              "active_matches=#{evaluation[:warning_matches].size}, " \
              "ignored_matches=#{evaluation[:ignored_matches].size} " \
              "=> #{evaluation[:result]}"
          end
          .join("; ")
      end

      def prior_rebate_reason(rule_result)
        case rule_result
        when "fail"
          "A latest invoice version on another invoice parent for this participant has the same exact detected upgrade type and an approved-paid status."
        when "warn"
          "A latest invoice version on another invoice parent for this participant has the same exact detected upgrade type in an active or payment-pending status."
        else
          nil
        end
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
