# frozen_string_literal: true

module Claims
  module Invoices
    class DestroyPackage
      def self.call(invoice_id:)
        new(invoice_id: invoice_id).call
      end

      def initialize(invoice_id:)
        @invoice_id = invoice_id
      end

      def call
        invoice = ::Claims::Invoice.find(@invoice_id)
        session_id = invoice.session_id
        counts = empty_counts(invoice.id)

        ::Claims::Invoice.transaction do
          version_ids = invoice.invoice_versions.pluck(:id)
          supporting_document_ids =
            ::Claims::SupportingDocument.where(
              invoice_version_id: version_ids
            ).pluck(:id)
          run_ids = invoice.ingest_runs.pluck(:id)

          counts[:lineitems] = delete_where(
            ::Claims::Lineitem,
            invoice_version_id: version_ids
          )
          counts[:conversation_messages] = delete_where(
            ::Claims::ConversationMessage,
            invoice_id: invoice.id
          )
          counts[:revision_issue_comments] = ::Claims::RevisionIssueComment
            .joins(:revision_issue)
            .where("claims.revision_issues" => { invoice_id: invoice.id })
            .delete_all
          counts[:revision_issues] = delete_where(
            ::Claims::RevisionIssue,
            invoice_id: invoice.id
          )
          counts[:revision_rounds] = delete_where(
            ::Claims::RevisionRound,
            invoice_id: invoice.id
          )

          counts[:ingest_step_runs] = ::Claims::IngestStepRun.where(
            ingest_run_id: run_ids
          ).count
          counts[:ingest_documents] = ::Claims::IngestDocument.where(
            ingest_run_id: run_ids
          ).count
          counts[:ingest_runs] = ::Claims::IngestRun.where(
            id: run_ids
          ).delete_all

          counts[:supporting_documents] = delete_where(
            ::Claims::SupportingDocument,
            id: supporting_document_ids
          )
          counts[:invoice_versions] = delete_where(
            ::Claims::InvoiceVersion,
            id: version_ids
          )

          invoice.destroy!
          counts[:sessions] = delete_empty_session(session_id)
        end

        counts
      end

      private

      def delete_where(model, conditions)
        return 0 if empty_collection?(conditions.values)

        model.where(conditions).delete_all
      end

      def empty_collection?(values)
        values.any? { |value| value.respond_to?(:empty?) && value.empty? }
      end

      def delete_empty_session(session_id)
        return 0 if session_id.blank?
        return 0 if ::Claims::Invoice.exists?(session_id: session_id)
        return 0 if ::Claims::IngestRun.exists?(session_id: session_id)

        ::Claims::Session.where(id: session_id).delete_all
      end

      def empty_counts(invoice_id)
        {
          invoice_id: invoice_id,
          invoice_versions: 0,
          lineitems: 0,
          revision_rounds: 0,
          revision_issues: 0,
          revision_issue_comments: 0,
          conversation_messages: 0,
          supporting_documents: 0,
          ingest_documents: 0,
          ingest_runs: 0,
          ingest_step_runs: 0,
          sessions: 0
        }
      end
    end
  end
end
