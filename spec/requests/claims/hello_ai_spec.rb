require "rails_helper"

RSpec.describe "Claims AI connectivity", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::Claims::HelloAiController).to receive(
      :require_claims_admin!
    )
  end

  it "defaults to the comparison deployment from configuration" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!(
          created_at: Time.current,
          updated_at: Time.current
        )
    config.update!(comparison_deployment_name: "comparison-model")

    get "/api/claims/admin/hello_ai"

    expect(response).to have_http_status(:ok)
    expect(json_response).to eq("deployment_name" => "comparison-model")
  end

  it "forwards the selected deployment to Node without changing configuration" do
    original_config = Claims::Genai::DeploymentConfig.current
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("INV_NODE_BASE_URL").and_return(
      "http://claims-ai:3001"
    )
    node_response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(node_response).to receive(:body).and_return('{"message":"Hello"}')
    http = double("HTTP")
    expect(Net::HTTP).to receive(:start).with(
      "claims-ai",
      3001,
      anything
    ).and_yield(http)
    expect(http).to receive(:request) do |request|
      expect(request.path).to eq("/inv/simple-chat")
      expect(JSON.parse(request.body)).to eq(
        "prompt" => "Hello",
        "deployment_name" => "alternate-model"
      )
      node_response
    end

    post "/api/claims/admin/hello_ai",
         params: {
           prompt: "Hello",
           deployment_name: " alternate-model "
         },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response).to eq("message" => "Hello")
    expect(Claims::Genai::DeploymentConfig.current).to eq(original_config)
  end

  it "rejects missing or oversized deployments before making a provider request" do
    expect(Net::HTTP).not_to receive(:start)
    [nil, " ", "a" * 201].each do |deployment|
      post "/api/claims/admin/hello_ai",
           params: {
             prompt: "Hello",
             deployment_name: deployment
           },
           as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json_response.fetch("error")).to match(/deployment name/)
    end
  end
end
