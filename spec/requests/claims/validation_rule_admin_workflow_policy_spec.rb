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
        contractor_action: "Original code action.",
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
        contractor_action: "Original GenAI action.",
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
      policy: "all_results",
      contractor_action: "Updated code action.",
      upgrade_type: upgrade_type
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("detail", "admin_workflow_policy")).to eq(
      "all_results"
    )
    expect(json_response.dig("detail", "contractor_action")).to eq(
      "Updated code action."
    )

    patch_rule_policy(
      record_type: "genai_rule",
      rule: genai_rule,
      policy: "warn_and_fail",
      contractor_action: "Updated GenAI action.",
      upgrade_type: upgrade_type
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("detail", "admin_workflow_policy")).to eq(
      "warn_and_fail"
    )
    expect(json_response.dig("detail", "contractor_action")).to eq(
      "Updated GenAI action."
    )

    expect(code_rule.reload.admin_workflow_policy).to eq("all_results")
    expect(genai_rule.reload.admin_workflow_policy).to eq("warn_and_fail")
    expect(code_rule.contractor_action).to eq("Updated code action.")
    expect(genai_rule.contractor_action).to eq("Updated GenAI action.")
    expect(
      Claims::CodeRuleHistory
        .where(source_id: code_rule.id)
        .last
        .contractor_action
    ).to eq("Original code action.")
    expect(
      Claims::GenaiRuleHistory
        .where(source_id: genai_rule.id)
        .last
        .contractor_action
    ).to eq("Original GenAI action.")
  end

  private

  def patch_rule_policy(
    record_type:,
    rule:,
    policy:,
    contractor_action:,
    upgrade_type:
  )
    patch(
      "/api/claims/admin/validation_rules/#{record_type}/#{rule.id}",
      params: {
        admin_workflow_policy: policy,
        contractor_action: contractor_action,
        mappings: [{ invoice_upgrade_type_id: upgrade_type.id }]
      },
      as: :json
    )
  end
end
