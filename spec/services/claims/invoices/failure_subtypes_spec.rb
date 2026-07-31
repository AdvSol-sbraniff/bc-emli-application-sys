require "rails_helper"

RSpec.describe Claims::Invoices::FailureSubtypes do
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
        status: described_class.genai_status(error),
        status_subtype: described_class.genai(error),
        error: error
      )
    ).to include(
      failure_status: "package_needs_correction",
      failure_status_subtype: "package_unreadable_file",
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
end
