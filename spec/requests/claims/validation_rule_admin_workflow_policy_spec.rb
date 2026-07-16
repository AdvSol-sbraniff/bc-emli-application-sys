require "rails_helper"

RSpec.describe "Claims validation-rule admin workflow policy", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(
      Api::Claims::ValidationRulesAdminController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
  end

  it "round-trips the policy through both Code and GenAI rule editors" do
    upgrade_type =
      Claims::InvoiceUpgradeType.create!(
        upgrade_type_key: "workflow_policy_#{SecureRandom.hex(5)}",
        description: "Workflow policy API test"
      )
    code_rule =
      Claims::CodeRule.create!(
        code_rule_key: "workflow_policy_code_#{SecureRandom.hex(5)}",
        contractor_display_name: "Code workflow API test",
        description: "Code workflow API test.",
        enabled: true,
        source_quote: "Test requirement.",
        contractor_visibility: "fail_only",
        contractor_blocking_policy: "non_blocking",
        admin_workflow_policy: "fail_only"
      )
    Claims::CodeRuleUpgradeType.create!(
      code_rule: code_rule,
      invoice_upgrade_type: upgrade_type
    )
    genai_rule =
      Claims::GenaiRule.create!(
        genai_rule_key: "workflow_policy_genai_#{SecureRandom.hex(5)}",
        contractor_display_name: "GenAI workflow API test",
        prompt_text: "GenAI workflow API test.",
        enabled: true,
        source_quote: "Test requirement.",
        contractor_visibility: "fail_only",
        contractor_blocking_policy: "non_blocking",
        admin_workflow_policy: "fail_only"
      )
    Claims::GenaiRuleUpgradeType.create!(
      genai_rule: genai_rule,
      invoice_upgrade_type: upgrade_type
    )

    patch_rule_policy(
      record_type: "code_rule",
      rule: code_rule,
      policy: "not_managed",
      upgrade_type: upgrade_type
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("detail", "admin_workflow_policy")).to eq(
      "not_managed"
    )

    patch_rule_policy(
      record_type: "genai_rule",
      rule: genai_rule,
      policy: "warn_and_fail",
      upgrade_type: upgrade_type
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("detail", "admin_workflow_policy")).to eq(
      "warn_and_fail"
    )

    expect(code_rule.reload.admin_workflow_policy).to eq("not_managed")
    expect(genai_rule.reload.admin_workflow_policy).to eq("warn_and_fail")
  end

  private

  def patch_rule_policy(record_type:, rule:, policy:, upgrade_type:)
    patch(
      "/api/claims/admin/validation_rules/#{record_type}/#{rule.id}",
      params: {
        admin_workflow_policy: policy,
        mappings: [{ invoice_upgrade_type_id: upgrade_type.id }]
      },
      as: :json
    )
  end
end
