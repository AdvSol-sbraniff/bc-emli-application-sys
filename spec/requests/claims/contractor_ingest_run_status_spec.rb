require "rails_helper"

RSpec.describe "Claims contractor ingest run status", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_contractor
    ).and_return(contractor)
  end

  let(:contractor) do
    Contractor.create!(business_name: "Single Polling Contractor")
  end

  it "returns the resolved invoice and readiness in the run response" do
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "genai_complete",
        status_updated_at: Time.current
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "single-poll/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf"
      )
    ingest_run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        resolved_invoice_version_id: invoice_version.id,
        status: "succeeded",
        total_files: 1,
        completed_files: 1,
        failed_files: 0,
        completed_at: Time.current
      )

    get "/api/claims/contractor/ingest/runs/#{ingest_run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "id" => ingest_run.id,
      "status" => "succeeded",
      "invoice_id" => invoice.id,
      "invoice_status" => "genai_complete",
      "invoice_version_id" => invoice_version.id,
      "invoice_versionno" => 1,
      "original_filename" => "Invoice.pdf",
      "can_continue" => true
    )
  end

  it "returns processing invoice context without allowing continuation" do
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "ocr_in_progress"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "single-poll/processing.pdf",
        original_filename: "Processing.pdf",
        content_type: "application/pdf"
      )
    ingest_run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "running",
        total_files: 2,
        completed_files: 0,
        failed_files: 0
      )

    get "/api/claims/contractor/ingest/runs/#{ingest_run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "status" => "running",
      "invoice_id" => invoice.id,
      "invoice_status" => "ocr_in_progress",
      "invoice_version_id" => invoice_version.id,
      "can_continue" => false
    )
  end

  it "returns one contractor-facing failure from the authoritative run response" do
    session = Claims::Session.create!
    ingest_run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "failed",
        total_files: 2,
        completed_files: 0,
        failed_files: 1,
        completed_at: Time.current,
        failure_status: "technical_failure",
        failure_status_subtype: "genai_service_error"
      )
    Claims::IngestStepRun.create!(
      ingest_run_id: ingest_run.id,
      session_id: session.id,
      step_type: "classifier_files",
      status: "failed",
      error_text: "Private provider failure.",
      failure_status: "technical_failure",
      failure_status_subtype: "genai_service_error",
      error_code: "genai_provider_gateway_error",
      error_category: "provider_gateway_error",
      retryable: true,
      diagnostic_id: "private-diagnostic",
      provider_status: 503,
      provider_code: "service_unavailable"
    )

    get "/api/claims/contractor/ingest/runs/#{ingest_run.id}"

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "status" => "failed",
      "failure_status" => "technical_failure",
      "failure_status_subtype" => "genai_service_error",
      "can_continue" => false
    )
    expect(json_response.fetch("failure_message")).to be_present
    expect(json_response).not_to have_key("messages")
    expect(json_response.to_json).not_to include("provider_status")
    expect(json_response.to_json).not_to include("private-diagnostic")
    expect(json_response.fetch("invoice_id")).to be_nil
  end
end
