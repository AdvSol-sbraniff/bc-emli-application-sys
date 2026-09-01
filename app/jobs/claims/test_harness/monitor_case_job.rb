# frozen_string_literal: true

module Claims
  module TestHarness
    class MonitorCaseJob
      include Sidekiq::Job
      sidekiq_options queue: :claims_genai, retry: 3

      sidekiq_retry_in do |count, _exception, _job|
        ::Claims::TestHarness::Scheduling.genai_interval.to_i * (2**count)
      end

      sidekiq_retries_exhausted do |job, _error|
        kind, case_id = job["args"]
        test_case =
          case kind
          when "model_compare"
            ::Claims::TestRunModelCompareCase.find_by(id: case_id)
          when "rule_compare"
            ::Claims::TestRunRuleCompareCase.find_by(id: case_id)
          when "regression"
            ::Claims::TestRunRegressionCase.find_by(id: case_id)
          end
        next unless test_case

        test_case.update!(
          status: "failed",
          failure_code:
            kind == "regression" ? "internal_error" : "comparison_failed"
        )
        ::Claims::TestHarness::FinalizeRunJob.perform_async(
          kind,
          test_case.test_run.id
        )
      end

      def perform(kind, case_id)
        test_case = case_for(kind, case_id)
        return if terminal?(test_case.status)

        run = ingest_run_for(kind, test_case)
        raise "Harness case has no generated ingest run." unless run

        if %w[queued running].include?(run.status)
          self.class.perform_in(10.seconds, kind, case_id)
          return
        end
        if run.status == "failed"
          test_case.update!(
            status: "failed",
            failure_code:
              (
                if kind == "regression"
                  "processing_failed"
                else
                  "candidate_processing_failed"
                end
              )
          )
          finalize(kind, test_case)
          return
        end

        version = run.resolved_invoice_version
        unless version
          raise "Succeeded candidate run has no resolved invoice version."
        end

        if kind != "regression" && test_case.candidate_invoice_version_id.blank?
          test_case.update!(candidate_invoice_version_id: version.id)
          self.class.perform_async(kind, test_case.id)
          return
        end

        completed =
          if kind == "regression"
            complete_regression(test_case, run, version)
            true
          else
            complete_comparison(kind, test_case, run, version)
          end
        return unless completed

        finalize(kind, test_case)
      rescue StandardError => e
        Rails.logger.error(
          "[claims][test_harness] monitor case=#{case_id} #{e.class}: #{e.message}"
        )
        raise if e.respond_to?(:retryable?) && e.retryable?

        test_case&.update!(
          status: "failed",
          failure_code:
            kind == "regression" ? "internal_error" : "comparison_failed"
        )
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

      def ingest_run_for(kind, test_case)
        if kind == "regression"
          test_case.ingest_run
        else
          test_case.candidate_ingest_run
        end
      end

      def complete_comparison(kind, test_case, run, version)
        test_case.update!(candidate_invoice_version_id: version.id)
        if kind == "model_compare"
          complete_model_compare(test_case, run, version)
        else
          complete_rule_compare(test_case, run, version)
          true
        end
      end

      def complete_model_compare(test_case, candidate_run, candidate_version)
        parent = test_case.test_run
        baseline_version = test_case.baseline_invoice_version
        baseline_run = test_case.baseline_ingest_run
        mapping = {
          document_classification: :document_classification_comparison,
          supporting_document_extraction:
            :supporting_document_extraction_comparison,
          upgrade_analysis: :upgrade_analysis_comparison
        }
        next_comparison =
          mapping.find do |_domain, column|
            test_case.public_send(column).blank?
          end
        unless next_comparison
          test_case.update!(status: "completed", failure_code: nil)
          return true
        end

        domain, column = next_comparison
        baseline =
          ::Claims::TestHarness::EvidenceSnapshot.for_domain(
            domain: domain,
            invoice_version: baseline_version,
            ingest_run: baseline_run
          )
        candidate =
          ::Claims::TestHarness::EvidenceSnapshot.for_domain(
            domain: domain,
            invoice_version: candidate_version,
            ingest_run: candidate_run
          )
        comparison =
          ::Claims::TestHarness::Evaluator.compare(
            domain: domain,
            baseline: baseline,
            candidate: candidate,
            deployment_name: parent.comparison_deployment_name
          )
        test_case.update!(column => comparison)
        self.class.perform_async("model_compare", test_case.id)
        false
      end

      def complete_rule_compare(test_case, candidate_run, candidate_version)
        parent = test_case.test_run
        rule_key = parent.candidate_rule.genai_rule_key
        baseline =
          ::Claims::TestHarness::EvidenceSnapshot.new(
            invoice_version: test_case.baseline_invoice_version,
            ingest_run: test_case.baseline_ingest_run
          ).rule(rule_key)
        candidate =
          ::Claims::TestHarness::EvidenceSnapshot.new(
            invoice_version: candidate_version,
            ingest_run: candidate_run
          ).rule(rule_key)
        comparison =
          ::Claims::TestHarness::Evaluator.compare(
            domain: "rule #{rule_key}",
            baseline: baseline,
            candidate: candidate,
            deployment_name: parent.comparison_deployment_name
          )
        test_case.update!(
          rule_comparison: comparison,
          status: "completed",
          failure_code: nil
        )
      end

      def complete_regression(test_case, run, version)
        checks = {
          pipeline_succeeded: run.status == "succeeded",
          resolved_invoice_version: version.present?,
          classification_completed:
            run
              .ingest_step_runs
              .where(step_type: "classify_document", status: "succeeded")
              .exists?,
          validation_finalized:
            run
              .ingest_step_runs
              .where(step_type: "finalize_validation", status: "succeeded")
              .exists?,
          rule_results_present: version.rulechecks.exists?,
          no_failed_steps: !run.ingest_step_runs.where(status: "failed").exists?
        }
        failed = checks.reject { |_name, passed| passed }.keys
        if failed.any?
          test_case.update!(
            invoice_version_id: version.id,
            status: "failed",
            failure_code: "expectation_failed",
            result_summary:
              "Pipeline completed, but these health checks failed: #{failed.map { |v| v.to_s.humanize }.to_sentence}."
          )
        else
          test_case.update!(
            invoice_version_id: version.id,
            status: "completed",
            failure_code: nil,
            result_summary:
              "Completed the full pipeline successfully. Classification, validation, persisted rule results, and step health checks passed."
          )
        end
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
