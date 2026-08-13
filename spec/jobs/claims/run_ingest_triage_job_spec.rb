require "rails_helper"

RSpec.describe Claims::RunIngestTriageJob do
  def build_context
    contractor = Contractor.create!(business_name: "Triage Retry Contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck"
      )
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        status: "running",
        total_files: 1
      )
    document =
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        storage_provider: "azure_blob",
        storage_key: "triage/image.jpg",
        original_filename: "Image.jpg",
        content_type: "image/jpeg",
        di_read_raw_json: {
          "content" => "read result"
        }
      )

    { run: run, document: document }
  end

  it "records and does not retry a permanent provider rejection" do
    context = build_context
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 422,
        payload: {
          code: "genai_input_image_invalid",
          category: "provider_invalid_image",
          retryable: false,
          diagnostic_id: "diag-job",
          provider_status: 400
        }
      )
    job = described_class.new
    allow(job).to receive(:build_classifier_contextwindowjson).and_return([])
    allow(job).to receive(:advance_run!)
    allow(Claims::Genai::NodeClient).to receive(:call).and_raise(error)

    expect do
      job.perform(context[:document].id, context[:run].id)
    end.not_to raise_error

    step =
      Claims::IngestStepRun.find_by!(
        ingest_run_id: context[:run].id,
        ingest_document_id: context[:document].id,
        step_type: "classify_document"
      )
    expect(step.status).to eq("failed")
    expect(step.genai_results_json).to be_nil
    expect(step).to have_attributes(
      failure_category: "package_needs_correction",
      failure_code: "package_unreadable_file",
      error_code: "genai_input_image_invalid",
      retryable: false,
      diagnostic_id: "diag-job",
      provider_status: 400
    )
  end

  it "raises a retryable provider outage for Sidekiq" do
    context = build_context
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 503,
        payload: {
          code: "genai_provider_gateway_error",
          category: "provider_gateway_error",
          retryable: true,
          diagnostic_id: "diag-retry"
        }
      )
    job = described_class.new
    allow(job).to receive(:build_classifier_contextwindowjson).and_return([])
    allow(job).to receive(:advance_run!)
    allow(Claims::Genai::NodeClient).to receive(:call).and_raise(error)

    expect do
      job.perform(context[:document].id, context[:run].id)
    end.to raise_error(Claims::Genai::NodeClient::Error)
  end

  it "records a claimed failure when required OCR evidence is absent" do
    context = build_context
    context[:document].update!(di_read_raw_json: nil)
    job = described_class.new
    allow(job).to receive(:advance_run!)

    expect do
      job.perform(context[:document].id, context[:run].id)
    end.not_to raise_error

    outcome =
      Claims::Ingest::StepOutcome.for_target(
        ingest_run_id: context[:run].id,
        ingest_document_id: context[:document].id,
        step_type: "classify_document"
      )
    expect(outcome.failed?).to be(true)
    expect(outcome.effective_step.status).to eq("failed")
  end

  it "recovers on a later attempt and ignores duplicate delivery after success" do
    context = build_context
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 503,
        payload: {
          code: "genai_provider_gateway_error",
          category: "provider_gateway_error",
          retryable: true,
          diagnostic_id: "diag-ordered-retry"
        }
      )
    payload = { "document_kind" => "invoice" }
    job = described_class.new
    allow(job).to receive(:build_classifier_contextwindowjson).and_return([])
    allow(job).to receive(:advance_run!)
    allow(job).to receive(:call_node_genai!).and_invoke(
      ->(*) { raise error },
      ->(*) { payload }
    )
    allow(Claims::Ingest::ApplyDocumentTriageResult).to receive(
      :call
    ).and_return(ok: true)

    expect do
      job.perform(context[:document].id, context[:run].id)
    end.to raise_error(Claims::Genai::NodeClient::Error)
    expect(context[:run].reload.status).to eq("running")

    expect do
      job.perform(context[:document].id, context[:run].id)
    end.not_to raise_error
    job.perform(context[:document].id, context[:run].id)

    outcome =
      Claims::Ingest::StepOutcome.for_target(
        ingest_run_id: context[:run].id,
        ingest_document_id: context[:document].id,
        step_type: "classify_document"
      )
    expect(outcome.succeeded?).to be(true)
    expect(outcome.attempt_count).to eq(2)
    expect(job).to have_received(:call_node_genai!).twice
  end

  it "directs unusual but clearly supporting evidence to the catchall type" do
    ask = described_class.new.send(:classifier_actual_ask)

    expect(ask).to include(
      "Use other_supporting_document when the file is clearly supplementary evidence"
    )
    expect(ask).to include("do not use unknown solely for that reason")
  end
end
