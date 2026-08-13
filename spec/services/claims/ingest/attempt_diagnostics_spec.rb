require "rails_helper"

RSpec.describe Claims::Ingest::AttemptDiagnostics do
  def create_run(status: "running")
    session = Claims::Session.create!
    contractor = Contractor.create!(business_name: "Diagnostics Contractor")
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "test",
        storage_key: "diagnostics/invoice.pdf",
        original_filename: "invoice.pdf",
        content_type: "application/pdf"
      )
    Claims::IngestRun.create!(
      run_kind: "initial_upload",
      session_id: session.id,
      contractor_id: contractor.id,
      invoice_id: invoice.id,
      resolved_invoice_version_id:
        status == "succeeded" ? invoice_version.id : nil,
      status: status,
      total_files: 1,
      completed_files: status == "succeeded" ? 1 : 0,
      failed_files: status == "failed" ? 1 : 0,
      failure_category: status == "failed" ? "technical_failure" : nil,
      failure_code: status == "failed" ? "unknown_runtime_failure" : nil,
      completed_at: status.in?(%w[succeeded failed]) ? Time.current : nil
    )
  end

  def create_step(
    run:,
    status:,
    created_at:,
    error_code: nil,
    retryable: nil,
    step_type: "case_facts"
  )
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: run.session_id,
      step_type: step_type,
      status: status,
      error_text: status == "failed" ? "Injected retryable failure." : nil,
      error_code: error_code,
      retryable: retryable,
      created_at: created_at,
      updated_at: created_at
    )
  end

  it "marks a historical failed attempt recovered after the target succeeds" do
    run = create_run(status: "succeeded")
    failed =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "case_facts",
        status: "failed",
        error_text: "The model returned malformed JSON.",
        retryable: true,
        error_code: "genai_model_output_invalid_json",
        created_at: 2.minutes.ago,
        updated_at: 2.minutes.ago
      )
    succeeded =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "case_facts",
        status: "succeeded",
        created_at: 1.minute.ago,
        updated_at: 1.minute.ago
      )

    result =
      described_class.call(steps: [failed, succeeded], run_status: run.status)

    expect(result.annotations_by_step_id.fetch(failed.id)).to include(
      attempt_number: 1,
      attempt_count: 2,
      logical_state: "succeeded",
      display_status: "recovered",
      effective_attempt: false
    )
    expect(result.annotations_by_step_id.fetch(succeeded.id)).to include(
      attempt_number: 2,
      display_status: "succeeded",
      effective_attempt: true
    )
    expect(result.summary).to include(
      failed_attempts: 1,
      recovered_attempts: 1,
      retried_targets: 1,
      retrying_targets: 0,
      failed_targets: 0
    )
    expect(result.terminal_failure_step).to be_nil
  end

  it "marks a retryable failure as retrying only while its run is active" do
    running_run = create_run
    failure =
      create_step(
        run: running_run,
        status: "failed",
        created_at: Time.current,
        error_code: "genai_service_unavailable",
        retryable: true
      )

    active = described_class.call(steps: [failure], run_status: "running")
    terminal = described_class.call(steps: [failure], run_status: "failed")

    expect(active.annotations_by_step_id.fetch(failure.id)).to include(
      logical_state: "retrying",
      display_status: "retrying"
    )
    expect(active.summary.fetch(:retrying_targets)).to eq(1)
    expect(terminal.annotations_by_step_id.fetch(failure.id)).to include(
      logical_state: "failed",
      display_status: "failed"
    )
    expect(terminal.terminal_failure_step).to eq(failure)
  end

  it "keeps a historical failure marked retrying while its next attempt is active" do
    run = create_run
    failure =
      create_step(
        run: run,
        status: "failed",
        created_at: 1.minute.ago,
        error_code: "genai_service_unavailable",
        retryable: true,
        step_type: "stage_package"
      )
    queued =
      create_step(
        run: run,
        status: "queued",
        created_at: Time.current,
        step_type: "stage_package"
      )

    result =
      described_class.call(steps: [failure, queued], run_status: run.status)

    expect(result.annotations_by_step_id.fetch(failure.id)).to include(
      logical_state: "active",
      display_status: "retrying",
      effective_attempt: false
    )
    expect(result.annotations_by_step_id.fetch(queued.id)).to include(
      display_status: "queued",
      effective_attempt: true
    )
    expect(result.summary.fetch(:retrying_targets)).to eq(1)
  end

  it "selects terminal failure only from targets that did not recover" do
    run = create_run(status: "failed")
    recovered_failure =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "case_facts",
        status: "failed",
        error_text: "First call failed.",
        error_code: "genai_service_unavailable",
        retryable: true,
        created_at: 3.minutes.ago,
        updated_at: 3.minutes.ago
      )
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: run.session_id,
      step_type: "case_facts",
      status: "succeeded",
      created_at: 2.minutes.ago,
      updated_at: 2.minutes.ago
    )
    terminal_failure =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        step_type: "stage_package",
        status: "failed",
        error_text: "Package could not be staged.",
        error_code: "upload_unexpected_exception",
        retryable: false,
        created_at: 1.minute.ago,
        updated_at: 1.minute.ago
      )

    result =
      described_class.call(
        steps:
          Claims::IngestStepRun.where(ingest_run_id: run.id).order(
            :created_at,
            :id
          ),
        run_status: run.status
      )

    expect(
      result.annotations_by_step_id.fetch(recovered_failure.id)
    ).to include(display_status: "recovered")
    expect(result.terminal_failure_step).to eq(terminal_failure)
  end
end
