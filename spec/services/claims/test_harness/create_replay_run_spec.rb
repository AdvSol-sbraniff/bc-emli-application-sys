require "rails_helper"

RSpec.describe Claims::TestHarness::CreateReplayRun do
  it "creates a fresh package using the same immutable blobs and selected models" do
    now = Time.current
    contractor =
      Contractor.create!(business_name: "Replay #{SecureRandom.hex(4)}")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck",
        created_at: now,
        updated_at: now
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice: invoice,
        invoice_versionno: 1,
        storage_key: "source/invoice.pdf",
        created_at: now,
        updated_at: now
      )
    baseline_run =
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
        completed_at: now,
        created_at: now,
        updated_at: now
      )
    Claims::IngestDocument.create!(
      ingest_run: baseline_run,
      session: session,
      contractor: contractor,
      invoice: invoice,
      resolved_invoice: invoice,
      resolved_invoice_version: version,
      storage_key: "source/invoice.pdf",
      original_filename: "invoice.pdf",
      content_type: "application/pdf",
      created_at: now,
      updated_at: now
    )
    harness_case =
      instance_double(Claims::TestRunRegressionCase, ingest_run_id: nil)
    allow(harness_case).to receive(:lock!)
    expect(harness_case).to receive(:update!).with(
      ingest_run_id: kind_of(String)
    ).ordered
    expect(Claims::RunIngestReadOcrJob).to receive(:perform_async).ordered
    allow(Claims::Ingest::AdvanceRun).to receive(:call)

    run =
      described_class.call(
        baseline_ingest_run: baseline_run,
        deployments: {
          document_triage_deployment_name: "luna",
          supporting_document_extraction_deployment_name: "terra",
          upgrade_analysis_deployment_name: "terra"
        },
        harness_case: harness_case,
        ingest_run_pointer: :ingest_run_id
      )

    expect(run).not_to eq(baseline_run)
    expect(run.invoice_id).not_to eq(invoice.id)
    expect(run.document_triage_deployment_name).to eq("luna")
    expect(run.ingest_documents.pluck(:storage_key)).to eq(
      ["source/invoice.pdf"]
    )
    expect(run.ingest_documents.first.di_read_raw_json).to be_nil
  end

  it "returns the already-attached replay when a duplicate job is delivered" do
    baseline_run =
      instance_double(
        Claims::IngestRun,
        id: SecureRandom.uuid,
        status: "succeeded"
      )
    existing_run = instance_double(Claims::IngestRun)
    harness_case =
      instance_double(
        Claims::TestRunRegressionCase,
        ingest_run_id: SecureRandom.uuid
      )
    allow(harness_case).to receive(:lock!)
    allow(Claims::IngestDocument).to receive(:where).and_return(
      double(order: [double(storage_key: "source/invoice.pdf")])
    )
    allow(Claims::IngestRun).to receive(:find).with(
      harness_case.ingest_run_id
    ).and_return(existing_run)

    result =
      described_class.call(
        baseline_ingest_run: baseline_run,
        deployments: {
          document_triage_deployment_name: "luna",
          supporting_document_extraction_deployment_name: "terra",
          upgrade_analysis_deployment_name: "terra"
        },
        harness_case: harness_case,
        ingest_run_pointer: :ingest_run_id
      )

    expect(result).to eq(existing_run)
  end
end
