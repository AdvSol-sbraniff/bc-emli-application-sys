require "rails_helper"

RSpec.describe "Claims lifecycle schema contract" do
  let(:connection) { ActiveRecord::Base.connection }

  it "keeps invoice status limited to business ownership states" do
    expect(Claims::Invoice::STATUSES).to contain_exactly(
      "contractor_precheck",
      "admin_review_inbox",
      "contractor_revision_inbox",
      "in_review",
      "approved_pending",
      "approved_paid",
      "ineligible",
      "contractor_withdrawn"
    )
    expect(constraint("invoices_status_chk")).not_to match(
      /upload|ocr|genai|technical_failure|package_needs_correction/
    )
  end

  it "keeps run kind and lifecycle independent from invoice status" do
    expect(Claims::IngestRun::RUN_KINDS).to contain_exactly(
      "initial_upload",
      "fix_upload",
      "rules_rerun"
    )
    expect(Claims::IngestRun::ACTIVE_STATUSES).to contain_exactly(
      "queued",
      "running"
    )
    expect(Claims::IngestRun::TERMINAL_STATUSES).to contain_exactly(
      "succeeded",
      "failed"
    )
    expect(constraint("ingest_runs_status_chk")).not_to include("partial")
  end

  it "keeps one canonical vocabulary for logical step attempts" do
    expect(Claims::IngestStepRun::STEP_TYPES).to contain_exactly(
      "stage_package",
      "read_document",
      "classify_document",
      "extract_supporting_document",
      "extract_invoice",
      "clone_evidence",
      "case_facts",
      "evaluate_genai_ruleset",
      "evaluate_code_ruleset",
      "finalize_validation"
    )
    expect(constraint("ingest_step_runs_step_type_chk")).not_to match(
      /aggregate_advice|fix_|genai_common|genai_upgrade|ocr_/
    )
  end

  it "enforces terminal run shape in the database" do
    definition = constraint("ingest_runs_terminal_shape_chk")

    expect(definition).to include("resolved_invoice_version_id IS NOT NULL")
    expect(definition).to include("failure_category IS NOT NULL")
    expect(definition).to include("failure_code IS NOT NULL")
    expect(definition).to include("completed_at IS NOT NULL")
  end

  it "nulls a retained diagnostic run link when its invoice is deleted" do
    delete_action = connection.select_value(<<~SQL.squish)
        SELECT confdeltype
        FROM pg_constraint
        WHERE conname = 'fk_ingest_runs_invoice'
      SQL

    expect(delete_action).to eq("n")
  end

  it "does not retain removed duplicate lifecycle columns" do
    expect(columns("claims.invoices")).not_to include("status_subtype")
    expect(columns("claims.invoice_versions")).not_to include(
      "genai_result",
      "genai_raw_json"
    )
    expect(columns("claims.ingest_documents")).not_to include(
      "classification_status"
    )
    expect(columns("claims.supporting_documents")).not_to include(
      "classification_status"
    )
    expect(columns("claims.invoice_version_upgrade_types")).not_to include(
      "source_engine",
      "call_status",
      "result",
      "admin_advice"
    )
  end

  def constraint(name)
    connection.select_value(<<~SQL.squish)
      SELECT pg_get_constraintdef(oid)
      FROM pg_constraint
      WHERE conname = #{connection.quote(name)}
    SQL
  end

  def columns(table_name)
    connection.columns(table_name).map(&:name)
  end
end
