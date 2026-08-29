require "rails_helper"

RSpec.describe Claims::TestHarness::Scheduling do
  before do
    allow(Claims::TestHarness::RunLookup).to receive(:harness_run?).and_return(
      true
    )
    stub_const(
      "Claims::TestHarness::Scheduling::DEFAULT_GENAI_INTERVAL_SECONDS",
      60
    )
  end

  it "paces a harness retry with exponential backoff" do
    job_class = class_double(Claims::RunIngestTriageJob)
    allow(job_class).to receive(:perform_in)

    handled =
      described_class.retry_job(
        job_class,
        "run-id",
        "document-id",
        "run-id",
        attempt_count: 3
      )

    expect(handled).to be(true)
    expect(job_class).to have_received(:perform_in).with(
      240.seconds,
      "document-id",
      "run-id"
    )
  end

  it "does not enqueue a fifth attempt" do
    job_class = class_double(Claims::RunIngestTriageJob)
    allow(job_class).to receive(:perform_in)

    handled =
      described_class.retry_job(
        job_class,
        "run-id",
        "document-id",
        "run-id",
        attempt_count: Claims::Ingest::RetryPolicy::MAX_ATTEMPTS
      )

    expect(handled).to be(true)
    expect(job_class).not_to have_received(:perform_in)
  end
end
