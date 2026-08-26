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

  it "reads and updates the admin PDF viewer settings" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!(
          show_admin_field_revision_plus: true,
          created_at: Time.current,
          updated_at: Time.current
        )
    config.update!(
      show_admin_field_revision_plus: true,
      admin_pdf_viewer_ux_mode: "simple"
    )

    get "/api/claims/admin/validationgenai_config"

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("show_admin_field_revision_plus")).to eq(true)
    expect(json_response.fetch("admin_pdf_viewer_ux_mode")).to eq("simple")

    patch "/api/claims/admin/validationgenai_config",
          params: {
            show_admin_field_revision_plus: false,
            admin_pdf_viewer_ux_mode: "enterprise"
          },
          as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("show_admin_field_revision_plus")).to eq(false)
    expect(json_response.fetch("admin_pdf_viewer_ux_mode")).to eq("enterprise")
    expect(config.reload.show_admin_field_revision_plus).to eq(false)
    expect(config.admin_pdf_viewer_ux_mode).to eq("enterprise")

    patch "/api/claims/admin/validationgenai_config",
          params: {
            admin_pdf_viewer_ux_mode: "unsupported"
          },
          as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(config.reload.admin_pdf_viewer_ux_mode).to eq("enterprise")
  end

  it "includes the setting in the existing admin invoice read payload" do
    config =
      Claims::ValidationgenaiConfig.order(:created_at).first ||
        Claims::ValidationgenaiConfig.create!(
          show_admin_field_revision_plus: false,
          created_at: Time.current,
          updated_at: Time.current
        )
    config.update!(
      show_admin_field_revision_plus: false,
      admin_pdf_viewer_ux_mode: "enterprise"
    )
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
    expect(json_response.fetch("read").fetch("admin_pdf_viewer_ux_mode")).to eq(
      "enterprise"
    )
    expect(json_response.fetch("invoice")).to include(
      "reference_number" => invoice.reference_number,
      "contractor_business_name" => contractor.business_name
    )
  end
end
