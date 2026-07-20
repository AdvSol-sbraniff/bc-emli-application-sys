require "rails_helper"

RSpec.describe "Claims contractor portal index", type: :request do
  it "returns the stable reference number, service address, and submitter name" do
    host! "localhost"
    submitter = create(:user, first_name: "Jordan", last_name: "Lee")
    contractor = Contractor.create!(business_name: "Reference Number Test")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        submitter_id: submitter.id,
        status: "genai_complete"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "contractor-portal/invoice.pdf",
        original_filename: "Less useful filename.pdf",
        content_type: "application/pdf",
        di_ocr_customer_address: "123 Main Street, Victoria, BC"
      )

    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_contractor
    ).and_return(contractor)

    get "/api/claims/contractor/invoices"

    expect(response).to have_http_status(:ok)
    row = json_response.fetch("rows").sole
    expect(row.fetch("invoice_id")).to eq(invoice.id)
    expect(row.fetch("reference_number")).to eq(invoice.reference_number)
    expect(row.fetch("latest_invoice_version_id")).to eq(invoice_version.id)
    expect(row.fetch("latest_di_ocr_customer_address")).to eq(
      "123 Main Street, Victoria, BC"
    )
    expect(row.fetch("submitter_name")).to eq("Jordan Lee")
  end
end
