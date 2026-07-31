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

          retain_step_history!(
            invoice_version_ids: invoice_version_ids,
            ingest_document_ids: ingest_document_ids
          )
          retain_ingest_documents!(ingest_document_ids)

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

      def retain_ingest_documents!(ingest_document_ids)
        ::Claims::IngestDocument.where(id: ingest_document_ids).update_all(
          invoice_id: nil,
          resolved_invoice_id: nil,
          resolved_invoice_version_id: nil,
          promoted_supporting_document_id: nil,
          di_read_raw_json: nil,
          classifier_raw_json: nil,
          updated_at: Time.current
        )
      end

      def retain_step_history!(invoice_version_ids:, ingest_document_ids:)
        scope =
          ::Claims::IngestStepRun.where(ingest_run_id: ingest_run.id).where(
            "invoice_version_id IN (:invoice_version_ids) " \
              "OR ingest_document_id IN (:ingest_document_ids)",
            invoice_version_ids: invoice_version_ids.presence || [nil],
            ingest_document_ids: ingest_document_ids.presence || [nil]
          )

        scope.find_each do |step|
          retained_status =
            if %w[queued in_progress].include?(step.status)
              "failed"
            else
              step.status
            end
          diagnostic_attributes =
            retained_step_diagnostic_attributes(
              step,
              retained_status: retained_status
            )

          step.update_columns(
            invoice_version_id: nil,
            status: retained_status,
            completed_at: step.completed_at || Time.current,
            error_text:
              retained_error_text(
                step,
                diagnostic_attributes: diagnostic_attributes,
                retained_status: retained_status
              ),
            di_results_json: nil,
            genai_results_json: nil,
            context_window_json: nil,
            **diagnostic_attributes,
            updated_at: Time.current
          )
        end
      end

      def retained_step_diagnostic_attributes(step, retained_status:)
        analytics =
          ::Claims::Invoices::FailureSubtypes.analytics_from_step(step)
        attributes = {
          failure_status: analytics["failure_status"],
          failure_status_subtype: analytics["failure_status_subtype"],
          error_code: analytics["error_code"],
          error_category: analytics["error_category"],
          error_phase: analytics["phase"],
          retryable: analytics["retryable"],
          diagnostic_id: analytics["diagnostic_id"],
          provider_status: analytics["provider_status"],
          provider_code: analytics["provider_code"],
          provider_attempt_count: analytics["provider_attempt_count"]
        }

        if retained_status == "failed" && attributes[:error_code].blank?
          attributes[:failure_status] = "technical_failure"
          attributes[:failure_status_subtype] = "unknown_runtime_failure"
          attributes[:error_code] = "pipeline_cancelled_after_failure"
          attributes[:error_category] = "pipeline_cancelled"
          attributes[:retryable] = false
        end

        attributes
      end

      def retained_error_text(step, diagnostic_attributes:, retained_status:)
        return nil if retained_status == "succeeded"

        if %w[queued in_progress].include?(step.status)
          return "Processing cancelled after the upload run failed."
        end

        code =
          diagnostic_attributes[:error_code].presence ||
            "processing_step_failed"
        diagnostic_id = diagnostic_attributes[:diagnostic_id].presence
        detail = diagnostic_id ? " diagnostic_id=#{diagnostic_id}" : ""
        "Retained failure: #{code}.#{detail}"
      end

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
