require "rails_helper"

RSpec.describe "Claims revision issue workflow API", type: :request do
  let(:now) { Time.zone.parse("2026-07-15 22:00:00") }
  let(:user) { create(:user, :submitter) }
  let(:contractor) do
    Contractor.create!(business_name: "Revision API Contractor")
  end
  let(:session) { Claims::Session.create!(created_at: now, updated_at: now) }
  let(:invoice) do
    Claims::Invoice.create!(
      session_id: session.id,
      contractor_id: contractor.id,
      submitter_id: user.id,
      status: "admin_review_inbox",
      status_updated_at: now,
      created_at: now,
      updated_at: now
    )
  end
  let(:version) do
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_provider: "azure_blob",
      storage_key: "revision-api/invoice.pdf",
      original_filename: "API invoice.pdf",
      content_type: "application/pdf",
      created_at: now,
      updated_at: now
    )
  end
  let(:upgrade_type) do
    Claims::InvoiceUpgradeType.find_or_create_by!(
      upgrade_type_key: "revision_api_test"
    ) do |row|
      row.description = "Revision API test"
      row.created_at = now
      row.updated_at = now
    end
  end
  let(:rule) do
    key = "revision_api_#{SecureRandom.hex(5)}"
    Claims::GenaiRule.create!(
      genai_rule_key: key,
      contractor_display_name: "Confirm installation detail",
      prompt_text: "Confirm the installation detail.",
      enabled: true,
      source_quote: "Revision API test rule.",
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "fail_only",
      created_at: now,
      updated_at: now
    )
    Claims::InvoiceVersionRulecheck.create!(
      invoice_version_id: version.id,
      invoice_upgrade_type_id: upgrade_type.id,
      source_engine: "genai",
      rule_key: key,
      contractor_display_name: "Confirm installation detail",
      rule_result: "fail",
      confidence: 88,
      reason_and_likely_causes: "A required detail is ambiguous.",
      evidence_text: "The invoice has abbreviated wording.",
      created_at: now,
      updated_at: now
    )
  end

  def select_recommendation(invoice_id, issue, remedy: "provide_explanation")
    comment = issue.fetch("comments").first
    patch "/api/claims/admin/invoices/#{invoice_id}/revision_issue_comments/#{comment.fetch("id")}",
          params: {
            admin_recommended_remedy: remedy,
            comment_text: comment.fetch("comment_text")
          },
          as: :json
    expect(response).to have_http_status(:ok)
  end

  before do
    host! "localhost"
    version
    allow_any_instance_of(
      Api::Claims::InvoiceRevisionIssuesAdminController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
    allow_any_instance_of(
      Api::Claims::InvoiceRevisionIssuesAdminController
    ).to receive(:current_user).and_return(user)
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_user
    ).and_return(user)
    allow_any_instance_of(Api::Claims::ContractorPortalController).to receive(
      :current_contractor
    ).and_return(contractor)
  end

  it "carries a durable issue through an admin recommendation and contractor response" do
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues",
         params: {
           issue_type: "rule",
           invoice_version_rulecheck_id: rule.id
         },
         as: :json
    expect(response).to have_http_status(:created)
    round = json_response.fetch("rounds").first
    expect(round.fetch("state")).to eq("draft")

    issue = json_response.fetch("issues").first
    expect(issue.dig("source", "friendly_label")).to eq(
      "Confirm installation detail"
    )
    expect(issue.fetch("comments").length).to eq(1)

    admin_comment = issue.fetch("comments").first
    expect(admin_comment.fetch("admin_recommended_remedy")).to be_nil
    expect(json_response.dig("capabilities", "can_send_issues")).to be(false)
    patch "/api/claims/admin/invoices/#{invoice.id}/revision_issue_comments/#{admin_comment.fetch("id")}",
          params: {
            admin_recommended_remedy: "provide_explanation",
            comment_text: "Please explain the abbreviated installation detail."
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("capabilities", "can_send_issues")).to be(true)

    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues/send",
         as: :json
    expect(response).to have_http_status(:ok)
    expect(invoice.reload.status).to eq("contractor_revision_inbox")

    get "/api/claims/contractor/invoices/#{invoice.id}/revision_issues"
    expect(response).to have_http_status(:ok)
    contractor_issue = json_response.fetch("issues").first
    expect(contractor_issue).not_to have_key("source_reference")
    expect(contractor_issue.fetch("can_contractor_respond")).to be(true)
    expect(json_response.dig("capabilities", "can_submit_response")).to be(
      false
    )
    expect(json_response.dig("capabilities", "incomplete_issue_ids")).to eq(
      [issue.fetch("id")]
    )

    patch "/api/claims/contractor/invoices/#{invoice.id}/revision_issues/#{issue.fetch("id")}/comment",
          params: {
            contractor_response_method: "explanation_provided",
            comment_text:
              "The abbreviation identifies the installed outdoor unit."
          },
          as: :json
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("capabilities", "can_submit_response")).to be(true)

    post "/api/claims/contractor/invoices/#{invoice.id}/submit_to_admin",
         as: :json
    expect(response).to have_http_status(:ok)
    expect(invoice.reload.status).to eq("admin_review_inbox")

    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues/#{issue.fetch("id")}/close",
         params: {
           status: "closed_via_attestation",
           comment_text:
             "The administrator accepted the explanation as an attestation."
         },
         as: :json
    expect(response).to have_http_status(:ok)
    closed = json_response.fetch("issues").first
    expect(closed.fetch("status")).to eq("closed_via_attestation")
    expect(
      closed.fetch("comments").map { |comment| comment.fetch("author_type") }
    ).to eq(%w[admin contractor admin])
  end

  it "returns issue ids when the contractor tries to submit an incomplete round" do
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues",
         params: {
           issue_type: "rule",
           invoice_version_rulecheck_id: rule.id
         },
         as: :json
    issue = json_response.fetch("issues").first
    issue_id = issue.fetch("id")
    select_recommendation(invoice.id, issue)
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues/send",
         as: :json

    post "/api/claims/contractor/invoices/#{invoice.id}/submit_to_admin",
         as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error_code")).to eq(
      "revision_response_incomplete"
    )
    expect(json_response.fetch("issue_ids")).to eq([issue_id])
  end

  it "continues an open issue without exposing round creation" do
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues",
         params: {
           issue_type: "rule",
           invoice_version_rulecheck_id: rule.id
         },
         as: :json
    issue = json_response.fetch("issues").first
    issue_id = issue.fetch("id")
    select_recommendation(invoice.id, issue)
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues/send",
         as: :json
    patch "/api/claims/contractor/invoices/#{invoice.id}/revision_issues/#{issue_id}/comment",
          params: {
            contractor_response_method: "explanation_provided",
            comment_text: "Here is the requested explanation."
          },
          as: :json
    post "/api/claims/contractor/invoices/#{invoice.id}/submit_to_admin",
         as: :json

    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues/#{issue_id}/comment",
         params: {
           admin_recommended_remedy: "provide_explanation",
           comment_text: "Please clarify one remaining detail."
         },
         as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("rounds").first.fetch("state")).to eq("draft")
    continued_issue = json_response.fetch("issues").first
    expect(
      continued_issue
        .fetch("comments")
        .map { |comment| comment.fetch("author_type") }
    ).to eq(%w[admin contractor admin])
    expect(json_response.dig("capabilities", "can_send_issues")).to be(true)
  end

  it "distinguishes a required corrected-document upload from an incomplete response" do
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues",
         params: {
           issue_type: "rule",
           invoice_version_rulecheck_id: rule.id
         },
         as: :json
    issue = json_response.fetch("issues").first
    issue_id = issue.fetch("id")
    select_recommendation(
      invoice.id,
      issue,
      remedy: "correct_and_reupload_invoice"
    )
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues/send",
         as: :json
    patch "/api/claims/contractor/invoices/#{invoice.id}/revision_issues/#{issue_id}/comment",
          params: {
            contractor_response_method: "corrected_invoice_uploaded",
            comment_text: "A corrected invoice will be uploaded."
          },
          as: :json

    expect(json_response.dig("capabilities", "can_submit_response")).to be(
      false
    )
    expect(
      json_response.dig("capabilities", "document_upload_required_issue_ids")
    ).to eq([issue_id])

    post "/api/claims/contractor/invoices/#{invoice.id}/submit_to_admin",
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error_code")).to eq(
      "revision_document_upload_required"
    )
    expect(json_response.fetch("issue_ids")).to eq([issue_id])
  end

  it "only deletes a new issue that has never been sent" do
    post "/api/claims/admin/invoices/#{invoice.id}/revision_issues",
         params: {
           issue_type: "rule",
           invoice_version_rulecheck_id: rule.id
         },
         as: :json
    issue_id = json_response.fetch("issues").first.fetch("id")

    delete "/api/claims/admin/invoices/#{invoice.id}/revision_issues/#{issue_id}",
           as: :json

    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("issues")).to be_empty
  end
end
