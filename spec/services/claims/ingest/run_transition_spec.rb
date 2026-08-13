require "rails_helper"

RSpec.describe Claims::Ingest::RunTransition do
  let(:contractor) do
    Contractor.create!(business_name: "Transition Contractor")
  end
  let(:session) { Claims::Session.create! }
  let(:invoice) do
    Claims::Invoice.create!(
      session_id: session.id,
      contractor_id: contractor.id,
      status: "contractor_precheck"
    )
  end
  let(:run) do
    Claims::IngestRun.create!(
      run_kind: "initial_upload",
      session_id: session.id,
      contractor_id: contractor.id,
      invoice_id: invoice.id,
      status: "queued",
      total_files: 1
    )
  end
  let(:invoice_version) do
    Claims::InvoiceVersion.create!(
      invoice_id: invoice.id,
      invoice_versionno: 1,
      storage_provider: "test",
      storage_key: "transition/invoice.pdf",
      original_filename: "invoice.pdf",
      content_type: "application/pdf"
    )
  end

  before { allow(Claims::PipelineAudit::CheckRun).to receive(:call) }

  it "keeps processing transitions nonterminal" do
    described_class.mark_running!(run: run, total_files: 1)

    expect(run.reload).to have_attributes(
      status: "running",
      failure_category: nil,
      failure_code: nil,
      pipeline_error_code: nil,
      completed_at: nil
    )
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  it "completes the run without changing invoice business ownership" do
    run.update!(
      status: "running",
      resolved_invoice_version_id: invoice_version.id
    )

    described_class.mark_succeeded!(run: run, total_files: 1)

    expect(run.reload).to have_attributes(
      status: "succeeded",
      completed_files: 1,
      failed_files: 0,
      failure_category: nil
    )
    expect(run.completed_at).to be_present
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  it "stores one authoritative terminal failure" do
    run.update!(status: "running")

    described_class.mark_failed!(
      run: run,
      total_files: 1,
      failed_files: 1,
      failure_category: "technical_failure",
      failure_code: "genai_service_error",
      pipeline_error_code: "genai_provider_gateway_error",
      pipeline_error_description: "GenAI failed after four attempts."
    )

    expect(run.reload).to have_attributes(
      status: "failed",
      failed_files: 1,
      failure_category: "technical_failure",
      failure_code: "genai_service_error",
      pipeline_error_code: "genai_provider_gateway_error"
    )
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  it "does not reopen a terminal run" do
    described_class.mark_failed!(
      run: run,
      total_files: 1,
      failed_files: 1,
      failure_category: "technical_failure",
      failure_code: "unknown_runtime_failure",
      pipeline_error_code: "pipeline_failed",
      pipeline_error_description: "The run failed."
    )

    changed = described_class.mark_running!(run: run, total_files: 1)

    expect(changed).to be(false)
    expect(run.reload.status).to eq("failed")
    expect(invoice.reload.status).to eq("contractor_precheck")
  end

  it "does not clean contractor artifacts while another attempt is active" do
    run.update!(cleanup_failed_invoice_artifacts: true)
    active_step =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        step_type: "stage_package",
        status: "in_progress"
      )
    allow(Claims::Ingest::CleanupFailedContractorUpload).to receive(:call)

    described_class.mark_failed!(
      run: run,
      total_files: 1,
      failed_files: 1,
      failure_category: "technical_failure",
      failure_code: "unknown_runtime_failure",
      pipeline_error_code: "pipeline_failed",
      pipeline_error_description: "The run failed."
    )

    expect(Claims::Ingest::CleanupFailedContractorUpload).not_to have_received(
      :call
    )

    active_step.update!(
      status: "failed",
      error_text: "Cancelled after terminal failure.",
      retryable: false
    )
    described_class.reconcile_terminal_cleanup!(run: run)

    expect(Claims::Ingest::CleanupFailedContractorUpload).to have_received(
      :call
    ).with(ingest_run: run)
  end
end
