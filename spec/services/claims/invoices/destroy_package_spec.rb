require "rails_helper"

RSpec.describe Claims::Invoices::DestroyPackage do
  describe ".call" do
    it "deletes same-session ingest leftovers when deleting the last invoice" do
      now = Time.zone.parse("2026-06-23 17:10:00")
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
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "current/invoice.pdf",
          original_filename: "Invoice.pdf",
          content_type: "application/pdf",
          created_at: now,
          updated_at: now
        )
      status_transition =
        Claims::InvoiceStatusTransition.create!(
          invoice_id: invoice.id,
          invoice_version_id: invoice_version.id,
          from_status: "genai_in_progress",
          to_status: "genai_complete",
          created_at: now
        )
      package_run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "succeeded",
          total_files: 1,
          completed_files: 1,
          failed_files: 0,
          resolved_invoice_version_id: invoice_version.id,
          created_at: now,
          updated_at: now
        )
      package_document =
        Claims::IngestDocument.create!(
          ingest_run_id: package_run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: invoice_version.id,
          storage_provider: "azure_blob",
          storage_key: "current/invoice.pdf",
          original_filename: "Invoice.pdf",
          content_type: "application/pdf",
          document_kind: "invoice",
          classification_status: "classified",
          created_at: now,
          updated_at: now
        )
      stale_run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "succeeded",
          total_files: 1,
          completed_files: 1,
          failed_files: 0,
          created_at: now + 1.second,
          updated_at: now + 1.second
        )
      stale_document =
        Claims::IngestDocument.create!(
          ingest_run_id: stale_run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          storage_provider: "azure_blob",
          storage_key: "stale/unlinked.pdf",
          original_filename: "Unlinked.pdf",
          content_type: "application/pdf",
          document_kind: "unknown",
          classification_status: "pending",
          created_at: now + 1.second,
          updated_at: now + 1.second
        )

      [package_document, stale_document].each do |document|
        Claims::IngestStepRun.create!(
          ingest_run_id: document.ingest_run_id,
          session_id: session.id,
          ingest_document_id: document.id,
          step_type: "ocr_read",
          status: "succeeded",
          created_at: document.created_at,
          updated_at: document.updated_at
        )
      end

      deleted = described_class.call(invoice_id: invoice.id)

      expect(deleted[:invoice_versions]).to eq(1)
      expect(deleted[:ingest_documents]).to eq(2)
      expect(deleted[:ingest_runs]).to eq(2)
      expect(deleted[:ingest_step_runs]).to eq(2)
      expect(deleted[:sessions]).to eq(1)
      expect(Claims::Invoice.exists?(invoice.id)).to be(false)
      expect(
        Claims::InvoiceStatusTransition.exists?(status_transition.id)
      ).to be(false)
      expect(Claims::Session.exists?(session.id)).to be(false)
      expect(Claims::IngestRun.where(session_id: session.id)).to be_empty
      expect(Claims::IngestDocument.where(session_id: session.id)).to be_empty
      expect(Claims::IngestStepRun.where(session_id: session.id)).to be_empty
    end
  end
end
