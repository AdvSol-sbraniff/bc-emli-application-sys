# frozen_string_literal: true

module Claims
  module TestHarness
    class FinalizeRunJob
      include Sidekiq::Job
      sidekiq_options queue: :claims_genai, retry: 3

      sidekiq_retry_in do |count, _exception, _job|
        ::Claims::TestHarness::Scheduling.genai_interval.to_i * (2**count)
      end

      sidekiq_retries_exhausted do |job, _error|
        kind, parent_id = job["args"]
        parent =
          case kind
          when "model_compare"
            ::Claims::TestRunModelCompare.find_by(id: parent_id)
          when "rule_compare"
            ::Claims::TestRunRuleCompare.find_by(id: parent_id)
          when "regression"
            ::Claims::TestRunRegression.find_by(id: parent_id)
          end
        parent&.update!(status: "failed") unless parent&.status == "cancelled"
      end

      TERMINAL_CASE_STATUSES = %w[completed failed skipped cancelled].freeze

      def perform(kind, parent_id)
        parent = parent_for(kind, parent_id)
        return if %w[completed failed cancelled].include?(parent.status)

        cases =
          parent
            .test_cases
            .includes(:test_suite_case)
            .order(:created_at, :id)
            .to_a
        return if cases.empty?

        unless cases.all? { |row| TERMINAL_CASE_STATUSES.include?(row.status) }
          next_case = cases.find { |row| row.status == "queued" }
          if next_case && cases.none? { |row| row.status == "running" }
            ::Claims::TestHarness::RunCaseJob.perform_async(kind, next_case.id)
          end
          return
        end

        if cases.any? { |row| row.status != "completed" }
          parent.update!(status: "failed")
          return
        end

        attributes =
          case kind
          when "model_compare"
            ::Claims::TestHarness::Evaluator.finalize_model(
              case_rows: cases,
              deployment_name: parent.comparison_deployment_name
            )
          when "rule_compare"
            {
              overall_rule_comparison:
                ::Claims::TestHarness::Evaluator.finalize_rule(
                  case_rows: cases,
                  deployment_name: parent.comparison_deployment_name
                )
            }
          when "regression"
            {}
          end
        parent.update!(**attributes, status: "completed")
      rescue StandardError => e
        Rails.logger.error(
          "[claims][test_harness] finalize parent=#{parent_id} #{e.class}: #{e.message}"
        )
        unless (e.respond_to?(:retryable?) && e.retryable?) ||
                 parent&.status == "cancelled"
          parent&.update!(status: "failed")
        end
        raise
      end

      private

      def parent_for(kind, id)
        case kind
        when "model_compare"
          ::Claims::TestRunModelCompare.find(id)
        when "rule_compare"
          ::Claims::TestRunRuleCompare.find(id)
        when "regression"
          ::Claims::TestRunRegression.find(id)
        else
          raise ArgumentError, "Unknown harness run kind: #{kind}"
        end
      end
    end
  end
end
