require "rails_helper"

RSpec.describe Claims::Ingest::CreateDraftBatch do
  describe ".call" do
    it "terminally records a technical failure created before the staging step" do
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

      run = Claims::IngestRun.find(raised_error.ingest_run_id)
      invoice = Claims::Invoice.find(raised_error.invoice_id)

      expect(raised_error.message).to eq(
        Claims::Ingest::UploadErrors::SAFE_TECHNICAL_MESSAGE
      )
      expect(raised_error.cause).to equal(raw_error)
      expect(raised_error.diagnostic_id).to be_present
      expect(run).to have_attributes(
        status: "failed",
        failure_status: "technical_failure",
        failure_status_subtype: "upload_unexpected_exception",
        pipeline_error_code: "upload_unexpected_exception"
      )
      expect(run.completed_at).to be_present
      expect(invoice).to have_attributes(
        status: "technical_failure",
        status_subtype: "upload_unexpected_exception"
      )
      expect(run.pipeline_error_description).not_to include("undefined method")
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
