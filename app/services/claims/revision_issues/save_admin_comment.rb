# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SaveAdminComment
      def self.call(**args)
        new(**args).call
      end

      def initialize(issue:, attributes:)
        @issue = issue
        @attributes = attributes.to_h.symbolize_keys
      end

      def call
        comment = nil
        ::Claims::RevisionIssue.transaction do
          issue = ::Claims::RevisionIssue.lock.find(@issue.id)
          unless issue.unresolved?
            raise ActiveRecord::ReadOnlyRecord, "Closed issues are immutable"
          end

          round = EnsureDraftRound.call(invoice: issue.invoice)
          comment =
            issue.comments.find_or_initialize_by(
              revision_round: round,
              author_type: "admin"
            )
          comment.assign_attributes(
            @attributes.slice(:admin_recommended_remedy, :comment_text)
          )
          comment.save!
        end
        comment
      end
    end
  end
end
