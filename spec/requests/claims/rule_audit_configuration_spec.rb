require "rails_helper"

RSpec.describe "Claims rule audit configuration", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    allow_any_instance_of(
      Api::Claims::ValidationgenaiConfigController
    ).to receive(:claims_function_keys).and_return(["claims.configuration"])
  end

  it "shows the maintained default and persists a separate editable audit instruction" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!(
          system_record: "Existing validation instruction"
        )
    config.update!(
      rule_audit_system_record: nil,
      comparison_deployment_name: "existing-comparison"
    )
    existing_validation = config.system_record
    get "/api/claims/admin/validationgenai_config"
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["rule_audit_system_record"]).to eq(
      Claims::RuleAudits::Configuration.default_system_record
    )
    patch "/api/claims/admin/validationgenai_config",
          params: {
            rule_audit_system_record:
              "Explain evidence, next steps and uncertainty."
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(config.reload.rule_audit_system_record).to eq(
      "Explain evidence, next steps and uncertainty."
    )
    expect(config.system_record).to eq(existing_validation)
    expect(config.comparison_deployment_name).to eq("existing-comparison")
    expect(Claims::RuleAudits::Configuration.system_record).to eq(
      config.rule_audit_system_record
    )
  end

  it "restores the application default when an administrator clears the override" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!
    config.update!(rule_audit_system_record: "An old override")
    patch "/api/claims/admin/validationgenai_config",
          params: {
            rule_audit_system_record: ""
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(Claims::RuleAudits::Configuration.system_record).to eq(
      Claims::RuleAudits::Configuration.default_system_record
    )
  end

  it "rejects oversized instructions without overwriting saved configuration" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!
    config.update!(rule_audit_system_record: "Preserved audit instructions")
    patch "/api/claims/admin/validationgenai_config",
          params: {
            rule_audit_system_record: "x" * 60_001
          },
          as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(config.reload.rule_audit_system_record).to eq(
      "Preserved audit instructions"
    )
  end
end
