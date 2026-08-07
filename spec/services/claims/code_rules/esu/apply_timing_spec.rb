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

  def run_rule(invoice_version, upgrade_type)
    described_class.call(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type.id
    )
  end

  def timing_rulecheck(invoice_version)
    Claims::InvoiceVersionRulecheck.find_by!(
      invoice_version_id: invoice_version.id,
      rule_key: "esu_timing_within_six_months_of_heat_pump_installation"
    )
  end

  def configured_upgrade_type
    upgrade_type = invoice_upgrade_type("electrical_service_upgrade")
    enable_code_rule(
      "esu_timing_within_six_months_of_heat_pump_installation",
      upgrade_type
    )

    upgrade_type
  end

  it "passes when the invoice-date proxy is within six months of the heat pump installation date" do
    upgrade_type = configured_upgrade_type
    invoice_version =
      create_invoice_version(invoice_date: Date.new(2026, 4, 15))
    add_invoice_field(
      invoice_version,
      upgrade_type,
      "esu_heat_pump_installation_date_reference",
      "Heat pump installed 2026-01-01"
    )

    result = run_rule(invoice_version, upgrade_type)

    expect(result[:ok]).to be(true)
    expect(result[:rule_result]).to eq("pass")
    rulecheck = timing_rulecheck(invoice_version)
    expect(rulecheck.calculation).to include(
      "esu_service_upgrade_date=2026-04-15",
      "esu_service_upgrade_date_source=invoice_date_proxy",
      "heat_pump_installation_date=2026-01-01",
      "heat_pump_installation_date_source=located_field",
      "within_window=true"
    )
    expect(rulecheck.evidence_text).to include("invoice_date_proxy: 2026-04-15")
  end

  it "fails from the invoice-date proxy even when a supporting document contains a date within the window" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version(invoice_date: Date.new(2026, 8, 2))
    add_invoice_field(
      invoice_version,
      upgrade_type,
      "esu_heat_pump_installation_date_reference",
      "Heat pump installed 2026-01-01"
    )
    add_supporting_service_date(
      invoice_version,
      "Electrical service connected 2026-01-15"
    )

    result = run_rule(invoice_version, upgrade_type)

    expect(result[:ok]).to be(true)
    expect(result[:rule_result]).to eq("fail")
    rulecheck = timing_rulecheck(invoice_version)
    expect(rulecheck.calculation).to include(
      "esu_service_upgrade_date=2026-08-02",
      "esu_service_upgrade_date_source=invoice_date_proxy",
      "heat_pump_installation_date=2026-01-01",
      "allowed_window=2025-07-01..2026-07-01",
      "within_window=false"
    )
    expect(rulecheck.evidence_text).not_to include(
      "service_completion_or_invoice_date"
    )
  end

  it "warns only about the heat pump date when the invoice-date proxy is present" do
    upgrade_type = configured_upgrade_type
    invoice_version =
      create_invoice_version(invoice_date: Date.new(2026, 4, 15))

    result = run_rule(invoice_version, upgrade_type)

    expect(result[:ok]).to be(true)
    expect(result[:rule_result]).to eq("warn")
    rulecheck = timing_rulecheck(invoice_version)
    expect(rulecheck.calculation).to include(
      "esu_service_upgrade_date=2026-04-15",
      "esu_service_upgrade_date_source=invoice_date_proxy",
      "heat_pump_installation_date=(missing)"
    )
    reason = rulecheck.reason_and_likely_causes.split("\n\n").first
    expect(reason).to eq(
      "Code could not compare ESU timing because heat pump installation date is missing or not parseable."
    )
  end

  it "warns about the invoice-date proxy when the heat pump date is present" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version
    add_invoice_field(
      invoice_version,
      upgrade_type,
      "esu_heat_pump_installation_date_reference",
      "Heat pump installed 2026-01-01"
    )

    result = run_rule(invoice_version, upgrade_type)

    expect(result[:ok]).to be(true)
    expect(result[:rule_result]).to eq("warn")
    rulecheck = timing_rulecheck(invoice_version)
    expect(rulecheck.calculation).to include(
      "esu_service_upgrade_date=(missing)",
      "esu_service_upgrade_date_source=(missing)",
      "heat_pump_installation_date=2026-01-01"
    )
    expect(rulecheck.reason_and_likely_causes).to include(
      "invoice date used as the ESU installation-date proxy is missing or not parseable"
    )
  end

  [Date.new(2025, 7, 1), Date.new(2026, 7, 1)].each do |boundary_date|
    it "includes the #{boundary_date} six-month boundary" do
      upgrade_type = configured_upgrade_type
      invoice_version = create_invoice_version(invoice_date: boundary_date)
      add_invoice_field(
        invoice_version,
        upgrade_type,
        "esu_heat_pump_installation_date_reference",
        "Heat pump installed 2026-01-01"
      )

      result = run_rule(invoice_version, upgrade_type)

      expect(result[:rule_result]).to eq("pass")
      expect(timing_rulecheck(invoice_version).calculation).to include(
        "within_window=true"
      )
    end
  end
end
