require "rails_helper"

RSpec.describe "Personal-information evidence promotion" do
  let(:now) { Time.zone.parse("2026-07-28 10:15:00") }
  let!(:pi_type) do
    Claims::PersonalInformationType.find_or_create_by!(
      type_key: "unrelated_third_party_information"
    ) do |row|
      row.display_name = "Unrelated third-party information"
      row.description = "Unrelated information about other people."
      row.enabled = true
      row.sort_order = 70
    end
  end

  it "promotes a per-file result to supporting-document evidence" do
    contractor = Contractor.create!(business_name: "PI Evidence Contractor")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "ocr_in_progress",
        created_at: now,
        updated_at: now
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_key: "invoice.pdf",
        created_at: now,
        updated_at: now
      )
    run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        resolved_invoice_version_id: version.id,
        status: "running",
        total_files: 1,
        completed_files: 0,
        failed_files: 0,
        created_at: now,
        updated_at: now
      )
    reason = "Unrelated children with names and ages appear in the image."
    ingest_document =
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        storage_provider: "azure_blob",
        storage_key: "children-label.jpeg",
        original_filename: "energy-label.jpeg",
        content_type: "image/jpeg",
        classifier_raw_json: {
          "document_kind" => "supporting_document",
          "personal_information_review_status" => "high_risk",
          "personal_information_type_key" => pi_type.type_key,
          "personal_information_review_reason" => reason
        },
        document_kind: "supporting_document",
        document_kind_confidence: 99,
        document_kind_reason: "Supporting image.",
        classification_status: "classified",
        classification_confidence: 99,
        classification_reason: "Energy label.",
        classified_at: now,
        created_at: now,
        updated_at: now
      )

    document =
      Claims::SupportingDocuments::CreateOrUpdateFromIngestDocument.call(
        resolved_invoice_version_id: version.id,
        ingest_document_id: ingest_document.id
      )

    expect(document).to have_attributes(
      personal_information_review_status: "high_risk",
      personal_information_type_id: pi_type.id,
      personal_information_review_reason: reason
    )
    expect(ingest_document.reload.promoted_supporting_document_id).to eq(
      document.id
    )
  end
end
