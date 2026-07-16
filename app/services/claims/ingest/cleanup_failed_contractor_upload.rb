# frozen_string_literal: true

module Claims
  module Ingest
    class CleanupFailedContractorUpload
      FAILURE_STATUSES = %w[package_needs_correction technical_failure].freeze

      def self.call(ingest_run:)
        new(ingest_run: ingest_run).call
      end

      def initialize(ingest_run:)
        @ingest_run = ingest_run
      end

      def call
        return unless ingest_run&.cleanup_failed_invoice_artifacts
        return if ingest_run.contractor_id.blank?

        invoice_ids = failed_invoice_ids
        return if invoice_ids.empty?

        ActiveRecord::Base.transaction do
          invoice_version_ids =
            ::Claims::InvoiceVersion.where(invoice_id: invoice_ids).pluck(:id)

          supporting_document_ids =
            ::Claims::SupportingDocument.where(
              invoice_version_id: invoice_version_ids
            ).pluck(:id)

          ingest_document_ids =
            ::Claims::IngestDocument
              .where(ingest_run_id: ingest_run.id)
              .where(
                "invoice_id IN (:ids) OR resolved_invoice_id IN (:ids)",
                ids: invoice_ids
              )
              .pluck(:id)

          ::Claims::IngestStepRun.where(
            invoice_version_id: invoice_version_ids
          ).delete_all
          ::Claims::IngestStepRun.where(
            ingest_document_id: ingest_document_ids
          ).delete_all

          ::Claims::RevisionIssueComment
            .joins(:revision_issue)
            .where("claims.revision_issues" => { invoice_id: invoice_ids })
            .delete_all
          ::Claims::RevisionIssue.where(invoice_id: invoice_ids).delete_all
          ::Claims::RevisionRound.where(invoice_id: invoice_ids).delete_all
          ::Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: invoice_version_ids
          ).delete_all
          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version_ids
          ).delete_all
          ::Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: invoice_version_ids
          ).delete_all
          ::Claims::Lineitem.where(
            invoice_version_id: invoice_version_ids
          ).delete_all

          ::Claims::SupportingDocumentLocatedField.where(
            supporting_document_id: supporting_document_ids
          ).delete_all
          ::Claims::SupportingDocumentVisualFinding.where(
            supporting_document_id: supporting_document_ids
          ).delete_all
          ::Claims::SupportingDocument.where(
            id: supporting_document_ids
          ).delete_all

          ::Claims::IngestDocument.where(id: ingest_document_ids).delete_all
          ::Claims::InvoiceVersion.where(id: invoice_version_ids).delete_all
          ::Claims::InternalNote.where(invoice_id: invoice_ids).delete_all
          ::Claims::ConversationMessage.where(
            invoice_id: invoice_ids
          ).delete_all
          ::Claims::Invoice.where(id: invoice_ids).delete_all
        end
      end

      private

      attr_reader :ingest_run

      def failed_invoice_ids
        ids =
          ::Claims::Invoice.where(
            session_id: ingest_run.session_id,
            contractor_id: ingest_run.contractor_id,
            status: FAILURE_STATUSES
          ).pluck(:id)

        staging_invoice_ids =
          ::Claims::IngestDocument
            .where(ingest_run_id: ingest_run.id)
            .pluck(:invoice_id, :resolved_invoice_id)
            .flatten
            .compact

        (ids + staging_invoice_ids).uniq
      end
    end
  end
end
