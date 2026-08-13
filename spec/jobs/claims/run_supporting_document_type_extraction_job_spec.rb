require "rails_helper"

RSpec.describe Claims::RunSupportingDocumentTypeExtractionJob do
  it "records a claimed failure when the expected supporting evidence is absent" do
    contractor = Contractor.create!(business_name: "Missing Support Evidence")
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
        storage_key: "missing-support/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf"
      )
    document_type =
      Claims::SupportingDocumentType.create!(
        type_key: "missing_support_test",
        description: "Missing support test"
      )
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        resolved_invoice_version_id: invoice_version.id,
        status: "running",
        total_files: 1
      )
    job = described_class.new
    allow(job).to receive(:advance_run!)

    expect do
      job.perform(invoice_version.id, document_type.id, run.id)
    end.not_to raise_error

    outcome =
      Claims::Ingest::StepOutcome.for_target(
        ingest_run_id: run.id,
        invoice_version_id: invoice_version.id,
        supporting_document_type_id: document_type.id,
        step_type: "extract_supporting_document"
      )
    expect(outcome.failed?).to be(true)
    expect(outcome.effective_step.status).to eq("failed")
  end
end
