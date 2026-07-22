# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SendRound
      class Incomplete < StandardError
        attr_reader :details

        def initialize(message, details = {})
          @details = details
          super(message)
        end
      end

      def self.call(**args)
        new(**args).call
      end

      def initialize(revision_round:, actor_user_id:)
        @revision_round = revision_round
        @actor_user_id = actor_user_id
      end

      def call
        round = nil
        ::Claims::RevisionRound.transaction do
          round = ::Claims::RevisionRound.lock.find(@revision_round.id)
          unless round.latest? && round.draft?
            raise ActiveRecord::ReadOnlyRecord,
                  "Only the latest unsent issue comments can be sent"
          end
          unless round.invoice.status == "admin_review_inbox"
            raise ActiveRecord::ReadOnlyRecord,
                  "The invoice is not in the first-level admin inbox"
          end

          coverage =
            ReviewCoverage.call(
              invoice: round.invoice,
              invoice_version: round.invoice_version
            )
          if coverage.missing_rulechecks.any?
            raise Incomplete.new(
                    "Every workflow-managed rule result needs a revision issue",
                    missing_rulecheck_ids:
                      coverage.missing_rulechecks.map(&:id),
                    missing_decisions:
                      coverage.missing_rulechecks.map do |row|
                        {
                          source_type: "rule",
                          source_id: row.id,
                          friendly_label:
                            row.contractor_display_name.to_s.strip.presence ||
                              row.rule_key.to_s.humanize
                        }
                      end
                  )
          end

          admin_comments =
            round
              .comments
              .includes(:revision_issue)
              .where(author_type: "admin")
              .to_a
          unresolved_issues =
            round.invoice.revision_issues.unresolved_issues.to_a
          represented_issue_ids = admin_comments.to_set(&:revision_issue_id)
          missing_issues =
            unresolved_issues.reject do |issue|
              represented_issue_ids.include?(issue.id)
            end
          if missing_issues.any?
            raise Incomplete.new(
                    "Every unresolved issue needs an admin recommendation before sending",
                    issue_ids: missing_issues.map(&:id),
                    missing_decisions:
                      missing_issues.map do |issue|
                        source = SourcePresenter.call(issue)
                        {
                          source_type: issue.issue_type,
                          source_id: issue.id,
                          friendly_label:
                            source[:friendly_label].to_s.strip.presence ||
                              issue.issue_type.humanize
                        }
                      end
                  )
          end
          actionable =
            admin_comments.select do |comment|
              comment.revision_issue.unresolved?
            end
          if actionable.empty?
            raise Incomplete,
                  "At least one unresolved issue needs an admin recommendation"
          end
          incomplete =
            actionable.select do |comment|
              comment.admin_recommended_remedy.blank? ||
                comment.comment_text.to_s.strip.blank?
            end
          if incomplete.any?
            raise Incomplete.new(
                    "Every unresolved issue needs a recommendation and comment",
                    comment_ids: incomplete.map(&:id),
                    issue_ids: incomplete.map(&:revision_issue_id)
                  )
          end

          now = Time.current
          actionable
            .map(&:revision_issue)
            .select(&:pending_admin_review?)
            .uniq(&:id)
            .each { |issue| issue.update!(status: "open") }
          round.update!(admin_sent_at: now)
          round.invoice.set_workflow_status!(
            "contractor_revision_inbox",
            actor_user_id: @actor_user_id,
            invoice_version_id: round.invoice_version_id
          )
        end
        round
      end
    end
  end
end
