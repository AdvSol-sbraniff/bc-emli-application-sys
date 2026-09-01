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

  it "reruns only comparison jobs using completed candidate invoice records" do
    baseline = create_baseline
    candidate = create_baseline(deployment: "candidate-luna")
    suite = create_suite_case(baseline)
    parent =
      suite.model_compares.create!(
        status: "completed",
        baseline_document_triage_deployment_name: "baseline-terra",
        baseline_supporting_document_extraction_deployment_name:
          "baseline-terra",
        baseline_upgrade_analysis_deployment_name: "baseline-terra",
        candidate_document_triage_deployment_name: "candidate-luna",
        candidate_supporting_document_extraction_deployment_name:
          "candidate-luna",
        candidate_upgrade_analysis_deployment_name: "candidate-luna",
        comparison_deployment_name: "evaluator-terra",
        overall_document_classification_comparison: "Old classification",
        overall_supporting_document_extraction_comparison: "Old extraction",
        overall_upgrade_analysis_comparison: "Old upgrade"
      )
    comparison_case =
      parent.test_cases.create!(
        test_suite_case: suite.test_suite_cases.first,
        baseline_invoice_version: baseline.fetch(:version),
        baseline_ingest_run: baseline.fetch(:run),
        candidate_invoice_version: candidate.fetch(:version),
        candidate_ingest_run: candidate.fetch(:run),
        status: "completed",
        document_classification_comparison: "Old classification",
        supporting_document_extraction_comparison: "Old extraction",
        upgrade_analysis_comparison: "Old upgrade"
      )
    ingest_run_count = Claims::IngestRun.count

    post "/api/claims/admin/test_harness/model_compares/#{parent.id}/rerun_comparisons",
         params: {
         },
         as: :json

    expect(response).to have_http_status(:accepted)
    expect(json_response).to include(
      "status" => "queued",
      "overall_document_classification_comparison" => nil,
      "overall_supporting_document_extraction_comparison" => nil,
      "overall_upgrade_analysis_comparison" => nil
    )
    expect(json_response.fetch("cases")).to contain_exactly(
      hash_including(
        "id" => comparison_case.id,
        "status" => "queued",
        "candidate_invoice_version_id" => candidate.fetch(:version).id,
        "candidate_ingest_run_id" => candidate.fetch(:run).id,
        "document_classification_comparison" => nil,
        "supporting_document_extraction_comparison" => nil,
        "upgrade_analysis_comparison" => nil
      )
    )
    expect(Claims::IngestRun.count).to eq(ingest_run_count)
    expect(Claims::TestHarness::StartRunJob).to have_received(
      :perform_async
    ).with("model_compare", parent.id)
  end

  it "does not rerun comparisons when reusable candidate records are missing" do
    baseline = create_baseline
    suite = create_suite_case(baseline)
    parent =
      suite.model_compares.create!(
        status: "completed",
        baseline_document_triage_deployment_name: "baseline-terra",
        baseline_supporting_document_extraction_deployment_name:
          "baseline-terra",
        baseline_upgrade_analysis_deployment_name: "baseline-terra",
        candidate_document_triage_deployment_name: "candidate-luna",
        candidate_supporting_document_extraction_deployment_name:
          "candidate-luna",
        candidate_upgrade_analysis_deployment_name: "candidate-luna",
        comparison_deployment_name: "evaluator-terra",
        overall_document_classification_comparison: "Old classification",
        overall_supporting_document_extraction_comparison: "Old extraction",
        overall_upgrade_analysis_comparison: "Old upgrade"
      )
    parent.test_cases.create!(
      test_suite_case: suite.test_suite_cases.first,
      baseline_invoice_version: baseline.fetch(:version),
      baseline_ingest_run: baseline.fetch(:run),
      status: "completed",
      document_classification_comparison: "Old classification",
      supporting_document_extraction_comparison: "Old extraction",
      upgrade_analysis_comparison: "Old upgrade"
    )

    post "/api/claims/admin/test_harness/model_compares/#{parent.id}/rerun_comparisons",
         params: {
         },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to include(
      "does not have a completed candidate invoice to reuse"
    )
    expect(parent.reload.status).to eq("completed")
    expect(Claims::TestHarness::StartRunJob).not_to have_received(
      :perform_async
    )
  end

  it "returns persisted baseline and candidate evidence for a model comparison case" do
    baseline = create_baseline
    candidate = create_baseline(deployment: "candidate-luna")
    suite = create_suite_case(baseline)
    suite_case = suite.test_suite_cases.first
    upgrade_type =
      Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
    supporting_document_type =
      Claims::SupportingDocumentType.create!(
        type_key: "harness_photo_#{SecureRandom.hex(4)}",
        description: "Before and after photographs"
      )

    [baseline, candidate].each_with_index do |source, index|
      Claims::InvoiceVersionUpgradeType.create!(
        invoice_version_id: source.fetch(:version).id,
        invoice_upgrade_type_id: upgrade_type.id,
        confidence: 90 + index,
        evidence_text: "Classifier evidence #{index}",
        classification_explanation: "Classifier explanation #{index}"
      )
      Claims::SupportingDocument.create!(
        invoice_version_id: source.fetch(:version).id,
        supporting_document_type_id: supporting_document_type.id,
        storage_provider: "azure_blob",
        storage_key: "harness/#{SecureRandom.uuid}/photos.pdf",
        original_filename: "photos.pdf",
        content_type: "application/pdf",
        sha256: "shared-document-sha",
        classification_confidence: 95 + index,
        classification_reason: "Supporting classification #{index}",
        supporting_document_routing_quality: "usable",
        supporting_document_routing_quality_reason: "Readable evidence",
        created_at: Time.current,
        updated_at: Time.current
      )
    end
    %w[genai code].each do |source_engine|
      Claims::InvoiceVersionLocatedField.create!(
        invoice_version_id: baseline.fetch(:version).id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: source_engine,
        field_key: "#{source_engine}.field",
        value_type: "text",
        value_text: "#{source_engine} value",
        confidence: 90
      )
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version_id: baseline.fetch(:version).id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: source_engine,
        rule_key: "#{source_engine}_rule",
        contractor_display_name: "#{source_engine} rule",
        rule_result: "pass"
      )
    end

    parent =
      suite.model_compares.create!(
        status: "running",
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
    comparison_case =
      parent.test_cases.create!(
        test_suite_case: suite_case,
        baseline_invoice_version: baseline.fetch(:version),
        baseline_ingest_run: baseline.fetch(:run),
        candidate_invoice_version: candidate.fetch(:version),
        candidate_ingest_run: candidate.fetch(:run),
        status: "running"
      )

    get "/api/claims/admin/test_harness/model_compares/#{parent.id}/cases/#{comparison_case.id}/evidence",
        as: :json

    expect(response).to have_http_status(:ok)
    expect(
      json_response.dig("classification", "baseline", "upgrade_types").first
    ).to include(
      "invoice_upgrade_type_id" => upgrade_type.id,
      "confidence" => 90,
      "evidence_text" => "Classifier evidence 0"
    )
    expect(
      json_response.dig("classification", "candidate", "upgrade_types").first
    ).to include("confidence" => 91)
    expect(
      json_response.dig(
        "classification",
        "baseline",
        "supporting_documents"
      ).first
    ).to include(
      "original_filename" => "photos.pdf",
      "supporting_document_type_key" => supporting_document_type.type_key,
      "supporting_document_type_description" =>
        supporting_document_type.description,
      "classification_confidence" => 95,
      "classification_reason" => "Supporting classification 0",
      "supporting_document_routing_quality" => "usable"
    )
    expect(
      json_response.dig(
        "classification",
        "candidate",
        "supporting_documents"
      ).first
    ).to include("classification_confidence" => 96)
    expect(
      json_response
        .dig("extraction", "baseline", "documents")
        .first
        .fetch("document")
    ).not_to include(
      "classification_confidence",
      "classification_reason",
      "supporting_document_routing_quality",
      "supporting_document_routing_quality_reason"
    )
    expect(
      json_response.dig("upgrade_analysis", "baseline", "located_fields").pluck(
        "source_engine"
      )
    ).to eq(["genai"])
    expect(
      json_response.dig("upgrade_analysis", "baseline", "rulechecks").pluck(
        "source_engine"
      )
    ).to eq(["genai"])
  end

  it "returns model, suite, and rule bootstrap data" do
    rule = create_rule

    get "/api/claims/admin/test_harness/bootstrap", as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("rules")).to include(
      hash_including("id" => rule.id)
    )
    expect(json_response).not_to have_key("rule_histories")
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
    common = Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
    Claims::InvoiceVersionRulecheck.create!(
      invoice_version: baseline.fetch(:version),
      invoice_upgrade_type_id: common.id,
      source_engine: "genai",
      rule_key: rule.genai_rule_key,
      contractor_display_name: rule.contractor_display_name,
      rule_result: "pass"
    )
    post "/api/claims/admin/test_harness/rule_compares",
         params: {
           testsuite_id: suite.id,
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

  it "rejects a rule comparison when the baseline lacks that rule" do
    baseline = create_baseline
    suite = create_suite_case(baseline)
    rule = create_rule

    post "/api/claims/admin/test_harness/rule_compares",
         params: {
           testsuite_id: suite.id,
           candidate_genai_rule_id: rule.id,
           comparison_deployment_name: "evaluator-terra"
         },
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to include(
      "baseline version did not evaluate #{rule.genai_rule_key}"
    )
  end

  it "deletes inactive test runs and preserves active runs" do
    suite =
      Claims::TestSuite.create!(name: "Deletable runs #{SecureRandom.hex(4)}")
    rule = create_rule
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
end
