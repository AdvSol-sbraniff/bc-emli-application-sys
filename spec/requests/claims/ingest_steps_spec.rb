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
  end

  describe "GET /api/claims/ingest/runs/:ingest_run_id" do
    it "renders pipeline checker fields on the run header" do
      host! "localhost"

      session = Claims::Session.create!
      ingest_run =
        Claims::IngestRun.create!(
          session_id: session.id,
          status: "failed",
          total_files: 1,
          completed_files: 0,
          failed_files: 1,
          failure_status: "technical_failure",
          failure_status_subtype: "genai_service_error",
          pipeline_error_code: "checker_test_error",
          pipeline_error_description: "Checker test description."
        )
      failed_step =
        Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run.id,
          session_id: session.id,
          step_type: "classifier_files",
          status: "failed",
          error_text: "Provider request failed.",
          failure_status: "technical_failure",
          failure_status_subtype: "genai_service_error",
          error_code: "genai_provider_gateway_error",
          error_category: "provider_gateway_error",
          retryable: true,
          diagnostic_id: "diag-admin-monitor",
          provider_status: 503,
          provider_code: "service_unavailable"
        )

      get "/api/claims/ingest/runs/#{ingest_run.id}"

      expect(response).to have_http_status(:ok)
      expect(json_response.fetch("pipeline_error_code")).to eq(
        "checker_test_error"
      )
      expect(json_response.fetch("pipeline_error_description")).to eq(
        "Checker test description."
      )
      expect(json_response.fetch("failure_status")).to eq("technical_failure")
      expect(json_response.fetch("primary_failure")).to include(
        "step_id" => failed_step.id,
        "error_code" => "genai_provider_gateway_error",
        "provider_status" => 503,
        "provider_code" => "service_unavailable",
        "retryable" => true,
        "diagnostic_id" => "diag-admin-monitor"
      )
      expect(json_response).not_to have_key("messages")
    end
  end
end
