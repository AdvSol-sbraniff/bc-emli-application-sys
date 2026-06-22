require "rails_helper"

RSpec.describe "Claims ingest step history", type: :request do
  before do
    allow_any_instance_of(Api::Claims::IngestController).to receive(
      :require_claims_admin!
    )
  end

  describe "GET /api/claims/ingest/invoices/:invoice_id/steps" do
    it "renders supporting-document extraction only as a supporting-document-type row" do
      host! "localhost"

      now = Time.zone.parse("2026-06-20 13:26:17")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      ingest_run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "succeeded",
          total_files: 3,
          completed_files: 3,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
          status_updated_at: now,
          created_at: now,
          updated_at: now
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "fenestration-invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          created_at: now,
          updated_at: now
        )
      supporting_document_type =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "fenestration_energy_performance_label"
        ) do |type|
          type.description = "Fenestration Energy Performance Label"
          type.created_at = now
          type.updated_at = now
        end

      [
        "Fenestration energy tag (1).jpeg",
        "Fenestration energy tag (2).jpeg"
      ].each do |filename|
        Claims::SupportingDocument.create!(
          invoice_version_id: invoice_version.id,
          supporting_document_type_id: supporting_document_type.id,
          storage_provider: "azure_blob",
          storage_key: filename,
          original_filename: filename,
          content_type: "image/jpeg",
          created_at: now,
          updated_at: now
        )
      end

      Claims::IngestStepRun.create!(
        ingest_run_id: ingest_run.id,
        session_id: session.id,
        invoice_version_id: invoice_version.id,
        supporting_document_type_id: supporting_document_type.id,
        step_type: "supporting_document_extraction",
        status: "succeeded",
        created_at: now,
        updated_at: now
      )
      Claims::IngestStepRun.create!(
        ingest_run_id: ingest_run.id,
        session_id: session.id,
        invoice_version_id: invoice_version.id,
        step_type: "ocr_invoice",
        status: "succeeded",
        created_at: now + 1.second,
        updated_at: now + 1.second
      )

      get "/api/claims/ingest/invoices/#{invoice.id}/steps",
          params: {
            ingest_run_id: ingest_run.id,
            limit: 500
          }

      expect(response).to have_http_status(:ok)
      rows = json_response.fetch("rows")
      extraction_rows =
        rows.select do |row|
          row.fetch("step_type") == "supporting_document_extraction"
        end

      expect(extraction_rows.size).to eq(1)
      expect(extraction_rows.first.fetch("document_kind")).to eq(
        "supporting_document_type"
      )
      expect(extraction_rows.first.fetch("original_filename")).to include(
        "Fenestration Energy Performance Label"
      )
      expect(
        rows.any? do |row|
          row.fetch("step_type") == "supporting_document_extraction" &&
            row.fetch("document_kind") == "invoice"
        end
      ).to be(false)
      expect(
        rows.any? do |row|
          row.fetch("step_type") == "ocr_invoice" &&
            row.fetch("document_kind") == "invoice"
        end
      ).to be(true)
    end

    it "labels reused fix invoice OCR rows distinctly from fresh OCR work" do
      host! "localhost"

      now = Time.zone.parse("2026-06-22 10:09:01")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      ingest_run =
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
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_queued",
          status_updated_at: now,
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
          created_at: now,
          updated_at: now
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 2,
          storage_provider: "azure_blob",
          storage_key: "cloned/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          created_at: now,
          updated_at: now
        )

      Claims::IngestStepRun.create!(
        ingest_run_id: ingest_run.id,
        session_id: session.id,
        invoice_version_id: invoice_version.id,
        step_type: "fix_ocr_invoice",
        status: "succeeded",
        di_results_json: {
          reused_invoice_ocr: true,
          reused_from_invoice_version_id: source_version.id
        },
        created_at: now,
        updated_at: now
      )

      get "/api/claims/ingest/invoices/#{invoice.id}/steps",
          params: {
            ingest_run_id: ingest_run.id,
            limit: 500
          }

      expect(response).to have_http_status(:ok)
      row =
        json_response
          .fetch("rows")
          .find do |candidate|
            candidate.fetch("step_type") == "fix_ocr_invoice"
          end

      expect(row).to include(
        "document_kind" => "invoice",
        "state_label" => "reused"
      )
      expect(row.fetch("step_note")).to include("Reused prior invoice OCR")
    end
  end
end
