# frozen_string_literal: true

module Claims
  module TestHarness
    class StartRunJob
      include Sidekiq::Job
      sidekiq_options queue: :claims_genai, retry: 3

      def perform(kind, parent_id)
        parent = parent_for(kind, parent_id)
        return if %w[completed failed cancelled].include?(parent.status)

        parent.with_lock do
          return if %w[completed failed cancelled].include?(parent.status)

          parent
            .test_suite
            .test_suite_cases
            .order(:created_at, :id)
            .each { |suite_case| create_case(kind, parent, suite_case) }
          parent.update!(status: "running")
        end

        test_case =
          parent
            .test_cases
            .where(status: "queued")
            .order(:created_at, :id)
            .first
        if test_case
          ::Claims::TestHarness::RunCaseJob.perform_async(kind, test_case.id)
        end
      rescue StandardError
        parent&.update!(status: "failed") unless parent&.status == "cancelled"
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

      def create_case(kind, parent, suite_case)
        attributes = { testsuite_case_id: suite_case.id, status: "queued" }
        if %w[model_compare rule_compare].include?(kind)
          attributes.merge!(
            baseline_invoice_version_id: suite_case.baseline_invoice_version_id,
            baseline_ingest_run_id: suite_case.baseline_ingest_run_id
          )
        end
        parent
          .test_cases
          .find_or_create_by!(testsuite_case_id: suite_case.id) do |row|
            row.assign_attributes(attributes)
          end
      end
    end
  end
end
