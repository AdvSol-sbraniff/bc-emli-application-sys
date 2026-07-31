require "rails_helper"

RSpec.describe Claims::Ingest::UploadFixPackage do
  describe ".call" do
    it "ignores legacy role hints and classifies every new fix file through the pipeline" do
      now = Time.zone.parse("2026-06-22 10:07:24")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
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
          byte_size: 1234,
          di_raw_json: {
            "invoice" => "di"
          },
          created_at: now,
          updated_at: now
        )
      files = [
        fake_upload("Invoice removal confirmation.pdf", "application/pdf"),
        fake_upload("Fenestration energy tag.jpeg")
      ]

      allow(Claims::Ingest::UploadEvidenceFileToNode).to receive(
        :call
      ) do |args|
        {
          "storage_key" => "uploaded/#{args.fetch(:ingest_document_id)}.jpg",
          "byte_size" => 2345,
          "sha256" => SecureRandom.hex(16)
        }
      end
      allow(Claims::RunIngestReadOcrJob).to receive(:perform_async)

      result =
        described_class.call(
          invoice_id: invoice.id,
          clone_invoice_version_id: source_version.id,
          files: files,
          file_roles: %w[invoice invoice]
        )

      run_id = result.ingest_run_id
      expect(Claims::IngestRun.find(run_id).resolved_invoice_version_id).to eq(
        result.invoice_version_id
      )
      cloned_invoice_document =
        Claims::IngestDocument.find_by!(
          ingest_run_id: run_id,
          original_filename: "Fenestration invoice.pdf"
        )
      cloned_invoice_steps =
        Claims::IngestStepRun.where(
          ingest_run_id: run_id,
          ingest_document_id: cloned_invoice_document.id
        )

      expect(cloned_invoice_steps.pluck(:step_type)).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run_id,
          step_type: "fix_ocr_invoice"
        )
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run_id,
          step_type: "fix_clone_existing_evidence"
        )
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run_id,
          step_type: "fix_ocr_read",
          ingest_document_id:
            Claims::IngestDocument.where(
              ingest_run_id: run_id,
              original_filename: [
                "Invoice removal confirmation.pdf",
                "Fenestration energy tag.jpeg"
              ]
            ).select(:id)
        ).count
      ).to eq(2)
      expect(
        Claims::IngestDocument
          .where(
            ingest_run_id: run_id,
            original_filename: [
              "Invoice removal confirmation.pdf",
              "Fenestration energy tag.jpeg"
            ]
          )
          .pluck(:document_kind, :classification_status)
          .uniq
      ).to eq([[nil, "pending"]])
    end

    it "stages an invoice replacement without requiring a caller-selected invoice role" do
      now = Time.zone.parse("2026-06-22 10:07:24")
      contractor = Contractor.create!(business_name: "Replacement Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
          created_at: now,
          updated_at: now
        )
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "source/invoice.pdf",
        original_filename: "Original invoice.pdf",
        content_type: "application/pdf",
        byte_size: 1234,
        created_at: now,
        updated_at: now
      )
      files = [
        fake_upload("Replacement claim document.pdf", "application/pdf"),
        fake_upload(
          "Removal proof referencing invoice 42.pdf",
          "application/pdf"
        )
      ]
      uploaded_scopes = []

      allow(Claims::Ingest::UploadEvidenceFileToNode).to receive(
        :call
      ) do |args|
        uploaded_scopes << args.fetch(:upload_scope_id)
        {
          "storage_key" => "uploaded/#{args.fetch(:ingest_document_id)}.pdf",
          "byte_size" => 2345,
          "sha256" => SecureRandom.hex(16)
        }
      end
      allow(Claims::RunIngestReadOcrJob).to receive(:perform_async)

      result =
        described_class.call(
          invoice_id: invoice.id,
          clone_invoice_version_id: nil,
          files: files
        )

      expect(result.ok).to be(true)
      replacement_version =
        Claims::InvoiceVersion.find(result.invoice_version_id)
      documents =
        Claims::IngestDocument.where(ingest_run_id: result.ingest_run_id).order(
          :created_at,
          :id
        )

      expect(replacement_version.invoice_versionno).to eq(2)
      expect(replacement_version.storage_key).to start_with("PENDING/")
      expect(replacement_version.original_filename).to be_nil
      expect(replacement_version.content_type).to be_nil
      expect(documents.pluck(:original_filename)).to match_array(
        files.map(&:original_filename)
      )
      expect(documents.pluck(:document_kind).uniq).to eq([nil])
      expect(documents.pluck(:classification_status).uniq).to eq(["pending"])
      expect(uploaded_scopes).to match_array(documents.pluck(:id))
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: result.ingest_run_id,
          ingest_document_id: documents.select(:id),
          step_type: "fix_ocr_read",
          status: "queued"
        ).count
      ).to eq(2)
    end

    it "retains PI review evidence when invoice and supporting files are cloned" do
      now = Time.zone.parse("2026-07-28 13:05:00")
      contractor = Contractor.create!(business_name: "PI Clone Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
          created_at: now,
          updated_at: now
        )
      pi_type =
        Claims::PersonalInformationType.find_or_create_by!(
          type_key: "government_identifier"
        ) do |row|
          row.display_name = "Government identifier"
          row.description = "Government identification."
          row.enabled = true
          row.sort_order = 20
        end
      source_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "source/pi-invoice.pdf",
          original_filename: "PI invoice.pdf",
          content_type: "application/pdf",
          personal_information_review_status: "high_risk",
          personal_information_type_id: pi_type.id,
          personal_information_review_reason:
            "A possible government identifier appears on page 2.",
          created_at: now,
          updated_at: now
        )
      source_document =
        Claims::SupportingDocument.create!(
          invoice_version_id: source_version.id,
          storage_provider: "azure_blob",
          storage_key: "source/pi-support.pdf",
          original_filename: "PI supporting document.pdf",
          content_type: "application/pdf",
          classification_status: "classified",
          personal_information_review_status: "review_recommended",
          personal_information_type_id: pi_type.id,
          personal_information_review_reason:
            "Unexpected personal information appears in this file.",
          created_at: now,
          updated_at: now
        )

      allow(Claims::Ingest::UploadEvidenceFileToNode).to receive(
        :call
      ) do |args|
        {
          "storage_key" => "uploaded/#{args.fetch(:ingest_document_id)}.jpg",
          "byte_size" => 2345,
          "sha256" => SecureRandom.hex(16)
        }
      end
      allow(Claims::RunIngestReadOcrJob).to receive(:perform_async)

      result =
        described_class.call(
          invoice_id: invoice.id,
          clone_invoice_version_id: source_version.id,
          clone_supporting_document_ids: [source_document.id],
          files: [fake_upload("new-label.jpeg")]
        )

      cloned_version = Claims::InvoiceVersion.find(result.invoice_version_id)
      cloned_document =
        Claims::SupportingDocument.find_by!(
          invoice_version_id: cloned_version.id,
          storage_key: source_document.storage_key
        )

      expect(cloned_version).to have_attributes(
        personal_information_review_status: "high_risk",
        personal_information_type_id: pi_type.id,
        personal_information_review_reason:
          source_version.personal_information_review_reason
      )
      expect(cloned_document).to have_attributes(
        personal_information_review_status: "review_recommended",
        personal_information_type_id: pi_type.id,
        personal_information_review_reason:
          source_document.personal_information_review_reason
      )
    end

    it "returns a safe structured technical failure and closes the fix run" do
      now = Time.zone.parse("2026-07-30 18:00:00")
      contractor = Contractor.create!(business_name: "Fix Failure Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
          created_at: now,
          updated_at: now
        )
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "source/fix-failure.pdf",
        original_filename: "Original invoice.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )
      raw_message = "undefined method `completed_at=' for a private object"
      allow(Claims::Ingest::UploadEvidenceFileToNode).to receive(
        :call
      ).and_raise(NoMethodError, raw_message)

      result =
        described_class.call(
          invoice_id: invoice.id,
          files: [fake_upload("Replacement invoice.pdf", "application/pdf")]
        )

      run = Claims::IngestRun.find(result.ingest_run_id)
      stage_step =
        Claims::IngestStepRun.find_by!(
          ingest_run_id: run.id,
          step_type: "fix_upload_package_stage"
        )

      expect(result).to have_attributes(
        ok: false,
        failure_status: "technical_failure",
        failure_status_subtype: "upload_unexpected_exception",
        error_code: "upload_unexpected_exception",
        retryable: false
      )
      expect(result.diagnostic_id).to be_present
      expect(result.error).not_to include(raw_message)
      expect(run.status).to eq("failed")
      expect(run.completed_at).to be_present
      expect(stage_step).to have_attributes(
        status: "failed",
        error_text: "Fix upload failed: upload_unexpected_exception.",
        diagnostic_id: result.diagnostic_id
      )
      expect(stage_step.completed_at).to be_present
    end

    it "keeps an unsupported fix file as a correctable package failure" do
      now = Time.zone.parse("2026-07-30 18:05:00")
      contractor =
        Contractor.create!(business_name: "Fix Validation Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
          created_at: now,
          updated_at: now
        )
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "source/fix-validation.pdf",
        original_filename: "Original invoice.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )

      result =
        described_class.call(
          invoice_id: invoice.id,
          files: [fake_upload("notes.txt", "text/plain")]
        )

      expect(result).to have_attributes(
        ok: false,
        failure_status: "package_needs_correction",
        failure_status_subtype: "package_unsupported_file_type",
        error_code: "package_unsupported_file_type",
        retryable: false,
        diagnostic_id: nil
      )
      expect(result.error).to include("upload package needs a change")
      expect(result.error).not_to include("RuntimeError")
    end
  end

  def fake_upload(filename, content_type = "image/jpeg")
    instance_double(
      "UploadedFile",
      original_filename: filename,
      content_type: content_type,
      size: 2345
    )
  end
end
