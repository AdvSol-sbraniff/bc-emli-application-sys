# frozen_string_literal: true

module Claims
  module RevisionIssues
    class ResetAdminComment
      def self.call(comment:)
        UpdateAdminComment.call(
          comment: comment,
          attributes: {
            admin_recommended_remedy:
              BuildAdminCommentDraft.default_remedy(
                issue: comment.revision_issue
              ),
            comment_text:
              BuildAdminCommentDraft.call(issue: comment.revision_issue)
          }
        )
      end
    end
  end
end
