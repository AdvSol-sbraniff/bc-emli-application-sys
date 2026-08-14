require "rails_helper"

RSpec.describe "Claims validation GenAI config", type: :request do
  before do
    host! "localhost"
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(
      Api::Claims::ValidationgenaiConfigController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(
      Api::Claims::InvoiceVersionsAdminController
    ).to receive(:require_claims_admin!)
  end

  it "reads and updates the admin field revision plus setting" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!(
          show_admin_field_revision_plus: true,
          created_at: Time.current,
          updated_at: Time.current
        )
    config.update!(show_admin_field_revision_plus: true)

    get "/api/claims/admin/validationgenai_config"

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("show_admin_field_revision_plus")).to eq(true)

    patch "/api/claims/admin/validationgenai_config",
          params: {
            show_admin_field_revision_plus: false
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("show_admin_field_revision_plus")).to eq(false)
    expect(config.reload.show_admin_field_revision_plus).to eq(false)
  end

  it "includes the setting in the existing admin invoice read payload" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!(
          show_admin_field_revision_plus: false,
          created_at: Time.current,
          updated_at: Time.current
        )
    config.update!(show_admin_field_revision_plus: false)
    now = Time.zone.parse("2026-08-12 10:00:00")
    contractor = Contractor.create!(business_name: "Viewer Config Contractor")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "admin_review_inbox",
        created_at: now,
        updated_at: now
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_key: "viewer-config/invoice.pdf",
        created_at: now,
        updated_at: now
      )

    get "/api/claims/admin/invoice_versions/#{version.id}/read"

    expect(response).to have_http_status(:ok)
    expect(
      json_response.fetch("read").fetch("show_admin_field_revision_plus")
    ).to eq(false)
  end
end
