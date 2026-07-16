# frozen_string_literal: true

module Claims
  module RevisionIssues
    class DeleteUnsentIssue
      def self.call(issue:)
        ::Claims::RevisionIssue.transaction do
          issue = ::Claims::RevisionIssue.lock.find(issue.id)
          round = issue.invoice.revision_rounds.newest_first.first
          unless issue.open? && round&.latest? && round.draft?
            raise ActiveRecord::ReadOnlyRecord,
                  "Only a new issue that has never been sent can be deleted"
          end
          if issue.contractor_visible?
            raise ActiveRecord::ReadOnlyRecord,
                  "An issue that was already sent cannot be deleted; close it with a disposition"
          end

          issue.destroy!
          round.destroy! unless round.comments.exists?
        end
      end
    end
  end
end
