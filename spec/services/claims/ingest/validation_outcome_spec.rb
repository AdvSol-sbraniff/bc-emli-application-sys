require "rails_helper"

RSpec.describe Claims::Ingest::ValidationOutcome do
  let(:session) { Claims::Session.create! }
  let(:contractor) { Contractor.create!(business_name: "Validation State") }
  let(:invoice) do
    Claims::Invoice.create!(
      session_id: session.id,
      contractor_id: contractor.id
    )
  end
  let(:invoice_version) do
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_provider: "test",
      storage_key: "validation/invoice.pdf",
      original_filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end
  let(:run) do
    Claims::IngestRun.create!(
      run_kind: "initial_upload",
      session_id: session.id,
      resolved_invoice_version_id: invoice_version.id,
      status: "running"
    )
  end
  let(:common) do
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: "common"
    ) { |row| row.description = "Common" }
  end
  let(:upgrade) do
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: "state-test"
    ) { |row| row.description = "State test" }
  end

  before do
    common
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade.id
    )
  end

  def step!(step_type, status, upgrade_type_id: nil, retryable: nil)
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type_id,
      step_type: step_type,
      status: status,
      error_text: status == "failed" ? "Injected failure" : nil,
      retryable: retryable
    )
  end

  it "is missing before case facts start" do
    expect(
      described_class.call(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id
      )
    ).to be_missing
  end

  it "is ready only after every required GenAI target succeeds" do
    step!("case_facts", "succeeded")
    step!("evaluate_genai_ruleset", "succeeded", upgrade_type_id: common.id)
    step!("evaluate_genai_ruleset", "succeeded", upgrade_type_id: upgrade.id)

    expect(
      described_class.call(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id
      )
    ).to be_ready_to_finalize
  end

  it "keeps a retryable ruleset failure nonterminal" do
    step!("case_facts", "succeeded")
    step!(
      "evaluate_genai_ruleset",
      "failed",
      upgrade_type_id: common.id,
      retryable: true
    )
    step!("evaluate_genai_ruleset", "succeeded", upgrade_type_id: upgrade.id)

    expect(
      described_class.call(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id
      )
    ).to be_retrying
  end

  it "lets a later success absorb an earlier failed attempt" do
    step!("case_facts", "succeeded")
    step!(
      "evaluate_genai_ruleset",
      "failed",
      upgrade_type_id: common.id,
      retryable: true
    )
    step!("evaluate_genai_ruleset", "succeeded", upgrade_type_id: common.id)
    step!("evaluate_genai_ruleset", "succeeded", upgrade_type_id: upgrade.id)
    step!("finalize_validation", "succeeded")

    expect(
      described_class.call(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id
      )
    ).to be_succeeded
  end
end
