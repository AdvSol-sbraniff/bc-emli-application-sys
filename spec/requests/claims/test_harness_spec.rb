require "rails_helper"

RSpec.describe "Claims test harness", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::Claims::TestHarnessController).to receive(
      :require_claims_admin!
    )
    allow(Claims::TestHarness::StartRunJob).to receive(:perform_async)
  end

  it "manages suites and creates a validated model-comparison draft" do
    baseline = create_baseline

    post "/api/claims/admin/test_harness/suites",
         params: {
           name: "Model comparison #{SecureRandom.hex(4)}",
           description: "Representative heat-pump packages"
         },
         as: :json

    expect(response).to have_http_status(:created)
    suite_id = json_response.fetch("id")

    post "/api/claims/admin/test_harness/suites/#{suite_id}/cases",
         params: {
           name: "Complete invoice",
           description: "Clean accepted package",
           baseline_invoice_version_id: baseline.fetch(:version).id,
           baseline_ingest_run_id: baseline.fetch(:run).id
         },
         as: :json

    expect(response).to have_http_status(:created)
    expect(json_response).to include(
      "baseline_invoice_version_id" => baseline.fetch(:version).id,
      "baseline_ingest_run_id" => baseline.fetch(:run).id
    )

    get "/api/claims/admin/test_harness/suites/#{suite_id}", as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response).to include("id" => suite_id, "case_count" => 1)
    expect(json_response.fetch("cases")).to contain_exactly(
      hash_including("name" => "Complete invoice")
    )

    post "/api/claims/admin/test_harness/model_compares",
         params: {
           testsuite_id: suite_id,
           candidate_document_triage_deployment_name: "candidate-luna",
           candidate_supporting_document_extraction_deployment_name:
             "candidate-luna",
           candidate_upgrade_analysis_deployment_name: "candidate-terra",
           comparison_deployment_name: "evaluator-terra"
         },
         as: :json

    expect(response).to have_http_status(:created)
    expect(json_response).to include(
      "status" => "draft",
      "baseline_document_triage_deployment_name" => "baseline-terra",
      "candidate_document_triage_deployment_name" => "candidate-luna"
    )
    run_id = json_response.fetch("id")

    post "/api/claims/admin/test_harness/model_compares/#{run_id}/submit",
         params: {
         },
         as: :json

    expect(response).to have_http_status(:accepted)
    expect(json_response.fetch("status")).to eq("queued")
    expect(Claims::TestHarness::StartRunJob).to have_received(
      :perform_async
    ).with("model_compare", run_id)
  end

  it "rejects a model comparison when suite baselines used different models" do
    first = create_baseline(deployment: "baseline-terra")
    second = create_baseline(deployment: "baseline-luna")
    suite =
      Claims::TestSuite.create!(name: "Mixed models #{SecureRandom.hex(4)}")
    [first, second].each_with_index do |baseline, index|
      suite.test_suite_cases.create!(
        name: "Case #{index + 1}",
        baseline_invoice_version: baseline.fetch(:version),
        baseline_ingest_run: baseline.fetch(:run)
      )
    end

    post "/api/claims/admin/test_harness/model_compares",
         params: {
           testsuite_id: suite.id,
           candidate_document_triage_deployment_name: "candidate-luna",
           candidate_supporting_document_extraction_deployment_name:
             "candidate-luna",
           candidate_upgrade_analysis_deployment_name: "candidate-luna",
           comparison_deployment_name: "evaluator-terra"
         },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to include(
      "baseline models do not match"
    )
  end

  it "returns model, suite, and historical-rule bootstrap data" do
    rule = create_rule
    history = create_rule_history(rule)

    get "/api/claims/admin/test_harness/bootstrap", as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("rules")).to include(
      hash_including("id" => rule.id)
    )
    expect(json_response.fetch("rule_histories")).to include(
      hash_including(
        "id" => history.id,
        "created_at" => history.history_created_at.as_json
      )
    )
  end

  it "creates and submits a regression run" do
    baseline = create_baseline
    suite = create_suite_case(baseline)

    post "/api/claims/admin/test_harness/regressions",
         params: {
           testsuite_id: suite.id,
           document_triage_deployment_name: "candidate-luna",
           supporting_document_extraction_deployment_name: "candidate-luna",
           upgrade_analysis_deployment_name: "candidate-terra"
         },
         as: :json

    expect(response).to have_http_status(:created)
    run_id = json_response.fetch("id")

    post "/api/claims/admin/test_harness/regressions/#{run_id}/submit",
         params: {
         },
         as: :json

    expect(response).to have_http_status(:accepted)
    expect(Claims::TestHarness::StartRunJob).to have_received(
      :perform_async
    ).with("regression", run_id)
  end

  it "returns a readable error when deleting a suite used by a test run" do
    suite = create_suite_case(create_baseline)
    regression =
      suite.regressions.create!(
        status: "draft",
        document_triage_deployment_name: "candidate-luna",
        supporting_document_extraction_deployment_name: "candidate-luna",
        upgrade_analysis_deployment_name: "candidate-terra"
      )
    regression.test_cases.create!(
      test_suite_case: suite.test_suite_cases.first,
      status: "queued"
    )

    get "/api/claims/admin/test_harness/suites", as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("rows")).to include(
      hash_including("id" => suite.id, "has_runs" => true)
    )

    delete "/api/claims/admin/test_harness/suites/#{suite.id}", as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to eq(
      "This test suite cannot be deleted because it has been used by one or more test runs."
    )
  end

  it "creates and submits a single-rule comparison" do
    baseline = create_baseline
    suite = create_suite_case(baseline)
    rule = create_rule
    history = create_rule_history(rule)
    common = Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
    Claims::InvoiceVersionRulecheck.create!(
      invoice_version: baseline.fetch(:version),
      invoice_upgrade_type_id: common.id,
      source_engine: "genai",
      rule_key: rule.genai_rule_key,
      contractor_display_name: rule.contractor_display_name,
      rule_result: "pass"
    )
    Claims::IngestStepRun.create!(
      ingest_run_id: baseline.fetch(:run).id,
      session_id: baseline.fetch(:run).session_id,
      invoice_version_id: baseline.fetch(:version).id,
      invoice_upgrade_type_id: common.id,
      step_type: "evaluate_genai_ruleset",
      status: "succeeded",
      context_window_json: [
        {
          role: "user",
          content: [{ type: "input_text", text: history.prompt_text }]
        }
      ]
    )

    post "/api/claims/admin/test_harness/rule_compares",
         params: {
           testsuite_id: suite.id,
           baseline_genai_rule_history_id: history.id,
           candidate_genai_rule_id: rule.id,
           comparison_deployment_name: "evaluator-terra"
         },
         as: :json

    expect(response).to have_http_status(:created)
    run_id = json_response.fetch("id")

    post "/api/claims/admin/test_harness/rule_compares/#{run_id}/submit",
         params: {
         },
         as: :json

    expect(response).to have_http_status(:accepted)
    expect(Claims::TestHarness::StartRunJob).to have_received(
      :perform_async
    ).with("rule_compare", run_id)
  end

  it "deletes inactive test runs and preserves active runs" do
    suite =
      Claims::TestSuite.create!(name: "Deletable runs #{SecureRandom.hex(4)}")
    rule = create_rule
    history = create_rule_history(rule)
    model_compare =
      suite.model_compares.create!(
        status: "draft",
        baseline_document_triage_deployment_name: "baseline-terra",
        baseline_supporting_document_extraction_deployment_name:
          "baseline-terra",
        baseline_upgrade_analysis_deployment_name: "baseline-terra",
        candidate_document_triage_deployment_name: "candidate-luna",
        candidate_supporting_document_extraction_deployment_name:
          "candidate-luna",
        candidate_upgrade_analysis_deployment_name: "candidate-luna",
        comparison_deployment_name: "evaluator-terra"
      )
    rule_compare =
      suite.rule_compares.create!(
        status: "failed",
        baseline_rule_history: history,
        candidate_rule: rule,
        comparison_deployment_name: "evaluator-terra"
      )
    regression =
      suite.regressions.create!(
        status: "draft",
        document_triage_deployment_name: "candidate-luna",
        supporting_document_extraction_deployment_name: "candidate-luna",
        upgrade_analysis_deployment_name: "candidate-luna"
      )

    [
      ["model_compares", model_compare],
      ["rule_compares", rule_compare],
      ["regressions", regression]
    ].each do |resource, run|
      delete "/api/claims/admin/test_harness/#{resource}/#{run.id}", as: :json

      expect(response).to have_http_status(:no_content)
      expect(run.class.exists?(run.id)).to be(false)
    end

    active_run =
      suite.regressions.create!(
        status: "running",
        document_triage_deployment_name: "candidate-luna",
        supporting_document_extraction_deployment_name: "candidate-luna",
        upgrade_analysis_deployment_name: "candidate-luna"
      )

    delete "/api/claims/admin/test_harness/regressions/#{active_run.id}",
           as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to eq(
      "Queued or running test runs cannot be deleted."
    )
    expect(Claims::TestRunRegression.exists?(active_run.id)).to be(true)
  end

  private

  def create_baseline(deployment: "baseline-terra")
    now = Time.current
    contractor =
      Contractor.create!(business_name: "Harness #{SecureRandom.hex(4)}")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck",
        status_updated_at: now,
        created_at: now,
        updated_at: now
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice: invoice,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "harness/#{SecureRandom.uuid}/invoice.pdf",
        original_filename: "invoice.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )
    run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_version_id: version.id,
        run_kind: "initial_upload",
        status: "succeeded",
        total_files: 1,
        completed_files: 1,
        failed_files: 0,
        document_triage_deployment_name: deployment,
        supporting_document_extraction_deployment_name: deployment,
        upgrade_analysis_deployment_name: deployment,
        completed_at: now,
        created_at: now,
        updated_at: now
      )
    Claims::IngestDocument.create!(
      ingest_run: run,
      session: session,
      contractor: contractor,
      invoice: invoice,
      resolved_invoice: invoice,
      resolved_invoice_version: version,
      storage_provider: "azure_blob",
      storage_key: version.storage_key,
      original_filename: "invoice.pdf",
      content_type: "application/pdf",
      classification_confidence: 100,
      document_kind: "invoice",
      document_kind_confidence: 100,
      created_at: now,
      updated_at: now
    )
    { version: version, run: run }
  end

  def create_suite_case(baseline)
    suite = Claims::TestSuite.create!(name: "Suite #{SecureRandom.hex(4)}")
    suite.test_suite_cases.create!(
      name: "Case #{SecureRandom.hex(4)}",
      baseline_invoice_version: baseline.fetch(:version),
      baseline_ingest_run: baseline.fetch(:run)
    )
    suite
  end

  def create_rule
    Claims::GenaiRule.create!(
      genai_rule_key: "harness_rule_#{SecureRandom.hex(4)}",
      contractor_display_name: "Harness rule",
      prompt_text: "Candidate prompt #{SecureRandom.hex(8)}",
      source_quote: "Harness source",
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "fail_only"
    )
  end

  def create_rule_history(rule)
    Claims::GenaiRuleHistory.create!(
      source_id: rule.id,
      genai_rule_key: rule.genai_rule_key,
      contractor_display_name: rule.contractor_display_name,
      prompt_text: "Baseline prompt #{SecureRandom.hex(8)}",
      enabled: true,
      source_quote: rule.source_quote,
      contractor_visibility: rule.contractor_visibility,
      contractor_blocking_policy: rule.contractor_blocking_policy,
      admin_workflow_policy: rule.admin_workflow_policy,
      history_created_at: Time.current
    )
  end
end
