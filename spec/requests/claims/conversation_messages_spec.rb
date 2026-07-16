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

    patch "/api/claims/admin/conversation_messages/#{message_id}",
          params: {
            request_text: "General message updated."
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("request_text")).to eq(
      "General message updated."
    )

    expect(Claims::RevisionRound.where(invoice_id: invoice.id)).to be_empty
    expect(Claims::RevisionIssue.where(invoice_id: invoice.id)).to be_empty

    delete "/api/claims/admin/conversation_messages/#{message_id}"
    expect(response).to have_http_status(:ok)
    expect(Claims::ConversationMessage.where(id: message_id)).to be_empty
  end
end
