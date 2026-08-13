require "rails_helper"

RSpec.describe Claims::Ingest::FailureClassifier do
  it "maps an invalid image to a permanent package correction" do
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 422,
        payload: {
          code: "genai_input_image_invalid",
          category: "provider_invalid_image",
          retryable: false,
          diagnostic_id: "diag-image",
          provider_status: 400
        }
      )

    expect(described_class.genai_status(error)).to eq(
      "package_needs_correction"
    )
    expect(described_class.genai(error)).to eq("package_unreadable_file")
    expect(described_class).not_to be_retryable(error)
    expect(
      described_class.step_attributes(
        failure_category: described_class.genai_status(error),
        failure_code: described_class.genai(error),
        error: error
      )
    ).to include(
      failure_category: "package_needs_correction",
      failure_code: "package_unreadable_file",
      error_code: "genai_input_image_invalid",
      retryable: false,
      diagnostic_id: "diag-image",
      provider_status: 400
    )
  end

  it "allows retries for a transient provider outage" do
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 503,
        payload: {
          code: "genai_provider_gateway_error",
          category: "provider_gateway_error",
          retryable: true
        }
      )

    expect(described_class).to be_retryable(error)
    expect(described_class.genai_status(error)).to eq("technical_failure")
  end

  it "maps invalid model JSON to a retryable malformed GenAI response" do
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 503,
        payload: {
          code: "genai_model_output_invalid_json",
          category: "model_output_invalid_json",
          retryable: true,
          diagnostic_id: "diag-json",
          phase: "classify_document",
          snippet: "not json"
        }
      )

    expect(described_class.genai_status(error)).to eq("technical_failure")
    expect(described_class.genai(error)).to eq(
      "genai_service_malformed_response"
    )
    expect(described_class).to be_retryable(error)
    expect(
      described_class.step_attributes(
        failure_category: described_class.genai_status(error),
        failure_code: described_class.genai(error),
        error: error
      )
    ).to include(
      failure_category: "technical_failure",
      failure_code: "genai_service_malformed_response",
      error_code: "genai_model_output_invalid_json",
      error_category: "model_output_invalid_json",
      retryable: true,
      diagnostic_id: "diag-json",
      error_phase: "classify_document"
    )
    expect(error.message).to include("snippet=not json")
  end
end
