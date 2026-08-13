require "rails_helper"

RSpec.describe Claims::IngestRun do
  it "uses the structured ingest failure schema without the retired messages column" do
    expect(described_class.column_names).to include(
      "failure_category",
      "failure_code",
      "pipeline_error_code",
      "pipeline_error_description"
    )
    expect(described_class.column_names).not_to include("messages")
  end
end
