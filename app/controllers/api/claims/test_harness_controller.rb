# frozen_string_literal: true

module Api
  module Claims
    class TestHarnessController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization
      claims_function "claims.test_tools"

      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped
      skip_forgery_protection

      rescue_from ActiveRecord::RecordInvalid,
                  ActiveRecord::RecordNotDestroyed,
                  ActiveRecord::RecordNotUnique,
                  ActiveRecord::InvalidForeignKey,
                  ActiveRecord::DeleteRestrictionError,
                  ArgumentError,
                  with: :render_unprocessable

      def bootstrap
        config = ::Claims::Genai::DeploymentConfig.current
        render json: {
                 deployments: config,
                 deployment_options: deployment_options(config),
                 suites:
                   ::Claims::TestSuite
                     .left_joins(:test_suite_cases)
                     .select(
                       "claims.testsuites.*, " \
                         "COUNT(claims.testsuite_cases.id) AS harness_case_count"
                     )
                     .group("claims.testsuites.id")
                     .order(:name)
                     .map do |suite| serialize_suite(suite) end,
                 rules:
                   ::Claims::GenaiRule
                     .order(:genai_rule_key)
                     .map do |rule|
                       {
                         id: rule.id,
                         rule_key: rule.genai_rule_key,
                         name: rule.contractor_display_name,
                         prompt_text: rule.prompt_text
                       }
                     end,
                 rule_histories:
                   ::Claims::GenaiRuleHistory
                     .order(history_created_at: :desc)
                     .map do |row|
                       {
                         id: row.id,
                         source_id: row.source_id,
                         rule_key: row.genai_rule_key,
                         name: row.contractor_display_name,
                         prompt_text: row.prompt_text,
                         created_at: row.history_created_at
                       }
                     end
               },
               status: :ok
      end

      def invoice_versions
        scope =
          ::Claims::IngestRun
            .where(status: "succeeded")
            .where.not(resolved_invoice_version_id: nil)
            .joins(:ingest_documents)
            .distinct
            .includes(:resolved_invoice_version, :invoice)
            .order(created_at: :desc)
        query = params[:q].to_s.strip
        if query.present?
          like = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
          scope =
            scope.joins(:resolved_invoice_version, :invoice).where(
              "CAST(claims.invoice_versions.id AS text) ILIKE :like OR " \
                "CAST(claims.invoices.reference_number AS text) ILIKE :like OR " \
                "claims.invoice_versions.original_filename ILIKE :like",
              like: like
            )
        end
        rows = scope.limit(100).map { |run| serialize_eligible_run(run) }
        render json: { rows: rows }, status: :ok
      end

      def suites_index
        render json: {
                 rows:
                   ::Claims::TestSuite
                     .includes(
                       :model_compares,
                       :rule_compares,
                       :regressions,
                       test_suite_cases: [
                         { baseline_invoice_version: :invoice },
                         :baseline_ingest_run
                       ]
                     )
                     .order(:name)
                     .map do |suite|
                       serialize_suite(
                         suite,
                         include_cases: true,
                         include_usage: true
                       )
                     end
               },
               status: :ok
      end

      def suites_create
        suite = ::Claims::TestSuite.create!(suite_params)
        render json: serialize_suite(suite, include_cases: true),
               status: :created
      end

      def suites_show
        suite =
          ::Claims::TestSuite.includes(
            test_suite_cases: [
              { baseline_invoice_version: :invoice },
              :baseline_ingest_run
            ]
          ).find(params[:id])
        render json: serialize_suite(suite, include_cases: true), status: :ok
      end

      def suites_update
        suite = ::Claims::TestSuite.find(params[:id])
        suite.update!(suite_params)
        render json: serialize_suite(suite, include_cases: true), status: :ok
      end

      def suites_destroy
        ::Claims::TestSuite.find(params[:id]).destroy!
        head :no_content
      rescue ActiveRecord::InvalidForeignKey,
             ActiveRecord::DeleteRestrictionError,
             ActiveRecord::RecordNotDestroyed
        render json: {
                 error:
                   "This test suite cannot be deleted because it has been used by one or more test runs."
               },
               status: :unprocessable_entity
      end

      def suite_cases_create
        suite = ::Claims::TestSuite.find(params[:testsuite_id])
        version =
          ::Claims::InvoiceVersion.find(
            params.require(:baseline_invoice_version_id)
          )
        run = producing_run(version.id, params[:baseline_ingest_run_id])
        row =
          suite.test_suite_cases.create!(
            name: params.require(:name),
            description: params[:description],
            baseline_invoice_version: version,
            baseline_ingest_run: run
          )
        render json: serialize_suite_case(row), status: :created
      end

      def suite_cases_update
        row = ::Claims::TestSuiteCase.find(params[:id])
        attributes = params.permit(:name, :description).to_h
        if params[:baseline_invoice_version_id].present?
          version =
            ::Claims::InvoiceVersion.find(params[:baseline_invoice_version_id])
          attributes.merge!(
            baseline_invoice_version_id: version.id,
            baseline_ingest_run_id:
              producing_run(version.id, params[:baseline_ingest_run_id]).id
          )
        end
        row.update!(attributes)
        render json: serialize_suite_case(row), status: :ok
      end

      def suite_cases_destroy
        ::Claims::TestSuiteCase.find(params[:id]).destroy!
        head :no_content
      end

      def model_compares_index
        render_run_index(::Claims::TestRunModelCompare)
      end

      def model_compares_show
        render json:
                 serialize_model_compare(
                   ::Claims::TestRunModelCompare.find(params[:id]),
                   include_cases: true
                 ),
               status: :ok
      end

      def model_compares_create
        suite = ::Claims::TestSuite.find(params.require(:testsuite_id))
        _cases, baseline =
          ::Claims::TestHarness::Preflight.model_compare!(suite)
        row =
          ::Claims::TestRunModelCompare.create!(
            testsuite_id: suite.id,
            status: "draft",
            baseline_document_triage_deployment_name:
              baseline.fetch(:document_triage_deployment_name),
            baseline_supporting_document_extraction_deployment_name:
              baseline.fetch(:supporting_document_extraction_deployment_name),
            baseline_upgrade_analysis_deployment_name:
              baseline.fetch(:upgrade_analysis_deployment_name),
            **params
              .permit(
                :candidate_document_triage_deployment_name,
                :candidate_supporting_document_extraction_deployment_name,
                :candidate_upgrade_analysis_deployment_name,
                :comparison_deployment_name
              )
              .to_h
              .symbolize_keys
          )
        render json: serialize_model_compare(row, include_cases: true),
               status: :created
      end

      def model_compares_submit
        row = ::Claims::TestRunModelCompare.find(params[:id])
        unless row.status == "draft"
          raise ArgumentError, "Only a draft comparison can be run."
        end

        _cases, baseline =
          ::Claims::TestHarness::Preflight.model_compare!(row.test_suite)
        expected = {
          document_triage_deployment_name:
            row.baseline_document_triage_deployment_name,
          supporting_document_extraction_deployment_name:
            row.baseline_supporting_document_extraction_deployment_name,
          upgrade_analysis_deployment_name:
            row.baseline_upgrade_analysis_deployment_name
        }
        if baseline != expected
          raise ArgumentError,
                "Suite baseline model provenance changed after this draft was created."
        end
        submit!("model_compare", row)
      end

      def model_compares_destroy
        destroy_run!(::Claims::TestRunModelCompare.find(params[:id]))
      end

      def rule_compares_index
        render_run_index(::Claims::TestRunRuleCompare)
      end

      def rule_compares_show
        render json:
                 serialize_rule_compare(
                   ::Claims::TestRunRuleCompare.find(params[:id]),
                   include_cases: true
                 ),
               status: :ok
      end

      def rule_compares_create
        suite = ::Claims::TestSuite.find(params.require(:testsuite_id))
        history =
          ::Claims::GenaiRuleHistory.find(
            params.require(:baseline_genai_rule_history_id)
          )
        rule =
          ::Claims::GenaiRule.find(params.require(:candidate_genai_rule_id))
        ::Claims::TestHarness::Preflight.rule_compare!(
          suite: suite,
          baseline_history: history,
          candidate_rule: rule
        )
        row =
          ::Claims::TestRunRuleCompare.create!(
            testsuite_id: suite.id,
            baseline_genai_rule_history_id: history.id,
            candidate_genai_rule_id: rule.id,
            comparison_deployment_name:
              params.require(:comparison_deployment_name),
            status: "draft"
          )
        render json: serialize_rule_compare(row, include_cases: true),
               status: :created
      end

      def rule_compares_submit
        row = ::Claims::TestRunRuleCompare.find(params[:id])
        unless row.status == "draft"
          raise ArgumentError, "Only a draft comparison can be run."
        end

        ::Claims::TestHarness::Preflight.rule_compare!(
          suite: row.test_suite,
          baseline_history: row.baseline_rule_history,
          candidate_rule: row.candidate_rule
        )
        submit!("rule_compare", row)
      end

      def rule_compares_destroy
        destroy_run!(::Claims::TestRunRuleCompare.find(params[:id]))
      end

      def regressions_index
        render_run_index(::Claims::TestRunRegression)
      end

      def regressions_show
        render json:
                 serialize_regression(
                   ::Claims::TestRunRegression.find(params[:id]),
                   include_cases: true
                 ),
               status: :ok
      end

      def regressions_create
        suite = ::Claims::TestSuite.find(params.require(:testsuite_id))
        ::Claims::TestHarness::Preflight.suite!(suite)
        row =
          ::Claims::TestRunRegression.create!(
            testsuite_id: suite.id,
            status: "draft",
            **params
              .permit(
                :document_triage_deployment_name,
                :supporting_document_extraction_deployment_name,
                :upgrade_analysis_deployment_name
              )
              .to_h
              .symbolize_keys
          )
        render json: serialize_regression(row, include_cases: true),
               status: :created
      end

      def regressions_submit
        row = ::Claims::TestRunRegression.find(params[:id])
        unless row.status == "draft"
          raise ArgumentError, "Only a draft regression can be run."
        end

        ::Claims::TestHarness::Preflight.suite!(row.test_suite)
        submit!("regression", row)
      end

      def regressions_destroy
        destroy_run!(::Claims::TestRunRegression.find(params[:id]))
      end

      private

      def suite_params
        params.permit(:name, :description)
      end

      def producing_run(invoice_version_id, requested_id)
        scope =
          ::Claims::IngestRun
            .where(
              status: "succeeded",
              resolved_invoice_version_id: invoice_version_id
            )
            .joins(:ingest_documents)
            .distinct
        scope = scope.where(id: requested_id) if requested_id.present?
        run = scope.order(created_at: :desc).first
        unless run
          raise ArgumentError,
                "No successful replayable ingest run was found for that invoice version."
        end

        run
      end

      def submit!(kind, row)
        row.update!(status: "queued")
        ::Claims::TestHarness::StartRunJob.perform_async(kind, row.id)
        serializer =
          case kind
          when "model_compare"
            method(:serialize_model_compare)
          when "rule_compare"
            method(:serialize_rule_compare)
          when "regression"
            method(:serialize_regression)
          end
        render json: serializer.call(row, include_cases: true),
               status: :accepted
      end

      def destroy_run!(row)
        row.with_lock do
          if %w[queued running].include?(row.status)
            raise ArgumentError,
                  "Queued or running test runs cannot be deleted."
          end

          row.destroy!
        end
        head :no_content
      end

      def render_run_index(model)
        scope =
          model.includes(:test_suite, :test_cases).order(created_at: :desc)
        scope = scope.where(testsuite_id: params[:testsuite_id]) if params[
          :testsuite_id
        ].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        rows =
          scope
            .limit(200)
            .map do |row|
              case row
              when ::Claims::TestRunModelCompare
                serialize_model_compare(row)
              when ::Claims::TestRunRuleCompare
                serialize_rule_compare(row)
              else
                serialize_regression(row)
              end
            end
        render json: { rows: rows }, status: :ok
      end

      def serialize_suite(suite, include_cases: false, include_usage: false)
        case_count =
          if suite.has_attribute?(:harness_case_count)
            suite[:harness_case_count].to_i
          else
            suite.test_suite_cases.size
          end
        payload = {
          id: suite.id,
          name: suite.name,
          description: suite.description,
          case_count: case_count,
          created_at: suite.created_at,
          updated_at: suite.updated_at
        }
        if include_usage
          payload[:has_runs] = suite.model_compares.any? ||
            suite.rule_compares.any? || suite.regressions.any?
        end
        if include_cases
          rows =
            if suite.test_suite_cases.loaded?
              suite.test_suite_cases.sort_by { |row| row.name.downcase }
            else
              suite.test_suite_cases.order(:name)
            end
          payload[:cases] = rows.map { |row| serialize_suite_case(row) }
        end
        payload
      end

      def serialize_suite_case(row)
        version = row.baseline_invoice_version
        run = row.baseline_ingest_run
        {
          id: row.id,
          testsuite_id: row.testsuite_id,
          name: row.name,
          description: row.description,
          baseline_invoice_version_id: version.id,
          baseline_ingest_run_id: run.id,
          invoice_reference_number: version.invoice.reference_number,
          original_filename: version.original_filename,
          deployments: ::Claims::TestHarness::Preflight.deployment_values(run),
          created_at: row.created_at,
          updated_at: row.updated_at
        }
      end

      def serialize_eligible_run(run)
        version = run.resolved_invoice_version
        {
          invoice_version_id: version.id,
          ingest_run_id: run.id,
          invoice_id: version.invoice_id,
          invoice_reference_number: run.invoice&.reference_number,
          invoice_versionno: version.invoice_versionno,
          original_filename: version.original_filename,
          deployments: ::Claims::TestHarness::Preflight.deployment_values(run),
          completed_at: run.completed_at
        }
      end

      def base_run(row)
        {
          id: row.id,
          testsuite_id: row.testsuite_id,
          suite_name: row.test_suite.name,
          status: row.status,
          case_count: row.test_cases.size,
          completed_case_count:
            row.test_cases.count do |test_case|
              test_case.status == "completed"
            end,
          failed_case_count:
            row.test_cases.count { |test_case| test_case.status == "failed" },
          created_at: row.created_at,
          updated_at: row.updated_at
        }
      end

      def serialize_model_compare(row, include_cases: false)
        payload =
          base_run(row).merge(
            baseline_document_triage_deployment_name:
              row.baseline_document_triage_deployment_name,
            baseline_supporting_document_extraction_deployment_name:
              row.baseline_supporting_document_extraction_deployment_name,
            baseline_upgrade_analysis_deployment_name:
              row.baseline_upgrade_analysis_deployment_name,
            candidate_document_triage_deployment_name:
              row.candidate_document_triage_deployment_name,
            candidate_supporting_document_extraction_deployment_name:
              row.candidate_supporting_document_extraction_deployment_name,
            candidate_upgrade_analysis_deployment_name:
              row.candidate_upgrade_analysis_deployment_name,
            comparison_deployment_name: row.comparison_deployment_name,
            overall_document_classification_comparison:
              row.overall_document_classification_comparison,
            overall_supporting_document_extraction_comparison:
              row.overall_supporting_document_extraction_comparison,
            overall_upgrade_analysis_comparison:
              row.overall_upgrade_analysis_comparison
          )
        if include_cases
          payload[:cases] = row
            .test_cases
            .includes(:test_suite_case)
            .map { |item| serialize_model_case(item) }
        end
        payload
      end

      def serialize_model_case(row)
        {
          id: row.id,
          name: row.test_suite_case.name,
          status: row.status,
          failure_code: row.failure_code,
          baseline_invoice_version_id: row.baseline_invoice_version_id,
          candidate_invoice_version_id: row.candidate_invoice_version_id,
          candidate_ingest_run_id: row.candidate_ingest_run_id,
          document_classification_comparison:
            row.document_classification_comparison,
          supporting_document_extraction_comparison:
            row.supporting_document_extraction_comparison,
          upgrade_analysis_comparison: row.upgrade_analysis_comparison
        }
      end

      def serialize_rule_compare(row, include_cases: false)
        payload =
          base_run(row).merge(
            baseline_genai_rule_history_id: row.baseline_genai_rule_history_id,
            candidate_genai_rule_id: row.candidate_genai_rule_id,
            rule_key: row.candidate_rule.genai_rule_key,
            candidate_rule_name: row.candidate_rule.contractor_display_name,
            baseline_rule_history_created_at:
              row.baseline_rule_history.history_created_at,
            comparison_deployment_name: row.comparison_deployment_name,
            overall_rule_comparison: row.overall_rule_comparison
          )
        if include_cases
          payload[:cases] = row
            .test_cases
            .includes(:test_suite_case)
            .map do |item|
              {
                id: item.id,
                name: item.test_suite_case.name,
                status: item.status,
                failure_code: item.failure_code,
                baseline_invoice_version_id: item.baseline_invoice_version_id,
                candidate_invoice_version_id: item.candidate_invoice_version_id,
                candidate_ingest_run_id: item.candidate_ingest_run_id,
                rule_comparison: item.rule_comparison
              }
            end
        end
        payload
      end

      def serialize_regression(row, include_cases: false)
        payload =
          base_run(row).merge(
            document_triage_deployment_name:
              row.document_triage_deployment_name,
            supporting_document_extraction_deployment_name:
              row.supporting_document_extraction_deployment_name,
            upgrade_analysis_deployment_name:
              row.upgrade_analysis_deployment_name
          )
        if include_cases
          payload[:cases] = row
            .test_cases
            .includes(:test_suite_case)
            .map do |item|
              {
                id: item.id,
                name: item.test_suite_case.name,
                status: item.status,
                failure_code: item.failure_code,
                invoice_version_id: item.invoice_version_id,
                ingest_run_id: item.ingest_run_id,
                result_summary: item.result_summary
              }
            end
        end
        payload
      end

      def deployment_options(config)
        values = config.values.compact_blank
        values.concat(
          ::Claims::IngestRun
            .where.not(document_triage_deployment_name: nil)
            .distinct
            .limit(50)
            .pluck(:document_triage_deployment_name)
        )
        values.concat(
          ::Claims::IngestRun
            .where.not(supporting_document_extraction_deployment_name: nil)
            .distinct
            .limit(50)
            .pluck(:supporting_document_extraction_deployment_name)
        )
        values.concat(
          ::Claims::IngestRun
            .where.not(upgrade_analysis_deployment_name: nil)
            .distinct
            .limit(50)
            .pluck(:upgrade_analysis_deployment_name)
        )
        values.map(&:to_s).map(&:strip).reject(&:blank?).uniq.sort
      end

      def render_unprocessable(error)
        message =
          if error.respond_to?(:record)
            error.record.errors.full_messages.to_sentence.presence ||
              error.message
          else
            error.message
          end
        render json: { error: message }, status: :unprocessable_entity
      end
    end
  end
end
