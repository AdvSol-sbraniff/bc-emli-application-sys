require "rails_helper"

RSpec.describe Claims::Ingest::AdvanceExistingEvidenceRun do
  let(:contractor) { Contractor.create!(business_name: "Existing Evidence") }
  let(:session) { Claims::Session.create! }
  let(:invoice) do
    Claims::Invoice.create!(
      session_id: session.id,
      contractor_id: contractor.id,
      status: "contractor_precheck"
    )
  end
  let(:invoice_version) do
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 2,
      storage_provider: "test",
      storage_key: "rerun/invoice.pdf",
      original_filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end
  let(:run) do
    Claims::IngestRun.create!(
      run_kind: "rules_rerun",
      session_id: session.id,
      contractor_id: contractor.id,
      invoice_id: invoice.id,
      resolved_invoice_version_id: invoice_version.id,
      status: "running",
      total_files: 1
    )
  end
  let(:common) do
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: "common"
    ) { |row| row.description = "Common" }
  end
  let(:upgrade) do
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: "rerun-test"
    ) { |row| row.description = "Rerun test" }
  end

  before do
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade.id
    )
    create_step!("clone_evidence", "succeeded")
    create_step!("case_facts", "succeeded")
    create_step!("evaluate_genai_ruleset", "succeeded", upgrade.id)
    allow(Claims::PipelineAudit::CheckRun).to receive(:call)
  end

  it "remains running while a retryable ruleset attempt can retry" do
    create_step!("evaluate_genai_ruleset", "failed", common.id, retryable: true)

    described_class.call(ingest_run_id: run.id)

    expect(run.reload.status).to eq("running")
    expect(run.failure_category).to be_nil
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  it "fails only after all allowed retryable attempts are exhausted" do
    4.times do
      create_step!(
        "evaluate_genai_ruleset",
        "failed",
        common.id,
        retryable: true
      )
    end

    described_class.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "failed",
      failure_category: "technical_failure"
    )
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  it "succeeds despite a retained earlier failed attempt" do
    create_step!("evaluate_genai_ruleset", "failed", common.id, retryable: true)
    create_step!("evaluate_genai_ruleset", "succeeded", common.id)
    create_step!("finalize_validation", "succeeded")

    described_class.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "succeeded",
      failure_category: nil,
      failed_files: 0
    )
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  def create_step!(step_type, status, upgrade_type_id = nil, retryable: nil)
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type_id,
      step_type: step_type,
      status: status,
      error_text: status == "failed" ? "Injected ruleset failure" : nil,
      failure_category: status == "failed" ? "technical_failure" : nil,
      failure_code: status == "failed" ? "genai_service_error" : nil,
      error_code: status == "failed" ? "genai_provider_gateway_error" : nil,
      retryable: retryable
    )
  end
end
