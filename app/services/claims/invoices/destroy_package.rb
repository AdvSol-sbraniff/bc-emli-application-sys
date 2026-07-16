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
        deleted = empty_counts(invoice.id)

        ::Claims::Invoice.transaction do
          invoice_version_ids =
            ::Claims::InvoiceVersion.where(invoice_id: invoice.id).pluck(:id)
          supporting_document_ids =
            ::Claims::SupportingDocument.where(
              invoice_version_id: invoice_version_ids
            ).pluck(:id)
          ingest_document_ids =
            package_ingest_document_scope(
              invoice_id: invoice.id,
              invoice_version_ids: invoice_version_ids,
              supporting_document_ids: supporting_document_ids
            ).pluck(:id)
          ingest_run_ids =
            ::Claims::IngestDocument
              .where(id: ingest_document_ids)
              .pluck(:ingest_run_id)
              .compact
              .uniq
          orphanable_ingest_run_ids =
            ingest_run_ids.select do |ingest_run_id|
              ::Claims::IngestDocument
                .where(ingest_run_id: ingest_run_id)
                .where.not(id: ingest_document_ids)
                .none?
            end

          deleted[:lineitems] = delete_lineitems(invoice_version_ids)
          deleted[:conversation_messages] = delete_conversation_messages(
            invoice.id
          )
          deleted[:revision_issue_comments] = ::Claims::RevisionIssueComment
            .joins(:revision_issue)
            .where("claims.revision_issues" => { invoice_id: invoice.id })
            .delete_all
          deleted[:revision_issues] = ::Claims::RevisionIssue.where(
            invoice_id: invoice.id
          ).delete_all
          deleted[:revision_rounds] = ::Claims::RevisionRound.where(
            invoice_id: invoice.id
          ).delete_all
          deleted[:ingest_step_runs] += delete_version_step_runs(
            invoice_version_ids
          )
          deleted[:ingest_step_runs] += delete_document_step_runs(
            ingest_document_ids
          )
          deleted[:ingest_step_runs] += delete_run_step_runs(
            orphanable_ingest_run_ids
          )

          deleted[:ingest_documents] = delete_ingest_documents(
            ingest_document_ids
          )
          deleted[:supporting_documents] = delete_supporting_documents(
            supporting_document_ids
          )
          deleted[:invoice_versions] = delete_invoice_versions(
            invoice_version_ids
          )
          deleted[:ingest_runs] = delete_ingest_runs(orphanable_ingest_run_ids)

          invoice.destroy!

          if session_has_no_invoices?(session_id)
            deleted[:ingest_step_runs] += delete_session_step_runs(session_id)
            deleted[:ingest_documents] += delete_session_ingest_documents(
              session_id
            )
            deleted[:ingest_runs] += delete_session_ingest_runs(session_id)
            deleted[:sessions] = delete_session(session_id)
          end
        end

        deleted
      end

      private

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

      def package_ingest_document_scope(
        invoice_id:,
        invoice_version_ids:,
        supporting_document_ids:
      )
        scope = ::Claims::IngestDocument.where(invoice_id: invoice_id)
        scope =
          scope.or(
            ::Claims::IngestDocument.where(resolved_invoice_id: invoice_id)
          )

        if invoice_version_ids.any?
          scope =
            scope.or(
              ::Claims::IngestDocument.where(
                resolved_invoice_version_id: invoice_version_ids
              )
            )
        end

        if supporting_document_ids.any?
          scope =
            scope.or(
              ::Claims::IngestDocument.where(
                promoted_supporting_document_id: supporting_document_ids
              )
            )
        end

        scope
      end

      def delete_lineitems(invoice_version_ids)
        return 0 if invoice_version_ids.empty?

        ::Claims::Lineitem.where(
          invoice_version_id: invoice_version_ids
        ).delete_all
      end

      def delete_conversation_messages(invoice_id)
        ::Claims::ConversationMessage.where(invoice_id: invoice_id).delete_all
      end

      def delete_version_step_runs(invoice_version_ids)
        return 0 if invoice_version_ids.empty?

        ::Claims::IngestStepRun.where(
          invoice_version_id: invoice_version_ids
        ).delete_all
      end

      def delete_document_step_runs(ingest_document_ids)
        return 0 if ingest_document_ids.empty?

        ::Claims::IngestStepRun.where(
          ingest_document_id: ingest_document_ids
        ).delete_all
      end

      def delete_run_step_runs(ingest_run_ids)
        return 0 if ingest_run_ids.empty?

        ::Claims::IngestStepRun.where(ingest_run_id: ingest_run_ids).delete_all
      end

      def delete_ingest_documents(ingest_document_ids)
        return 0 if ingest_document_ids.empty?

        ::Claims::IngestDocument.where(id: ingest_document_ids).delete_all
      end

      def delete_supporting_documents(supporting_document_ids)
        return 0 if supporting_document_ids.empty?

        ::Claims::SupportingDocument.where(
          id: supporting_document_ids
        ).delete_all
      end

      def delete_invoice_versions(invoice_version_ids)
        return 0 if invoice_version_ids.empty?

        ::Claims::InvoiceVersion.where(id: invoice_version_ids).delete_all
      end

      def delete_ingest_runs(ingest_run_ids)
        return 0 if ingest_run_ids.empty?

        ::Claims::IngestRun.where(id: ingest_run_ids).delete_all
      end

      def delete_session_step_runs(session_id)
        return 0 if session_id.blank?

        ::Claims::IngestStepRun.where(session_id: session_id).delete_all
      end

      def delete_session_ingest_documents(session_id)
        return 0 if session_id.blank?

        ::Claims::IngestDocument.where(session_id: session_id).delete_all
      end

      def delete_session_ingest_runs(session_id)
        return 0 if session_id.blank?

        ::Claims::IngestRun.where(session_id: session_id).delete_all
      end

      def delete_session(session_id)
        return 0 if session_id.blank?

        ::Claims::Session.where(id: session_id).delete_all
      end

      def session_has_no_invoices?(session_id)
        return false if session_id.blank?

        ::Claims::Invoice.where(session_id: session_id).none?
      end
    end
  end
end
