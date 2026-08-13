# frozen_string_literal: true

module Claims
  module Ingest
    module RetryPolicy
      MAX_ATTEMPTS = 4
      SIDEKIQ_RETRIES = MAX_ATTEMPTS - 1

      module_function

      def sidekiq_retries
        SIDEKIQ_RETRIES
      end

      def retryable?(error)
        ::Claims::Ingest::FailureClassifier.retryable?(error)
      end

      def retryable_step?(step)
        return false if step.nil?

        analytics =
          ::Claims::Ingest::FailureClassifier.analytics_from_step(step)
        analytics["retryable"] != false
      end

      def retry_pending?(attempt_count:, step:)
        retryable_step?(step) && attempt_count.to_i < MAX_ATTEMPTS
      end
    end
  end
end
