require "rails_helper"

RSpec.describe Claims::Ingest::FixUpgradeTypeScopeGuard do
  let(:now) { Time.zone.parse("2026-08-12 10:00:00") }

  def upgrade_type(key, description)
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: key
    ) { |row| row.description = description }
  end

  def add_claimed_type(invoice_version, type)
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: type.id,
      confidence: 98
    )
  end

  def build_fix(upgrade_keys:)
    contractor = Contractor.create!(business_name: "Scope Guard Contractor")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_revision_inbox",
        created_at: now,
        updated_at: now
      )
    source =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "invoice/#{invoice.id}/v1.pdf",
        original_filename: "invoice-v1.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )
    run =
      Claims::IngestRun.create!(
        run_kind: "fix_upload",
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        status: "running",
        total_files: 1,
        completed_files: 0,
        failed_files: 0,
        created_at: now,
        updated_at: now
      )
    document =
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        storage_provider: "azure_blob",
        storage_key: "replacement/#{run.id}.pdf",
        original_filename: "Replacement invoice.pdf",
        content_type: "application/pdf",
        classifier_raw_json: {
          "detected_upgrade_types" =>
            upgrade_keys.map { |key| { "upgrade_type_key" => key } }
        },
        document_kind: "invoice",
        document_kind_confidence: 99,
        classification_confidence: 99,
        created_at: now,
        updated_at: now
      )

    [invoice, source, run, document]
  end

  it "rejects changed scope before creating a replacement version" do
    electrical =
      upgrade_type("electrical_service_upgrade", "Electrical service upgrade")
    heat_pump =
      upgrade_type(
        "air_source_heat_pump_gas_propane",
        "Air source heat pump - convert from natural gas or propane"
      )
    invoice, source, run, document =
      build_fix(
        upgrade_keys: [electrical.upgrade_type_key, heat_pump.upgrade_type_key]
      )
    add_claimed_type(source, electrical)

    result =
      described_class.call(ingest_run: run, replacement_document: document)

    expect(result.changed).to be(true)
    expect(result.payload[:added_upgrade_types]).to contain_exactly(
      a_hash_including(upgrade_type_key: heat_pump.upgrade_type_key)
    )
    expect(result.payload[:removed_upgrade_types]).to be_empty
    expect(run.reload).to have_attributes(
      status: "failed",
      failure_category: "package_needs_correction",
      failure_code: "package_replacement_upgrade_types_changed",
      pipeline_error_code: "fix_upgrade_types_changed",
      resolved_invoice_version_id: nil
    )
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(
      Claims::InvoiceVersion.where(invoice_id: invoice.id).pluck(:id)
    ).to eq([source.id])
    expect(described_class.preview(ingest_run: run).payload).to eq(
      result.payload
    )
  end

  it "allows unchanged scope without changing the run or invoice" do
    electrical =
      upgrade_type("electrical_service_upgrade", "Electrical service upgrade")
    invoice, source, run, document =
      build_fix(upgrade_keys: [electrical.upgrade_type_key])
    add_claimed_type(source, electrical)

    result =
      described_class.call(ingest_run: run, replacement_document: document)

    expect(result.changed).to be(false)
    expect(result.payload).to be_nil
    expect(run.reload.status).to eq("running")
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(
      Claims::InvoiceVersion.where(invoice_id: invoice.id).pluck(:id)
    ).to eq([source.id])
  end
end
