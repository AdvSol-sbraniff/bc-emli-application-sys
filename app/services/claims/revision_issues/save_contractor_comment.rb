# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SaveContractorComment
      def self.call(**args)
        new(**args).call
      end

      def initialize(issue:, round:, attributes:)
        @issue = issue
        @round = round
        @attributes = attributes.to_h.symbolize_keys
      end

      def call
        comment = nil
        ::Claims::RevisionIssueComment.transaction do
          issue = ::Claims::RevisionIssue.lock.find(@issue.id)
          round = ::Claims::RevisionRound.lock.find(@round.id)
          unless issue.open? && round.latest? && round.waiting_for_contractor?
            raise ActiveRecord::ReadOnlyRecord,
                  "This issue is not awaiting a contractor response"
          end
          unless round
                   .comments
                   .where(revision_issue_id: issue.id, author_type: "admin")
                   .where.not(admin_recommended_remedy: nil)
                   .exists?
            raise ActiveRecord::ReadOnlyRecord,
                  "This issue was not requested in the current round"
          end

          attrs =
            @attributes.slice(
              :contractor_response_method,
              :comment_text,
              :contractor_asserted_value
            )
          comment =
            round
              .comments
              .where(revision_issue_id: issue.id, author_type: "contractor")
              .order(created_at: :desc, id: :desc)
              .first
          if comment
            comment.update!(attrs)
          else
            comment =
              issue.comments.create!(
                attrs.merge(revision_round: round, author_type: "contractor")
              )
          end
        end
        comment
      end
    end
  end
end
