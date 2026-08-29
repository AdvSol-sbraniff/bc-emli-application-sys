# frozen_string_literal: true

# Creates and submits one local regression smoke run using the most recent
# successful Azure-backed package. Intended for development verification only.
#
# Usage:
#   ALLOW_PROVENANCE_BACKFILL=1 bundle exec rails runner \
#     claims_ai_service_ddl/dev_tools/run_test_harness_smoke.rb

source_run =
  Claims::IngestRun
    .where(status: "succeeded")
    .where.not(resolved_invoice_version_id: nil)
    .joins(:ingest_documents)
    .distinct
    .order(created_at: :desc)
    .limit(100)
    .select do |run|
      run.ingest_documents.all? { |document| document.storage_key.present? }
    end
    .min_by { |run| run.ingest_documents.size }
unless source_run
  raise "No successful Azure-backed baseline ingest run was found."
end

deployments = Claims::Genai::DeploymentConfig.snapshot_attributes
if deployments.values.any?(&:blank?)
  raise "Configure all three AI Models in System Config before running this smoke test."
end
smoke_deployment = ENV["SMOKE_DEPLOYMENT"].to_s.strip.presence
if smoke_deployment
  deployments = deployments.transform_values { smoke_deployment }
end

missing =
  Claims::TestHarness::Preflight::RUN_DEPLOYMENTS.select do |attribute|
    source_run.public_send(attribute).blank?
  end
if missing.any?
  raise <<~TEXT.squish unless ENV["ALLOW_PROVENANCE_BACKFILL"] == "1"
      The selected legacy baseline lacks model provenance. Set
      ALLOW_PROVENANCE_BACKFILL=1 only when its former GENAI_DEPLOYMENT is
      known to match current System Config.
    TEXT
  source_run.update!(**deployments)
end

timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
suite =
  Claims::TestSuite.create!(
    name: "Automated regression smoke #{timestamp}",
    description: "Created by run_test_harness_smoke.rb"
  )
suite_case =
  suite.test_suite_cases.create!(
    name: "Azure package replay",
    description: "End-to-end smoke case",
    baseline_invoice_version_id: source_run.resolved_invoice_version_id,
    baseline_ingest_run_id: source_run.id
  )
run =
  Claims::TestRunRegression.create!(
    testsuite_id: suite.id,
    status: "queued",
    **deployments
  )
Claims::TestHarness::StartRunJob.perform_async("regression", run.id)

puts(
  {
    testsuite_id: suite.id,
    testsuite_case_id: suite_case.id,
    regression_id: run.id,
    baseline_ingest_run_id: source_run.id
  }.to_json
)
