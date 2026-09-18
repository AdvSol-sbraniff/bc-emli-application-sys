require "rails_helper"

RSpec.describe Claims::RuleAudits::Audit do
  let(:params) do
    {
      source_engine: "genai",
      rule_key: "example",
      invoice_id: SecureRandom.uuid
    }
  end
  let(:context) do
    {
      contextwindowjson: [
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text:
                '{"record_type":"invoice_version","complaint":"Name the document"}'
            }
          ]
        }
      ],
      attachments: [
        {
          type: "input_file",
          storageKey: "evidence/invoice.pdf",
          filename: "invoice.pdf",
          reference: "source_file_1"
        }
      ],
      manifest: {
        invoice_id: params[:invoice_id],
        version_count: 2,
        limitations: ["Rule history is inferred."]
      }
    }
  end
  let(:response) do
    {
      "advice" => "The finding is correct; make the next action clearer.",
      "proposed_rule_prompt" => nil,
      "proposed_precheck_action" => nil,
      "proposed_contractor_guidance" =>
        "Include the named document when preparing the package.",
      "transport" => {
        "provider_status" => "completed",
        "deployment" => "comparison-model",
        "attachment_count" => 1,
        "attachments" => [
          {
            "reference" => "source_file_1",
            "storage_key" => "evidence/invoice.pdf",
            "byte_size" => 100,
            "sha256" => "a" * 64
          }
        ],
        "omissions" => [],
        "context_record_count" => 2,
        "context_sha256" =>
          Digest::SHA256.hexdigest(
            JSON.generate(
              [
                {
                  role: "system",
                  content: [
                    { type: "input_text", text: "Audit the supplied evidence." }
                  ]
                },
                *context[:contextwindowjson]
              ]
            )
          )
      }
    }
  end

  before do
    allow(Claims::RuleAudits::Guidance).to receive(:for_engine).with(
      "genai"
    ).and_return({ "reference_sha256" => "guide-digest" })
    allow(Claims::RuleAudits::Configuration).to receive(
      :system_record
    ).and_return("Audit the supplied evidence.")
    allow(Claims::Genai::DeploymentConfig).to receive(:current).and_return(
      comparison_deployment_name: "comparison-model"
    )
    allow(Claims::RuleAudits::ContextBuilder).to receive(:new).and_return(
      double(call: context)
    )
    allow(Claims::Genai::NodeClient).to receive(:rule_audit).and_return(
      response
    )
  end

  it "sends the full server-built evidence and separate system instruction to the comparison deployment" do
    expect(Claims::Genai::NodeClient).to receive(:rule_audit) do |request|
      expect(request[:deployment_name]).to eq("comparison-model")
      expect(request[:contextwindowjson].first[:role]).to eq("system")
      expect(request[:contextwindowjson].drop(1)).to eq(
        context[:contextwindowjson]
      )
      expect(request[:attachments]).to eq(context[:attachments])
      expect(request[:diagnostic_context][:step_type]).to eq(
        "rule_package_audit"
      )
      response
    end
    result = described_class.new(**params).call
    expect(result).to include(
      saved: false,
      proposed_rule_prompt: nil,
      proposed_precheck_action: nil
    )
    expect(result[:proposed_contractor_guidance]).to include("named document")
    expect(result[:evidence]).to include(context[:manifest])
    expect(result[:evidence][:file_transport_status]).to start_with("Verified:")
    expect(result[:transport]["context_sha256"]).to eq(
      response["transport"]["context_sha256"]
    )
    expect(result[:guidance_sha256]).to eq("guide-digest")
  end

  it "accepts an advice-only no-change result with all proposal fields null" do
    response["proposed_contractor_guidance"] = nil
    expect(
      described_class
        .new(**params)
        .call
        .values_at(
          :proposed_rule_prompt,
          :proposed_precheck_action,
          :proposed_contractor_guidance
        )
    ).to eq([nil, nil, nil])
  end

  it "rejects advice when evidence transport is absent, incomplete or belongs to a different context" do
    [
      nil,
      response["transport"].merge("attachment_count" => 0),
      response["transport"].merge("context_sha256" => "wrong-context")
    ].each do |transport|
      allow(Claims::Genai::NodeClient).to receive(:rule_audit).and_return(
        response.merge("transport" => transport)
      )
      expect { described_class.new(**params).call }.to raise_error(
        described_class::InvalidResponse,
        /complete audit evidence/
      )
    end
  end

  it "rejects incomplete, blank and wrongly typed model fields" do
    [
      response.except("proposed_precheck_action"),
      response.merge("advice" => " "),
      response.merge("proposed_rule_prompt" => [])
    ].each do |invalid|
      allow(Claims::Genai::NodeClient).to receive(:rule_audit).and_return(
        invalid
      )
      expect { described_class.new(**params).call }.to raise_error(
        described_class::InvalidResponse
      )
    end
  end

  it "rejects a prompt proposal for executable code" do
    allow(Claims::RuleAudits::Guidance).to receive(:for_engine).with(
      "code"
    ).and_return({ "reference_sha256" => "guide-digest" })
    response["proposed_rule_prompt"] = "Invent a code-rule prompt"
    expect {
      described_class.new(**params.merge(source_engine: "code")).call
    }.to raise_error(described_class::InvalidResponse, /code rule/)
  end

  it "checks the combined system and evidence size before any AI call" do
    allow(Claims::RuleAudits::Configuration).to receive(
      :system_record
    ).and_return("x" * Claims::RuleAudits::ContextBuilder::MAX_CONTEXT_BYTES)
    expect(Claims::Genai::NodeClient).not_to receive(:rule_audit)
    expect { described_class.new(**params).call }.to raise_error(
      Claims::RuleAudits::ContextBuilder::TooLarge
    )
  end

  it "requires configured model without changing another deployment" do
    allow(Claims::Genai::DeploymentConfig).to receive(:current).and_return(
      comparison_deployment_name: nil
    )
    expect(Claims::Genai::NodeClient).not_to receive(:rule_audit)
    expect { described_class.new(**params).call }.to raise_error(
      Claims::RuleAudits::Configuration::Unavailable,
      /model/
    )
  end
end
