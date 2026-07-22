# frozen_string_literal: true

module Claims
  module RevisionIssues
    class CloseIssue
      TERMINAL_STATUSES = %w[
        closed_no_contractor_action_required
        closed_via_corrected_documentation
        closed_via_attestation
        closed_via_exception
        closed_as_withdrawn
      ].freeze

      def self.call(**args)
        new(**args).call
      end

      def initialize(issue:, status:, disposition_comment:)
        @issue = issue
        @status = status.to_s
        @disposition_comment = disposition_comment.to_s
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
          if @disposition_comment.strip.blank?
            issue.errors.add(:base, "A disposition comment is required")
            raise ActiveRecord::RecordInvalid, issue
          end
          unless issue.invoice.status == "admin_review_inbox"
            raise ActiveRecord::ReadOnlyRecord,
                  "Issues can only be closed in the first-level admin inbox"
          end

          if issue.pending_admin_review?
            close_internal_issue!(issue)
          else
            close_contractor_issue!(issue)
          end
        end
        issue
      end

      private

      def close_internal_issue!(issue)
        unless @status == "closed_no_contractor_action_required"
          issue.errors.add(
            :status,
            "must be no contractor action required before an issue is sent"
          )
          raise ActiveRecord::RecordInvalid, issue
        end

        round = latest_round(issue)
        if round.nil? || !round.draft?
          raise ActiveRecord::ReadOnlyRecord,
                "Internal closure is only available before an issue is sent"
        end
        issue.comments.where(revision_round: round).destroy_all
        issue.update!(
          status: @status,
          disposition_comment: @disposition_comment.strip
        )
        round.destroy! unless round.comments.exists?
      end

      def close_contractor_issue!(issue)
        if @status == "closed_no_contractor_action_required"
          issue.errors.add(
            :status,
            "is unavailable after an issue has been sent to the contractor"
          )
          raise ActiveRecord::RecordInvalid, issue
        end

        response = latest_contractor_response(issue)
        round = response&.revision_round || latest_round(issue)
        if round.nil?
          raise ActiveRecord::RecordNotFound, "Revision issue history not found"
        end
        if round.waiting_for_contractor?
          raise ActiveRecord::ReadOnlyRecord,
                "Wait for the contractor response before closing this issue"
        end
        remove_unsent_follow_up!(issue, basis_round: round)
        issue.update!(
          status: @status,
          disposition_comment: @disposition_comment.strip
        )
      end

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
