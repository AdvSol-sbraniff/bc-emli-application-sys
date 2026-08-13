require "rails_helper"

RSpec.describe Claims::Genai::NodeClient do
  describe Claims::Genai::NodeClient::Error do
    it "exposes only sanitized analytics fields" do
      error =
        described_class.new(
          http_status: 422,
          payload: {
            code: "genai_input_image_invalid",
            category: "provider_invalid_image",
            retryable: false,
            diagnostic_id: "diag-123",
            provider_status: 400,
            provider_code: "invalid_value",
            provider_attempt_count: 1,
            phase: "classify_document",
            provider_response_snippet: "private provider detail"
          }
        )

      expect(error).not_to be_retryable
      expect(error.analytics_payload).to eq(
        "error_code" => "genai_input_image_invalid",
        "error_category" => "provider_invalid_image",
        "retryable" => false,
        "diagnostic_id" => "diag-123",
        "provider_status" => 400,
        "provider_code" => "invalid_value",
        "provider_attempt_count" => 1,
        "phase" => "classify_document"
      )
      expect(error.message).not_to include("private provider detail")
    end
  end

  it "raises a typed error from the Node error envelope" do
    previous_base_url = ENV["INV_NODE_BASE_URL"]
    ENV["INV_NODE_BASE_URL"] = "http://claims-ai:3000"
    response =
      instance_double(
        Net::HTTPResponse,
        code: "422",
        body: {
          message: "GenAI provider request failed",
          code: "genai_input_image_invalid",
          category: "provider_invalid_image",
          retryable: false,
          diagnostic_id: "diag-response",
          provider_status: 400
        }.to_json
      )
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:open_timeout=)
    allow(http).to receive(:read_timeout=)
    allow(http).to receive(:request).and_return(response)
    allow(Net::HTTP).to receive(:new).and_return(http)

    expect do described_class.call(contextwindowjson: []) end.to raise_error(
      Claims::Genai::NodeClient::Error
    ) do |error|
      expect(error.error_code).to eq("genai_input_image_invalid")
      expect(error.error_category).to eq("provider_invalid_image")
      expect(error).not_to be_retryable
    end
  ensure
    ENV["INV_NODE_BASE_URL"] = previous_base_url
  end
end
