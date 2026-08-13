require "rails_helper"

RSpec.describe Claims::Ingest::RetryPolicy do
  it "keeps every processing worker on the same total attempt count" do
    workers = [
      Claims::RunIngestReadOcrJob,
      Claims::RunIngestTriageJob,
      Claims::RunSupportingDocumentTypeExtractionJob,
      Claims::RunOcrJob,
      Claims::RunGenaiJob,
      Claims::RunGenaiRulesetJob,
      Claims::FinalizeGenaiValidationJob,
      Claims::Ingest::AdvanceRunJob
    ]

    expect(
      workers.map { |worker| worker.get_sidekiq_options.fetch("retry") }.uniq
    ).to eq([described_class.sidekiq_retries])
    expect(described_class.sidekiq_retries + 1).to eq(
      described_class::MAX_ATTEMPTS
    )
  end
end
