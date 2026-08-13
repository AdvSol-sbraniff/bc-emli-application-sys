# frozen_string_literal: true

module Claims
  class FinalizeGenaiValidationJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai,
                    retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

    def perform(session_id, invoice_version_id, ingest_run_id)
      if ingest_run_id.blank?
        raise "Missing ingest_run_id for GenAI finalization."
      end

      run = ::Claims::IngestRun.find(ingest_run_id)
      if ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(run.status)
        return
      end

      ::Claims::RunGenaiJob.new.finalize_validation!(
        session_id: session_id,
        invoice_version_id: invoice_version_id,
        ingest_run_id: ingest_run_id
      )
    rescue StandardError => e
      begin
        step =
          ::Claims::Ingest::StepOutcome.for_target(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: "finalize_validation"
          ).effective_step
        if step&.status.in?(%w[queued in_progress])
          subtype = ::Claims::Ingest::FailureClassifier.runtime(e)
          step.update!(
            status: "failed",
            error_text: "#{e.class}: #{e.message}",
            genai_results_json: nil,
            **::Claims::Ingest::FailureClassifier.step_attributes(
              failure_category: "technical_failure",
              failure_code: subtype,
              error: e
            ),
            updated_at: Time.current
          )
        end
      rescue StandardError
        nil
      end
      raise if ::Claims::Ingest::RetryPolicy.retryable?(e)
    ensure
      if ingest_run_id.present?
        ::Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
      end
    end
  end
end
