require "rails_helper"

RSpec.describe "fix-package candidate lifecycle" do
  let(:now) { Time.zone.parse("2026-08-11 14:00:00") }

  def upgrade_type(key, description)
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: key
    ) do |row|
      row.description = description
      row.created_at = now
      row.updated_at = now
    end
  end

  def add_upgrade!(invoice_version, key)
    type = upgrade_type(key, key.humanize)
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: invoice_version.id,
      invoice_upgrade_type_id: type.id,
      confidence: 99,
      created_at: now,
      updated_at: now
    )
  end

  def build_claim
    contractor = Contractor.create!(business_name: "Candidate Test Contractor")
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
        storage_key: "source/original.pdf",
        original_filename: "Original invoice.pdf",
        content_type: "application/pdf",
        byte_size: 111,
        di_raw_json: {
          "invoice" => "source OCR"
        },
        created_at: now,
        updated_at: now
      )
    add_upgrade!(source, "windows_doors")
    [contractor, session, invoice, source]
  end

  def build_fix_run(contractor:, session:, invoice:, source:)
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
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      step_type: "stage_package",
      status: "succeeded",
      created_at: now,
      updated_at: now
    )
    run
  end

  def stage_document(
    run:,
    contractor:,
    session:,
    invoice:,
    filename:,
    kind:,
    upgrade_keys: [],
    reused: false,
    storage_key: nil,
    supporting_document_type_id: nil
  )
    payload = {
      "document_kind" => kind,
      "detected_upgrade_types" =>
        upgrade_keys.map do |key|
          {
            "upgrade_type_key" => key,
            "confidence" => 99,
            "evidence_text" => "Test evidence for #{key}."
          }
        end
    }
    document =
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        resolved_invoice_version_id: nil,
        storage_provider: "azure_blob",
        storage_key: storage_key || "staged/#{SecureRandom.uuid}/#{filename}",
        original_filename: filename,
        content_type: "application/pdf",
        byte_size: 222,
        sha256: reused ? nil : SecureRandom.hex(32),
        di_read_raw_json: {
          "read" => filename
        },
        classifier_raw_json: payload,
        document_kind: kind,
        document_kind_confidence: 99,
        document_kind_reason:
          (
            if reused
              "Cloned from prior invoice version."
            else
              "Classified candidate file."
            end
          ),
        supporting_document_type_id: supporting_document_type_id,
        classification_confidence: 99,
        classification_reason: "Test classification.",
        classified_at: now,
        created_at: now,
        updated_at: now
      )
    unless reused
      %w[read_document classify_document].each do |step_type|
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          ingest_document_id: document.id,
          step_type: step_type,
          status: "succeeded",
          created_at: now,
          updated_at: now
        )
      end
    end
    document
  end

  before do
    allow(Claims::RunOcrJob).to receive(:perform_async)
    allow(Claims::RunGenaiJob).to receive(:perform_async)
    allow(Claims::RunSupportingDocumentTypeExtractionJob).to receive(
      :perform_async
    )
  end

  it "fails a supporting-document-only candidate without creating a version or changing the invoice" do
    contractor, session, invoice, source = build_claim
    run =
      build_fix_run(
        contractor: contractor,
        session: session,
        invoice: invoice,
        source: source
      )
    stage_document(
      run: run,
      contractor: contractor,
      session: session,
      invoice: invoice,
      filename: "Handover record.pdf",
      kind: "supporting_document"
    )

    Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "failed",
      failure_code: "package_no_invoice_pdf",
      resolved_invoice_version_id: nil
    )
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(
      Claims::InvoiceVersion.where(invoice_id: invoice.id).pluck(:id)
    ).to eq([source.id])
  end

  it "returns the contractor-facing no-invoice failure immediately when preflight finishes in the request" do
    contractor, _session, invoice, source = build_claim
    support_type =
      Claims::SupportingDocumentType.create!(
        type_key: "candidate_immediate_failure_support",
        description: "Candidate immediate failure support",
        created_at: now,
        updated_at: now
      )
    support =
      Claims::SupportingDocument.create!(
        invoice_version_id: source.id,
        supporting_document_type_id: support_type.id,
        storage_provider: "azure_blob",
        storage_key: "source/immediate-failure-support.pdf",
        original_filename: "Retained evidence.pdf",
        content_type: "application/pdf",
        classification_confidence: 99,
        created_at: now,
        updated_at: now
      )

    result =
      Claims::Ingest::UploadFixPackage.call(
        invoice_id: invoice.id,
        clone_supporting_document_ids: [support.id],
        clone_all_current_supporting_documents: false,
        files: []
      )

    expect(result).to have_attributes(
      ok: false,
      status: "failed",
      failure_category: "package_needs_correction",
      failure_code: "package_no_invoice_pdf",
      retryable: false
    )
    expect(result.error).to include("No invoice PDF was found")
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(Claims::InvoiceVersion.where(invoice_id: invoice.id).count).to eq(1)
  end

  it "fails two candidate invoices without creating a version" do
    contractor, session, invoice, source = build_claim
    run =
      build_fix_run(
        contractor: contractor,
        session: session,
        invoice: invoice,
        source: source
      )
    2.times do |index|
      stage_document(
        run: run,
        contractor: contractor,
        session: session,
        invoice: invoice,
        filename: "Replacement #{index + 1}.pdf",
        kind: "invoice",
        upgrade_keys: ["windows_doors"]
      )
    end
    run.update!(total_files: 2)

    Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "failed",
      failure_code: "package_multiple_invoice_pdfs",
      resolved_invoice_version_id: nil
    )
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(Claims::InvoiceVersion.where(invoice_id: invoice.id).count).to eq(1)
  end

  it "rejects a changed upgrade scope before creating a version" do
    upgrade_type("electrical_service_upgrade", "Electrical service upgrade")
    contractor, session, invoice, source = build_claim
    run =
      build_fix_run(
        contractor: contractor,
        session: session,
        invoice: invoice,
        source: source
      )
    stage_document(
      run: run,
      contractor: contractor,
      session: session,
      invoice: invoice,
      filename: "Different upgrade invoice.pdf",
      kind: "invoice",
      upgrade_keys: ["electrical_service_upgrade"]
    )

    Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "failed",
      failure_code: "package_replacement_upgrade_types_changed",
      resolved_invoice_version_id: nil
    )
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(Claims::InvoiceVersion.where(invoice_id: invoice.id).count).to eq(1)
  end

  it "promotes one valid replacement atomically after preflight" do
    contractor, session, invoice, source = build_claim
    run =
      build_fix_run(
        contractor: contractor,
        session: session,
        invoice: invoice,
        source: source
      )
    replacement =
      stage_document(
        run: run,
        contractor: contractor,
        session: session,
        invoice: invoice,
        filename: "Corrected invoice.pdf",
        kind: "invoice",
        upgrade_keys: ["windows_doors"]
      )

    Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: run.id)

    target = Claims::InvoiceVersion.find(run.reload.resolved_invoice_version_id)
    expect(target).to have_attributes(
      invoice_versionno: 2,
      storage_key: replacement.storage_key,
      original_filename: "Corrected invoice.pdf"
    )
    expect(target.storage_key).not_to start_with("PENDING/")
    expect(replacement.reload.resolved_invoice_version_id).to eq(target.id)
    expect(Claims::InvoiceVersion.where(invoice_id: invoice.id).count).to eq(2)
    expect(Claims::RunOcrJob).to have_received(:perform_async).with(
      target.id,
      run.id
    )
  end

  it "clones retained evidence only when the candidate is promoted" do
    contractor, session, invoice, source = build_claim
    support_type =
      Claims::SupportingDocumentType.create!(
        type_key: "candidate_test_support",
        description: "Candidate test support",
        created_at: now,
        updated_at: now
      )
    source_support =
      Claims::SupportingDocument.create!(
        invoice_version_id: source.id,
        supporting_document_type_id: support_type.id,
        storage_provider: "azure_blob",
        storage_key: "source/retained-support.pdf",
        original_filename: "Retained support.pdf",
        content_type: "application/pdf",
        classification_confidence: 99,
        created_at: now,
        updated_at: now
      )
    run =
      build_fix_run(
        contractor: contractor,
        session: session,
        invoice: invoice,
        source: source
      )
    stage_document(
      run: run,
      contractor: contractor,
      session: session,
      invoice: invoice,
      filename: source.original_filename,
      kind: "invoice",
      reused: true,
      storage_key: source.storage_key
    )
    staged_support =
      stage_document(
        run: run,
        contractor: contractor,
        session: session,
        invoice: invoice,
        filename: source_support.original_filename,
        kind: "supporting_document",
        reused: true,
        storage_key: source_support.storage_key,
        supporting_document_type_id: support_type.id
      )
    run.update!(total_files: 2)

    expect(Claims::InvoiceVersion.where(invoice_id: invoice.id).count).to eq(1)
    expect(staged_support.resolved_invoice_version_id).to be_nil

    Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: run.id)

    target = Claims::InvoiceVersion.find(run.reload.resolved_invoice_version_id)
    cloned_support =
      Claims::SupportingDocument.find_by!(
        invoice_version_id: target.id,
        storage_key: source_support.storage_key
      )
    expect(target.invoice_versionno).to eq(2)
    expect(staged_support.reload).to have_attributes(
      resolved_invoice_version_id: target.id,
      promoted_supporting_document_id: cloned_support.id
    )
    expect(Claims::RunOcrJob).not_to have_received(:perform_async)
    expect(Claims::RunGenaiJob).to have_received(:perform_async).with(
      session.id,
      target.id,
      run.id,
      "use_existing_classifier"
    )
  end
end
