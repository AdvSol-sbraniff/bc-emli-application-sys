require "rails_helper"

RSpec.describe "Claims validation-rule admin logging", type: :request do
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

    @info_logs = []
    @warn_logs = []
    allow(Rails.logger).to receive(:info) { |message| @info_logs << message }
    allow(Rails.logger).to receive(:warn) { |message| @warn_logs << message }
  end

  it "logs a safe structured start and successful commit" do
    upgrade_type, rule = create_genai_rule
    sensitive_prompt = "do-not-log-prompt-#{SecureRandom.hex(6)}"

    patch_rule(
      rule,
      upgrade_type,
      contractor_visibility: "warn_and_fail",
      prompt_text: sensitive_prompt
    )

    expect(response).to have_http_status(:ok)
    events = parsed_events(@info_logs)
    started = events.find { |event| event.fetch("outcome") == "started" }
    succeeded = events.find { |event| event.fetch("outcome") == "succeeded" }

    expect(started).to include(
      "event" => "claims.validation_rule_admin.update",
      "record_type" => "genai_rule",
      "record_id" => rule.id,
      "requested_contractor_visibility" => "warn_and_fail"
    )
    expect(started.fetch("changed_fields")).to include(
      "contractor_visibility",
      "prompt_text"
    )
    expect(succeeded).to include(
      "http_status" => 200,
      "committed" => true,
      "previous_contractor_visibility" => "fail_only",
      "saved_contractor_visibility" => "warn_and_fail"
    )
    expect(succeeded.fetch("duration_ms")).to be_a(Numeric)
    expect((@info_logs + @warn_logs).join).not_to include(sensitive_prompt)
  end

  it "logs validation metadata without logging an invalid submitted value" do
    upgrade_type, rule = create_genai_rule
    invalid_value = "do-not-log-invalid-value-#{SecureRandom.hex(6)}"

    patch_rule(
      rule,
      upgrade_type,
      contractor_visibility: invalid_value,
      prompt_text: rule.prompt_text
    )

    expect(response).to have_http_status(:unprocessable_entity)
    failed =
      parsed_events(@warn_logs).find do |event|
        event.fetch("outcome") == "validation_failed"
      end

    expect(failed).to include(
      "http_status" => 422,
      "committed" => false,
      "requested_contractor_visibility" => "invalid",
      "previous_contractor_visibility" => "fail_only",
      "error_class" => "ActiveRecord::RecordInvalid"
    )
    expect(failed.fetch("validation_errors")).to include(
      "field" => "contractor_visibility",
      "type" => "inclusion"
    )
    expect((@info_logs + @warn_logs).join).not_to include(invalid_value)
  end

  private

  def create_genai_rule
    upgrade_type =
      Claims::InvoiceUpgradeType.create!(
        upgrade_type_key: "logging_#{SecureRandom.hex(5)}",
        description: "Logging API test"
      )
    rule =
      Claims::GenaiRule.create!(
        genai_rule_key: "logging_genai_#{SecureRandom.hex(5)}",
        contractor_display_name: "Logging API test",
        prompt_text: "Logging API test prompt.",
        enabled: true,
        source_quote: "Logging API test requirement.",
        contractor_action: "Logging API test action.",
        contractor_visibility: "fail_only",
        contractor_blocking_policy: "non_blocking",
        admin_workflow_policy: "fail_only"
      )
    Claims::GenaiRuleUpgradeType.create!(
      genai_rule: rule,
      invoice_upgrade_type: upgrade_type
    )
    [upgrade_type, rule]
  end

  def patch_rule(rule, upgrade_type, contractor_visibility:, prompt_text:)
    patch(
      "/api/claims/admin/validation_rules/genai_rule/#{rule.id}",
      params: {
        prompt_text: prompt_text,
        contractor_visibility: contractor_visibility,
        mappings: [{ invoice_upgrade_type_id: upgrade_type.id }]
      },
      as: :json
    )
  end

  def parsed_events(messages)
    messages.filter_map do |message|
      next unless message.is_a?(String)

      parsed = JSON.parse(message)
      parsed if parsed["event"] == "claims.validation_rule_admin.update"
    rescue JSON::ParserError
      nil
    end
  end
end
