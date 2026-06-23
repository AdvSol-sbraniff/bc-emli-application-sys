require "rails_helper"

RSpec.describe "Claims advice refresh", type: :request do
  describe "POST /api/claims/admin/invoices/:id/reanalyze_advice" do
    it "clones the current invoice version before rerunning advice" do
      host! "localhost"

      now = Time.zone.parse("2026-06-22 11:04:00")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "genai_complete",
          status_updated_at: now,
          created_at: now,
          updated_at: now
        )
      source_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 3,
          storage_provider: "azure_blob",
          storage_key: "source/fenestration-invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          byte_size: 1234,
          di_raw_json: {
            "invoice" => "di"
          },
          genai_raw_json: {
            "old" => "advice"
          },
          genai_overall_confidence: 88,
          genai_result: "fail",
          genai_admin_advice: "Old advice",
          created_at: now,
          updated_at: now
        )
      upgrade_type =
        Claims::InvoiceUpgradeType.find_or_create_by!(
          upgrade_type_key: "windows_doors"
        ) do |row|
          row.description = "Windows and doors"
          row.created_at = now
          row.updated_at = now
        end
      supporting_type =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "fenestration_energy_performance_label"
        ) do |row|
          row.description = "Fenestration Energy Performance Label"
          row.created_at = now
          row.updated_at = now
        end
      supporting_document =
        Claims::SupportingDocument.create!(
          invoice_version_id: source_version.id,
          supporting_document_type_id: supporting_type.id,
          storage_provider: "azure_blob",
          storage_key: "source/fenestration-label.jpg",
          original_filename: "Fenestration energy tag.jpg",
          content_type: "image/jpeg",
          byte_size: 2345,
          di_read_raw_json: {
            "read" => "di"
          },
          classifier_raw_json: {
            "kind" => "label"
          },
          classification_status: "classified",
          classification_confidence: 99,
          created_at: now,
          updated_at: now
        )

      Claims::Lineitem.create!(
        invoice_version_id: source_version.id,
        lineitem_seqno: 1,
        ocr_description: "Total 8 Vinyl Windows Supply & installation",
        created_at: now,
        updated_at: now
      )
      Claims::InvoiceVersionLocatedField.create!(
        invoice_version_id: source_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "classifier",
        field_key: "classifier.eligibility_code",
        value_type: "text",
        value_text: "ESP1-NatGas9c0f0033",
        confidence: 90,
        created_at: now,
        updated_at: now
      )
      Claims::InvoiceVersionLocatedField.create!(
        invoice_version_id: source_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "code",
        field_key: "users_eligibilitycodes.eligibility_code",
        value_type: "text",
        value_text: "stale-code-fact",
        confidence: 100,
        created_at: now,
        updated_at: now
      )
      Claims::InvoiceVersionUpgradeType.create!(
        invoice_version_id: source_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "classifier",
        call_status: "classified",
        confidence: 98,
        raw_json: {
          "upgrade_type_key" => "windows_doors"
        },
        created_at: now,
        updated_at: now
      )
      Claims::InvoiceVersionUpgradeType.create!(
        invoice_version_id: source_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "genai",
        call_status: "succeeded",
        confidence: 75,
        result: "fail",
        created_at: now,
        updated_at: now
      )
      Claims::SupportingDocumentLocatedField.create!(
        supporting_document_id: supporting_document.id,
        source_engine: "genai",
        field_key: "u_factor",
        value_type: "text",
        value_text: "1.22",
        confidence: 95,
        created_at: now,
        updated_at: now
      )
      Claims::SupportingDocumentVisualFinding.create!(
        supporting_document_id: supporting_document.id,
        finding_seqno: 1,
        source_engine: "genai",
        finding_type: "label_visible",
        summary: "Label is visible.",
        legibility: "legible",
        confidence: 94,
        created_at: now,
        updated_at: now
      )

      allow(Claims::RunGenaiJob).to receive(:perform_async).and_return(
        "jid-123"
      )

      post "/api/claims/admin/invoices/#{invoice.id}/reanalyze_advice"

      expect(response).to have_http_status(:accepted)
      body = json_response
      new_version =
        Claims::InvoiceVersion.find(body.fetch("invoice_version_id"))
      ingest_run = Claims::IngestRun.find(body.fetch("ingest_run_id"))

      expect(body).to include(
        "ok" => true,
        "source_invoice_version_id" => source_version.id,
        "invoice_versionno" => 4,
        "job_id" => "jid-123",
        "status" => "genai_queued"
      )
      expect(new_version.invoice_id).to eq(invoice.id)
      expect(new_version.invoice_versionno).to eq(4)
      expect(ingest_run.resolved_invoice_version_id).to eq(new_version.id)
      expect(new_version.di_raw_json).to eq("invoice" => "di")
      expect(new_version.genai_raw_json).to be_nil
      expect(new_version.genai_overall_confidence).to eq(0)
      expect(new_version.genai_result).to be_nil
      expect(new_version.genai_admin_advice).to be_nil
      expect(new_version.users_eligibilitycode_id).to be_nil
      expect(new_version.participant_user_id).to be_nil

      expect(
        Claims::Lineitem.where(invoice_version_id: new_version.id).pluck(
          :ocr_description
        )
      ).to eq(["Total 8 Vinyl Windows Supply & installation"])
      expect(
        Claims::InvoiceVersionLocatedField.where(
          invoice_version_id: new_version.id
        ).pluck(:source_engine)
      ).to eq(["classifier"])
      expect(
        Claims::InvoiceVersionUpgradeType.where(
          invoice_version_id: new_version.id
        ).pluck(:source_engine)
      ).to eq(["classifier"])

      cloned_supporting_document =
        Claims::SupportingDocument.find_by!(
          invoice_version_id: new_version.id,
          original_filename: "Fenestration energy tag.jpg"
        )
      expect(cloned_supporting_document.storage_key).to eq(
        "source/fenestration-label.jpg"
      )
      expect(
        cloned_supporting_document.supporting_document_located_fields.count
      ).to eq(1)
      expect(
        cloned_supporting_document.supporting_document_visual_findings.count
      ).to eq(1)

      expect(
        Claims::IngestDocument.where(ingest_run_id: ingest_run.id)
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: ingest_run.id,
          invoice_version_id: new_version.id,
          step_type: "ruleclone_clone_existing_evidence",
          status: "succeeded"
        )
      ).to exist
      expect(Claims::RunGenaiJob).to have_received(:perform_async).with(
        session.id,
        new_version.id,
        ingest_run.id,
        "use_existing_classifier"
      )
    end
  end
end
