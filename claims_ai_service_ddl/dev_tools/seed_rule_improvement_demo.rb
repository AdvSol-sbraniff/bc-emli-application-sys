# frozen_string_literal: true

# Local-only, rerunnable evidence for the Rule Improvement Report.
# Run from the app container with:
#   bin/rails runner claims_ai_service_ddl/dev_tools/seed_rule_improvement_demo.rb

prefix = "demo_rule_improvement_"
rule_ids =
  Claims::GenaiRule.where("genai_rule_key LIKE ?", "#{prefix}%").pluck(:id)
invoice_ids =
  Claims::InvoiceVersionRulecheck
    .where("rule_key LIKE ?", "#{prefix}%")
    .joins(
      "JOIN claims.invoice_versions iv ON iv.id = claims.invoice_version_rulechecks.invoice_version_id"
    )
    .pluck("iv.invoice_id")
    .uniq

invoice_ids.each do |invoice_id|
  next unless Claims::Invoice.exists?(invoice_id)

  Claims::Invoices::DestroyPackage.call(invoice_id: invoice_id)
end
Claims::GenaiRuleUpgradeType.where(genai_rule_id: rule_ids).delete_all
Claims::GenaiRuleHistory.where(source_id: rule_ids).delete_all
Claims::GenaiRule.where(id: rule_ids).delete_all

contractor = Contractor.order(:business_name).first
raise "Seed at least one contractor before running this demo" unless contractor

upgrade_type = Claims::InvoiceUpgradeType.order(:description).first
raise "Run the canonical claims reference-data seeds first" unless upgrade_type

scenarios = [
  {
    key: "#{prefix}applicability",
    name: "Demo — equipment eligibility evidence",
    action: "Upload proof that the installed equipment is eligible.",
    result: "fail",
    count: 8,
    issues: 5,
    disposition: "closed_no_contractor_action_required",
    complaint_indexes: []
  },
  {
    key: "#{prefix}missed_issue",
    name: "Demo — invoice address matches the application",
    action: "Correct the invoice address or explain the discrepancy.",
    result: "pass",
    count: 7,
    issues: 4,
    disposition: "closed_via_corrected_documentation",
    complaint_indexes: []
  },
  {
    key: "#{prefix}reason_quality",
    name: "Demo — supporting document is complete",
    action: "Upload the missing supporting evidence.",
    result: "warn",
    count: 10,
    issues: 1,
    disposition: "closed_via_attestation",
    complaint_indexes: [0, 2, 5, 8]
  },
  {
    key: "#{prefix}contractor_guidance",
    name: "Demo — costs are itemized clearly",
    action: "Provide an itemized invoice showing labour and materials.",
    result: "fail",
    count: 6,
    issues: 5,
    disposition: "closed_via_corrected_documentation",
    complaint_indexes: [],
    sent_rounds: 2
  }
]

scenarios.each_with_index do |scenario, scenario_index|
  created_at = 7.months.ago + scenario_index.weeks
  rule =
    Claims::GenaiRule.create!(
      genai_rule_key: scenario[:key],
      contractor_display_name: scenario[:name],
      prompt_text:
        "Check the invoice and named evidence for this local reporting demonstration.",
      enabled: true,
      source_quote: "Local demonstration requirement; not production policy.",
      contractor_action: scenario[:action],
      contractor_visibility: "warn_and_fail",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "warn_and_fail",
      created_at: created_at,
      updated_at: created_at
    )
  Claims::GenaiRuleUpgradeType.create!(
    genai_rule: rule,
    invoice_upgrade_type: upgrade_type
  )

  original_action = rule.contractor_action
  rule.update!(
    contractor_action: "#{original_action} Include the relevant page."
  )
  rule.update!(
    contractor_action:
      "#{original_action} Include the relevant page and label the evidence clearly."
  )

  scenario[:count].times do |index|
    observed_at = (scenario[:count] - index).months.ago + scenario_index.days
    session =
      Claims::Session.create!(created_at: observed_at, updated_at: observed_at)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "admin_review_inbox",
        status_updated_at: observed_at,
        created_at: observed_at,
        updated_at: observed_at
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "local-rule-improvement-demo/#{invoice.id}.pdf",
        original_filename:
          "Rule improvement demo #{scenario_index + 1}-#{index + 1}.pdf",
        content_type: "application/pdf",
        created_at: observed_at,
        updated_at: observed_at
      )
    complaint = scenario[:complaint_indexes].include?(index)
    rulecheck =
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version_id: version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "genai",
        rule_key: rule.genai_rule_key,
        contractor_display_name: rule.contractor_display_name,
        rule_result: scenario[:result],
        reason_and_likely_causes:
          "The demo evidence was evaluated, but the result needs an administrator to verify the operational context.",
        reason_complaint_code: complaint ? "required_action_unclear" : nil,
        reason_complaint_text:
          (
            if complaint
              "The reason identifies the problem but does not say which document or page would resolve it."
            else
              nil
            end
          ),
        created_at: observed_at,
        updated_at: observed_at
      )

    next unless index < scenario[:issues]

    issue =
      Claims::RevisionIssue.create!(
        invoice_id: invoice.id,
        issue_type: "rule",
        opened_from_invoice_version_rulecheck_id: rulecheck.id,
        opened_from_rule_key: rule.genai_rule_key,
        opened_from_rule_upgrade_type_id: upgrade_type.id,
        opened_from_source_snapshot: {
          friendly_label: rule.contractor_display_name,
          contractor_action: rule.contractor_action
        },
        status: scenario[:disposition],
        disposition_comment:
          (
            if scenario[:disposition] == "closed_no_contractor_action_required"
              "Admin review found the supplied evidence was already sufficient."
            else
              "The issue was resolved through the recorded contractor response."
            end
          ),
        created_at: observed_at + 1.day,
        updated_at: observed_at + 3.days
      )

    scenario
      .fetch(:sent_rounds, 0)
      .times do |round_index|
        sent_at = observed_at + (round_index * 2 + 1).days
        round =
          Claims::RevisionRound.create!(
            invoice_id: invoice.id,
            invoice_version_id: version.id,
            round_number: round_index + 1,
            admin_sent_at: sent_at,
            contractor_response_submitted_at: sent_at + 1.day,
            created_at: sent_at,
            updated_at: sent_at + 1.day
          )
        Claims::RevisionIssueComment.create!(
          revision_issue_id: issue.id,
          revision_round_id: round.id,
          author_type: "admin",
          admin_recommended_remedy: "correct_and_reupload_invoice",
          comment_text: "Please provide clearer itemization for this cost.",
          created_at: sent_at,
          updated_at: sent_at
        )
        Claims::RevisionIssueComment.create!(
          revision_issue_id: issue.id,
          revision_round_id: round.id,
          author_type: "contractor",
          contractor_response_method: "corrected_invoice_uploaded",
          comment_text: "An updated invoice has been supplied.",
          created_at: sent_at + 1.day,
          updated_at: sent_at + 1.day
        )
      end
  end
end

puts "Created #{scenarios.length} demo rules and #{scenarios.sum { |scenario| scenario[:count] }} demo checks."
