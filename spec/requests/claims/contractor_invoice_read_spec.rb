require "rails_helper"

RSpec.describe "Claims contractor invoice read", type: :request do
  before do
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::Claims::InvoiceVersionsController).to receive(
      :require_claims_invoice_reader!
    )
    allow_any_instance_of(
      Api::Claims::InvoiceVersionsAdminController
    ).to receive(:require_claims_admin!)
  end

  describe "GET /api/claims/sessions/:session_id/invoices/:invoice_id/read" do
    it "includes supporting-document evidence and possible supporting-document mappings" do
      host! "localhost"

      now = Time.zone.parse("2026-06-22 12:15:00")
      contractor = Contractor.create!(business_name: "Mini Windows")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "contractor_precheck",
          status_updated_at: now,
          submitted_at: now,
          created_at: now,
          updated_at: now
        )
      invoice_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
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
      supporting_type_key = "spec_fenestration_label_#{SecureRandom.hex(4)}"
      supporting_type =
        Claims::SupportingDocumentType.create!(
          type_key: supporting_type_key,
          description: "Fenestration Energy Performance Label",
          enabled: true,
          created_at: now,
          updated_at: now
        )
      field_definition =
        Claims::SupportingDocumentTypeLocatedField.create!(
          supporting_document_type_id: supporting_type.id,
          field_key: "u_factor",
          contractor_display_name: "U-factor",
          prompt_text: "Find the U-factor.",
          field_number: 1,
          enabled: true,
          created_at: now,
          updated_at: now
        )
      Claims::SupportingDocumentTypeUpgradeType.create!(
        supporting_document_type_id: supporting_type.id,
        invoice_upgrade_type_id: upgrade_type.id,
        created_at: now
      )
      Claims::InvoiceVersionUpgradeType.create!(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        confidence: 98,
        raw_json: {
          "upgrade_type_key" => "windows_doors"
        },
        created_at: now,
        updated_at: now
      )
      rule_key = "contractor_action_#{SecureRandom.hex(4)}"
      Claims::GenaiRule.create!(
        genai_rule_key: rule_key,
        contractor_display_name: "Invoice requirement test",
        prompt_text: "Check the invoice requirement.",
        enabled: true,
        source_quote: "The invoice must show the required information.",
        contractor_action:
          "Upload a corrected invoice if the information is missing.",
        contractor_visibility: "fail_only",
        contractor_blocking_policy: "non_blocking",
        admin_workflow_policy: "fail_only",
        created_at: now,
        updated_at: now
      )
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "genai",
        rule_key: rule_key,
        contractor_display_name: "Invoice requirement test",
        rule_result: "fail",
        compliance_score: 12,
        created_at: now,
        updated_at: now
      )
      supporting_document =
        Claims::SupportingDocument.create!(
          invoice_version_id: invoice_version.id,
          supporting_document_type_id: supporting_type.id,
          storage_provider: "azure_blob",
          storage_key: "label.jpg",
          original_filename: "Fenestration energy tag.jpg",
          content_type: "image/jpeg",
          classification_confidence: 99,
          created_at: now,
          updated_at: now
        )
      Claims::SupportingDocumentLocatedField.create!(
        supporting_document_id: supporting_document.id,
        supporting_document_type_located_field_id: field_definition.id,
        source_engine: "genai",
        field_key: "u_factor",
        value_type: "text",
        value_text: "1.22",
        confidence: 95,
        page: 1,
        polygon: [1, 1, 2, 1, 2, 2, 1, 2],
        evidence_text: "U-Factor 1.22",
        created_at: now,
        updated_at: now
      )
      Claims::SupportingDocumentVisualFinding.create!(
        supporting_document_id: supporting_document.id,
        finding_seqno: 1,
        source_engine: "genai",
        finding_type: "label_visible",
        page: 1,
        summary: "The energy label is visible.",
        legibility: "legible",
        confidence: 94,
        created_at: now,
        updated_at: now
      )

      get "/api/claims/sessions/#{session.id}/invoices/#{invoice.id}/read"

      expect(response).to have_http_status(:ok)
      read = json_response.fetch("read")
      expect(read.fetch("reference_number")).to eq(invoice.reference_number)
      expect(Time.zone.parse(read.fetch("submitted_at"))).to eq(now)

      supporting_type_group =
        read
          .fetch("supporting_document_types_by_upgrade_type")
          .find { |row| row.fetch("upgrade_type_key") == "windows_doors" }
      expect(supporting_type_group).to be_present
      expect(
        supporting_type_group.fetch("supporting_document_types")
      ).to include(
        include(
          "type_key" => supporting_type_key,
          "description" => "Fenestration Energy Performance Label"
        )
      )

      document = read.fetch("uploaded_supporting_documents").first
      expect(document).to include(
        "id" => supporting_document.id,
        "supporting_document_type_key" => supporting_type_key,
        "original_filename" => "Fenestration energy tag.jpg"
      )
      expect(document.fetch("located_fields").first).to include(
        "field_key" => "u_factor",
        "contractor_display_name" => "U-factor",
        "value_text" => "1.22",
        "field_number" => 1,
        "prompt_text" => "Find the U-factor."
      )
      expect(document.fetch("visual_findings").first).to include(
        "finding_type" => "label_visible",
        "summary" => "The energy label is visible."
      )

      get "/api/claims/sessions/#{session.id}/invoices/#{invoice.id}/read_genai"

      expect(response).to have_http_status(:ok)
      rulecheck =
        json_response
          .fetch("rulechecks")
          .find { |row| row.fetch("rule_key") == rule_key }
      expect(rulecheck).to include(
        "source_quote" => "The invoice must show the required information.",
        "contractor_action" =>
          "Upload a corrected invoice if the information is missing."
      )
      expect(rulecheck).not_to have_key("compliance_score")

      get "/api/claims/admin/invoice_versions/#{invoice_version.id}/read_genai"

      expect(response).to have_http_status(:ok)
      admin_rulecheck =
        json_response
          .fetch("rulechecks")
          .find { |row| row.fetch("rule_key") == rule_key }
      expect(admin_rulecheck.fetch("compliance_score")).to eq(12)
    end
  end
end
