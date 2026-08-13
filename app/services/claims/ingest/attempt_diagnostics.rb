# frozen_string_literal: true

module Claims
  module Ingest
    class AttemptDiagnostics
      Result =
        Struct.new(
          :annotations_by_step_id,
          :summary,
          :terminal_failure_step,
          keyword_init: true
        )

      TARGET_COLUMNS =
        (
          ["step_type"] +
            ::Claims::Ingest::StepOutcome::TARGET_COLUMNS.map(&:to_s)
        ).freeze
      TERMINAL_RUN_STATUSES = ::Claims::IngestRun::TERMINAL_STATUSES

      def self.call(steps:, run_status:)
        new(steps: steps, run_status: run_status).call
      end

      def initialize(steps:, run_status:)
        @steps = Array(steps).compact
        @run_status = run_status.to_s
      end

      def call
        annotations = {}
        recovered_attempts = 0
        retrying_targets = 0
        failed_targets = 0
        retried_targets = 0
        terminal_failed_steps = []

        grouped_steps.each_value do |attempts|
          ordered = attempts.sort_by { |step| attempt_sort_key(step) }
          outcome = ::Claims::Ingest::StepOutcome.for_attempts(ordered)
          logical_state = terminalized_state(outcome.state)
          failed_attempts = ordered.count { |step| step.status == "failed" }
          retry_in_progress =
            logical_state == :active && failed_attempts.positive?

          if logical_state == :succeeded && failed_attempts.positive?
            recovered_attempts += failed_attempts
            retried_targets += 1
          elsif logical_state == :retrying || retry_in_progress
            retrying_targets += 1
          elsif logical_state == :failed
            failed_targets += 1
            terminal_failed_steps << outcome.effective_step
          end

          ordered.each_with_index do |step, index|
            annotations[step.id.to_s] = {
              attempt_number: index + 1,
              attempt_count: ordered.size,
              attempt_limit: outcome.attempt_limit,
              logical_state: logical_state.to_s,
              display_status:
                display_status(step, logical_state, retry_in_progress),
              effective_attempt: outcome.effective_step&.id.to_s == step.id.to_s
            }
          end
        end

        Result.new(
          annotations_by_step_id: annotations,
          summary: {
            total_attempts: @steps.size,
            failed_attempts: @steps.count { |step| step.status == "failed" },
            recovered_attempts: recovered_attempts,
            retried_targets: retried_targets,
            retrying_targets: retrying_targets,
            failed_targets: failed_targets
          },
          terminal_failure_step: terminal_failure_step(terminal_failed_steps)
        )
      end

      private

      def grouped_steps
        @steps.group_by do |step|
          TARGET_COLUMNS.map { |column| step.public_send(column) }
        end
      end

      def attempt_sort_key(step)
        [step.created_at || Time.at(0), step.id.to_s]
      end

      def terminalized_state(state)
        return state unless TERMINAL_RUN_STATUSES.include?(@run_status)
        return :failed if state == :retrying

        state
      end

      def display_status(step, logical_state, retry_in_progress)
        return step.status unless step.status == "failed"
        return "recovered" if logical_state == :succeeded
        return "retrying" if logical_state == :retrying || retry_in_progress

        "failed"
      end

      def terminal_failure_step(failed_steps)
        return unless @run_status == "failed"

        ::Claims::Ingest::FailureClassifier.primary_failed_step(
          failed_steps.compact
        )
      end
    end
  end
end
