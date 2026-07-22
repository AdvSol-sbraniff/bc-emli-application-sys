require "rails_helper"

RSpec.describe "Claims rule admin workflow policy" do
  it "supports all result levels for both rule engines" do
    expected = %w[not_managed fail_only warn_and_fail all_results]

    expect(Claims::CodeRule::ADMIN_WORKFLOW_POLICIES).to eq(expected)
    expect(Claims::GenaiRule::ADMIN_WORKFLOW_POLICIES).to eq(expected)
  end

  def build_code_rule(policy: "fail_only")
    Claims::CodeRule.new(
      code_rule_key: "workflow_policy_code_#{SecureRandom.hex(5)}",
      contractor_display_name: "Code workflow policy test",
      description: "Tests the per-rule admin workflow policy.",
      enabled: true,
      source_quote: "Test requirement.",
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: policy
    )
  end

  def build_genai_rule(policy: "fail_only")
    Claims::GenaiRule.new(
      genai_rule_key: "workflow_policy_genai_#{SecureRandom.hex(5)}",
      contractor_display_name: "GenAI workflow policy test",
      prompt_text: "Test the per-rule admin workflow policy.",
      enabled: true,
      source_quote: "Test requirement.",
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: policy
    )
  end

  [Claims::CodeRule, Claims::GenaiRule].each do |model|
    it "allows every supported policy for #{model.name}" do
      builder = model == Claims::CodeRule ? :build_code_rule : :build_genai_rule

      model::ADMIN_WORKFLOW_POLICIES.each do |policy|
        expect(send(builder, policy: policy)).to be_valid
      end
    end

    it "rejects an unsupported policy for #{model.name}" do
      builder = model == Claims::CodeRule ? :build_code_rule : :build_genai_rule
      rule = send(builder, policy: "sometimes")

      expect(rule).not_to be_valid
      expect(rule.errors[:admin_workflow_policy]).to be_present
    end
  end

  it "preserves the previous Code rule policy in audit history" do
    rule = build_code_rule(policy: "warn_and_fail")
    rule.save!

    expect { rule.update!(admin_workflow_policy: "not_managed") }.to change(
      Claims::CodeRuleHistory,
      :count
    ).by(1)
    expect(
      Claims::CodeRuleHistory
        .order(:history_created_at)
        .last
        .admin_workflow_policy
    ).to eq("warn_and_fail")
  end

  it "preserves the previous GenAI rule policy in audit history" do
    rule = build_genai_rule(policy: "warn_and_fail")
    rule.save!

    expect { rule.update!(admin_workflow_policy: "not_managed") }.to change(
      Claims::GenaiRuleHistory,
      :count
    ).by(1)
    expect(
      Claims::GenaiRuleHistory
        .order(:history_created_at)
        .last
        .admin_workflow_policy
    ).to eq("warn_and_fail")
  end
end
