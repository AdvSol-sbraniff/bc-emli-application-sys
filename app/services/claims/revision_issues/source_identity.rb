# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SourceIdentity
      def self.for_issue(issue)
        case issue.issue_type
        when "rule"
          if issue.opened_from_rule_key.present?
            return [
              "rule",
              issue.opened_from_rule_key,
              issue.opened_from_rule_upgrade_type_id
            ]
          end

          row = issue.opened_from_invoice_version_rulecheck
          ["rule", row&.rule_key, row&.invoice_upgrade_type_id]
        when "invoice_field"
          if issue.opened_from_invoice_field_key.present?
            return [
              "invoice_field",
              issue.opened_from_invoice_field_key,
              issue.opened_from_invoice_field_upgrade_type_id
            ]
          end

          row = issue.opened_from_invoice_version_located_field
          ["invoice_field", row&.field_key, row&.invoice_upgrade_type_id]
        when "supporting_document_field"
          if issue.opened_from_supporting_field_key.present?
            return [
              "supporting_document_field",
              issue.opened_from_supporting_document_type_key,
              issue.opened_from_supporting_field_key
            ]
          end

          row = issue.opened_from_supporting_document_located_field
          [
            "supporting_document_field",
            row&.supporting_document&.supporting_document_type&.type_key,
            row&.field_key
          ]
        when "di_field"
          ["di_field", issue.opened_from_di_field_key]
        end
      end

      def self.for_source(issue_type:, source:)
        case issue_type
        when "rule"
          ["rule", source.rule_key, source.invoice_upgrade_type_id]
        when "invoice_field"
          ["invoice_field", source.field_key, source.invoice_upgrade_type_id]
        when "supporting_document_field"
          [
            "supporting_document_field",
            source.supporting_document&.supporting_document_type&.type_key,
            source.field_key
          ]
        when "di_field"
          ["di_field", source.to_s]
        end
      end

      def self.attributes_for_source(issue_type:, source:)
        case issue_type
        when "rule"
          {
            opened_from_rule_key: source.rule_key,
            opened_from_rule_upgrade_type_id: source.invoice_upgrade_type_id
          }
        when "invoice_field"
          {
            opened_from_invoice_field_key: source.field_key,
            opened_from_invoice_field_upgrade_type_id:
              source.invoice_upgrade_type_id
          }
        when "supporting_document_field"
          type_key =
            source.supporting_document&.supporting_document_type&.type_key
          if type_key.blank?
            raise CreateIssue::SourceMismatch,
                  "Supporting document must have a document type before opening a field issue"
          end

          {
            opened_from_supporting_document_type_key: type_key,
            opened_from_supporting_field_key: source.field_key
          }
        when "di_field"
          {}
        else
          {}
        end
      end

      def self.serialize(issue)
        identity = for_issue(issue)
        case identity&.first
        when "rule"
          {
            kind: "rule",
            rule_key: identity[1],
            invoice_upgrade_type_id: identity[2]
          }
        when "invoice_field"
          {
            kind: "invoice_field",
            field_key: identity[1],
            invoice_upgrade_type_id: identity[2]
          }
        when "supporting_document_field"
          {
            kind: "supporting_document_field",
            supporting_document_type_key: identity[1],
            field_key: identity[2]
          }
        when "di_field"
          { kind: "di_field", field_key: identity[1] }
        else
          {}
        end
      end
    end
  end
end
