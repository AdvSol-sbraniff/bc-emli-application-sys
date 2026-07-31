# frozen_string_literal: true

module Claims
  module Ingest
    class FinalizeInvoiceVersionRun
      TERMINAL_STATUSES = %w[succeeded failed partial].freeze
      PRE_VALIDATION_STEP_TYPES = %w[
        ruleclone_clone_existing_evidence
        ocr_invoice
        fix_ocr_invoice
        classifier_files
        fix_classifier_files
      ].freeze
      VALIDATION_STEP_TYPES = %w[
        case_facts
        genai_common
        genai_upgrade
        code_common
        code_upgrade
        aggregate_advice
      ].freeze

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return unless run

        invoice_version_ids = invoice_version_ids_for(run.id)
        total_items = run.total_files.to_i
        total_items = invoice_version_ids.size if total_items <= 0

        succeeded = 0
        failed = 0
        running = 0

        invoice_version_ids.each do |invoice_version_id|
          prep_status = pre_validation_status(run.id, invoice_version_id)
          if prep_status == "failed"
            failed += 1
            next
          end
          if prep_status == "running"
            running += 1
            next
          end

          case validation_status(run.id, invoice_version_id)
          when "succeeded"
            succeeded += 1
          when "failed"
            failed += 1
          else
            running += 1
          end
        end

        status =
          run_status(
            total_items: total_items,
            succeeded: succeeded,
            failed: failed,
            running: running
          )

        run.update!(
          status: status,
          total_files: total_items,
          completed_files: succeeded,
          failed_files: failed,
          completed_at: TERMINAL_STATUSES.include?(status) ? Time.current : nil,
          updated_at: Time.current
        )
        if status == "succeeded"
          ::Claims::PipelineAudit::CheckRun.call(ingest_run_id: run.id)
        end
      end

      private

      def invoice_version_ids_for(ingest_run_id)
        ::Claims::IngestStepRun
          .where(ingest_run_id: ingest_run_id)
          .where.not(invoice_version_id: nil)
          .distinct
          .pluck(:invoice_version_id)
      end

      def pre_validation_status(ingest_run_id, invoice_version_id)
        steps =
          latest_steps(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_types: PRE_VALIDATION_STEP_TYPES
          )
        return "succeeded" if steps.empty?
        return "failed" if steps.any? { |step| step.status == "failed" }
        return "running" if steps.any? { |step| step.status != "succeeded" }

        "succeeded"
      end

      def validation_status(ingest_run_id, invoice_version_id)
        steps =
          latest_steps(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_types: VALIDATION_STEP_TYPES
          )
        invoice_status = invoice_status_for(invoice_version_id)
        invoice_status =
          normalize_stale_validation_failure!(
            invoice_version_id: invoice_version_id,
            invoice_status: invoice_status,
            validation_steps: steps
          )

        return "failed" if steps.any? { |step| step.status == "failed" }
        if %w[genai_failed technical_failure].include?(invoice_status)
          return "failed"
        end
        if steps.empty? &&
             %w[genai_queued genai_in_progress].include?(invoice_status)
          return "running"
        end
        return "succeeded" if steps.empty?
        if invoice_status == "genai_complete" && validation_complete?(steps)
          return "succeeded"
        end

        "running"
      end

      def latest_steps(ingest_run_id:, invoice_version_id:, step_types:)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_types
          )
          .order(created_at: :desc)
          .to_a
          .group_by { |step| [step.step_type, step.invoice_upgrade_type_id] }
          .transform_values(&:first)
          .values
      end

      def validation_complete?(steps)
        steps.present? && steps.all? { |step| step.status == "succeeded" } &&
          steps.any? do |step|
            step.step_type == "aggregate_advice" && step.status == "succeeded"
          end
      end

      def normalize_stale_validation_failure!(
        invoice_version_id:,
        invoice_status:,
        validation_steps:
      )
        unless %w[technical_failure genai_failed].include?(invoice_status)
          return invoice_status
        end
        return invoice_status unless validation_complete?(validation_steps)

        invoice =
          ::Claims::InvoiceVersion
            .includes(:invoice)
            .find(invoice_version_id)
            .invoice
        invoice.set_workflow_status!("genai_complete")
        "genai_complete"
      rescue StandardError
        invoice_status
      end

      def invoice_status_for(invoice_version_id)
        ::Claims::InvoiceVersion
          .joins(
            "JOIN claims.invoices i ON i.id = claims.invoice_versions.invoice_id"
          )
          .where(id: invoice_version_id)
          .pick("i.status")
          .to_s
      end

      def run_status(total_items:, succeeded:, failed:, running:)
        processed = succeeded + failed
        if total_items.positive? && processed >= total_items
          return(
            (
              if failed.zero?
                "succeeded"
              else
                (succeeded.zero? ? "failed" : "partial")
              end
            )
          )
        end
        return "running" if processed.positive? || running.positive?

        "queued"
      end
    end
  end
end
