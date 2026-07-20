# frozen_string_literal: true

module Claims
  module RevisionIssues
    class CloseIssue
      TERMINAL_STATUSES = %w[
        closed_via_corrected_documentation
        closed_via_attestation
        closed_via_exception
        closed_as_withdrawn
      ].freeze

      def self.call(**args)
        new(**args).call
      end

      def initialize(issue:, status:, comment_text:)
        @issue = issue
        @status = status.to_s
        @comment_text = comment_text.to_s
      end

      def call
        issue = nil
        ::Claims::RevisionIssue.transaction do
          issue = ::Claims::RevisionIssue.lock.find(@issue.id)
          if issue.closed?
            raise ActiveRecord::ReadOnlyRecord, "This issue is already closed"
          end

          unless TERMINAL_STATUSES.include?(@status)
            issue.errors.add(:status, "is not a closing status")
            raise ActiveRecord::RecordInvalid, issue
          end
          if @comment_text.strip.blank?
            issue.errors.add(:base, "A final admin comment is required")
            raise ActiveRecord::RecordInvalid, issue
          end
          unless issue.invoice.status == "admin_review_inbox"
            raise ActiveRecord::ReadOnlyRecord,
                  "Issues can only be closed in the first-level admin inbox"
          end

          response = latest_contractor_response(issue)
          round = response&.revision_round || latest_round(issue)
          if round.nil?
            raise ActiveRecord::RecordNotFound,
                  "Revision issue history not found"
          end

          if round.waiting_for_contractor?
            raise ActiveRecord::ReadOnlyRecord,
                  "Wait for the contractor response before closing this issue"
          end
          remove_unsent_follow_up!(issue, basis_round: round)

          issue.comments.create!(
            revision_round: round,
            author_type: "admin",
            admin_recommended_remedy: nil,
            comment_text: @comment_text
          )
          issue.update!(status: @status)
        end
        issue
      end

      private

      def latest_contractor_response(issue)
        issue
          .comments
          .where(author_type: "contractor")
          .joins(:revision_round)
          .reorder(
            "claims.revision_rounds.round_number DESC",
            "claims.revision_issue_comments.created_at DESC",
            "claims.revision_issue_comments.id DESC"
          )
          .first
      end

      def latest_round(issue)
        issue.invoice.revision_rounds.newest_first.first
      end

      def remove_unsent_follow_up!(issue, basis_round:)
        draft = latest_round(issue)
        return unless draft&.draft?

        issue
          .comments
          .where(revision_round: draft, author_type: "admin")
          .destroy_all
        draft.destroy! if draft != basis_round && !draft.comments.exists?
      end
    end
  end
end
