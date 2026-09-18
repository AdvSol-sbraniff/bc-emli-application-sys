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

      expect(error.retryable?).to be(false)
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
      expect(error.retryable?).to be(false)
    end
  ensure
    ENV["INV_NODE_BASE_URL"] = previous_base_url
  end

  it "sends a rule audit to its isolated endpoint with attachments and model selection" do
    previous_base_url = ENV["INV_NODE_BASE_URL"]
    ENV["INV_NODE_BASE_URL"] = "http://claims-ai:3001"
    output = {
      "advice" => "No change is justified.",
      "proposed_rule_prompt" => nil,
      "proposed_precheck_action" => nil,
      "proposed_contractor_guidance" => nil,
      "transport" => {
        "attachment_count" => 1
      }
    }
    response = instance_double(Net::HTTPResponse, body: output.to_json)
    allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
    http = instance_double(Net::HTTP)
    allow(http).to receive(:open_timeout=).with(10)
    allow(http).to receive(:read_timeout=).with(300)
    allow(Net::HTTP).to receive(:new).with("claims-ai", 3001).and_return(http)
    expect(http).to receive(:request) do |request|
      expect(request.path).to eq("/inv/rule-audit")
      expect(JSON.parse(request.body)).to include(
        "contextwindowjson" => [{ "role" => "user", "content" => [] }],
        "attachments" => [{ "storageKey" => "invoice/source.pdf" }],
        "deployment_name" => "comparison-model"
      )
      response
    end
    expect(
      described_class.rule_audit(
        contextwindowjson: [{ role: "user", content: [] }],
        attachments: [{ storageKey: "invoice/source.pdf" }],
        deployment_name: "comparison-model"
      )
    ).to eq(output)
  ensure
    ENV["INV_NODE_BASE_URL"] = previous_base_url
  end
end
