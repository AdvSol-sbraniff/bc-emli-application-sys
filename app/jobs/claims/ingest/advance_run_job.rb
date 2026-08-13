# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceRunJob
      include Sidekiq::Job
      sidekiq_options queue: :claims_genai,
                      retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

      sidekiq_retries_exhausted do |job, error|
        run = ::Claims::IngestRun.find_by(id: job["args"]&.first)
        next if run.nil?
        if ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
             run.status
           )
          next
        end

        failure_code = ::Claims::Ingest::FailureClassifier.runtime(error)
        ::Claims::Ingest::RunTransition.mark_failed!(
          run: run,
          total_files: run.total_files.to_i,
          failed_files: [run.failed_files.to_i, 1].max,
          failure_category: "technical_failure",
          failure_code: failure_code,
          pipeline_error_code: "ingest_coordinator_failed",
          pipeline_error_description:
            "Ingest coordination could not complete after retrying."
        )
      end

      def perform(ingest_run_id)
        ::Claims::Ingest::AdvanceRun.call(ingest_run_id: ingest_run_id)
      end
    end
  end
end
