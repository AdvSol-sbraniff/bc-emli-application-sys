require "rails_helper"

RSpec.describe Claims::Invoices::DestroyPackage do
  describe ".call" do
    it "deletes the explicitly owned ingest package with the invoice" do
      now = Time.zone.parse("2026-06-23 17:10:00")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck",
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
          from_status: "contractor_precheck",
          to_status: "contractor_precheck",
          created_at: now
        )
      package_run =
        Claims::IngestRun.create!(
          run_kind: "initial_upload",
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          status: "succeeded",
          total_files: 1,
          completed_files: 1,
          failed_files: 0,
          resolved_invoice_version_id: invoice_version.id,
          created_at: now,
          updated_at: now,
          completed_at: now
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
          created_at: now,
          updated_at: now
        )
      Claims::IngestStepRun.create!(
        ingest_run_id: package_document.ingest_run_id,
        session_id: session.id,
        ingest_document_id: package_document.id,
        step_type: "read_document",
        status: "succeeded",
        created_at: package_document.created_at,
        updated_at: package_document.updated_at
      )

      deleted = described_class.call(invoice_id: invoice.id)

      expect(deleted[:invoice_versions]).to eq(1)
      expect(deleted[:ingest_documents]).to eq(1)
      expect(deleted[:ingest_runs]).to eq(1)
      expect(deleted[:ingest_step_runs]).to eq(1)
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
