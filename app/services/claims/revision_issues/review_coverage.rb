# frozen_string_literal: true

module Claims
  module RevisionIssues
    class ReviewCoverage
      Result =
        Struct.new(
          :complete,
          :missing_rulechecks,
          :open_issues,
          keyword_init: true
        )

      def self.call(invoice:, invoice_version: nil)
        version =
          invoice_version ||
            invoice
              .invoice_versions
              .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
              .first
        required =
          (
            if version
              version
                .rulechecks
                .admin_workflow_managed
                .order(:created_at, :id)
                .to_a
            else
              []
            end
          )
        issues = ::Claims::RevisionIssue.where(invoice_id: invoice.id).to_a
        identities =
          issues.map { |issue| SourceIdentity.for_issue(issue) }.to_set
        missing =
          required.reject do |row|
            identities.include?(
              SourceIdentity.for_source(issue_type: "rule", source: row)
            )
          end
        open_issues = issues.select(&:open?)

        Result.new(
          complete: missing.empty? && open_issues.empty?,
          missing_rulechecks: missing,
          open_issues: open_issues
        )
      end
    end
  end
end
