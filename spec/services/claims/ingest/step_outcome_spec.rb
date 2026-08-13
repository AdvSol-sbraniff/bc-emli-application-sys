require "rails_helper"

RSpec.describe Claims::Ingest::StepOutcome do
  let(:session) { Claims::Session.create! }
  let(:run) do
    Claims::IngestRun.create!(
      run_kind: "initial_upload",
      session_id: session.id,
      status: "running",
      total_files: 1
    )
  end

  def create_attempt(status:, retryable: nil, created_at: Time.current)
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: session.id,
      step_type: "stage_package",
      status: status,
      error_text: status == "failed" ? "Injected failure." : nil,
      failure_category: status == "failed" ? "technical_failure" : nil,
      failure_code: status == "failed" ? "genai_service_error" : nil,
      error_code: status == "failed" ? "injected_failure" : nil,
      retryable: retryable,
      created_at: created_at,
      updated_at: created_at
    )
  end

  def outcome
    described_class.for_target(
      ingest_run_id: run.id,
      step_type: "stage_package"
    )
  end

  it "reports a missing logical target" do
    expect(outcome).to have_attributes(state: :missing, attempt_count: 0)
  end

  it "reports an active logical target" do
    step = create_attempt(status: "in_progress")

    expect(outcome).to have_attributes(
      state: :active,
      effective_step: step,
      attempt_count: 1
    )
  end

  it "reports a retryable failure below the common attempt limit as retrying" do
    step = create_attempt(status: "failed", retryable: true)

    expect(outcome).to have_attributes(
      state: :retrying,
      effective_step: step,
      attempt_count: 1,
      attempt_limit: Claims::Ingest::RetryPolicy::MAX_ATTEMPTS
    )
  end

  it "reports a permanent failure immediately" do
    create_attempt(status: "failed", retryable: false)

    expect(outcome.state).to eq(:failed)
  end

  it "reports an exhausted retryable target as failed" do
    Claims::Ingest::RetryPolicy::MAX_ATTEMPTS.times do |index|
      create_attempt(
        status: "failed",
        retryable: true,
        created_at: Time.current + index.seconds
      )
    end

    expect(outcome).to have_attributes(
      state: :failed,
      attempt_count: Claims::Ingest::RetryPolicy::MAX_ATTEMPTS
    )
  end

  it "makes success absorb every historical failure" do
    failed = create_attempt(status: "failed", retryable: true)
    succeeded =
      create_attempt(
        status: "succeeded",
        created_at: failed.created_at + 1.second
      )

    expect(outcome).to have_attributes(
      state: :succeeded,
      effective_step: succeeded,
      attempt_count: 2
    )
  end
end
