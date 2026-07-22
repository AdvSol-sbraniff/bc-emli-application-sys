# frozen_string_literal: true

module Claims
  module RevisionIssues
    class BackfillSourceIdentity
      Result = Data.define(:updated, :skipped)

      def self.call(scope: ::Claims::RevisionIssue.all)
        new(scope: scope).call
      end

      def initialize(scope:)
        @scope = scope
      end

      def call
        updated = 0
        skipped = 0

        scope.find_each do |issue|
          source = source_for(issue)
          if source.blank?
            skipped += 1
            next
          end

          attributes =
            SourceIdentity.attributes_for_source(
              issue_type: issue.issue_type,
              source: source
            )
          attributes[:opened_from_source_snapshot] = SourcePresenter
            .new(issue)
            .call
            .deep_stringify_keys
          issue.update_columns(attributes.merge(updated_at: Time.current))
          updated += 1
        rescue CreateIssue::SourceMismatch
          skipped += 1
        end

        Result.new(updated: updated, skipped: skipped)
      end

      private

      attr_reader :scope

      def source_for(issue)
        case issue.issue_type
        when "rule"
          issue.opened_from_invoice_version_rulecheck
        when "invoice_field"
          issue.opened_from_invoice_version_located_field
        when "supporting_document_field"
          issue.opened_from_supporting_document_located_field
        when "di_field"
          issue.opened_from_di_field_key
        end
      end
    end
  end
end
