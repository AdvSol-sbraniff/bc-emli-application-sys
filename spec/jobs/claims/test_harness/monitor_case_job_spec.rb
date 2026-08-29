require "rails_helper"

RSpec.describe Claims::TestHarness::MonitorCaseJob do
  subject(:job) { described_class.new }

  it "persists one model-comparison domain before scheduling the next" do
    parent = double(comparison_deployment_name: "evaluator-terra")
    baseline_version = double
    baseline_run = double
    candidate_version = double
    candidate_run = double
    test_case =
      double(
        id: SecureRandom.uuid,
        test_run: parent,
        baseline_invoice_version: baseline_version,
        baseline_ingest_run: baseline_run,
        document_classification_comparison: nil,
        supporting_document_extraction_comparison: nil,
        upgrade_analysis_comparison: nil
      )
    allow(Claims::TestHarness::EvidenceSnapshot).to receive(:for_domain).with(
      domain: :document_classification,
      invoice_version: baseline_version,
      ingest_run: baseline_run
    ).and_return({ source: "baseline" })
    allow(Claims::TestHarness::EvidenceSnapshot).to receive(:for_domain).with(
      domain: :document_classification,
      invoice_version: candidate_version,
      ingest_run: candidate_run
    ).and_return({ source: "candidate" })
    allow(Claims::TestHarness::Evaluator).to receive(:compare).and_return(
      "Equivalent evidence"
    )
    allow(Claims::TestHarness::Scheduling).to receive(
      :genai_interval
    ).and_return(60.seconds)
    expect(test_case).to receive(:update!).with(
      document_classification_comparison: "Equivalent evidence"
    )
    expect(described_class).to receive(:perform_in).with(
      60.seconds,
      "model_compare",
      test_case.id
    )

    result =
      job.send(
        :complete_model_compare,
        test_case,
        candidate_run,
        candidate_version
      )

    expect(result).to be(false)
    expect(Claims::TestHarness::Evaluator).to have_received(:compare).with(
      domain: :document_classification,
      baseline: {
        source: "baseline"
      },
      candidate: {
        source: "candidate"
      },
      deployment_name: "evaluator-terra"
    )
  end

  it "completes without another evaluator call after all three domains exist" do
    test_case =
      double(
        test_run: double,
        baseline_invoice_version: double,
        baseline_ingest_run: double,
        document_classification_comparison: "done",
        supporting_document_extraction_comparison: "done",
        upgrade_analysis_comparison: "done"
      )
    expect(test_case).to receive(:update!).with(
      status: "completed",
      failure_code: nil
    )
    expect(Claims::TestHarness::Evaluator).not_to receive(:compare)

    result = job.send(:complete_model_compare, test_case, double, double)

    expect(result).to be(true)
  end
end
