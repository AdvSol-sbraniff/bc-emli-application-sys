require "rails_helper"

RSpec.describe "Claims upload-fix errors", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::Claims::IngestController).to receive(
      :require_upload_fix_actor!
    )
  end

  it "returns 500 for a structured technical fix failure" do
    result =
      instance_double(
        Claims::Ingest::UploadFixPackage::Result,
        ok: false,
        failure_category: "technical_failure",
        to_h: {
          ok: false,
          error:
            "A processing service is temporarily unavailable. Please try again.",
          failure_category: "technical_failure",
          failure_code: "upload_unexpected_exception",
          error_code: "upload_unexpected_exception",
          retryable: false,
          diagnostic_id: SecureRandom.uuid
        }
      )
    allow(Claims::Ingest::UploadFixPackage).to receive(:call).and_return(result)

    post "/api/claims/invoices/#{SecureRandom.uuid}/upload_fix_package"

    expect(response).to have_http_status(:internal_server_error)
    expect(json_response).to include(
      "ok" => false,
      "failure_category" => "technical_failure",
      "error_code" => "upload_unexpected_exception"
    )
  end

  it "returns 422 for a correctable fix-package failure" do
    result =
      instance_double(
        Claims::Ingest::UploadFixPackage::Result,
        ok: false,
        failure_category: "package_needs_correction",
        to_h: {
          ok: false,
          error:
            "We could not prepare your AI advice because the upload package needs a change.",
          failure_category: "package_needs_correction",
          failure_code: "package_unsupported_file_type",
          error_code: "package_unsupported_file_type",
          retryable: false
        }
      )
    allow(Claims::Ingest::UploadFixPackage).to receive(:call).and_return(result)

    post "/api/claims/invoices/#{SecureRandom.uuid}/upload_fix_package"

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response).to include(
      "ok" => false,
      "failure_category" => "package_needs_correction",
      "error_code" => "package_unsupported_file_type"
    )
  end
end
