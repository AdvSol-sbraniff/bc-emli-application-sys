require "rails_helper"

RSpec.describe "Claims contractor upload errors", type: :request do
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
    Contractor.create!(business_name: "Safe Upload Error Contractor")
  end

  it "returns a structured 500 without exposing an unexpected Ruby error" do
    diagnostic_id = SecureRandom.uuid
    error =
      Claims::Ingest::UploadErrors::UnexpectedError.new(
        diagnostic_id: diagnostic_id,
        ingest_run_id: SecureRandom.uuid,
        session_id: SecureRandom.uuid
      )
    error.set_backtrace(["private/server/path.rb:42"])
    allow(Claims::Ingest::CreateDraftBatch).to receive(:call).and_raise(error)

    post "/api/claims/contractor/invoices/upload_batch"

    expect(response).to have_http_status(:internal_server_error)
    expect(json_response).to include(
      "ok" => false,
      "error" => Claims::Ingest::UploadErrors::SAFE_TECHNICAL_MESSAGE,
      "failure_status" => "technical_failure",
      "failure_status_subtype" => "upload_unexpected_exception",
      "error_code" => "upload_unexpected_exception",
      "retryable" => false,
      "diagnostic_id" => diagnostic_id
    )
    expect(response.body).not_to include("undefined method")
    expect(response.body).not_to include("private/server/path")
  end

  it "returns a structured 422 for a correctable request validation error" do
    error =
      Claims::Ingest::UploadErrors::ValidationError.new(
        "Select at least one invoice or supporting document to upload."
      )
    allow(Claims::Ingest::CreateDraftBatch).to receive(:call).and_raise(error)

    post "/api/claims/contractor/invoices/upload_batch"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response).to eq(
      "ok" => false,
      "error" =>
        "Select at least one invoice or supporting document to upload.",
      "error_code" => "upload_validation_error",
      "retryable" => false
    )
  end
end
