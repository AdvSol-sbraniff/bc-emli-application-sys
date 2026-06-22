require "rails_helper"

RSpec.describe Claims::Ingest::AdvanceBundleRun do
  describe ".call" do
    it "treats cloned invoice evidence as reused and gates fix OCR/classifier on new files" do
      now = Time.zone.parse("2026-06-22 10:07:24")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      source_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "source/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: {
            "source" => "invoice-di"
          },
          created_at: now,
          updated_at: now
        )
      new_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 2,
          storage_provider: "azure_blob",
          storage_key: "cloned/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: source_version.di_raw_json,
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 3,
          completed_files: 0,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      type =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "test_fenestration_label_no_fields"
        ) do |row|
          row.description = "Test Fenestration Label With No Fields"
          row.created_at = now
          row.updated_at = now
        end

      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        step_type: "fix_upload_package_stage",
        status: "succeeded",
        created_at: now,
        updated_at: now
      )
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        invoice_version_id: new_version.id,
        step_type: "fix_clone_existing_evidence",
        status: "queued",
        created_at: now,
        updated_at: now
      )
      cloned_invoice_document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: new_version.id,
          storage_provider: "azure_blob",
          storage_key: new_version.storage_key,
          original_filename: new_version.original_filename,
          content_type: new_version.content_type,
          di_read_raw_json: source_version.di_raw_json,
          document_kind: "invoice",
          document_kind_reason: "Cloned from prior invoice version.",
          classification_status: "classified",
          classification_confidence: 100,
          classification_reason: "Cloned from prior invoice version.",
          classified_at: now,
          created_at: now,
          updated_at: now
        )
      new_support_document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: new_version.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/tag-1.jpg",
          original_filename: "Fenestration energy tag (1).jpeg",
          content_type: "image/jpeg",
          di_read_raw_json: {
            "read" => "tag"
          },
          classifier_raw_json: {
            "classified" => true
          },
          document_kind: "supporting_document",
          document_kind_reason: "Classified from new fix evidence.",
          supporting_document_type_id: type.id,
          classification_status: "classified",
          classification_confidence: 99,
          classification_reason: "Fenestration label.",
          classified_at: now + 20.seconds,
          created_at: now,
          updated_at: now + 20.seconds
        )
      %w[fix_ocr_read fix_classifier_files].each do |step_type|
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          ingest_document_id: new_support_document.id,
          step_type: step_type,
          status: "succeeded",
          created_at: now + 10.seconds,
          updated_at: now + 20.seconds
        )
      end

      allow(Claims::RunOcrJob).to receive(:perform_async)
      allow(Claims::RunGenaiJob).to receive(:perform_async)

      described_class.call(ingest_run_id: run.id)

      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          ingest_document_id: cloned_invoice_document.id
        )
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          step_type: "fix_clone_existing_evidence"
        ).pick(:status)
      ).to eq("succeeded")
      invoice_ocr_step =
        Claims::IngestStepRun.find_by!(
          ingest_run_id: run.id,
          invoice_version_id: new_version.id,
          step_type: "fix_ocr_invoice"
        )
      expect(invoice_ocr_step.status).to eq("succeeded")
      expect(invoice_ocr_step.di_results_json).to include(
        "reused_invoice_ocr" => true,
        "reused_from_invoice_version_id" => source_version.id
      )
      expect(Claims::RunOcrJob).not_to have_received(:perform_async)
      expect(Claims::RunGenaiJob).to have_received(:perform_async).with(
        session.id,
        new_version.id,
        run.id,
        "use_existing_classifier"
      )
    end
  end
end
