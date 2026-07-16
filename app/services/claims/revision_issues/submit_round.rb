# frozen_string_literal: true

module Claims
  module RevisionIssues
    class SubmitRound
      class Incomplete < StandardError
        attr_reader :issue_ids

        def initialize(message, issue_ids: [])
          @issue_ids = issue_ids
          super(message)
        end
      end

      class DocumentUploadRequired < Incomplete
      end

      def self.call(**args)
        new(**args).call
      end

      def initialize(invoice:, actor_user_id:, invoice_version:)
        @invoice = invoice
        @actor_user_id = actor_user_id
        @invoice_version = invoice_version
      end

      def call
        round = nil
        ::Claims::Invoice.transaction do
          invoice = ::Claims::Invoice.lock.find(@invoice.id)
          round = invoice.revision_rounds.newest_first.first
          unless round&.waiting_for_contractor?
            raise Incomplete,
                  "No revision issues are awaiting a contractor response"
          end

          coverage = ContractorResponseCoverage.call(round: round)
          if coverage.incomplete_issue_ids.any?
            raise Incomplete.new(
                    "Every requested issue needs a complete contractor response",
                    issue_ids: coverage.incomplete_issue_ids
                  )
          end

          if coverage.document_upload_required_issue_ids.any?
            raise DocumentUploadRequired.new(
                    "A corrected-document response requires a newly processed package version",
                    issue_ids: coverage.document_upload_required_issue_ids
                  )
          end

          now = Time.current
          round.update!(contractor_response_submitted_at: now)
          invoice.set_workflow_status!(
            "admin_review_inbox",
            actor_user_id: @actor_user_id,
            invoice_version_id: @invoice_version.id,
            submitter_id: invoice.submitter_id || @actor_user_id,
            submitted_at: invoice.submitted_at || now
          )
        end
        round
      end
    end
  end
end
