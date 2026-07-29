require "rails_helper"

RSpec.describe "Claims admin personal-information flags", type: :request do
  before do
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(
      Api::Claims::InvoiceVersionsAdminController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(Api::Claims::InvoiceVersionsController).to receive(
      :require_claims_invoice_reader!
    )
  end

  it "returns evidence flags to admins without exposing them to contractors" do
    host! "localhost"
    now = Time.zone.parse("2026-07-28 11:45:00")
    contractor = Contractor.create!(business_name: "Privacy Test Contractor")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "admin_review_inbox",
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
    invoice_reason = "A possible government identifier appears on page 2."
    version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_key: "flagged-invoice.pdf",
        personal_information_review_status: "high_risk",
        personal_information_type_id: pi_type.id,
        personal_information_review_reason: invoice_reason,
        created_at: now,
        updated_at: now
      )
    supporting_reason =
      "Unexpected personal information appears in the supporting file."
    document =
      Claims::SupportingDocument.create!(
        invoice_version_id: version.id,
        storage_key: "flagged-support.pdf",
        classification_status: "classified",
        personal_information_review_status: "review_recommended",
        personal_information_type_id: pi_type.id,
        personal_information_review_reason: supporting_reason,
        created_at: now,
        updated_at: now
      )

    get "/api/claims/admin/invoice_versions/#{version.id}/read"

    expect(response).to have_http_status(:ok)
    admin_read = json_response.fetch("read")
    expect(admin_read).to include(
      "personal_information_review_status" => "high_risk",
      "personal_information_review_reason" => invoice_reason,
      "personal_information_type" => {
        "type_key" => pi_type.type_key,
        "display_name" => pi_type.display_name
      }
    )
    expect(admin_read.fetch("uploaded_supporting_documents").first).to include(
      "id" => document.id,
      "personal_information_review_status" => "review_recommended",
      "personal_information_review_reason" => supporting_reason,
      "personal_information_type" => {
        "type_key" => pi_type.type_key,
        "display_name" => pi_type.display_name
      }
    )

    get "/api/claims/sessions/#{session.id}/invoices/#{invoice.id}/read"

    expect(response).to have_http_status(:ok)
    contractor_read = json_response.fetch("read")
    expect(contractor_read).not_to have_key(
      "personal_information_review_status"
    )
    expect(
      contractor_read.fetch("uploaded_supporting_documents").first
    ).not_to have_key("personal_information_review_status")
  end
end
