require "rails_helper"

RSpec.describe Claims::RunGenaiJob do
  subject(:job) { described_class.new }

  it "fans out all required rulesets for a test-harness replay" do
    ingest_run = double(id: "ingest-run-id", status: "running")
    invoice_version =
      double(
        id: "invoice-version-id",
        invoice_id: "invoice-id",
        di_raw_json: {
          "invoice" => true
        }
      )
    invoice = double(id: "invoice-id")
    claim_session = double(id: "session-id")
    common_upgrade_type = double(id: "common-id")
    detected_upgrade_type = double(id: "detected-id")
    classifier_payload = { "classification" => true }

    allow(Claims::IngestRun).to receive(:find).and_return(ingest_run)
    allow(Claims::InvoiceVersion).to receive(:find).and_return(invoice_version)
    allow(Claims::Invoice).to receive(:find).and_return(invoice)
    allow(Claims::Session).to receive(:find).and_return(claim_session)
    allow(Claims::TestHarness::RunLookup).to receive(:harness_run?).and_return(
      true
    )
    allow(Claims::TestHarness::Scheduling).to receive(:advance_run)
    allow(job).to receive(:classifier_payload_from_evidence).and_return(
      classifier_payload
    )
    allow(job).to receive(:run_case_facts_step!).and_return({ "facts" => true })
    allow(job).to receive(:detected_upgrade_types).and_return(
      [detected_upgrade_type]
    )
    allow(job).to receive(:upgrade_type_by_key!).with("common").and_return(
      common_upgrade_type
    )
    allow(job).to receive(:enqueue_genai_ruleset_job!)

    job.perform(
      claim_session.id,
      invoice_version.id,
      ingest_run.id,
      "use_existing_classifier"
    )

    expect(job).to have_received(:enqueue_genai_ruleset_job!).with(
      ingest_run_id: ingest_run.id,
      session_id: claim_session.id,
      invoice_version: invoice_version,
      step_type: "evaluate_genai_ruleset",
      upgrade_type: common_upgrade_type
    )
    expect(job).to have_received(:enqueue_genai_ruleset_job!).with(
      ingest_run_id: ingest_run.id,
      session_id: claim_session.id,
      invoice_version: invoice_version,
      step_type: "evaluate_genai_ruleset",
      upgrade_type: detected_upgrade_type
    )
  end
end
