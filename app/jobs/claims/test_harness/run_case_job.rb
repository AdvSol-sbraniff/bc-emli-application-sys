# frozen_string_literal: true

module Claims
  module TestHarness
    class RunCaseJob
      include Sidekiq::Job
      sidekiq_options queue: :claims_genai, retry: 2

      def perform(kind, case_id)
        test_case = case_for(kind, case_id)
        return if terminal?(test_case.status)

        if existing_ingest_run(test_case)
          schedule_monitor(kind, test_case.id)
          return
        end

        test_case.update!(status: "running", failure_code: nil)
        suite_case = test_case.test_suite_case
        pointer =
          kind == "regression" ? :ingest_run_id : :candidate_ingest_run_id
        ::Claims::TestHarness::CreateReplayRun.call(
          baseline_ingest_run: suite_case.baseline_ingest_run,
          deployments: deployments_for(kind, test_case),
          harness_case: test_case,
          ingest_run_pointer: pointer
        )
        schedule_monitor(kind, test_case.id)
      rescue StandardError => e
        code =
          (
            if kind == "regression"
              "ingest_run_creation_failed"
            else
              "candidate_run_creation_failed"
            end
          )
        fail_case(test_case, code, e)
        finalize(kind, test_case) if test_case
      end

      private

      def case_for(kind, id)
        case kind
        when "model_compare"
          ::Claims::TestRunModelCompareCase.find(id)
        when "rule_compare"
          ::Claims::TestRunRuleCompareCase.find(id)
        when "regression"
          ::Claims::TestRunRegressionCase.find(id)
        else
          raise ArgumentError, "Unknown harness run kind: #{kind}"
        end
      end

      def deployments_for(kind, test_case)
        case kind
        when "model_compare"
          parent = test_case.test_run
          {
            document_triage_deployment_name:
              parent.candidate_document_triage_deployment_name,
            supporting_document_extraction_deployment_name:
              parent.candidate_supporting_document_extraction_deployment_name,
            upgrade_analysis_deployment_name:
              parent.candidate_upgrade_analysis_deployment_name
          }
        when "rule_compare"
          ::Claims::TestHarness::Preflight.deployment_values(
            test_case.baseline_ingest_run
          )
        when "regression"
          test_case.test_run.attributes.symbolize_keys.slice(
            :document_triage_deployment_name,
            :supporting_document_extraction_deployment_name,
            :upgrade_analysis_deployment_name
          )
        end
      end

      def existing_ingest_run(test_case)
        if test_case.is_a?(::Claims::TestRunRegressionCase)
          test_case.ingest_run_id
        else
          test_case.candidate_ingest_run_id
        end
      end

      def schedule_monitor(kind, case_id)
        ::Claims::TestHarness::MonitorCaseJob.perform_in(
          5.seconds,
          kind,
          case_id
        )
      end

      def fail_case(test_case, code, error)
        return unless test_case

        Rails.logger.error(
          "[claims][test_harness] case=#{test_case.id} #{error.class}: #{error.message}"
        )
        test_case.update!(status: "failed", failure_code: code)
      rescue StandardError
        nil
      end

      def finalize(kind, test_case)
        ::Claims::TestHarness::FinalizeRunJob.perform_async(
          kind,
          test_case.test_run.id
        )
      end

      def terminal?(status)
        %w[completed failed skipped cancelled].include?(status)
      end
    end
  end
end
