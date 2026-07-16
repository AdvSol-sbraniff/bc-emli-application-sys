# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SourceIdentity
      def self.for_issue(issue)
        case issue.issue_type
        when "rule"
          row = issue.opened_from_invoice_version_rulecheck
          [
            "rule",
            row&.source_engine,
            row&.rule_key,
            row&.invoice_upgrade_type_id
          ]
        when "invoice_field"
          row = issue.opened_from_invoice_version_located_field
          [
            "invoice_field",
            row&.source_engine,
            row&.field_key,
            row&.invoice_upgrade_type_id
          ]
        when "supporting_document_field"
          row = issue.opened_from_supporting_document_located_field
          [
            "supporting_document_field",
            row&.supporting_document_type_located_field_id || row&.field_key
          ]
        when "di_field"
          ["di_field", issue.opened_from_di_field_key]
        end
      end

      def self.for_source(issue_type:, source:)
        case issue_type
        when "rule"
          [
            "rule",
            source.source_engine,
            source.rule_key,
            source.invoice_upgrade_type_id
          ]
        when "invoice_field"
          [
            "invoice_field",
            source.source_engine,
            source.field_key,
            source.invoice_upgrade_type_id
          ]
        when "supporting_document_field"
          [
            "supporting_document_field",
            source.supporting_document_type_located_field_id || source.field_key
          ]
        when "di_field"
          ["di_field", source.to_s]
        end
      end
    end
  end
end
