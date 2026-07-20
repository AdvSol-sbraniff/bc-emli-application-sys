require "rails_helper"

RSpec.describe "Claims durable revision issue workflow" do
  def build_package(rule_result: "fail", admin_workflow_policy: "fail_only")
    now = Time.zone.parse("2026-07-15 21:00:00")
    contractor = Contractor.create!(business_name: "Revision Workflow Test")
    session = Claims::Session.create!(created_at: now, updated_at: now)
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "admin_review_inbox",
        status_updated_at: now,
        created_at: now,
        updated_at: now
      )
    version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "revision-test/invoice-v1.pdf",
        original_filename: "Invoice v1.pdf",
        content_type: "application/pdf",
        di_ocr_invoice_id: "INV-100",
        di_ocr_invoice_id_page: 1,
        di_ocr_invoice_id_polygon: [1, 1, 2, 1, 2, 2, 1, 2],
        created_at: now,
        updated_at: now
      )
    upgrade_type =
      Claims::InvoiceUpgradeType.find_or_create_by!(
        upgrade_type_key: "revision_workflow_test"
      ) do |row|
        row.description = "Revision workflow test"
        row.created_at = now
        row.updated_at = now
      end
    rule_key = "revision_test_#{SecureRandom.hex(5)}"
    Claims::GenaiRule.create!(
      genai_rule_key: rule_key,
      contractor_display_name: "Invoice information is complete",
      prompt_text: "Check whether the invoice information is complete.",
      enabled: true,
      source_quote: "Revision workflow test rule.",
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: admin_workflow_policy,
      created_at: now,
      updated_at: now
    )
    rule =
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version_id: version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "genai",
        rule_key: rule_key,
        contractor_display_name: "Invoice information is complete",
        rule_result: rule_result,
        confidence: 91,
        evidence_text: "The invoice number needs confirmation.",
        reason_and_likely_causes: "The printed value is partly obscured.",
        created_at: now,
        updated_at: now
      )
    field =
      Claims::InvoiceVersionLocatedField.create!(
        invoice_version_id: version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "genai",
        field_key: "invoice_reference",
        value_type: "text",
        value_text: "INV-10?",
        confidence: 72,
        page: 1,
        polygon: [1, 1, 3, 1, 3, 2, 1, 2],
        evidence_text: "INV-10?",
        created_at: now,
        updated_at: now
      )
    [invoice, version, rule, field]
  end

  def create_issue(invoice, type, source_id)
    attribute =
      (
        if type == "rule"
          :invoice_version_rulecheck_id
        else
          :invoice_version_located_field_id
        end
      )
    Claims::RevisionIssues::CreateIssue.call(
      invoice: invoice,
      attributes: {
        :issue_type => type,
        attribute => source_id
      }
    )
  end

  def select_recommendation(issue, remedy: "provide_explanation")
    comment = issue.comments.order(:created_at, :id).last
    Claims::RevisionIssues::UpdateAdminComment.call(
      comment: comment,
      attributes: {
        admin_recommended_remedy: remedy,
        comment_text: comment.comment_text
      }
    )
  end

  it "creates the hidden draft exchange when an issue is added" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)

    expect(issue).to be_persisted
    expect(invoice.revision_rounds.count).to eq(1)
    expect(invoice.revision_rounds.first).to be_draft
    expect(issue.comments.count).to eq(1)
    expect(issue.comments.first.admin_recommended_remedy).to be_nil
    expect(issue.comments.first.comment_text).to be_present
  end

  it "requires an admin to select a recommendation before sending" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    round = invoice.revision_rounds.newest_first.first

    expect do
      Claims::RevisionIssues::SendRound.call(
        revision_round: round,
        actor_user_id: nil
      )
    end.to raise_error(
      Claims::RevisionIssues::SendRound::Incomplete,
      /recommendation and comment/
    )

    select_recommendation(issue)
    expect do
      Claims::RevisionIssues::SendRound.call(
        revision_round: round,
        actor_user_id: nil
      )
    end.to change { invoice.reload.status }.to("contractor_revision_inbox")
  end

  it "preserves one issue and ordered comments through multiple rounds" do
    invoice, version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    select_recommendation(issue)
    first_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: first_round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: issue,
      round: first_round,
      attributes: {
        contractor_response_method: "explanation_provided",
        comment_text: "The first explanation needs review."
      }
    )
    Claims::RevisionIssues::SubmitRound.call(
      invoice: invoice,
      actor_user_id: nil,
      invoice_version: version
    )

    Claims::RevisionIssues::SaveAdminComment.call(
      issue: issue,
      attributes: {
        admin_recommended_remedy: "provide_attestation",
        comment_text: "Please provide an attestation for the invoice number."
      }
    )
    second_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: second_round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: issue,
      round: second_round,
      attributes: {
        contractor_response_method: "attestation_provided",
        comment_text: "I attest that the invoice number is INV-100."
      }
    )
    Claims::RevisionIssues::SubmitRound.call(
      invoice: invoice,
      actor_user_id: nil,
      invoice_version: version
    )
    Claims::RevisionIssues::CloseIssue.call(
      issue: issue,
      status: "closed_via_attestation",
      comment_text: "Attestation accepted."
    )

    expect(invoice.revision_issues.count).to eq(1)
    expect(issue.reload.status).to eq("closed_via_attestation")
    expect(issue.comments.pluck(:revision_round_id)).to eq(
      [
        first_round.id,
        first_round.id,
        second_round.id,
        second_round.id,
        second_round.id
      ]
    )
    expect(issue.comments.pluck(:author_type)).to eq(
      %w[admin contractor admin contractor admin]
    )

    tracker =
      Claims::RevisionIssues::SerializeTracker.call(
        invoice: invoice.reload,
        role: :contractor
      )
    expect(
      tracker.fetch(:rounds).map { |round| round.fetch(:round_number) }
    ).to eq([2, 1])
    expect(tracker.fetch(:issues).first.fetch(:comments).length).to eq(5)
  end

  it "keeps closed issues immutable" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    Claims::RevisionIssues::CloseIssue.call(
      issue: issue,
      status: "closed_via_exception",
      comment_text: "Exception granted."
    )
    expect { issue.reload.update!(issue_type: "di_field") }.to raise_error(
      ActiveRecord::RecordInvalid
    )
  end

  it "does not require contractor responses for issues closed by exception before send" do
    invoice, version, rule, field = build_package
    exception_issue = create_issue(invoice, "rule", rule.id)
    requested_issue = create_issue(invoice, "invoice_field", field.id)
    round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::CloseIssue.call(
      issue: exception_issue,
      status: "closed_via_exception",
      comment_text: "The program granted an exception."
    )
    select_recommendation(requested_issue)

    Claims::RevisionIssues::SendRound.call(
      revision_round: round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: requested_issue,
      round: round,
      attributes: {
        contractor_response_method: "attestation_provided",
        contractor_asserted_value: "INV-100",
        comment_text: "I attest that the invoice reference is INV-100."
      }
    )

    expect do
      Claims::RevisionIssues::SubmitRound.call(
        invoice: invoice,
        actor_user_id: nil,
        invoice_version: version
      )
    end.to change { invoice.reload.status }.from(
      "contractor_revision_inbox"
    ).to("admin_review_inbox")
  end

  it "requires newly processed documentation for a corrected-document response" do
    invoice, version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    select_recommendation(issue, remedy: "correct_and_reupload_invoice")
    round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: issue,
      round: round,
      attributes: {
        contractor_response_method: "corrected_invoice_uploaded",
        comment_text: "A corrected invoice was uploaded."
      }
    )
    coverage =
      Claims::RevisionIssues::ContractorResponseCoverage.call(round: round)
    expect(coverage.incomplete_issue_ids).to be_empty
    expect(coverage.document_upload_required_issue_ids).to eq([issue.id])
    expect(coverage.complete?).to be(false)

    expect do
      Claims::RevisionIssues::SubmitRound.call(
        invoice: invoice,
        actor_user_id: nil,
        invoice_version: version
      )
    end.to raise_error(
      Claims::RevisionIssues::SubmitRound::DocumentUploadRequired,
      /newly processed/
    )
  end

  it "uses the rule-level workflow policy when enforcing coverage" do
    invoice, version, _rule, =
      build_package(rule_result: "warn", admin_workflow_policy: "fail_only")
    coverage =
      Claims::RevisionIssues::ReviewCoverage.call(
        invoice: invoice,
        invoice_version: version
      )
    expect(coverage.missing_rulechecks).to be_empty

    managed_invoice, managed_version, managed_rule, =
      build_package(rule_result: "warn", admin_workflow_policy: "warn_and_fail")
    managed_coverage =
      Claims::RevisionIssues::ReviewCoverage.call(
        invoice: managed_invoice,
        invoice_version: managed_version
      )
    expect(managed_coverage.missing_rulechecks.map(&:id)).to eq(
      [managed_rule.id]
    )
  end

  it "removes an empty hidden draft after its only unsent issue is deleted" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    Claims::RevisionIssues::DeleteUnsentIssue.call(issue: issue)
    expect(invoice.revision_rounds.reload).to be_empty
    expect(invoice.revision_issues.reload).to be_empty
  end

  it "continues the same open issue when the admin saves another comment" do
    invoice, version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    select_recommendation(issue)
    first_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: first_round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: issue,
      round: first_round,
      attributes: {
        contractor_response_method: "explanation_provided",
        comment_text: "Please review this explanation."
      }
    )
    Claims::RevisionIssues::SubmitRound.call(
      invoice: invoice,
      actor_user_id: nil,
      invoice_version: version
    )

    Claims::RevisionIssues::SaveAdminComment.call(
      issue: issue,
      attributes: {
        admin_recommended_remedy: "provide_explanation",
        comment_text: "Please clarify the remaining ambiguity."
      }
    )
    second_round = invoice.revision_rounds.newest_first.first
    carried_comment =
      issue.comments.find_by(revision_round: second_round, author_type: "admin")

    expect(carried_comment).to be_present
    expect do
      Claims::RevisionIssues::DeleteUnsentIssue.call(issue: issue)
    end.to raise_error(
      ActiveRecord::ReadOnlyRecord,
      /already sent cannot be deleted/
    )
    expect(issue.reload).to be_open
  end

  it "closes one response while another issue continues in the next exchange" do
    invoice, version, rule, field = build_package
    continued_issue = create_issue(invoice, "rule", rule.id)
    closed_issue = create_issue(invoice, "invoice_field", field.id)
    select_recommendation(continued_issue)
    select_recommendation(closed_issue)
    response_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: response_round,
      actor_user_id: nil
    )
    [continued_issue, closed_issue].each do |issue|
      Claims::RevisionIssues::SaveContractorComment.call(
        issue: issue,
        round: response_round,
        attributes: {
          contractor_response_method: "explanation_provided",
          comment_text: "Please review this response."
        }
      )
    end
    Claims::RevisionIssues::SubmitRound.call(
      invoice: invoice,
      actor_user_id: nil,
      invoice_version: version
    )

    Claims::RevisionIssues::SaveAdminComment.call(
      issue: continued_issue,
      attributes: {
        admin_recommended_remedy: "provide_explanation",
        comment_text: "Please provide one more detail."
      }
    )
    follow_up_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::CloseIssue.call(
      issue: closed_issue,
      status: "closed_via_exception",
      comment_text: "The explanation is accepted as an exception."
    )

    expect(closed_issue.reload).to be_closed
    expect(closed_issue.comments.last.revision_round_id).to eq(
      response_round.id
    )
    expect(follow_up_round.reload).to be_draft
    expect(follow_up_round.comments.pluck(:revision_issue_id)).to eq(
      [continued_issue.id]
    )
    expect do
      Claims::RevisionIssues::SendRound.call(
        revision_round: follow_up_round,
        actor_user_id: nil
      )
    end.to change { invoice.reload.status }.to("contractor_revision_inbox")
  end

  it "deletes a brand-new issue that has never been sent" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)

    expect do
      Claims::RevisionIssues::DeleteUnsentIssue.call(issue: issue)
    end.to change { invoice.revision_issues.count }.from(1).to(0)
  end

  it "refuses to send if an open issue has no admin follow-up" do
    invoice, version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    select_recommendation(issue)
    first_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: first_round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: issue,
      round: first_round,
      attributes: {
        contractor_response_method: "explanation_provided",
        comment_text: "Please review this explanation."
      }
    )
    Claims::RevisionIssues::SubmitRound.call(
      invoice: invoice,
      actor_user_id: nil,
      invoice_version: version
    )
    Claims::RevisionIssues::SaveAdminComment.call(
      issue: issue,
      attributes: {
        admin_recommended_remedy: "provide_explanation",
        comment_text: "Please provide a further explanation."
      }
    )
    second_round = invoice.revision_rounds.newest_first.first
    second_round.comments.destroy_all

    expect do
      Claims::RevisionIssues::SendRound.call(
        revision_round: second_round,
        actor_user_id: nil
      )
    end.to raise_error(
      Claims::RevisionIssues::SendRound::Incomplete,
      /Every open issue needs an admin recommendation/
    )
  end

  it "blocks four-eyes review until every issue is closed" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    blocked = Claims::RevisionIssues::ApprovalGate.call(invoice: invoice)
    expect(blocked.allowed).to be(false)
    expect(blocked.issue_ids).to eq([issue.id])

    Claims::RevisionIssues::CloseIssue.call(
      issue: issue,
      status: "closed_as_withdrawn",
      comment_text: "The rule result was withdrawn after admin review."
    )
    expect(
      Claims::RevisionIssues::ApprovalGate.call(invoice: invoice).allowed
    ).to be(true)
  end
end
