require "rails_helper"

RSpec.describe Claims::Ingest::StepClaim do
  let(:session) { Claims::Session.create! }
  let(:contractor) { Contractor.create!(business_name: "Step Claim") }
  let(:run) do
    Claims::IngestRun.create!(
      run_kind: "initial_upload",
      session_id: session.id,
      contractor_id: contractor.id,
      status: "running"
    )
  end
  let(:document) do
    Claims::IngestDocument.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      contractor_id: contractor.id,
      storage_provider: "test",
      storage_key: "claim/document.pdf",
      original_filename: "document.pdf",
      content_type: "application/pdf"
    )
  end

  it "claims one queued attempt and rejects a duplicate delivery" do
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      ingest_document_id: document.id,
      step_type: "read_document",
      status: "queued"
    )

    first =
      described_class.call(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "read_document"
      )
    duplicate =
      described_class.call(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "read_document"
      )

    expect(first.status).to eq("in_progress")
    expect(duplicate).to be_nil
  end

  it "creates a new attempt after a failed retryable attempt" do
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      ingest_document_id: document.id,
      step_type: "read_document",
      status: "failed",
      error_text: "Transient failure",
      retryable: true
    )

    claimed =
      described_class.call(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "read_document"
      )

    expect(claimed.status).to eq("in_progress")
    expect(
      Claims::IngestStepRun.where(
        ingest_run_id: run.id,
        ingest_document_id: document.id,
        step_type: "read_document"
      ).count
    ).to eq(2)
  end

  it "never creates work after logical success" do
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      ingest_document_id: document.id,
      step_type: "read_document",
      status: "succeeded"
    )

    expect(
      described_class.call(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "read_document"
      )
    ).to be_nil
  end
end
