require "rails_helper"

RSpec.describe Claims::RunIngestTriageJob do
  def build_context
    contractor = Contractor.create!(business_name: "Triage Retry Contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "ocr_in_progress"
      )
    run =
      Claims::IngestRun.create!(
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
        step_type: "classifier_files"
      )
    expect(step.status).to eq("failed")
    expect(step.genai_results_json).to be_nil
    expect(step).to have_attributes(
      failure_status: "package_needs_correction",
      failure_status_subtype: "package_unreadable_file",
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
end
