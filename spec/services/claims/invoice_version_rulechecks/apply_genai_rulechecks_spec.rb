require "rails_helper"

RSpec.describe Claims::InvoiceVersionRulechecks::ApplyGenaiRulechecks do
  let(:now) { Time.zone.parse("2026-08-11 10:00:00") }
  let(:contractor) do
    Contractor.create!(business_name: "Compliance Score Test")
  end
  let(:session) { Claims::Session.create!(created_at: now, updated_at: now) }
  let(:invoice) do
    Claims::Invoice.create!(
      session_id: session.id,
      contractor_id: contractor.id,
      status: "contractor_precheck",
      status_updated_at: now,
      created_at: now,
      updated_at: now
    )
  end
  let(:invoice_version) do
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_provider: "azure_blob",
      storage_key: "test/compliance-score.pdf",
      original_filename: "compliance-score.pdf",
      content_type: "application/pdf",
      created_at: now,
      updated_at: now
    )
  end
  let(:upgrade_type) do
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: "common"
    ) do |row|
      row.description = "Common"
      row.created_at = now
      row.updated_at = now
    end
  end

  it "stores the model compliance score for each GenAI rulecheck" do
    result =
      described_class.call(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        genai_payload: {
          "rulechecks" => [
            {
              "rule_key" => "borderline_rule",
              "rule_result" => "warn",
              "compliance_score" => 49,
              "confidence" => 99,
              "reason_and_likely_causes" => "Borderline evidence."
            },
            {
              "rule_key" => "stable_rule",
              "rule_result" => "pass",
              "compliance_score" => 88,
              "reason_and_likely_causes" => "Clear evidence."
            }
          ]
        }
      )

    expect(result).to eq(ok: true, replaced: 2)
    expect(
      Claims::InvoiceVersionRulecheck
        .where(invoice_version_id: invoice_version.id)
        .order(:rule_key)
        .pluck(:rule_key, :rule_result, :compliance_score)
    ).to eq([["borderline_rule", "warn", 49], ["stable_rule", "pass", 88]])
  end

  it "rejects a GenAI rulecheck that omits compliance_score" do
    result =
      described_class.call(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        genai_payload: {
          "rulechecks" => [
            { "rule_key" => "missing_score", "rule_result" => "warn" }
          ]
        }
      )

    expect(result).to include(ok: false, error_class: "ArgumentError")
    expect(result.fetch(:error)).to include("compliance_score is required")
    expect(
      Claims::InvoiceVersionRulecheck.where(
        invoice_version_id: invoice_version.id
      )
    ).to be_empty
  end

  it "rejects a compliance_score outside the 0 to 100 scale" do
    result =
      described_class.call(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        genai_payload: {
          "rulechecks" => [
            {
              "rule_key" => "invalid_score",
              "rule_result" => "pass",
              "compliance_score" => 101
            }
          ]
        }
      )

    expect(result).to include(ok: false, error_class: "ArgumentError")
    expect(result.fetch(:error)).to include("between 0 and 100")
  end
end
