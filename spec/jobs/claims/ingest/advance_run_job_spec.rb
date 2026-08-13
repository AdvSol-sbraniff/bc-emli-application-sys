require "rails_helper"

RSpec.describe Claims::Ingest::AdvanceRunJob do
  it "allows a transient coordination error to be retried without failing the run" do
    session = Claims::Session.create!
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        status: "running"
      )
    allow(Claims::Ingest::AdvanceRun).to receive(:call).and_invoke(
      ->(*) { raise "temporary coordinator error" },
      ->(*) {}
    )

    expect do described_class.new.perform(run.id) end.to raise_error(
      RuntimeError,
      "temporary coordinator error"
    )
    expect(run.reload.status).to eq("running")

    expect do described_class.new.perform(run.id) end.not_to raise_error
  end

  it "terminally fails the run after coordination retries are exhausted" do
    contractor = Contractor.create!(business_name: "Coordinator Failure")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "test",
        storage_key: "coordinator/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf"
      )
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_version_id: invoice_version.id,
        status: "running",
        total_files: 2
      )

    described_class.sidekiq_retries_exhausted_block.call(
      { "args" => [run.id] },
      RuntimeError.new("permanent coordinator error")
    )

    expect(run.reload).to have_attributes(
      status: "failed",
      failed_files: 1,
      failure_category: "technical_failure",
      pipeline_error_code: "ingest_coordinator_failed"
    )
    expect(run.completed_at).to be_present
    expect(invoice.reload.status).to eq("contractor_precheck")
  end
end
