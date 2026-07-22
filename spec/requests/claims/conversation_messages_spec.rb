require "rails_helper"

RSpec.describe "Claims conversation messages API", type: :request do
  it "stores and serves ordinary messages separately from formal revisions" do
    host! "localhost"
    user = create(:user, :submitter)
    contractor = Contractor.create!(business_name: "Conversation Test")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "in_review"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "conversation-test/invoice.pdf",
        original_filename: "Conversation invoice.pdf",
        content_type: "application/pdf"
      )
    allow_any_instance_of(
      Api::Claims::ConversationMessagesAdminController
    ).to receive(:require_claims_admin!)

    post "/api/claims/admin/conversation_messages",
         params: {
           invoice_id: invoice.id,
           requester_id: user.id,
           message_type: "admin_message",
           request_text: "Please call if you have a general question."
         },
         as: :json
    expect(response).to have_http_status(:created)
    message_id = json_response.fetch("id")

    get "/api/claims/admin/conversation_messages",
        params: {
          invoice_id: invoice.id
        }
    expect(response).to have_http_status(:ok)
    row = json_response.fetch("rows").sole
    expect(row.fetch("conversation_message_id")).to eq(message_id)
    expect(row.fetch("conversation_message_text")).to eq(
      "Please call if you have a general question."
    )

    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_contractor
    ).and_return(contractor)
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_user
    ).and_return(user)
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    get "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages"
    expect(response).to have_http_status(:ok)
    contractor_row = json_response.fetch("rows").sole
    expect(contractor_row.fetch("message_type")).to eq("admin_message")
    expect(contractor_row.fetch("request_text")).to eq(
      "Please call if you have a general question."
    )
    expect(json_response.fetch("unread_count")).to eq(1)
    expect(json_response.fetch("latest_admin_seqno")).to eq(1)

    post "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages/read",
         params: {
           through_seqno: 1
         },
         as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("unread_count")).to eq(0)
    expect(
      Claims::ConversationMessage.find(message_id).recipient_read_at
    ).to be_present

    post "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages",
         params: {
           request_text:
             "Here is some additional context for the administrator."
         },
         as: :json
    expect(response).to have_http_status(:created)
    contractor_message_id = json_response.fetch("id")
    expect(json_response.fetch("invoice_version_id")).to eq(invoice_version.id)
    expect(json_response.fetch("message_type")).to eq("contractor_note")

    get "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages"
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("unread_count")).to eq(0)

    patch "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages/#{contractor_message_id}",
          params: {
            request_text: "Here is the corrected additional context."
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("request_text")).to eq(
      "Here is the corrected additional context."
    )

    post "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages",
         params: {
           request_text: "  "
         },
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to eq("Message text is required.")

    other_invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "in_review"
      )
    patch "/api/claims/contractor/invoices/#{other_invoice.id}/conversation_messages/#{contractor_message_id}",
          params: {
            request_text: "This update must not cross invoice boundaries."
          },
          as: :json
    expect(response).to have_http_status(:not_found)

    post "/api/claims/admin/conversation_messages",
         params: {
           invoice_id: invoice.id,
           requester_id: user.id,
           message_type: "admin_message",
           request_text: "A new admin reply should be unread."
         },
         as: :json
    expect(response).to have_http_status(:created)

    get "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages"
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("unread_count")).to eq(1)
    expect(json_response.fetch("latest_admin_seqno")).to eq(3)

    post "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages/read",
         params: {
           through_seqno: -1
         },
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch "/api/claims/admin/conversation_messages/#{message_id}",
          params: {
            request_text: "General message updated."
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("request_text")).to eq(
      "General message updated."
    )
    expect(
      Claims::ConversationMessage.find(message_id).recipient_read_at
    ).to be_nil

    expect(Claims::RevisionRound.where(invoice_id: invoice.id)).to be_empty
    expect(Claims::RevisionIssue.where(invoice_id: invoice.id)).to be_empty

    delete "/api/claims/admin/conversation_messages/#{message_id}"
    expect(response).to have_http_status(:ok)
    expect(Claims::ConversationMessage.where(id: message_id)).to be_empty
  end

  it "shares message read state across contractor-company users" do
    host! "localhost"
    first_user = create(:user, :submitter)
    second_user = create(:user, :submitter)
    acting_user = first_user
    contractor = Contractor.create!(business_name: "Unread Cursor Test")
    invoice =
      Claims::Invoice.create!(
        session_id: Claims::Session.create!.id,
        contractor_id: contractor.id,
        status: "in_review"
      )
    Claims::ConversationMessage.create!(
      invoice_id: invoice.id,
      requester_id: first_user.id,
      message_type: "admin_message",
      request_text: "Please review this new message."
    )

    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_contractor
    ).and_return(contractor)
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_user
    ) { acting_user }
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )

    post "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages/read",
         params: {
           through_seqno: 1
         },
         as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("unread_count")).to eq(0)

    acting_user = second_user
    get "/api/claims/contractor/invoices/#{invoice.id}/conversation_messages"
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("unread_count")).to eq(0)
  end
end
