require "rails_helper"

RSpec.describe Claims::RuleAudits::ContextBuilder do
  include ActiveSupport::Testing::TimeHelpers

  let(:now) { Time.zone.parse("2026-09-18 10:00:00") }
  let(:contractor) do
    Contractor.create!(business_name: "Audit context contractor")
  end
  let(:session) { Claims::Session.create! }
  let(:invoice) do
    Claims::Invoice.create!(
      session_id: session.id,
      contractor_id: contractor.id,
      status: "admin_review_inbox",
      created_at: now
    )
  end
  let(:upgrade) do
    Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
  end
  let(:rule) do
    Claims::GenaiRule.create!(
      genai_rule_key: "audit_context_#{SecureRandom.hex(6)}",
      contractor_display_name: "Required supporting evidence",
      prompt_text: "Original strict requirement.",
      source_quote: "A suitable report is required.",
      contractor_action: "Include a suitable report.",
      enabled: false,
      contractor_visibility: "warn_and_fail",
      contractor_blocking_policy: "non_blocking",
      admin_workflow_policy: "warn_and_fail",
      created_at: now - 1.day,
      updated_at: now - 1.day
    )
  end
  let(:version) do
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_provider: "azure_blob",
      storage_key: "audit-context/invoice.pdf",
      original_filename: "Invoice.pdf",
      content_type: "application/pdf",
      di_raw_json: {
        "content" => "Invoice - the complete original invoice text.",
        "documents" => [
          { "fields" => { "InvoiceId" => { "content" => "INV-AUDIT" } } }
        ]
      },
      created_at: now,
      updated_at: now
    )
  end
  let(:check) do
    Claims::InvoiceVersionRulecheck.create!(
      invoice_version_id: version.id,
      invoice_upgrade_type_id: upgrade.id,
      source_engine: "genai",
      rule_key: rule.genai_rule_key,
      contractor_display_name: rule.contractor_display_name,
      rule_result: "warn",
      reason_and_likely_causes:
        "The required evidence appears missing. Please provide supporting evidence.",
      reason_complaint_code: "required_action_unclear",
      reason_complaint_text: "State the actual document that is missing.",
      created_at: now + 1.minute,
      updated_at: now + 1.hour
    )
  end

  def call_builder(**options)
    check
    described_class.new(
      source_engine: "genai",
      rule_key: rule.genai_rule_key,
      invoice_id: invoice.id,
      guidance: {
        "steps" => ["Inspect packages before choosing an improvement"]
      },
      **options
    ).call
  end

  def records(result)
    result
      .fetch(:contextwindowjson)
      .map { |message| JSON.parse(message.fetch(:content).first.fetch(:text)) }
  end

  def record(result, type)
    records(result)
      .find { |row| row.fetch("record_type") == type }
      .fetch("data")
  end

  it "includes authoritative evidence, complete discussions and original workflow snapshots without writes or ingest queries" do
    check
    actor = create(:user)
    Claims::GenaiRuleUpgradeType.create!(
      genai_rule: rule,
      invoice_upgrade_type: upgrade
    )
    Claims::InvoiceVersionLocatedField.create!(
      invoice_version_id: version.id,
      invoice_upgrade_type_id: upgrade.id,
      source_engine: "code",
      field_key: "participant.eligibility",
      value_type: "text",
      value_text: "Eligible when checked"
    )
    Claims::Lineitem.create!(
      invoice_version_id: version.id,
      lineitem_seqno: 1,
      ocr_description: "Installed equipment"
    )
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: version.id,
      invoice_upgrade_type_id: upgrade.id,
      confidence: 97,
      evidence_text: "Classifier's supporting evidence"
    )
    supporting =
      Claims::SupportingDocument.create!(
        invoice_version_id: version.id,
        storage_provider: "azure_blob",
        storage_key: "audit-context/supporting.pdf",
        original_filename: "Report.pdf",
        content_type: "application/pdf",
        di_read_raw_json: {
          "content" => "Original signed report"
        },
        classifier_raw_json: {
          "document_kind" => "report"
        }
      )
    Claims::SupportingDocumentLocatedField.create!(
      supporting_document_id: supporting.id,
      field_key: "signature",
      value_type: "text",
      value_text: "Jane",
      evidence_text: "Jane signed the report"
    )
    Claims::SupportingDocumentVisualFinding.create!(
      supporting_document_id: supporting.id,
      finding_seqno: 1,
      finding_type: "signature",
      summary: "A handwritten signature is visible",
      legibility: "legible",
      confidence: 90
    )
    Claims::InvoiceStatusTransition.create!(
      invoice_id: invoice.id,
      invoice_version_id: version.id,
      actor_user_id: actor.id,
      from_status: "contractor_precheck",
      to_status: "admin_review_inbox",
      created_at: now + 5.minutes
    )
    issue =
      Claims::RevisionIssue.create!(
        invoice_id: invoice.id,
        issue_type: "rule",
        opened_from_invoice_version_rulecheck_id: check.id,
        opened_from_rule_key: check.rule_key,
        opened_from_rule_upgrade_type_id: upgrade.id,
        opened_from_source_snapshot: {
          "reason" => "Original opening reason"
        },
        status: "closed_via_corrected_documentation",
        disposition_comment: "The final report resolves the issue.",
        created_at: now + 1.hour,
        updated_at: now + 3.hours
      )
    round =
      Claims::RevisionRound.create!(
        invoice_id: invoice.id,
        invoice_version_id: version.id,
        round_number: 1,
        admin_sent_at: now + 1.hour,
        contractor_response_submitted_at: now + 2.hours
      )
    Claims::RevisionIssueComment.create!(
      revision_issue_id: issue.id,
      revision_round_id: round.id,
      author_type: "admin",
      admin_recommended_remedy: "upload_supporting_document",
      comment_text: "Please upload the installation report."
    )
    Claims::RevisionIssueComment.create!(
      revision_issue_id: issue.id,
      revision_round_id: round.id,
      author_type: "contractor",
      contractor_response_method: "unable_to_resolve",
      comment_text: "Which report do you mean?"
    )
    Claims::ConversationMessage.create!(
      invoice_id: invoice.id,
      invoice_version_id: version.id,
      requester_id: actor.id,
      message_type: "admin_message",
      request_text: "The signed installation report is the relevant document.",
      created_at: now + 2.hours
    )
    Claims::ConversationMessage.create!(
      invoice_id: invoice.id,
      requester_id: actor.id,
      message_type: "contractor_note",
      request_text: "I understand now and will send it.",
      created_at: now + 150.minutes
    )
    Claims::InternalNote.create!(
      invoice_id: invoice.id,
      admin_user_id: actor.id,
      note_text: "The initial reason was too generic to prepopulate an issue.",
      created_at: now + 3.hours
    )

    sql = []
    result = nil
    subscriber = ->(*args) { sql << args.last.fetch(:sql) }
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      result = call_builder
    end

    expect(sql.grep(/\b(?:INSERT|UPDATE|DELETE)\b/i)).to be_empty
    expect(sql.grep(/claims\.ingest_/i)).to be_empty
    expect(result[:contextwindowjson]).to all(include(role: "user"))
    expect(record(result, "human_workflow_reference")["steps"]).to eq(
      ["Inspect packages before choosing an improvement"]
    )
    invoice_record = record(result, "invoice_version")
    expect(
      invoice_record.dig("invoice_version", "di_raw_json", "content")
    ).to include("complete original")
    expect(invoice_record["located_fields"].first["value_text"]).to eq(
      "Eligible when checked"
    )
    expect(invoice_record["lineitems"].first["ocr_description"]).to eq(
      "Installed equipment"
    )
    expect(invoice_record["rulechecks"].first).to include(
      "reason_complaint_text" => "State the actual document that is missing.",
      "selected_rule" => true
    )
    document_record = record(result, "supporting_document")
    expect(
      document_record.dig("document", "di_read_raw_json", "content")
    ).to eq("Original signed report")
    expect(document_record["located_fields"].first["value_text"]).to eq("Jane")
    expect(document_record["visual_findings"].first["summary"]).to include(
      "handwritten signature"
    )
    workflow = record(result, "workflow_issues")["issues"].first
    expect(workflow["opened_from_source_snapshot"]).to eq(
      "reason" => "Original opening reason"
    )
    expect(workflow["disposition_comment"]).to eq(
      "The final report resolves the issue."
    )
    expect(workflow["closure_provenance"]).to include(
      "closed_at" => nil,
      "closed_by_user_id" => nil
    )
    expect(workflow["comments"].map { |row| row["comment_text"] }).to eq(
      ["Please upload the installation report.", "Which report do you mean?"]
    )
    expect(
      record(result, "workflow_rounds")["rounds"].first["admin_sent_at"]
    ).to be_present
    expect(
      record(result, "ordinary_conversation")["messages"].map do |row|
        row["author_role"]
      end
    ).to eq(%w[admin contractor])
    expect(
      record(result, "ordinary_conversation")["messages"].last[
        "invoice_version_id"
      ]
    ).to be_nil
    expect(
      record(result, "internal_admin_discussion")["notes"].first[
        "admin_user_id"
      ]
    ).to eq(actor.id)
    expect(
      record(result, "package")["status_transitions"].first["actor_user_id"]
    ).to eq(actor.id)
    expect(result[:manifest][:source_coverage]).to include(
      "claims.revision_issue_comments" => 2,
      "claims.internal_notes" => 1
    )
    expect(
      result[:attachments].map { |attachment| attachment[:storageKey] }
    ).to eq([version.storage_key, supporting.storage_key])
    expect(result[:manifest][:omissions]).to eq([])
    expect(result[:manifest][:record_count]).to eq(
      result[:contextwindowjson].size
    )
    expect(result[:manifest][:context_bytes]).to eq(
      JSON.generate(result[:contextwindowjson]).bytesize
    )
  end

  it "preserves every version and deduplicates source pointers while distinguishing later evidence and inferred rule history" do
    check
    travel_to(now + 2.hours) do
      rule.update!(prompt_text: "Accept the invoice or the signed report.")
    end
    # history_created_at uses PostgreSQL now(), which does not follow Rails'
    # travel_to clock. Pin the persisted boundary as well as the rule clock.
    Claims::GenaiRuleHistory
      .where(source_id: rule.id)
      .sole
      .update!(history_created_at: now + 2.hours)
    later = version.dup
    later.invoice_versionno = 2
    later.created_at = now + 3.hours
    later.updated_at = now + 3.hours
    later.save!
    later_check = check.dup
    later_check.invoice_version_id = later.id
    later_check.rule_result = "pass"
    later_check.created_at = now + 3.hours
    later_check.updated_at = now + 3.hours
    later_check.save!
    Claims::SupportingDocument.create!(
      invoice_version_id: later.id,
      storage_key: "audit-context/later-report.pdf",
      content_type: "application/pdf"
    )

    result = call_builder
    versions =
      records(result)
        .select { |row| row["record_type"] == "invoice_version" }
        .map { |row| row["data"] }
    expect(versions.size).to eq(2)
    expect(
      versions.first["rulechecks"].first.dig(
        "definition_at_check",
        "inferred_definition_source"
      )
    ).to eq("claims.genai_rule_history")
    expect(
      versions.last["rulechecks"].first.dig(
        "definition_at_check",
        "inferred_definition_source"
      )
    ).to eq("claims.genai_rules")
    expect(
      versions.first["rulechecks"].first.dig("definition_at_check", "status")
    ).to eq("inferred_not_execution_provenance")
    expect(
      record(result, "rule_registry")["current_definition"]["enabled"]
    ).to eq(false)
    expect(result[:manifest][:selected_invoice_version_id]).to eq(later.id)
    expect(result[:manifest][:document_count]).to eq(3)
    expect(result[:attachments].size).to eq(2)
    expect(
      result[:attachments].first[:occurrences].map do |row|
        row[:invoice_version_id]
      end
    ).to eq([version.id, later.id])
    expect(record(result, "supporting_document")["invoice_version_id"]).to eq(
      later.id
    )
    expect(result[:manifest][:limitations].join(" ")).to include(
      "not proof",
      "Later edits"
    )
    expect(
      call_builder(selected_invoice_version_id: version.id)[:manifest]
    ).to include(selected_invoice_version_id: version.id, version_count: 2)
  end

  it "does not invent complaint or closure timestamps and distinguishes missing OCR, empty discussions and absent history" do
    version.update!(di_raw_json: nil)
    check
    result = call_builder
    complaint =
      record(result, "invoice_version")["rulechecks"].first[
        "complaint_provenance"
      ]
    expect(complaint).to include(
      "author_id" => nil,
      "recorded_at" => nil,
      "status" => "complaint_present_without_independent_author_or_timestamp"
    )
    expect(record(result, "invoice_version")["invoice_di_status"]).to eq(
      "not_stored"
    )
    expect(record(result, "ordinary_conversation")).to include("messages" => [])
    expect(result[:manifest][:source_coverage]).to include(
      "claims.supporting_documents" => 0,
      "claims.internal_notes" => 0
    )
    expect(result[:manifest][:limitations].join(" ")).to include(
      "no stored raw invoice",
      "No saved historical rule definitions",
      "no separate author"
    )
  end

  it "keeps other rules as contextual checks without attributing their issues to the selected rule" do
    check
    other = check.dup
    other.rule_key = "another_rule"
    other.save!
    Claims::RevisionIssue.create!(
      invoice_id: invoice.id,
      issue_type: "rule",
      opened_from_invoice_version_rulecheck_id: other.id,
      opened_from_rule_key: other.rule_key,
      opened_from_rule_upgrade_type_id: upgrade.id,
      status: "pending_admin_review"
    )
    result = call_builder
    other_check =
      record(result, "invoice_version")["rulechecks"].find do |row|
        row["id"] == other.id
      end
    expect(other_check).to include(
      "selected_rule" => false,
      "definition_at_check" => nil
    )
    expect(record(result, "workflow_issues")["issues"].first).to include(
      "selected_rule" => false,
      "selected_rule_relevance" => "other_package_issue"
    )
  end

  it "rejects a version from another invoice and a package without the selected rule" do
    check
    other_invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id
      )
    other_version = version.dup
    other_version.invoice_id = other_invoice.id
    other_version.save!
    expect {
      call_builder(selected_invoice_version_id: other_version.id)
    }.to raise_error(described_class::InvalidInput, /does not belong/)
    expect { call_builder(invoice_id: other_invoice.id) }.to raise_error(
      described_class::InvalidInput,
      /no recorded checks/
    )
  end

  it "supports code rules as configuration evidence without claiming their executable history is available" do
    check
    code_rule =
      Claims::CodeRule.create!(
        code_rule_key: "audit_code_#{SecureRandom.hex(6)}",
        contractor_display_name: "Code-owned eligibility check",
        description: "Check the stored eligibility dates.",
        source_quote: "An active eligibility code is required.",
        contractor_action: "Include a current eligibility code.",
        enabled: false,
        created_at: now - 1.day,
        updated_at: now - 1.day
      )
    code_check = check.dup
    code_check.source_engine = "code"
    code_check.rule_key = code_rule.code_rule_key
    code_check.save!
    result =
      call_builder(source_engine: "code", rule_key: code_rule.code_rule_key)
    expect(
      record(result, "rule_registry")["current_definition"]["description"]
    ).to eq("Check the stored eligibility dates.")
    expect(result[:manifest][:limitations].join(" ")).to include(
      "does not include executable Ruby"
    )
    checks = record(result, "invoice_version")["rulechecks"]
    expect(checks.find { |row| row["id"] == check.id }["selected_rule"]).to eq(
      false
    )
    expect(
      checks.find { |row| row["id"] == code_check.id }["selected_rule"]
    ).to eq(true)
  end

  it "does not associate a check before the current rule record with the current definition" do
    check.update_columns(created_at: now - 2.days)
    result = call_builder
    definition =
      record(result, "invoice_version")["rulechecks"].first[
        "definition_at_check"
      ]
    expect(definition["status"]).to eq("unknown")
    expect(definition).not_to have_key("inferred_definition_record_id")
  end

  it "rejects invalid identities and missing records without pretending evidence is absent" do
    expect { call_builder(source_engine: "unknown") }.to raise_error(
      described_class::InvalidInput
    )
    expect { call_builder(invoice_id: "not-a-uuid") }.to raise_error(
      described_class::InvalidInput
    )
    expect { call_builder(invoice_id: SecureRandom.uuid) }.to raise_error(
      ActiveRecord::RecordNotFound
    )
    expect { call_builder(rule_key: "missing_rule") }.to raise_error(
      ActiveRecord::RecordNotFound
    )
  end

  it "passes recorded file identity to transport and labels unknown historical hashes explicitly" do
    result = call_builder
    expect(result[:attachments].first).not_to have_key(:expected_sha256)
    expect(result[:attachments].first).not_to have_key(:expected_byte_size)
    expect(result[:manifest][:attachments].first).to include(
      stored_hash_status: "not_recorded",
      stored_size_status: "not_recorded"
    )
    expect(result[:manifest][:attachments].first[:integrity_status]).to include(
      "cannot prove"
    )

    version.update!(sha256: "AB" * 32, byte_size: 1234)
    result = call_builder
    expect(result[:attachments].first).to include(
      expected_sha256: "ab" * 32,
      expected_byte_size: 1234
    )
    expect(result[:manifest][:attachments].first).to include(
      stored_hash_status: "recorded_expected_hash",
      stored_size_status: "recorded_expected_size"
    )
  end

  it "can use a known identity from a later occurrence of the same source without losing the original unknown provenance" do
    check
    later = version.dup
    later.invoice_versionno = 2
    later.sha256 = "ab" * 32
    later.byte_size = 1234
    later.save!
    result = call_builder
    expect(result[:attachments].size).to eq(1)
    expect(result[:attachments].first).to include(
      expected_sha256: later.sha256,
      expected_byte_size: 1234
    )
    occurrences = result[:attachments].first[:occurrences]
    expect(occurrences.first[:stored_sha256]).to be_nil
    expect(occurrences.last[:stored_sha256]).to eq(later.sha256)
  end

  it "rejects conflicting historical identity for one source pointer instead of choosing the first version's metadata" do
    check
    version.update!(sha256: "ab" * 32, byte_size: 1234)
    later = version.dup
    later.invoice_versionno = 2
    later.sha256 = "cd" * 32
    later.save!
    expect { call_builder }.to raise_error(
      described_class::InvalidInput,
      /conflicting historical file hashes or sizes/
    )
    later.update!(sha256: version.sha256, byte_size: 4321)
    expect { call_builder }.to raise_error(
      described_class::InvalidInput,
      /conflicting historical file hashes or sizes/
    )
  end

  it "rejects malformed stored identity rather than dropping the expected-hash check" do
    version.update!(sha256: "not-a-sha256")
    expect { call_builder }.to raise_error(
      described_class::InvalidInput,
      /invalid stored SHA-256/
    )
    version.update!(sha256: nil, byte_size: -1)
    expect { call_builder }.to raise_error(
      described_class::InvalidInput,
      /invalid stored byte size/
    )
  end

  it "rejects oversized complete contexts instead of truncating Unicode text" do
    check.update!(reason_complaint_text: "é" * 800_000)
    expect { call_builder }.to raise_error(
      described_class::TooLarge,
      /No evidence was truncated/
    )
  end

  it "rejects too many attachments and unsupported source files without dropping them" do
    stub_const("Claims::RuleAudits::ContextBuilder::MAX_ATTACHMENTS", 1)
    Claims::SupportingDocument.create!(
      invoice_version_id: version.id,
      storage_key: "audit-context/second.pdf",
      content_type: "application/pdf"
    )
    expect { call_builder }.to raise_error(
      described_class::TooLarge,
      /No documents were omitted/
    )
    version.update!(content_type: "application/zip")
    expect { call_builder }.to raise_error(
      described_class::InvalidInput,
      /unsupported file type/
    )
  end

  it "propagates evidence query failures rather than silently replacing them with empty evidence" do
    check
    allow(Claims::ConversationMessage).to receive(:where).and_raise(
      ActiveRecord::StatementInvalid,
      "unavailable evidence"
    )
    allow_any_instance_of(Claims::Invoice).to receive(
      :conversation_messages
    ).and_raise(ActiveRecord::StatementInvalid, "unavailable evidence")
    expect { call_builder }.to raise_error(
      ActiveRecord::StatementInvalid,
      /unavailable evidence/
    )
  end
end
