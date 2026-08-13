# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceExistingEvidenceRun
      PRE_VALIDATION_STEP_TYPES = %w[clone_evidence].freeze

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return if run.nil?

        if ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
             run.status
           )
          ::Claims::Ingest::RunTransition.reconcile_terminal_cleanup!(run: run)
          return
        end

        invoice_version = invoice_version_for(run)
        unless invoice_version
          return(
            fail_run!(
              run: run,
              failed_step: nil,
              fallback_code: "rule_change_invoice_version_missing"
            )
          )
        end
        preparation = pre_validation_outcome(run, invoice_version)
        if preparation&.failed?
          return(
            fail_run!(
              run: run,
              failed_step: preparation.effective_step,
              fallback_code: "rule_change_preparation_failed"
            )
          )
        end
        if preparation&.active? || preparation&.retrying?
          return mark_running!(run)
        end

        validation =
          ::Claims::Ingest::ValidationOutcome.call(
            ingest_run_id: run.id,
            invoice_version_id: invoice_version.id
          )
        if validation.missing?
          ::Claims::Ingest::ValidationScheduler.start!(
            run: run,
            invoice_version: invoice_version
          )
          return mark_running!(run)
        end
        if validation.failed?
          return(
            fail_run!(
              run: run,
              failed_step: validation.failed_step,
              fallback_code: "rule_change_validation_failed"
            )
          )
        end
        if validation.ready_to_finalize?
          ::Claims::Ingest::ValidationScheduler.finalize!(
            run: run,
            invoice_version: invoice_version
          )
          return mark_running!(run)
        end
        return mark_running!(run) if validation.active? || validation.retrying?

        ::Claims::Ingest::RunTransition.mark_succeeded!(
          run: run,
          total_files: 1
        )
      end

      private

      def invoice_version_for(run)
        ::Claims::InvoiceVersion.find_by(id: run.resolved_invoice_version_id)
      end

      def pre_validation_outcome(run, invoice_version)
        grouped_attempts =
          ::Claims::IngestStepRun
            .where(
              ingest_run_id: run.id,
              invoice_version_id: invoice_version.id,
              step_type: PRE_VALIDATION_STEP_TYPES
            )
            .to_a
            .group_by do |step|
              [
                step.step_type,
                step.ingest_document_id,
                step.invoice_upgrade_type_id
              ]
            end
        outcomes =
          grouped_attempts.values.map do |attempts|
            ::Claims::Ingest::StepOutcome.for_attempts(attempts)
          end
        outcomes.find(&:failed?) || outcomes.find(&:retrying?) ||
          outcomes.find(&:active?) || outcomes.first
      end

      def mark_running!(run)
        ::Claims::Ingest::RunTransition.mark_running!(run: run, total_files: 1)
      end

      def fail_run!(run:, failed_step:, fallback_code:)
        analytics =
          ::Claims::Ingest::FailureClassifier.analytics_from_step(failed_step)
        failure_category =
          failed_step&.failure_category.presence || "technical_failure"
        failure_subtype =
          ::Claims::Ingest::FailureClassifier.from_step(
            failed_step,
            fallback: "unknown_runtime_failure"
          )
        error_code = analytics["error_code"].presence || fallback_code
        description = [
          failed_step&.step_type.presence || "validation",
          error_code,
          analytics["retryable"] == false ? "non-retryable" : nil,
          analytics["diagnostic_id"].presence
        ].compact.join("; ")

        ::Claims::Ingest::RunTransition.mark_failed!(
          run: run,
          total_files: 1,
          failed_files: 1,
          failure_category: failure_category,
          failure_code: failure_subtype,
          pipeline_error_code: error_code,
          pipeline_error_description: description
        )
      end
    end
  end
end
