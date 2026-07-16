# frozen_string_literal: true

module Claims
  module RevisionIssues
    class UpdateAdminComment
      def self.call(comment:, attributes:)
        round = comment.revision_round
        unless comment.admin? && round.draft? && round.latest?
          raise ActiveRecord::ReadOnlyRecord,
                "Only admin comments in the latest unsent round can be edited"
        end
        if comment.revision_issue.closed?
          raise ActiveRecord::ReadOnlyRecord, "Closed issues are immutable"
        end

        comment.update!(
          attributes.to_h.symbolize_keys.slice(
            :admin_recommended_remedy,
            :comment_text
          )
        )
        comment
      end
    end
  end
end
