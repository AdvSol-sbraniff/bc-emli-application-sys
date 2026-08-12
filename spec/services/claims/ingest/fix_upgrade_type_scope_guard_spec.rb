require "rails_helper"

RSpec.describe Claims::Ingest::FixUpgradeTypeScopeGuard do
  def upgrade_type(key, description)
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: key
    ) { |row| row.description = description }
  end

  def add_claimed_type(invoice_version, upgrade_type)
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: upgrade_type.id,
      source_engine: "classifier",
      call_status: "classified",
      confidence: 98
    )
  end

  def invoice_version(invoice, versionno)
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: versionno,
      storage_provider: "azure_blob",
      storage_key: "invoice/#{invoice.id}/v#{versionno}.pdf",
      original_filename: "invoice-v#{versionno}.pdf",
      content_type: "application/pdf"
    )
  end

  it "rejects and removes a staged replacement when claimed upgrade types change" do
    contractor = Contractor.create!(business_name: "Scope Guard Contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "ocr_in_progress"
      )
    source = invoice_version(invoice, 1)
    replacement = invoice_version(invoice, 2)
    electrical =
      upgrade_type("electrical_service_upgrade", "Electrical service upgrade")
    heat_pump =
      upgrade_type(
        "air_source_heat_pump_gas_propane",
        "Air source heat pump - convert from natural gas or propane"
      )
    add_claimed_type(source, electrical)
    add_claimed_type(replacement, electrical)
    add_claimed_type(replacement, heat_pump)

    run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        resolved_invoice_version_id: replacement.id,
        status: "running",
        messages: [
          {
            code: "fix_upload_context",
            source_invoice_version_id: source.id,
            prior_invoice_status: "contractor_revision_inbox"
          }
        ],
        total_files: 1,
        completed_files: 0,
        failed_files: 0
      )

    result =
      described_class.call(
        ingest_run: run,
        replacement_invoice_version_id: replacement.id
      )

    expect(result.changed).to be(true)
    expect(Claims::InvoiceVersion.exists?(replacement.id)).to be(false)
    expect(Claims::InvoiceVersion.exists?(source.id)).to be(true)
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(run.reload).to have_attributes(
      status: "failed",
      failure_status: "package_needs_correction",
      failure_status_subtype: "package_replacement_upgrade_types_changed",
      pipeline_error_code: "fix_upgrade_types_changed",
      resolved_invoice_version_id: nil
    )
    scope_message =
      Array(run.messages).find do |message|
        message["code"] == "fix_upgrade_types_changed"
      end
    expect(scope_message["added_upgrade_types"]).to contain_exactly(
      a_hash_including("upgrade_type_key" => "air_source_heat_pump_gas_propane")
    )
    expect(scope_message["removed_upgrade_types"]).to be_empty
  end

  it "allows a staged replacement when the claimed upgrade types are unchanged" do
    contractor = Contractor.create!(business_name: "Unchanged Scope Contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "ocr_in_progress"
      )
    source = invoice_version(invoice, 1)
    replacement = invoice_version(invoice, 2)
    electrical =
      upgrade_type("electrical_service_upgrade", "Electrical service upgrade")
    add_claimed_type(source, electrical)
    add_claimed_type(replacement, electrical)
    run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        resolved_invoice_version_id: replacement.id,
        status: "running",
        messages: [
          {
            code: "fix_upload_context",
            source_invoice_version_id: source.id,
            prior_invoice_status: "genai_complete"
          }
        ],
        total_files: 1,
        completed_files: 0,
        failed_files: 0
      )

    result =
      described_class.call(
        ingest_run: run,
        replacement_invoice_version_id: replacement.id
      )

    expect(result.changed).to be(false)
    expect(Claims::InvoiceVersion.exists?(replacement.id)).to be(true)
    expect(run.reload.status).to eq("running")
  end
end
