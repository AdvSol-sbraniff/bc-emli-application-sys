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
    expect(row.fetch("unread_message_count")).to eq(0)
    expect(row.fetch("reference_number")).to eq(invoice.reference_number)
    expect(row.fetch("latest_invoice_version_id")).to eq(invoice_version.id)
    expect(row.fetch("latest_di_ocr_customer_address")).to eq(
      "123 Main Street, Victoria, BC"
    )
    expect(row.fetch("submitter_name")).to eq("Jordan Lee")
  end

  it "returns unread admin-message counts for each contractor invoice" do
    host! "localhost"
    user = create(:user, :submitter)
    contractor = Contractor.create!(business_name: "Unread Dashboard Test")
    other_contractor = Contractor.create!(business_name: "Other Contractor")
    session = Claims::Session.create!
    first_invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "genai_complete"
      )
    second_invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_revision_inbox"
      )
    other_invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: other_contractor.id,
        status: "genai_complete"
      )

    [
      first_invoice,
      second_invoice,
      other_invoice
    ].each_with_index do |invoice, index|
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "contractor-portal/unread-#{index}.pdf",
        original_filename: "Unread #{index}.pdf",
        content_type: "application/pdf"
      )
    end

    2.times do |index|
      Claims::ConversationMessage.create!(
        invoice_id: first_invoice.id,
        requester_id: user.id,
        message_type: "admin_message",
        request_text: "Unread admin message #{index + 1}."
      )
    end
    Claims::ConversationMessage.create!(
      invoice_id: first_invoice.id,
      requester_id: user.id,
      message_type: "contractor_note",
      request_text: "Contractor messages do not count as unread admin messages."
    )
    Claims::ConversationMessage.create!(
      invoice_id: second_invoice.id,
      requester_id: user.id,
      message_type: "admin_message",
      request_text: "Already read admin message.",
      recipient_read_at: Time.current
    )
    Claims::ConversationMessage.create!(
      invoice_id: other_invoice.id,
      requester_id: user.id,
      message_type: "admin_message",
      request_text: "Another contractor cannot affect this dashboard."
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
    rows_by_invoice =
      json_response.fetch("rows").index_by { |row| row.fetch("invoice_id") }
    expect(
      rows_by_invoice.fetch(first_invoice.id).fetch("unread_message_count")
    ).to eq(2)
    expect(
      rows_by_invoice.fetch(second_invoice.id).fetch("unread_message_count")
    ).to eq(0)
    expect(rows_by_invoice).not_to have_key(other_invoice.id)
  end
end
