require "rails_helper"

RSpec.describe Claims::Ingest::CreateDraftBatch do
  describe ".call" do
    it "rolls back the shell and run when atomic staging initialization fails" do
      contractor =
        Contractor.create!(business_name: "Upload Failure Contractor")
      raw_error =
        NoMethodError.new(
          "undefined method `completed_at=' for Claims::IngestStepRun"
        )
      allow(Claims::IngestStepRun).to receive(:create!).and_raise(raw_error)

      raised_error = nil
      expect do
        described_class.call(
          contractor_id: contractor.id,
          files: [instance_double("UploadedFile")],
          log_prefix: "create_draft_batch_spec"
        )
      end.to raise_error(
        Claims::Ingest::UploadErrors::UnexpectedError
      ) { |error| raised_error = error }

      expect(raised_error.message).to eq(
        Claims::Ingest::UploadErrors::SAFE_TECHNICAL_MESSAGE
      )
      expect(raised_error.cause).to equal(raw_error)
      expect(raised_error.diagnostic_id).to be_present
      expect(raised_error.ingest_run_id).to be_nil
      expect(raised_error.invoice_id).to be_nil
      expect(Claims::IngestRun.count).to eq(0)
      expect(Claims::Invoice.count).to eq(0)
    end

    it "does not create a run for a request validation error" do
      contractor = Contractor.create!(business_name: "No Files Contractor")
      run_count = Claims::IngestRun.count

      expect do
        described_class.call(contractor_id: contractor.id, files: [])
      end.to raise_error(
        Claims::Ingest::UploadErrors::ValidationError,
        "Select at least one invoice or supporting document to upload."
      )
      expect(Claims::IngestRun.count).to eq(run_count)
    end
  end
end
