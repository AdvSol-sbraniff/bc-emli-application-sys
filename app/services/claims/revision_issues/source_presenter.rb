# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SourcePresenter
      DI_FIELDS = {
        "invoice_id" => ["Invoice number", "text"],
        "invoice_date" => ["Invoice date", "date"],
        "vendor_name" => ["Contractor name", "text"],
        "vendor_address" => ["Contractor address", "text"],
        "customer_name" => ["Participant name", "text"],
        "customer_address" => ["Participant address", "text"],
        "customer_address_recipient" => [
          "Participant address recipient",
          "text"
        ],
        "service_address" => ["Installation address", "text"],
        "service_address_recipient" => [
          "Installation address recipient",
          "text"
        ],
        "billing_address" => ["Billing address", "text"],
        "billing_address_recipient" => ["Billing address recipient", "text"],
        "sub_total" => %w[Sub-total currency],
        "total_tax" => ["Total tax", "currency"],
        "invoice_total" => ["Invoice total", "currency"],
        "amount_due" => ["Amount due", "currency"]
      }.freeze

      def self.call(issue)
        snapshot = issue.opened_from_source_snapshot
        return snapshot.deep_symbolize_keys if snapshot.present?

        new(issue).call
      end

      def initialize(issue)
        @issue = issue
      end

      def call
        case @issue.issue_type
        when "rule"
          rule_source
        when "invoice_field"
          invoice_field_source
        when "supporting_document_field"
          supporting_field_source
        when "di_field"
          di_field_source
        else
          {}
        end
      end

      private

      def rule_source
        row = @issue.opened_from_invoice_version_rulecheck
        registry = rule_registry(row)
        {
          source_key: row&.rule_key,
          friendly_label:
            row&.contractor_display_name.presence ||
              registry&.contractor_display_name.presence ||
              row&.rule_key.to_s.humanize,
          source_engine: row&.source_engine,
          rule_result: row&.rule_result,
          confidence: row&.confidence,
          reason: row&.reason_and_likely_causes,
          evidence_text: row&.evidence_text,
          expected_text: row&.expected_text,
          calculation: row&.calculation,
          source_quote: registry&.source_quote,
          page: nil,
          polygon: nil,
          value: nil,
          value_type: nil,
          document: invoice_document(row&.invoice_version)
        }
      end

      def invoice_field_source
        row = @issue.opened_from_invoice_version_located_field
        registry = located_field_registry(row)
        {
          source_key: row&.field_key,
          friendly_label:
            registry&.contractor_display_name.presence ||
              classifier_field_label(row) || row&.field_key.to_s.humanize,
          source_engine: row&.source_engine,
          confidence: row&.confidence,
          evidence_text: row&.evidence_text,
          page: row&.page,
          polygon: row&.polygon,
          value: located_value(row),
          value_type: row&.value_type,
          document: invoice_document(row&.invoice_version)
        }
      end

      def supporting_field_source
        row = @issue.opened_from_supporting_document_located_field
        definition = row&.supporting_document_type_located_field
        document = row&.supporting_document
        {
          source_key: row&.field_key,
          friendly_label:
            definition&.contractor_display_name.presence ||
              row&.field_key.to_s.humanize,
          source_engine: row&.source_engine,
          confidence: row&.confidence,
          evidence_text: row&.evidence_text,
          page: row&.page,
          polygon: row&.polygon,
          value: located_value(row),
          value_type: row&.value_type,
          document: {
            kind: "supporting_document",
            id: document&.id,
            invoice_version_id: document&.invoice_version_id,
            filename: document&.original_filename,
            content_type: document&.content_type
          }
        }
      end

      def di_field_source
        key = @issue.opened_from_di_field_key.to_s
        label, value_type = DI_FIELDS.fetch(key, [key.humanize, "text"])
        version = @issue.opened_from_di_invoice_version
        {
          source_key: key,
          friendly_label: label,
          source_engine: "document_intelligence",
          page: version&.public_send("di_ocr_#{key}_page"),
          polygon: version&.public_send("di_ocr_#{key}_polygon"),
          value: version&.public_send("di_ocr_#{key}"),
          value_type: value_type,
          evidence_text: nil,
          document: invoice_document(version)
        }
      rescue NoMethodError
        {
          source_key: key,
          friendly_label: label,
          source_engine: "document_intelligence",
          page: nil,
          polygon: nil,
          value: nil,
          value_type: value_type,
          document: invoice_document(version)
        }
      end

      def rule_registry(row)
        return if row.blank?

        if row.source_engine == "code"
          ::Claims::CodeRule.find_by(code_rule_key: row.rule_key)
        else
          ::Claims::GenaiRule.find_by(genai_rule_key: row.rule_key)
        end
      end

      def located_field_registry(row)
        return if row.blank?

        if row.source_engine == "code"
          ::Claims::CodeLocatedField.find_by(code_field_key: row.field_key)
        elsif row.source_engine == "genai"
          ::Claims::GenaiLocatedField.find_by(genai_field_key: row.field_key)
        end
      end

      def classifier_field_label(row)
        return unless row&.source_engine == "classifier"
        if row.field_key == "classifier.eligibility_code"
          return "Eligibility code"
        end
      end

      def located_value(row)
        return if row.blank?

        row.value_type == "json" ? row.value_json : row.value_text
      end

      def invoice_document(version)
        return {} if version.blank?

        {
          kind: "invoice",
          id: version.id,
          invoice_version_id: version.id,
          invoice_versionno: version.invoice_versionno,
          filename: version.original_filename,
          content_type: version.content_type
        }
      end
    end
  end
end
