# frozen_string_literal: true

module Claims
  module TestHarness
    module Scheduling
      DEFAULT_GENAI_INTERVAL_SECONDS = 60

      module_function

      def harness_run?(ingest_run_id)
        ::Claims::TestHarness::RunLookup.harness_run?(ingest_run_id)
      end

      def genai_interval
        configured =
          ENV.fetch(
            "TEST_HARNESS_GENAI_INTERVAL_SECONDS",
            DEFAULT_GENAI_INTERVAL_SECONDS
          ).to_i
        [configured, 1].max.seconds
      end

      def advance_run(ingest_run_id)
        return if ingest_run_id.blank?

        ::Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
      end

      def retry_job(job_class, ingest_run_id, *, attempt_count:)
        return false unless harness_run?(ingest_run_id)
        if attempt_count.to_i >= ::Claims::Ingest::RetryPolicy::MAX_ATTEMPTS
          return true
        end

        delay = genai_interval * (2**[attempt_count.to_i - 1, 0].max)
        job_class.perform_in(delay, *)
        true
      end
    end
  end
end
