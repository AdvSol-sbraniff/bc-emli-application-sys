require "rails_helper"

RSpec.describe Claims::Ingest::UploadFixPackage do
  describe ".call" do
    it "does not record cloned invoice evidence as new fix OCR or classifier work" do
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
        fake_upload("Fenestration energy tag (1).jpeg"),
        fake_upload("Fenestration energy tag (2).jpeg")
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
          file_roles: %w[supporting_document supporting_document]
        )

      run_id = result.ingest_run_id
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
                "Fenestration energy tag (1).jpeg",
                "Fenestration energy tag (2).jpeg"
              ]
            ).select(:id)
        ).count
      ).to eq(2)
    end
  end

  def fake_upload(filename)
    instance_double(
      "UploadedFile",
      original_filename: filename,
      content_type: "image/jpeg",
      size: 2345
    )
  end
end
