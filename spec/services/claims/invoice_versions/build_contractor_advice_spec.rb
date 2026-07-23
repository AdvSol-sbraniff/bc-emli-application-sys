require "rails_helper"

RSpec.describe Claims::InvoiceVersions::BuildContractorAdvice do
  it "renders the source quote and contractor action from separate registry fields" do
    now = Time.zone.parse("2026-07-23 12:00:00")
    contractor = Contractor.create!(business_name: "Advice Builder Test")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "genai_complete",
        created_at: now,
        updated_at: now
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "advice-builder/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )
    upgrade_type =
      Claims::InvoiceUpgradeType.create!(
        upgrade_type_key: "advice_builder_#{SecureRandom.hex(5)}",
        description: "Advice builder test",
        created_at: now,
        updated_at: now
      )
    rule_key = "advice_builder_#{SecureRandom.hex(5)}"
    Claims::GenaiRule.create!(
      genai_rule_key: rule_key,
      contractor_display_name: "Required invoice information",
      prompt_text: "Check the required invoice information.",
      enabled: true,
      source_quote: "The invoice must contain the required information.",
      contractor_action: "Upload a corrected invoice.",
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "fail_only",
      created_at: now,
      updated_at: now
    )
    Claims::InvoiceVersionRulecheck.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type.id,
      source_engine: "genai",
      rule_key: rule_key,
      contractor_display_name: "Required invoice information",
      rule_result: "fail",
      confidence: 90,
      created_at: now,
      updated_at: now
    )

    advice = described_class.call(invoice_version_id: invoice_version.id)

    expect(advice).to include(
      "The invoice must contain the required information."
    )
    expect(advice).to include("**Action:** Upload a corrected invoice.")
  end
end
