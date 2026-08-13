require "rails_helper"

RSpec.describe Claims::FinalizeGenaiValidationJob do
  it "delegates finalization and always requests run advancement" do
    session = Claims::Session.create!
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        status: "running"
      )
    runner = instance_double(Claims::RunGenaiJob)
    allow(Claims::RunGenaiJob).to receive(:new).and_return(runner)
    allow(runner).to receive(:finalize_validation!)
    allow(Claims::Ingest::AdvanceRunJob).to receive(:perform_async)

    described_class.new.perform("session", "version", run.id)

    expect(runner).to have_received(:finalize_validation!).with(
      session_id: "session",
      invoice_version_id: "version",
      ingest_run_id: run.id
    )
    expect(Claims::Ingest::AdvanceRunJob).to have_received(:perform_async).with(
      run.id
    )
  end

  it "does not reopen a terminal run" do
    session = Claims::Session.create!
    run =
      Claims::IngestRun.create!(
        run_kind: "initial_upload",
        session_id: session.id,
        status: "failed",
        failure_category: "technical_failure",
        failure_code: "unknown_runtime_failure",
        completed_at: Time.current
      )
    allow(Claims::RunGenaiJob).to receive(:new)
    allow(Claims::Ingest::AdvanceRunJob).to receive(:perform_async)

    described_class.new.perform("session", "version", run.id)

    expect(Claims::RunGenaiJob).not_to have_received(:new)
  end
end
