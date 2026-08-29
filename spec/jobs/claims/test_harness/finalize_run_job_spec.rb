require "rails_helper"

RSpec.describe Claims::TestHarness::FinalizeRunJob do
  subject(:job) { described_class.new }

  def relation_for(cases)
    relation = double
    allow(relation).to receive(:includes).with(:test_suite_case).and_return(
      relation
    )
    allow(relation).to receive(:order).with(:created_at, :id).and_return(
      relation
    )
    allow(relation).to receive(:to_a).and_return(cases)
    relation
  end

  it "starts the next queued package after an earlier package fails" do
    failed_case = double(status: "failed")
    queued_case = double(id: SecureRandom.uuid, status: "queued")
    parent =
      instance_double(
        Claims::TestRunRegression,
        status: "running",
        test_cases: relation_for([failed_case, queued_case])
      )
    allow(job).to receive(:parent_for).and_return(parent)
    expect(Claims::TestHarness::RunCaseJob).to receive(:perform_async).with(
      "regression",
      queued_case.id
    )

    job.perform("regression", SecureRandom.uuid)
  end

  it "completes a regression after every package completes" do
    completed_case = double(status: "completed")
    parent =
      instance_double(
        Claims::TestRunRegression,
        status: "running",
        test_cases: relation_for([completed_case])
      )
    allow(job).to receive(:parent_for).and_return(parent)
    expect(parent).to receive(:update!).with(status: "completed")

    job.perform("regression", SecureRandom.uuid)
  end

  it "leaves a model comparison running when its evaluator error is retryable" do
    completed_case = double(status: "completed")
    parent =
      instance_double(
        Claims::TestRunModelCompare,
        status: "running",
        comparison_deployment_name: "evaluator-terra",
        test_cases: relation_for([completed_case])
      )
    error =
      Claims::Genai::NodeClient::Error.new(
        http_status: 429,
        payload: {
          retryable: true
        }
      )
    allow(job).to receive(:parent_for).and_return(parent)
    allow(Claims::TestHarness::Evaluator).to receive(:finalize_model).and_raise(
      error
    )
    expect(parent).not_to receive(:update!)

    expect do
      job.perform("model_compare", SecureRandom.uuid)
    end.to raise_error(error)
  end
end
