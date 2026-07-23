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
      contractor_action:
        "Check the invoice and upload a corrected copy if needed.",
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
    expect(issue).to be_pending_admin_review
    expect(issue.opened_from_rule_key).to eq(rule.rule_key)
    expect(issue.opened_from_rule_upgrade_type_id).to eq(
      rule.invoice_upgrade_type_id
    )
    expect(issue.opened_from_source_snapshot).to include(
      "friendly_label" => "Invoice information is complete",
      "source_quote" => "Revision workflow test rule.",
      "contractor_action" =>
        "Check the invoice and upload a corrected copy if needed."
    )
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
    expect(issue.reload).to be_open
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
      disposition_comment: "Attestation accepted."
    )

    expect(invoice.revision_issues.count).to eq(1)
    expect(issue.reload.status).to eq("closed_via_attestation")
    expect(issue.disposition_comment).to eq("Attestation accepted.")
    expect(issue.comments.pluck(:revision_round_id)).to eq(
      [first_round.id, first_round.id, second_round.id, second_round.id]
    )
    expect(issue.comments.pluck(:author_type)).to eq(
      %w[admin contractor admin contractor]
    )

    tracker =
      Claims::RevisionIssues::SerializeTracker.call(
        invoice: invoice.reload,
        role: :contractor
      )
    expect(
      tracker.fetch(:rounds).map { |round| round.fetch(:round_number) }
    ).to eq([2, 1])
    expect(tracker.fetch(:issues).first.fetch(:comments).length).to eq(4)
    expect(tracker.fetch(:issues).first.fetch(:disposition_comment)).to eq(
      "Attestation accepted."
    )
  end

  it "keeps closed issues immutable" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    Claims::RevisionIssues::CloseIssue.call(
      issue: issue,
      status: "closed_no_contractor_action_required",
      disposition_comment: "No contractor action is required."
    )
    expect { issue.reload.update!(issue_type: "di_field") }.to raise_error(
      ActiveRecord::RecordInvalid
    )
  end

  it "rejects contractor-facing dispositions before an issue is sent" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)

    expect do
      Claims::RevisionIssues::CloseIssue.call(
        issue: issue,
        status: "closed_via_exception",
        disposition_comment: "An exception was granted."
      )
    end.to raise_error(
      ActiveRecord::RecordInvalid,
      /must be no contractor action required/
    )
  end

  it "requires a disposition comment when closing an issue" do
    invoice, _version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)

    expect do
      Claims::RevisionIssues::CloseIssue.call(
        issue: issue,
        status: "closed_no_contractor_action_required",
        disposition_comment: "  "
      )
    end.to raise_error(
      ActiveRecord::RecordInvalid,
      /disposition comment is required/i
    )
    expect(issue.reload).to be_pending_admin_review
  end

  it "rejects the internal-only disposition after an issue is sent" do
    invoice, version, rule, = build_package
    issue = create_issue(invoice, "rule", rule.id)
    select_recommendation(issue)
    round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: issue,
      round: round,
      attributes: {
        contractor_response_method: "explanation_provided",
        comment_text: "The requested explanation is provided."
      }
    )
    Claims::RevisionIssues::SubmitRound.call(
      invoice: invoice,
      actor_user_id: nil,
      invoice_version: version
    )

    expect do
      Claims::RevisionIssues::CloseIssue.call(
        issue: issue,
        status: "closed_no_contractor_action_required",
        disposition_comment: "No contractor action was required."
      )
    end.to raise_error(
      ActiveRecord::RecordInvalid,
      /unavailable after an issue has been sent/
    )
  end

  it "keeps an internally closed work item out of the contractor tracker" do
    invoice, version, rule, field = build_package
    exception_issue = create_issue(invoice, "rule", rule.id)
    requested_issue = create_issue(invoice, "invoice_field", field.id)
    round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::CloseIssue.call(
      issue: exception_issue,
      status: "closed_no_contractor_action_required",
      disposition_comment: "The result was confirmed during admin review."
    )
    select_recommendation(requested_issue)

    Claims::RevisionIssues::SendRound.call(
      revision_round: round,
      actor_user_id: nil
    )
    contractor_tracker =
      Claims::RevisionIssues::SerializeTracker.call(
        invoice: invoice.reload,
        role: :contractor
      )
    expect(
      contractor_tracker.fetch(:issues).map { |row| row.fetch(:id) }
    ).to eq([requested_issue.id])
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
    required_results = {
      "not_managed" => [],
      "fail_only" => %w[fail],
      "warn_and_fail" => %w[warn fail],
      "all_results" => %w[pass info warn fail]
    }

    required_results.each do |policy, required|
      %w[pass info warn fail].each do |result|
        invoice, version, rule, =
          build_package(rule_result: result, admin_workflow_policy: policy)
        coverage =
          Claims::RevisionIssues::ReviewCoverage.call(
            invoice: invoice,
            invoice_version: version
          )

        expected = required.include?(result) ? [rule.id] : []
        expect(coverage.missing_rulechecks.map(&:id)).to eq(expected)
      end
    end
  end

  it "creates required rule issues only after the current package reaches the admin inbox" do
    invoice, version, rule, field = build_package
    invoice.update_columns(
      status: "genai_complete",
      status_updated_at: Time.current,
      updated_at: Time.current
    )

    expect do
      Claims::RevisionIssues::EnsureManagedIssues.call(
        invoice: invoice,
        invoice_version: version
      )
    end.to raise_error(
      Claims::RevisionIssues::EnsureManagedIssues::WrongInvoiceStatus,
      /handed to the admin inbox/
    )
    expect(invoice.revision_issues).to be_empty

    invoice.set_workflow_status!(
      "admin_review_inbox",
      invoice_version_id: version.id
    )
    result =
      Claims::RevisionIssues::EnsureManagedIssues.call(
        invoice: invoice,
        invoice_version: version
      )

    issue = invoice.revision_issues.reload.sole
    expect(result.created_issue_ids).to eq([issue.id])
    expect(issue).to be_pending_admin_review
    expect(issue.opened_from_invoice_version_rulecheck_id).to eq(rule.id)
    expect(issue.opened_from_rule_key).to eq(rule.rule_key)
    expect(issue.opened_from_rule_upgrade_type_id).to eq(
      rule.invoice_upgrade_type_id
    )
    expect(issue.opened_from_invoice_version_located_field_id).to be_nil
    expect(field).to be_persisted
  end

  it "ensures managed rule issues idempotently without reopening a closed issue" do
    invoice, version, = build_package

    first =
      Claims::RevisionIssues::EnsureManagedIssues.call(
        invoice: invoice,
        invoice_version: version
      )
    second =
      Claims::RevisionIssues::EnsureManagedIssues.call(
        invoice: invoice,
        invoice_version: version
      )

    expect(first.created_issue_ids.length).to eq(1)
    expect(second.created_issue_ids).to be_empty
    expect(invoice.revision_issues.count).to eq(1)
    expect(invoice.revision_rounds.count).to eq(1)
    expect(invoice.revision_issues.first.comments.count).to eq(1)

    issue = invoice.revision_issues.first
    Claims::RevisionIssues::CloseIssue.call(
      issue: issue,
      status: "closed_no_contractor_action_required",
      disposition_comment: "The managed result was confirmed internally."
    )
    third =
      Claims::RevisionIssues::EnsureManagedIssues.call(
        invoice: invoice,
        invoice_version: version
      )

    expect(third.created_issue_ids).to be_empty
    expect(invoice.revision_issues.count).to eq(1)
    expect(issue.reload).to be_closed
  end

  it "creates distinct managed issues for the same rule in different upgrade contexts" do
    invoice, version, rule, = build_package
    second_upgrade_type =
      Claims::InvoiceUpgradeType.create!(
        upgrade_type_key: "revision_context_#{SecureRandom.hex(5)}",
        description: "Second revision context"
      )
    second_rulecheck =
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version: version,
        invoice_upgrade_type_id: second_upgrade_type.id,
        source_engine: rule.source_engine,
        rule_key: rule.rule_key,
        contractor_display_name: rule.contractor_display_name,
        rule_result: "fail",
        confidence: 90,
        reason_and_likely_causes: "The same check failed in another context."
      )

    Claims::RevisionIssues::EnsureManagedIssues.call(
      invoice: invoice,
      invoice_version: version
    )

    expect(invoice.revision_issues.count).to eq(2)
    expect(
      invoice.revision_issues.pluck(:opened_from_rule_upgrade_type_id).to_set
    ).to eq(
      [
        rule.invoice_upgrade_type_id,
        second_rulecheck.invoice_upgrade_type_id
      ].to_set
    )
  end

  it "ensures newly managed rules when a later package is handed back to admins" do
    invoice, first_version, first_rule, = build_package
    existing_issue = create_issue(invoice, "rule", first_rule.id)
    select_recommendation(existing_issue)
    sent_round = invoice.revision_rounds.newest_first.first
    Claims::RevisionIssues::SendRound.call(
      revision_round: sent_round,
      actor_user_id: nil
    )
    Claims::RevisionIssues::SaveContractorComment.call(
      issue: existing_issue,
      round: sent_round,
      attributes: {
        contractor_response_method: "explanation_provided",
        comment_text: "The contractor supplied the requested explanation."
      }
    )

    second_version =
      Claims::InvoiceVersion.create!(
        invoice: invoice,
        invoice_versionno: 2,
        storage_provider: "azure_blob",
        storage_key: "revision-test/invoice-v2.pdf",
        original_filename: "Invoice v2.pdf",
        content_type: "application/pdf"
      )
    new_rule_key = "revision_new_after_fix_#{SecureRandom.hex(5)}"
    Claims::GenaiRule.create!(
      genai_rule_key: new_rule_key,
      contractor_display_name: "Review newly detected information",
      prompt_text: "Review the newly detected information.",
      enabled: true,
      source_quote: "New rule after a package correction.",
      contractor_visibility: "hidden",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "all_results"
    )
    new_rulecheck =
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version: second_version,
        invoice_upgrade_type_id: first_rule.invoice_upgrade_type_id,
        source_engine: "genai",
        rule_key: new_rule_key,
        contractor_display_name: "Review newly detected information",
        rule_result: "pass",
        confidence: 95,
        reason_and_likely_causes:
          "The corrected package exposed new information."
      )

    expect do
      Claims::RevisionIssues::SubmitRound.call(
        invoice: invoice,
        actor_user_id: nil,
        invoice_version: second_version
      )
    end.to change { invoice.revision_issues.count }.from(1).to(2)

    new_issue =
      invoice.revision_issues.find_by!(
        opened_from_invoice_version_rulecheck_id: new_rulecheck.id
      )
    expect(new_issue).to be_pending_admin_review
    expect(invoice.reload.status).to eq("admin_review_inbox")
    expect(invoice.revision_rounds.newest_first.first.invoice_version_id).to eq(
      second_version.id
    )
    expect(first_version).to be_persisted
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
      disposition_comment: "The explanation is accepted as an exception."
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
      /Every unresolved issue needs an admin recommendation/
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
      status: "closed_no_contractor_action_required",
      disposition_comment:
        "The rule result requires no contractor action after admin review."
    )
    expect(
      Claims::RevisionIssues::ApprovalGate.call(invoice: invoice).allowed
    ).to be(true)
  end
end
