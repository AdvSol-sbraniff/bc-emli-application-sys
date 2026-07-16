# frozen_string_literal: true

module Claims
  module RevisionIssues
    class ApprovalGate
      Result =
        Struct.new(
          :allowed,
          :error,
          :issue_ids,
          :missing_rulecheck_ids,
          keyword_init: true
        )

      def self.call(invoice:)
        latest = invoice.revision_rounds.newest_first.first
        if latest&.waiting_for_contractor?
          return(
            Result.new(
              allowed: false,
              error: "The open revision issues are still with the contractor",
              issue_ids: open_issue_ids_for_round(latest),
              missing_rulecheck_ids: []
            )
          )
        end

        coverage = ReviewCoverage.call(invoice: invoice)
        if coverage.missing_rulechecks.any?
          return(
            Result.new(
              allowed: false,
              error:
                "Every workflow-managed failing rule needs a revision issue",
              issue_ids: coverage.open_issues.map(&:id),
              missing_rulecheck_ids: coverage.missing_rulechecks.map(&:id)
            )
          )
        end
        if coverage.open_issues.any?
          return(
            Result.new(
              allowed: false,
              error:
                "Every revision issue must be closed before four-eyes review",
              issue_ids: coverage.open_issues.map(&:id),
              missing_rulecheck_ids: []
            )
          )
        end

        Result.new(
          allowed: true,
          error: nil,
          issue_ids: [],
          missing_rulecheck_ids: []
        )
      end

      def self.open_issue_ids_for_round(round)
        round
          .comments
          .includes(:revision_issue)
          .map(&:revision_issue)
          .select(&:open?)
          .map(&:id)
          .uniq
      end
      private_class_method :open_issue_ids_for_round
    end
  end
end
