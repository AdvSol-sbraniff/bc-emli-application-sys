require "rails_helper"

RSpec.describe "Claims rule improvement reporting", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  before do
    host! "localhost"
    allow_any_instance_of(
      Api::Claims::ReportsRuleImprovementController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(
      Api::Claims::InvoiceVersionRulechecksAdminController
    ).to receive(:require_claims_admin!)
    allow_any_instance_of(Api::ApplicationController).to receive(
      :authenticate_user!
    )
    allow_any_instance_of(Api::ApplicationController).to receive(
      :require_confirmation
    )
  end

  it "uses the claims configuration permission boundary" do
    expect(
      Api::Claims::ReportsRuleImprovementController.required_claims_function_key
    ).to eq("claims.configuration")
  end

  it "persists structured reason feedback and enforces its shape" do
    package = build_package
    original_version_count = Claims::InvoiceVersion.count
    original_issue_count = Claims::RevisionIssue.count

    patch(
      "/api/claims/admin/invoice_version_rulechecks/#{package[:rulecheck].id}/reason_complaint",
      params: {
        reason_complaint_code: "too_vague",
        reason_complaint_text: "Name the missing evidence."
      },
      as: :json
    )

    expect(response).to have_http_status(:ok)
    expect(json_response).to include(
      "reason_complaint_code" => "too_vague",
      "reason_complaint_text" => "Name the missing evidence."
    )
    expect(package[:rulecheck].reload.reason_complaint_code).to eq("too_vague")

    patch(
      "/api/claims/admin/invoice_version_rulechecks/#{package[:rulecheck].id}/reason_complaint",
      params: {
        reason_complaint_code: "other",
        reason_complaint_text: ""
      },
      as: :json
    )

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.fetch("error")).to match(/required for Other/)

    Claims::InvoiceVersionRulecheck::REASON_COMPLAINT_CODES.each do |code|
      package[:rulecheck].update!(
        reason_complaint_code: code,
        reason_complaint_text: code == "other" ? "Other useful detail." : nil
      )
    end

    patch(
      "/api/claims/admin/invoice_version_rulechecks/#{package[:rulecheck].id}/reason_complaint",
      params: {
        reason_complaint_code: "not_a_real_category"
      },
      as: :json
    )
    expect(response).to have_http_status(:unprocessable_entity)

    patch(
      "/api/claims/admin/invoice_version_rulechecks/#{package[:rulecheck].id}/reason_complaint",
      params: {
        reason_complaint_code: nil,
        reason_complaint_text: nil
      },
      as: :json
    )
    expect(response).to have_http_status(:ok)
    expect(package[:rulecheck].reload.reason_complaint_code).to be_nil
    expect(package[:rulecheck].reason_complaint_text).to be_nil
    expect(Claims::InvoiceVersion.count).to eq(original_version_count)
    expect(Claims::RevisionIssue.count).to eq(original_issue_count)

    patch(
      "/api/claims/admin/invoice_version_rulechecks/#{SecureRandom.uuid}/reason_complaint",
      params: {
        reason_complaint_code: "too_vague"
      },
      as: :json
    )
    expect(response).to have_http_status(:not_found)
  end

  it "answers prioritization and investigation questions from one read model" do
    package =
      build_package(
        complaint_code: "required_action_unclear",
        complaint_text: "This complaint belongs to the previous rule version."
      )
    package[:rule].update!(
      prompt_text: "Check the evidence and cite the exact missing item."
    )
    current_time = package[:rule].reload.updated_at + 1.minute
    false_positive =
      add_rulecheck(
        package: package,
        version_number: 2,
        result: "fail",
        created_at: current_time,
        complaint_code: "required_action_unclear",
        complaint_text: "Say exactly what the contractor must upload."
      )
    false_positive_issue =
      add_issue(
        package: package,
        rulecheck: false_positive,
        status: "closed_no_contractor_action_required",
        disposition_comment: "The evidence was already sufficient."
      )
    add_sent_round(
      issue: false_positive_issue,
      invoice_version: false_positive.invoice_version,
      round_number: 1,
      sent_at: current_time + 1.minute
    )
    second_session =
      Claims::Session.create!(
        created_at: current_time,
        updated_at: current_time
      )
    second_invoice =
      Claims::Invoice.create!(
        session_id: second_session.id,
        contractor_id: package[:contractor].id,
        status: "admin_review_inbox",
        status_updated_at: current_time,
        created_at: current_time,
        updated_at: current_time
      )
    false_negative =
      add_rulecheck(
        package: package,
        invoice: second_invoice,
        version_number: 1,
        result: "pass",
        created_at: current_time + 1.minute
      )
    false_negative_issue =
      add_issue(
        package: package,
        rulecheck: false_negative,
        status: "closed_via_corrected_documentation",
        disposition_comment: "The contractor supplied the missing page."
      )
    add_sent_round(
      issue: false_negative_issue,
      invoice_version: false_negative.invoice_version,
      round_number: 1,
      sent_at: current_time + 2.minutes
    )
    add_sent_round(
      issue: false_negative_issue,
      invoice_version: false_negative.invoice_version,
      round_number: 2,
      sent_at: current_time + 4.minutes,
      contractor_method: "unable_to_resolve"
    )
    draft_round =
      Claims::RevisionRound.create!(
        invoice_id: false_negative_issue.invoice_id,
        invoice_version_id: false_negative.invoice_version_id,
        round_number: 3,
        created_at: current_time + 6.minutes,
        updated_at: current_time + 6.minutes
      )
    Claims::RevisionIssueComment.create!(
      revision_issue_id: false_negative_issue.id,
      revision_round_id: draft_round.id,
      author_type: "admin",
      admin_recommended_remedy: "provide_explanation",
      comment_text: "This draft request was never sent.",
      created_at: current_time + 6.minutes,
      updated_at: current_time + 6.minutes
    )
    Claims::RevisionIssueComment.create!(
      revision_issue_id: false_negative_issue.id,
      revision_round_id: draft_round.id,
      author_type: "contractor",
      contractor_response_method: "explanation_provided",
      comment_text: "This draft response was never submitted.",
      created_at: current_time + 6.minutes,
      updated_at: current_time + 6.minutes
    )

    get(
      "/api/claims/admin/reports/rule_improvement",
      params: {
        minimum_sample_size: 1
      }
    )
    expect(response).to have_http_status(:ok)
    row =
      json_response
        .fetch("rows")
        .find do |candidate|
          candidate.fetch("rule_key") == package[:rule].genai_rule_key
        end
    expect(row).to include(
      "source_engine" => "genai",
      "check_count" => 2,
      "invoice_count" => 2,
      "complaint_count" => 1,
      "workflow_issue_count" => 2,
      "follow_up_invoice_count" => 2,
      "no_action_count" => 1,
      "candidate_false_positive_count" => 1,
      "candidate_false_negative_count" => 1,
      "total_round_count" => 3,
      "repeat_round_count" => 1,
      "average_rounds" => 1.5,
      "median_rounds" => 1.5,
      "attention_signal" => "rule_review"
    )
    expect(Time.zone.parse(row.fetch("current_effective_at"))).to be >
      package[:rulecheck].created_at

    get(
      "/api/claims/admin/reports/rule_improvement/summary",
      params: {
        minimum_sample_size: 1
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("signal_counts", "rule_review")).to be >= 1
    expect(json_response.dig("options", "complaint_codes")).to include(
      "required_action_unclear"
    )

    rule_path =
      "/api/claims/admin/reports/rule_improvement/genai/#{package[:rule].genai_rule_key}"
    get(rule_path, params: { minimum_sample_size: 1 })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("rule", "attention_label")).to eq(
      "Review rule applicability"
    )
    expect(json_response.dig("breakdowns", "complaint_types")).to include(
      "value" => "required_action_unclear",
      "count" => 1
    )
    expect(json_response.dig("breakdowns", "closure_types")).to contain_exactly(
      { "value" => "closed_no_contractor_action_required", "count" => 1 },
      { "value" => "closed_via_corrected_documentation", "count" => 1 }
    )
    expect(
      json_response.dig("breakdowns", "admin_requests")
    ).to contain_exactly(
      { "value" => "upload_supporting_document", "count" => 3 }
    )
    expect(
      json_response.dig("breakdowns", "contractor_responses")
    ).to contain_exactly(
      { "value" => "supporting_document_uploaded", "count" => 2 },
      { "value" => "unable_to_resolve", "count" => 1 }
    )

    get("#{rule_path}/timeline", params: { minimum_sample_size: 1 })
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("milestones").length).to eq(1)
    expect(
      json_response.dig("milestones", 0, "changed_fields").pluck("field")
    ).to include("definition_text")
    expect(json_response.fetch("periods").length).to eq(2)
    expect(json_response.fetch("periods").pluck("label")).to eq(
      ["Initial version", "Revision 1"]
    )
    expect(json_response.dig("periods", 0, "metrics", "invoice_count")).to eq(1)
    expect(json_response.dig("periods", 1, "metrics", "invoice_count")).to eq(2)

    get("#{rule_path}/evidence", params: { evidence_type: "complaints" })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(1)
    expect(json_response.dig("rows", 0, "rulecheck_id")).to eq(
      false_positive.id
    )
    expect(json_response.dig("rows", 0, "reason_complaint_code")).to eq(
      "required_action_unclear"
    )

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "complaints",
        evidence_complaint_code: "required_action_unclear"
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(1)
    expect(json_response.dig("meta", "evidence_complaint_code")).to eq(
      "required_action_unclear"
    )

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "complaints",
        evidence_complaint_code: "too_vague"
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(0)

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "complaints",
        evidence_complaint_code: "not_a_category"
      }
    )
    expect(response).to have_http_status(:unprocessable_entity)

    get("#{rule_path}/evidence", params: { evidence_type: "false_positives" })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("rows", 0, "rulecheck_id")).to eq(
      false_positive.id
    )
    expect(json_response.dig("meta", "total")).to eq(1)

    get("#{rule_path}/evidence", params: { evidence_type: "false_negatives" })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("rows", 0, "rulecheck_id")).to eq(
      false_negative.id
    )
    expect(json_response.dig("meta", "total")).to eq(1)

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "contractor_follow_up"
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(2)
    expect(json_response.dig("rows", 0, "sent_round_count")).to eq(2)
    expect(json_response.fetch("rows").pluck("sent_round_count").max).to eq(2)

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "contractor_follow_up",
        minimum_sent_rounds: 2
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(1)
    expect(json_response.dig("meta", "minimum_sent_rounds")).to eq(2)
    expect(json_response.dig("rows", 0, "rulecheck_id")).to eq(
      false_negative.id
    )

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "contractor_follow_up",
        minimum_sent_rounds: 3
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(0)

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "contractor_follow_up",
        minimum_sent_rounds: 0
      }
    )
    expect(response).to have_http_status(:unprocessable_entity)

    get("#{rule_path}/evidence", params: { evidence_type: "closure_outcomes" })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(2)
    expect(
      json_response.fetch("rows").pluck("revision_issue_status")
    ).to contain_exactly(
      "closed_no_contractor_action_required",
      "closed_via_corrected_documentation"
    )

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "closure_outcomes",
        evidence_closure_outcome: "closed_no_contractor_action_required"
      }
    )
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(1)
    expect(json_response.dig("rows", 0, "rulecheck_id")).to eq(
      false_positive.id
    )

    get(
      "#{rule_path}/evidence",
      params: {
        evidence_type: "closure_outcomes",
        evidence_closure_outcome: "open"
      }
    )
    expect(response).to have_http_status(:unprocessable_entity)
    expect(false_positive_issue).to be_closed
  end

  it "includes every workflow outcome in false-negative counts and evidence" do
    package = build_package
    checked_at = package[:rule].reload.updated_at + 1.minute
    candidates =
      %w[pass info]
        .product(Claims::RevisionIssue::STATUSES)
        .map do |result, status|
          invoice =
            Claims::Invoice.create!(
              session_id: Claims::Session.create!.id,
              contractor_id: package[:contractor].id,
              status: "admin_review_inbox",
              status_updated_at: checked_at
            )
          rulecheck =
            add_rulecheck(
              package: package,
              invoice: invoice,
              version_number: 1,
              result: result,
              created_at: checked_at
            )
          add_issue(
            package: package,
            rulecheck: rulecheck,
            status: status,
            disposition_comment:
              (
                if Claims::RevisionIssue::UNRESOLVED_STATUSES.include?(status)
                  nil
                else
                  "Recorded workflow outcome."
                end
              )
          )
          rulecheck.id
        end

    # A linked fail and pass/info checks without an issue are not candidates.
    add_issue(
      package: package,
      rulecheck: package[:rulecheck],
      status: "open",
      disposition_comment: nil
    )
    %w[pass info].each_with_index do |result, index|
      add_rulecheck(
        package: package,
        version_number: index + 2,
        result: result,
        created_at: checked_at
      )
    end

    rule_path =
      "/api/claims/admin/reports/rule_improvement/genai/#{package[:rule].genai_rule_key}"
    get(rule_path)
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("rule", "candidate_false_negative_count")).to eq(
      candidates.length
    )

    get("#{rule_path}/evidence", params: { evidence_type: "false_negatives" })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("meta", "total")).to eq(candidates.length)
    expect(json_response.fetch("rows").pluck("rulecheck_id")).to match_array(
      candidates
    )
  end

  it "counts distinct invoices for signal percentages across versions and workflow selections" do
    package = build_package(complaint_code: "too_vague")
    checked_at = package[:rule].reload.updated_at + 1.minute
    add_rulecheck(
      package: package,
      version_number: 2,
      result: "fail",
      created_at: checked_at,
      complaint_code: "too_vague"
    )
    add_rulecheck(
      package: package,
      version_number: 3,
      result: "warn",
      created_at: checked_at + 1.minute,
      complaint_code: "unclear_or_confusing"
    )
    add_rulecheck(
      package: package,
      version_number: 4,
      result: "fail",
      created_at: checked_at + 2.minutes,
      complaint_code: "other",
      complaint_text: "A different concern on an invoice already counted."
    )
    issue =
      add_issue(
        package: package,
        rulecheck: package[:rulecheck],
        status: "closed_no_contractor_action_required",
        disposition_comment: "The evidence was sufficient."
      )
    3.times do |index|
      response_comment =
        add_sent_round(
          issue: issue,
          invoice_version: package[:version],
          round_number: index + 1,
          sent_at: checked_at + (index + 2).minutes
        )
      if index == 1
        response_comment
          .revision_round
          .comments
          .find_by!(author_type: "admin")
          .update!(admin_recommended_remedy: "correct_and_reupload_invoice")
      end
    end

    other_invoice =
      Claims::Invoice.create!(
        session_id: Claims::Session.create!.id,
        contractor_id: package[:contractor].id,
        status: "admin_review_inbox",
        status_updated_at: checked_at
      )
    other_check =
      add_rulecheck(
        package: package,
        invoice: other_invoice,
        version_number: 1,
        result: "pass",
        created_at: checked_at,
        complaint_code: "other",
        complaint_text: "This invoice has only an Other complaint."
      )
    add_issue(
      package: package,
      rulecheck: other_check,
      status: "closed_as_withdrawn",
      disposition_comment: "Invoice withdrawn."
    )
    build_package(complaint_code: "too_vague") # Unrelated rule is outside the denominator.

    rule_path =
      "/api/claims/admin/reports/rule_improvement/genai/#{package[:rule].genai_rule_key}"
    get(rule_path)
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("rule", "check_count")).to eq(5)
    expect(json_response.dig("rule", "complaint_count")).to eq(5)
    expect(json_response.dig("rule", "total_round_count")).to eq(3)
    coverage = json_response.dig("rule", "invoice_coverage")
    expect(coverage.fetch("total_invoice_count")).to eq(2)
    expect(coverage.fetch("signal_invoice_counts")).to include(
      "checks" => 2,
      "versions" => 2,
      "complaints" => 2,
      "complaint:too_vague" => 1,
      "complaint:unclear_or_confusing" => 1,
      "complaint:required_action_unclear" => 0,
      "complaint:other" => 2,
      "explanation_complaints" => 2,
      "false_positive" => 1,
      "false_negative" => 1,
      "closure:closed_no_contractor_action_required" => 1,
      "closure:closed_as_withdrawn" => 1,
      "result:pass" => 1,
      "result:fail" => 1,
      "result:warn" => 1,
      "result:info" => 0,
      "workflow_issues" => 2,
      "closed" => 2,
      "open" => 0,
      "follow_up" => 2,
      "sent_issues" => 1,
      "multi_round" => 1,
      "total_rounds" => 1,
      "repeat_rounds" => 1,
      "admin_requests:upload_supporting_document" => 1,
      "admin_requests:correct_and_reupload_invoice" => 1,
      "contractor_responses:supporting_document_uploaded" => 1,
      "document_requests" => 1
    )

    get(rule_path, params: { reason_complaint_code: "too_vague" })
    expect(response).to have_http_status(:ok)
    expect(
      json_response.dig("rule", "invoice_coverage", "total_invoice_count")
    ).to eq(1)

    package[:rule].update!(
      prompt_text: "A new rule definition with no evaluations yet."
    )
    get(rule_path)
    expect(response).to have_http_status(:ok)
    coverage = json_response.dig("rule", "invoice_coverage")
    expect(coverage.fetch("total_invoice_count")).to eq(0)
    expect(coverage.fetch("signal_invoice_counts").values).to all(eq(0))
  end

  it "reports each code-rule record as one executable implementation" do
    package = build_package
    implementation_started_at = package[:rule].created_at + 1.minute
    code_rule =
      Claims::CodeRule.create!(
        code_rule_key: "reporting_code_rule_#{SecureRandom.hex(5)}",
        contractor_display_name: "Required coded evidence",
        description: "Check required evidence using deterministic code.",
        enabled: true,
        source_quote: "Test coded requirement.",
        contractor_action: "Provide the required coded evidence.",
        contractor_visibility: "warn_and_fail",
        contractor_blocking_policy: "non_blocking",
        admin_workflow_policy: "warn_and_fail",
        created_at: implementation_started_at,
        updated_at: implementation_started_at
      )
    Claims::CodeRuleUpgradeType.create!(
      code_rule: code_rule,
      invoice_upgrade_type: package[:upgrade_type]
    )
    rulecheck =
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version_id: package[:version].id,
        invoice_upgrade_type_id: package[:upgrade_type].id,
        source_engine: "code",
        rule_key: code_rule.code_rule_key,
        contractor_display_name: code_rule.contractor_display_name,
        rule_result: "warn",
        reason_and_likely_causes: "The coded evidence check raised a warning.",
        created_at: implementation_started_at + 1.minute,
        updated_at: implementation_started_at + 1.minute
      )
    issue =
      add_issue(
        package: package,
        rulecheck: rulecheck,
        status: "closed_no_contractor_action_required",
        disposition_comment: "The coded evidence was already present."
      )
    code_rule.update!(
      contractor_display_name: "Required coded invoice evidence"
    )

    get(
      "/api/claims/admin/reports/rule_improvement",
      params: {
        minimum_sample_size: 1
      }
    )
    expect(response).to have_http_status(:ok)
    row =
      json_response
        .fetch("rows")
        .find do |candidate|
          candidate.fetch("rule_key") == code_rule.code_rule_key
        end
    expect(row).to include(
      "record_type" => "code_rule",
      "source_engine" => "code",
      "contractor_display_name" => "Required coded invoice evidence",
      "check_count" => 1,
      "candidate_false_positive_count" => 1
    )
    expect(Time.zone.parse(row.fetch("current_effective_at"))).to be_within(
      1.second
    ).of(implementation_started_at)

    rule_path =
      "/api/claims/admin/reports/rule_improvement/code/#{code_rule.code_rule_key}"
    get(rule_path, params: { minimum_sample_size: 1 })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("breakdowns", "closure_types")).to contain_exactly(
      { "value" => "closed_no_contractor_action_required", "count" => 1 }
    )

    get("#{rule_path}/timeline", params: { minimum_sample_size: 1 })
    expect(response).to have_http_status(:ok)
    expect(json_response.fetch("periods")).to contain_exactly(
      include(
        "label" => "Code implementation record",
        "period_end" => nil,
        "metrics" => include("invoice_count" => 1)
      )
    )
    expect(json_response.fetch("milestones").length).to eq(1)
    expect(json_response.fetch("tracking_note")).to match(
      /source code.*configuration changes only/i
    )

    get("#{rule_path}/evidence", params: { evidence_type: "false_positives" })
    expect(response).to have_http_status(:ok)
    expect(json_response.dig("rows", 0, "rulecheck_id")).to eq(rulecheck.id)
    expect(json_response.dig("rows", 0, "invoice_reference_number")).to eq(
      package[:invoice].reload.reference_number
    )
    expect(issue).to be_closed
  end

  it "rejects invalid filters and scopes detail by engine and key" do
    get(
      "/api/claims/admin/reports/rule_improvement/summary",
      params: {
        source_engine: "unknown"
      }
    )
    expect(response).to have_http_status(:unprocessable_entity)

    get(
      "/api/claims/admin/reports/rule_improvement/summary",
      params: {
        date_from: "2026-10-01",
        date_to: "2026-09-01"
      }
    )
    expect(response).to have_http_status(:unprocessable_entity)

    get("/api/claims/admin/reports/rule_improvement/code/no_such_rule")
    expect(response).to have_http_status(:not_found)
  end

  describe "pre-check package metrics" do
    it "keeps the first-submission failure even after a successful refresh and resubmission" do
      package = build_package
      at = package[:rulecheck].created_at
      record_submission(package, version: package[:version], at: at + 1.minute)
      refreshed =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 2.minutes
        )
      record_submission(
        package,
        version: refreshed.invoice_version,
        at: at + 3.minutes,
        from: "contractor_revision_inbox"
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unresolved_package_count" => 1,
        "cleared_package_count" => 0,
        "unknown_outcome_package_count" => 0,
        "unresolved_rate" => 1.0,
        "cleared_rate" => 0.0
      )
    end

    it "counts several pre-check versions as one cleared package and ignores a later failure" do
      package = build_package
      at = package[:rulecheck].created_at
      add_rulecheck(
        package: package,
        version_number: 2,
        result: "warn",
        created_at: at + 1.minute
      )
      clear =
        add_rulecheck(
          package: package,
          version_number: 3,
          result: "info",
          created_at: at + 2.minutes
        )
      record_submission(
        package,
        version: clear.invoice_version,
        at: at + 3.minutes
      )
      add_rulecheck(
        package: package,
        version_number: 4,
        result: "fail",
        created_at: at + 4.minutes
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "cleared_package_count" => 1,
        "unresolved_package_count" => 0,
        "unknown_outcome_package_count" => 0,
        "cleared_rate" => 1.0
      )
    end

    it "does not treat a hidden warning as a contractor-visible finding" do
      package = build_package
      package[:rulecheck].update_columns(rule_result: "warn")
      record_submission(
        package,
        version: package[:version],
        at: package[:rulecheck].created_at + 1.minute
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 0,
        "no_visible_finding_package_count" => 1,
        "unresolved_package_count" => 0,
        "cleared_package_count" => 0,
        "unresolved_rate" => nil,
        "cleared_rate" => nil
      )
    end

    it "does not count a missing matching upgrade check as cleared" do
      package = build_package
      at = package[:rulecheck].created_at
      final =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 1.minute
        )
      other_upgrade =
        Claims::InvoiceUpgradeType.create!(
          upgrade_type_key: "precheck_other_#{SecureRandom.hex(5)}",
          description: "Another upgrade"
        )
      final.update_columns(invoice_upgrade_type_id: other_upgrade.id)
      record_submission(
        package,
        version: final.invoice_version,
        at: at + 2.minutes
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "cleared_package_count" => 0,
        "unresolved_package_count" => 0,
        "unknown_outcome_package_count" => 1,
        "cleared_rate" => 0.0
      )
    end

    it "counts a warning when warn-and-fail visibility was configured" do
      package = build_package
      package[:rule].update_columns(contractor_visibility: "warn_and_fail")
      package[:rulecheck].update_columns(rule_result: "warn")
      record_submission(
        package,
        version: package[:version],
        at: package[:rulecheck].created_at + 1.minute
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unresolved_package_count" => 1,
        "no_visible_finding_package_count" => 0
      )
    end

    it "counts a package with mixed upgrade outcomes once and requires every finding to clear" do
      package = build_package
      at = package[:rulecheck].created_at
      other_upgrade =
        Claims::InvoiceUpgradeType.create!(
          upgrade_type_key: "precheck_mixed_#{SecureRandom.hex(5)}",
          description: "Another upgrade"
        )
      other_finding = package[:rulecheck].dup
      other_finding.invoice_upgrade_type_id = other_upgrade.id
      other_finding.created_at = at
      other_finding.save!
      final =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 1.minute
        )
      other_final = final.dup
      other_final.assign_attributes(
        invoice_upgrade_type_id: other_upgrade.id,
        rule_result: "fail"
      )
      other_final.created_at = at + 1.minute
      other_final.save!
      record_submission(
        package,
        version: final.invoice_version,
        at: at + 2.minutes
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unresolved_package_count" => 1,
        "cleared_package_count" => 0
      )

      other_final.destroy!
      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unresolved_package_count" => 0,
        "cleared_package_count" => 0,
        "unknown_outcome_package_count" => 1
      )
    end

    it "uses historical visibility when the code rule was hidden after submission" do
      package = build_package
      switch_to_code_rule(package)
      at = package[:rulecheck].created_at
      record_submission(package, version: package[:version], at: at + 1.minute)
      change_rule_at(package, at + 2.minutes, contractor_visibility: "hidden")

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unresolved_package_count" => 1,
        "unknown_history_package_count" => 0
      )
    end

    it "does not treat hiding a finding before submission as clearing it" do
      package = build_package
      switch_to_code_rule(package)
      at = package[:rulecheck].created_at
      change_rule_at(package, at + 1.minute, contractor_visibility: "hidden")
      record_submission(package, version: package[:version], at: at + 2.minutes)

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unresolved_package_count" => 0,
        "cleared_package_count" => 0,
        "unknown_outcome_package_count" => 1
      )
    end

    it "does not credit a clear result across a recorded rule revision" do
      package = build_package
      switch_to_code_rule(package)
      at = package[:rulecheck].created_at
      change_rule_at(package, at + 1.minute, description: "Changed requirement")
      final =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 2.minutes
        )
      record_submission(
        package,
        version: final.invoice_version,
        at: at + 3.minutes
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "cleared_package_count" => 0,
        "unknown_outcome_package_count" => 1
      )
    end

    it "distinguishes missing submission history from a package that has not been submitted" do
      package = build_package
      expect(precheck_metrics(package)).to include(
        "unknown_history_package_count" => 1,
        "finding_package_count" => 0,
        "cleared_rate" => nil
      )

      package[:invoice].update_columns(status: "contractor_precheck")
      expect(precheck_metrics(package)).to include(
        "unknown_history_package_count" => 0,
        "unsubmitted_package_count" => 1
      )
    end

    it "does not substitute a later resubmission when the first submission has no version" do
      package = build_package
      at = package[:rulecheck].created_at
      record_submission(package, version: nil, at: at + 1.minute)
      final =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 2.minutes
        )
      record_submission(
        package,
        version: final.invoice_version,
        at: at + 3.minutes,
        from: "contractor_revision_inbox"
      )

      expect(precheck_metrics(package)).to include(
        "unknown_history_package_count" => 1,
        "finding_package_count" => 0,
        "cleared_package_count" => 0
      )
    end

    it "does not use checks produced after the submission to fill a missing outcome" do
      package = build_package
      at = package[:rulecheck].created_at
      final =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 1.minute
        )
      record_submission(
        package,
        version: final.invoice_version,
        at: at + 2.minutes
      )
      final.update_columns(created_at: at + 3.minutes)

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 1,
        "unknown_outcome_package_count" => 1,
        "cleared_package_count" => 0
      )
    end

    it "uses current-period observations and excludes findings produced only after first submission" do
      package = build_package
      at = package[:rulecheck].created_at
      record_submission(package, version: package[:version], at: at + 1.minute)
      change_rule_at(package, at + 2.minutes, prompt_text: "A new prompt")
      add_rulecheck(
        package: package,
        version_number: 2,
        result: "fail",
        created_at: at + 3.minutes
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 0,
        "post_submission_only_package_count" => 1,
        "unresolved_package_count" => 0,
        "cleared_package_count" => 0
      )
    end

    it "applies report filters to observations without filtering away the submitted outcome" do
      package = build_package(complaint_code: "required_action_unclear")
      at = package[:rulecheck].created_at
      final =
        add_rulecheck(
          package: package,
          version_number: 2,
          result: "pass",
          created_at: at + 1.day
        )
      record_submission(
        package,
        version: final.invoice_version,
        at: at + 1.day + 1.minute
      )

      expect(
        precheck_metrics(
          package,
          params: {
            reason_complaint_code: "required_action_unclear",
            date_to: at.to_date.iso8601,
            contractor_id: package[:contractor].id,
            invoice_upgrade_type_id: package[:upgrade_type].id
          }
        )
      ).to include(
        "finding_package_count" => 1,
        "cleared_package_count" => 1,
        "unresolved_package_count" => 0
      )
    end

    it "reports unknown visibility instead of using current settings for a gap in history" do
      package = build_package
      at = package[:rulecheck].created_at
      record_submission(package, version: package[:version], at: at + 1.minute)
      package[:rule].update_columns(
        contractor_visibility: "hidden",
        updated_at: at + 2.minutes
      )

      expect(precheck_metrics(package)).to include(
        "finding_package_count" => 0,
        "unknown_history_package_count" => 1,
        "cleared_package_count" => 0,
        "no_visible_finding_package_count" => 0
      )
    end
  end

  private

  def record_submission(package, version:, at:, from: "contractor_precheck")
    package[:invoice].update_columns(
      status: "admin_review_inbox",
      submitted_at: package[:invoice].submitted_at || at
    )
    Claims::InvoiceStatusTransition.create!(
      invoice_id: package[:invoice].id,
      invoice_version_id: version&.id,
      from_status: from,
      to_status: "admin_review_inbox",
      created_at: at
    )
  end

  def change_rule_at(package, at, **attributes)
    travel_to(at) { package[:rule].update!(attributes) }
    model =
      (
        if package[:rule].is_a?(Claims::CodeRule)
          Claims::CodeRuleHistory
        else
          Claims::GenaiRuleHistory
        end
      )
    # History timestamps use PostgreSQL's now() default; travel_to only changes
    # the Ruby clock. Align the saved fixture with the simulated edit time.
    model
      .where(source_id: package[:rule].id)
      .order(history_created_at: :desc)
      .first!
      .update_columns(history_created_at: at)
  end

  def precheck_metrics(package, params: {})
    code = package[:rule].is_a?(Claims::CodeRule)
    key = code ? package[:rule].code_rule_key : package[:rule].genai_rule_key
    get(
      "/api/claims/admin/reports/rule_improvement/#{code ? "code" : "genai"}/#{key}",
      params: params
    )
    expect(response).to have_http_status(:ok)
    json_response.fetch("rule").fetch("precheck_metrics")
  end

  def switch_to_code_rule(package)
    at = package[:rule].created_at
    package[:rule] = Claims::CodeRule.create!(
      code_rule_key: "precheck_code_#{SecureRandom.hex(5)}",
      contractor_display_name: "Code evidence check",
      description: "Check evidence",
      source_quote: "Evidence requirement",
      enabled: true,
      contractor_visibility: "fail_only",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "fail_only",
      created_at: at,
      updated_at: at
    )
    package[:rulecheck].update_columns(
      source_engine: "code",
      rule_key: package[:rule].code_rule_key
    )
  end

  def build_package(complaint_code: nil, complaint_text: nil)
    now = Time.zone.parse("2026-09-01 12:00:00")
    contractor = Contractor.create!(business_name: "Reporting Test Contractor")
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
        storage_key: "report-test/invoice-v1.pdf",
        original_filename: "Invoice v1.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )
    upgrade_type =
      Claims::InvoiceUpgradeType.create!(
        upgrade_type_key: "reporting_#{SecureRandom.hex(5)}",
        description: "Reporting test upgrade",
        created_at: now,
        updated_at: now
      )
    rule =
      Claims::GenaiRule.create!(
        genai_rule_key: "reporting_rule_#{SecureRandom.hex(5)}",
        contractor_display_name: "Evidence is complete",
        prompt_text: "Check the evidence.",
        enabled: true,
        source_quote: "Test requirement.",
        contractor_action: "Upload the missing evidence.",
        contractor_visibility: "fail_only",
        contractor_blocking_policy: "non_blocking",
        admin_workflow_policy: "fail_only",
        created_at: now,
        updated_at: now
      )
    Claims::GenaiRuleUpgradeType.create!(
      genai_rule: rule,
      invoice_upgrade_type: upgrade_type
    )
    rulecheck =
      Claims::InvoiceVersionRulecheck.create!(
        invoice_version_id: version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "genai",
        rule_key: rule.genai_rule_key,
        contractor_display_name: rule.contractor_display_name,
        rule_result: "fail",
        reason_and_likely_causes: "Evidence could not be found.",
        reason_complaint_code: complaint_code,
        reason_complaint_text: complaint_text,
        created_at: now,
        updated_at: now
      )

    {
      contractor: contractor,
      session: session,
      invoice: invoice,
      version: version,
      upgrade_type: upgrade_type,
      rule: rule,
      rulecheck: rulecheck
    }
  end

  def add_rulecheck(
    package:,
    version_number:,
    result:,
    created_at:,
    invoice: nil,
    complaint_code: nil,
    complaint_text: nil
  )
    invoice ||= package[:invoice]
    version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: version_number,
        storage_provider: "azure_blob",
        storage_key: "report-test/invoice-v#{version_number}.pdf",
        original_filename: "Invoice v#{version_number}.pdf",
        content_type: "application/pdf",
        created_at: created_at,
        updated_at: created_at
      )
    code = package[:rule].is_a?(Claims::CodeRule)
    Claims::InvoiceVersionRulecheck.create!(
      invoice_version_id: version.id,
      invoice_upgrade_type_id: package[:upgrade_type].id,
      source_engine: code ? "code" : "genai",
      rule_key:
        code ? package[:rule].code_rule_key : package[:rule].genai_rule_key,
      contractor_display_name: package[:rule].contractor_display_name,
      rule_result: result,
      reason_and_likely_causes: "Current-version evidence explanation.",
      reason_complaint_code: complaint_code,
      reason_complaint_text: complaint_text,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def add_issue(package:, rulecheck:, status:, disposition_comment:)
    Claims::RevisionIssue.create!(
      invoice_id: rulecheck.invoice_version.invoice_id,
      issue_type: "rule",
      opened_from_invoice_version_rulecheck_id: rulecheck.id,
      opened_from_rule_key: rulecheck.rule_key,
      opened_from_rule_upgrade_type_id: package[:upgrade_type].id,
      opened_from_source_snapshot: {
      },
      status: status,
      disposition_comment: disposition_comment
    )
  end

  def add_sent_round(
    issue:,
    invoice_version:,
    round_number:,
    sent_at:,
    contractor_method: "supporting_document_uploaded"
  )
    round =
      Claims::RevisionRound.create!(
        invoice_id: issue.invoice_id,
        invoice_version_id: invoice_version.id,
        round_number: round_number,
        admin_sent_at: sent_at,
        contractor_response_submitted_at: sent_at + 1.minute,
        created_at: sent_at,
        updated_at: sent_at
      )
    Claims::RevisionIssueComment.create!(
      revision_issue_id: issue.id,
      revision_round_id: round.id,
      author_type: "admin",
      admin_recommended_remedy: "upload_supporting_document",
      comment_text: "Please provide the missing page.",
      created_at: sent_at,
      updated_at: sent_at
    )
    Claims::RevisionIssueComment.create!(
      revision_issue_id: issue.id,
      revision_round_id: round.id,
      author_type: "contractor",
      contractor_response_method: contractor_method,
      comment_text: "Contractor response for the requested action.",
      created_at: sent_at + 1.minute,
      updated_at: sent_at + 1.minute
    )
  end
end
