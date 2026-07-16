# frozen_string_literal: true

module Claims
  module RevisionIssues
    class ContractorResponseCoverage
      Result =
        Struct.new(
          :issue_ids,
          :responses_by_issue,
          :incomplete_issue_ids,
          :document_upload_required_issue_ids,
          keyword_init: true
        ) do
          def complete?
            incomplete_issue_ids.empty? &&
              document_upload_required_issue_ids.empty?
          end
        end

      def self.call(round:)
        issue_ids =
          round
            .comments
            .reorder(nil)
            .joins(:revision_issue)
            .where(
              :author_type => "admin",
              "claims.revision_issues" => {
                status: "open"
              }
            )
            .where.not(admin_recommended_remedy: nil)
            .distinct
            .pluck(:revision_issue_id)
        responses =
          round
            .comments
            .reorder(nil)
            .where(author_type: "contractor", revision_issue_id: issue_ids)
            .order(:created_at, :id)
            .index_by(&:revision_issue_id)
        incomplete =
          issue_ids.reject do |issue_id|
            responses[issue_id]&.contractor_response_complete?
          end
        document_issue_ids =
          responses
            .values
            .select do |comment|
              comment.contractor_response_method.in?(
                %w[corrected_invoice_uploaded supporting_document_uploaded]
              )
            end
            .map(&:revision_issue_id)
        latest_invoice_version_id =
          round
            .invoice
            .invoice_versions
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .pick(:id)
        document_upload_required_issue_ids =
          if latest_invoice_version_id == round.invoice_version_id
            document_issue_ids
          else
            []
          end

        Result.new(
          issue_ids: issue_ids,
          responses_by_issue: responses,
          incomplete_issue_ids: incomplete,
          document_upload_required_issue_ids: document_upload_required_issue_ids
        )
      end
    end
  end
end
