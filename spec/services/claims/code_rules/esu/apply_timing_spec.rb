require "rails_helper"

RSpec.describe Claims::CodeRules::Esu::ApplyTiming do
  let(:now) { Time.zone.parse("2026-07-10 10:00:00") }

  def invoice_upgrade_type(key)
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: key
    ) do |row|
      row.description = key.titleize
      row.created_at = now
      row.updated_at = now
    end
  end

  def enable_code_rule(rule_key, upgrade_type)
    code_rule =
      Claims::CodeRule.find_or_create_by!(code_rule_key: rule_key) do |row|
        row.description = "test"
        row.enabled = true
        row.created_at = now
        row.updated_at = now
      end
    code_rule.update_columns(enabled: true, updated_at: now)
    Claims::CodeRuleUpgradeType.find_or_create_by!(
      code_rule: code_rule,
      invoice_upgrade_type: upgrade_type
    ) { |row| row.created_at = now }
  end

  def create_invoice_version(invoice_date: nil)
    session = Claims::Session.create!(created_at: now, updated_at: now)
    contractor = Contractor.create!(business_name: "Test Contractor")
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "genai_in_progress",
        created_at: now,
        updated_at: now
      )

    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_key: "invoice-#{SecureRandom.hex(4)}.pdf",
      di_ocr_invoice_date: invoice_date,
      created_at: now,
      updated_at: now
    )
  end

  def add_invoice_field(invoice_version, upgrade_type, field_key, value)
    Claims::InvoiceVersionLocatedField.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type.id,
      source_engine: "genai",
      field_key: field_key,
      value_type: "text",
      value_text: value,
      confidence: 100,
      evidence_text: value,
      created_at: now,
      updated_at: now
    )
  end

  def add_supporting_service_date(invoice_version, value)
    document_type =
      Claims::SupportingDocumentType.find_or_create_by!(
        type_key: "electrical_utility_upgrade_document"
      ) do |row|
        row.description = "Electrical utility upgrade document"
        row.enabled = true
        row.created_at = now
        row.updated_at = now
      end
    document =
      Claims::SupportingDocument.create!(
        invoice_version_id: invoice_version.id,
        supporting_document_type_id: document_type.id,
        storage_key: "utility-#{SecureRandom.hex(4)}.pdf",
        classification_status: "classified",
        supporting_document_routing_quality: "usable",
        created_at: now,
        updated_at: now
      )

    Claims::SupportingDocumentLocatedField.create!(
      supporting_document_id: document.id,
      source_engine: "genai",
      field_key: "service_completion_or_invoice_date",
      value_type: "text",
      value_text: value,
      confidence: 100,
      evidence_text: value,
      created_at: now,
      updated_at: now
    )
  end

  it "fails when the utility service date is outside six months of the heat pump installation date" do
    upgrade_type = invoice_upgrade_type("electrical_service_upgrade")
    enable_code_rule(
      "esu_timing_within_six_months_of_heat_pump_installation",
      upgrade_type
    )
    invoice_version = create_invoice_version
    add_invoice_field(
      invoice_version,
      upgrade_type,
      "esu_heat_pump_installation_date_reference",
      "Heat pump installed 2026-01-01"
    )
    add_supporting_service_date(
      invoice_version,
      "Electrical service connected 2026-08-02"
    )

    result =
      described_class.call(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id
      )

    expect(result[:ok]).to be(true)
    expect(result[:rule_result]).to eq("fail")
    rulecheck =
      Claims::InvoiceVersionRulecheck.find_by!(
        invoice_version_id: invoice_version.id,
        rule_key: "esu_timing_within_six_months_of_heat_pump_installation"
      )
    expect(rulecheck.calculation).to include(
      "esu_service_upgrade_date=2026-08-02",
      "heat_pump_installation_date=2026-01-01",
      "allowed_window=2025-07-01..2026-07-01",
      "within_window=false"
    )
  end

  it "passes using invoice date as a shared timing proxy when same-invoice heat pump association is visible" do
    upgrade_type = invoice_upgrade_type("electrical_service_upgrade")
    enable_code_rule(
      "esu_timing_within_six_months_of_heat_pump_installation",
      upgrade_type
    )
    invoice_version =
      create_invoice_version(invoice_date: Date.new(2026, 4, 15))
    add_invoice_field(
      invoice_version,
      upgrade_type,
      "esu_associated_heat_pump_or_hpwh_reference",
      "Electrical service upgrade completed on same invoice as heat pump installation"
    )

    result =
      described_class.call(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id
      )

    expect(result[:ok]).to be(true)
    expect(result[:rule_result]).to eq("pass")
    rulecheck =
      Claims::InvoiceVersionRulecheck.find_by!(
        invoice_version_id: invoice_version.id,
        rule_key: "esu_timing_within_six_months_of_heat_pump_installation"
      )
    expect(rulecheck.calculation).to include(
      "same_invoice_proxy=true",
      "invoice_date=2026-04-15",
      "esu_associated_heat_pump_or_hpwh_reference=present"
    )
  end
end
