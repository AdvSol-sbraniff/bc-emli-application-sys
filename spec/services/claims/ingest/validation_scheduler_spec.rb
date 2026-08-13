require "rails_helper"

RSpec.describe Claims::Ingest::ValidationScheduler do
  let(:contractor) { Contractor.create!(business_name: "Scheduler") }
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
      invoice_versionno: 1,
      storage_provider: "test",
      storage_key: "scheduler/invoice.pdf",
      original_filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end
  let(:run) do
    Claims::IngestRun.create!(
      run_kind: "initial_upload",
      session_id: session.id,
      contractor_id: contractor.id,
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
      upgrade_type_key: "scheduler-test"
    ) { |row| row.description = "Scheduler test" }
  end

  before do
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade.id
    )
    allow(Claims::RunGenaiJob).to receive(:perform_async).and_return(
      "start-job"
    )
    allow(Claims::FinalizeGenaiValidationJob).to receive(
      :perform_async
    ).and_return("finish-job")
  end

  it "creates and enqueues one validation root under duplicate advancement" do
    2.times do
      described_class.start!(run: run, invoice_version: invoice_version)
    end

    expect(
      Claims::IngestStepRun.where(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id,
        step_type: "case_facts"
      ).count
    ).to eq(1)
    expect(Claims::RunGenaiJob).to have_received(:perform_async).once
  end

  it "creates and enqueues one aggregate fan-in marker" do
    create_step!("case_facts", "succeeded")
    create_step!("evaluate_genai_ruleset", "succeeded", common.id)
    create_step!("evaluate_genai_ruleset", "succeeded", upgrade.id)

    2.times do
      described_class.finalize!(run: run, invoice_version: invoice_version)
    end

    expect(
      Claims::IngestStepRun.where(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id,
        step_type: "finalize_validation"
      ).count
    ).to eq(1)
    expect(Claims::FinalizeGenaiValidationJob).to have_received(
      :perform_async
    ).once
  end

  def create_step!(step_type, status, upgrade_type_id = nil)
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type_id,
      step_type: step_type,
      status: status
    )
  end
end
