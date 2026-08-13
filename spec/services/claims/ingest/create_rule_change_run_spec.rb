require "rails_helper"

RSpec.describe Claims::Ingest::CreateRuleChangeRun do
  def build_source
    contractor = Contractor.create!(business_name: "Rule refresh contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_precheck"
      )
    source =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "test",
        storage_key: "rule-refresh/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf",
        di_raw_json: {
          "documents" => []
        }
      )
    upgrade =
      Claims::InvoiceUpgradeType.find_by!(
        upgrade_type_key: "electrical_service_upgrade"
      )
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: source.id,
      invoice_upgrade_type_id: upgrade.id,
      confidence: 99
    )
    [contractor, invoice, source, upgrade]
  end

  it "uses the shared retry and fan-in lifecycle through terminal success" do
    contractor, invoice, source, upgrade = build_source
    common = Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
    allow(Claims::RunGenaiJob).to receive(:perform_async).and_return("case-job")
    allow(Claims::FinalizeGenaiValidationJob).to receive(
      :perform_async
    ).and_return("final-job")

    result = described_class.call(invoice_id: invoice.id)
    run = Claims::IngestRun.find(result.ingest_run_id)
    target = Claims::InvoiceVersion.find(result.invoice_version_id)
    expect(target.invoice_versionno).to eq(2)
    expect(target.di_raw_json).to eq(source.di_raw_json)
    expect(run.status).to eq("running")

    first_case_facts =
      Claims::IngestStepRun.find_by!(
        ingest_run_id: run.id,
        invoice_version_id: target.id,
        step_type: "case_facts"
      )
    first_case_facts.update!(
      status: "failed",
      error_text: "Injected temporary model failure",
      retryable: true,
      failure_category: "technical_failure",
      failure_code: "genai_service_error"
    )
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
    expect(run.reload.status).to eq("running")

    retry_case_facts =
      Claims::Ingest::StepClaim.call(
        ingest_run_id: run.id,
        session_id: run.session_id,
        invoice_version_id: target.id,
        step_type: "case_facts"
      )
    retry_case_facts.update!(
      status: "succeeded",
      genai_results_json: {
        "case_facts" => {
        }
      }
    )
    [
      [common, "evaluate_genai_ruleset"],
      [upgrade, "evaluate_genai_ruleset"]
    ].each do |upgrade_type, step_type|
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        invoice_version_id: target.id,
        invoice_upgrade_type_id: upgrade_type.id,
        step_type: step_type,
        status: "succeeded",
        genai_results_json: {
        }
      )
    end
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)
    Claims::IngestStepRun.find_by!(
      ingest_run_id: run.id,
      invoice_version_id: target.id,
      step_type: "finalize_validation"
    ).update!(status: "succeeded", genai_results_json: {})
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "succeeded",
      failure_category: nil,
      pipeline_error_code: nil
    )
    expect(invoice.reload.status).to eq("contractor_precheck")
    expect(
      Claims::Ingest::ContractorRunPresenter.call(
        run: run,
        contractor_id: contractor.id
      ).fetch(:presentation_state)
    ).to eq("ready")
  end

  it "terminally records a failure if validation cannot be scheduled" do
    _contractor, invoice, _source, _upgrade = build_source
    allow(Claims::Ingest::ValidationScheduler).to receive(:start!).and_raise(
      "queue unavailable"
    )

    expect do described_class.call(invoice_id: invoice.id) end.to raise_error(
      RuntimeError,
      "queue unavailable"
    )

    run = Claims::IngestRun.order(:created_at, :id).last
    expect(run).to have_attributes(
      status: "failed",
      failure_category: "technical_failure",
      pipeline_error_code: "rule_change_start_failed"
    )
    expect(run.completed_at).to be_present
    expect(invoice.reload.status).to eq("contractor_precheck")
  end
end
