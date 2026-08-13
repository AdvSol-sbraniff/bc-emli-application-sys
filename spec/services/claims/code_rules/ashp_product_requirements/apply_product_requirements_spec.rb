require "rails_helper"

RSpec.describe Claims::CodeRules::AshpProductRequirements::ApplyProductRequirements do
  let(:now) { Time.zone.parse("2026-08-13 10:00:00") }

  def configured_upgrade_type
    upgrade_type =
      Claims::InvoiceUpgradeType.find_or_create_by!(
        upgrade_type_key: "air_source_heat_pump_gas_propane"
      ) do |row|
        row.description = "Air source heat pump - convert from gas or propane"
        row.created_at = now
        row.updated_at = now
      end
    code_rule =
      Claims::CodeRule.find_or_create_by!(
        code_rule_key: "ashp_product_specs_meet_requirements"
      ) do |row|
        row.contractor_display_name = "Heat pump product specifications"
        row.description = "Test ASHP product specifications"
        row.enabled = true
        row.source_quote = "Test source quote"
        row.contractor_visibility = "fail_only"
        row.contractor_blocking_policy = "non_blocking"
        row.admin_workflow_policy = "warn_and_fail"
        row.created_at = now
        row.updated_at = now
      end
    code_rule.update_columns(enabled: true, updated_at: now)
    Claims::CodeRuleUpgradeType.find_or_create_by!(
      code_rule: code_rule,
      invoice_upgrade_type: upgrade_type
    ) { |row| row.created_at = now }

    upgrade_type
  end

  def create_ahri_product(capacity: 13_600, seer: 19.0, hspf: 10.3)
    source =
      Claims::AhriSource.create!(
        description: "Test BC Hydro heat-pump product list",
        source_url: "https://example.test/heat-pumps-#{SecureRandom.hex(4)}",
        created_at: now,
        updated_at: now
      )
    import_run =
      Claims::AhriImportRun.create!(
        ahri_source: source,
        status: "succeeded",
        started_at: now,
        completed_at: now,
        records_imported: 1,
        created_at: now,
        updated_at: now
      )

    Claims::AhriProduct.create!(
      import_run: import_run,
      ahri_reference_number:
        SecureRandom.random_number(900_000_000) + 100_000_000,
      heat_pump_type: "Central ducted heat pump (Tier 2)",
      make: "BRYANT",
      outdoor_model: "38MAQB18R--3",
      indoor_model_or_air_handler: "FMC4Z1800AL",
      rated_capacity_btu_at_minus_5c: capacity,
      seer: seer,
      hspf: hspf,
      created_at: now,
      updated_at: now
    )
  end

  def create_invoice_version(product:)
    session = Claims::Session.create!(created_at: now, updated_at: now)
    contractor =
      Contractor.create!(
        business_name: "Test Contractor #{SecureRandom.hex(4)}"
      )
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck",
        created_at: now,
        updated_at: now
      )

    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_key: "invoice-#{SecureRandom.hex(4)}.pdf",
      ahri_product_id: product.id,
      created_at: now,
      updated_at: now
    )
  end

  def add_genai_field(
    invoice_version:,
    upgrade_type:,
    field_key:,
    value_text:,
    evidence_text: value_text
  )
    Claims::InvoiceVersionLocatedField.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type.id,
      source_engine: "genai",
      field_key: field_key,
      value_type: "text",
      value_text: value_text,
      confidence: 100,
      evidence_text: evidence_text,
      created_at: now,
      updated_at: now
    )
  end

  def run_rule(invoice_version, upgrade_type)
    result =
      described_class.call(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id
      )
    raise result.inspect unless result[:ok]

    result
  end

  def product_spec_rulecheck(invoice_version)
    Claims::InvoiceVersionRulecheck.find_by!(
      invoice_version_id: invoice_version.id,
      rule_key: "ashp_product_specs_meet_requirements"
    )
  end

  def add_complete_efficiency_field(invoice_version, upgrade_type)
    add_genai_field(
      invoice_version: invoice_version,
      upgrade_type: upgrade_type,
      field_key: "hp_efficiency_and_capacity",
      value_text: "SEER 19.0; HSPF 10.3; capacity 13,600 BTU/h"
    )
  end

  it "passes when hp_make_model evidence identifies a variable-speed system" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version(product: create_ahri_product)
    add_complete_efficiency_field(invoice_version, upgrade_type)
    add_genai_field(
      invoice_version: invoice_version,
      upgrade_type: upgrade_type,
      field_key: "hp_make_model",
      value_text: "Bryant 38MAQB18R--3; FMC4Z1800AL",
      evidence_text: "Supply and commissioning of Bryant variable-speed system"
    )

    result = run_rule(invoice_version, upgrade_type)
    rulecheck = product_spec_rulecheck(invoice_version)

    expect(result[:ok]).to be(true)
    expect(rulecheck.rule_result).to eq("pass")
    expect(rulecheck.calculation).to include("variable_speed_evidence=present")
    expect(rulecheck.evidence_text).to include(
      "hp_make_model: Supply and commissioning of Bryant variable-speed system"
    )
  end

  it "continues to pass when variable-speed evidence is in hp_efficiency_and_capacity" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version(product: create_ahri_product)
    add_genai_field(
      invoice_version: invoice_version,
      upgrade_type: upgrade_type,
      field_key: "hp_efficiency_and_capacity",
      value_text:
        "Variable-speed compressor; SEER 19.0; HSPF 10.3; capacity 13,600 BTU/h"
    )

    run_rule(invoice_version, upgrade_type)

    expect(product_spec_rulecheck(invoice_version).rule_result).to eq("pass")
  end

  it "warns when no named evidence identifies the compressor speed" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version(product: create_ahri_product)
    add_complete_efficiency_field(invoice_version, upgrade_type)

    run_rule(invoice_version, upgrade_type)
    rulecheck = product_spec_rulecheck(invoice_version)

    expect(rulecheck.rule_result).to eq("warn")
    expect(rulecheck.calculation).to include(
      "variable_speed_evidence=(missing)"
    )
  end

  it "fails when hp_make_model explicitly identifies a fixed-speed system" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version(product: create_ahri_product)
    add_complete_efficiency_field(invoice_version, upgrade_type)
    add_genai_field(
      invoice_version: invoice_version,
      upgrade_type: upgrade_type,
      field_key: "hp_make_model",
      value_text: "Bryant fixed-speed system"
    )

    run_rule(invoice_version, upgrade_type)
    rulecheck = product_spec_rulecheck(invoice_version)

    expect(rulecheck.rule_result).to eq("fail")
    expect(rulecheck.calculation).to include(
      "variable_speed_evidence=contradicted"
    )
  end

  it "fails a numeric threshold even when variable-speed evidence passes" do
    upgrade_type = configured_upgrade_type
    invoice_version =
      create_invoice_version(product: create_ahri_product(capacity: 11_999))
    add_complete_efficiency_field(invoice_version, upgrade_type)
    add_genai_field(
      invoice_version: invoice_version,
      upgrade_type: upgrade_type,
      field_key: "hp_make_model",
      value_text: "Bryant variable-speed system"
    )

    run_rule(invoice_version, upgrade_type)
    rulecheck = product_spec_rulecheck(invoice_version)

    expect(rulecheck.rule_result).to eq("fail")
    expect(rulecheck.calculation).to include(
      "capacity=11999 BTU",
      "variable_speed_evidence=present"
    )
  end

  it "updates a rulecheck in place when a workflow issue references it" do
    upgrade_type = configured_upgrade_type
    invoice_version = create_invoice_version(product: create_ahri_product)
    add_complete_efficiency_field(invoice_version, upgrade_type)
    run_rule(invoice_version, upgrade_type)
    original_rulecheck = product_spec_rulecheck(invoice_version)
    issue =
      Claims::RevisionIssue.create!(
        invoice_id: invoice_version.invoice_id,
        issue_type: "rule",
        opened_from_invoice_version_rulecheck_id: original_rulecheck.id,
        opened_from_rule_key: original_rulecheck.rule_key,
        opened_from_rule_upgrade_type_id: upgrade_type.id,
        opened_from_source_snapshot: {
        },
        status: "pending_admin_review",
        created_at: now,
        updated_at: now
      )
    add_genai_field(
      invoice_version: invoice_version,
      upgrade_type: upgrade_type,
      field_key: "hp_make_model",
      value_text: "Bryant variable-speed system"
    )

    result = run_rule(invoice_version, upgrade_type)
    updated_rulecheck = product_spec_rulecheck(invoice_version)

    expect(result[:ok]).to be(true)
    expect(updated_rulecheck.id).to eq(original_rulecheck.id)
    expect(updated_rulecheck.rule_result).to eq("pass")
    expect(issue.reload.opened_from_invoice_version_rulecheck_id).to eq(
      original_rulecheck.id
    )
  end
end
