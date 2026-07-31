require "rails_helper"

RSpec.describe Claims::Ingest::CleanupFailedContractorUpload do
  it "deletes failed evidence but retains the scrubbed run ledger and relationships" do
    contractor = Contractor.create!(business_name: "Cleanup Contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "package_needs_correction",
        status_subtype: "package_unreadable_file"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "failed/invoice.pdf",
        original_filename: "Invoice.pdf",
        content_type: "application/pdf"
      )
    run =
      Claims::IngestRun.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "failed",
        cleanup_failed_invoice_artifacts: true,
        total_files: 1,
        failed_files: 1
      )
    document =
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        resolved_invoice_version_id: invoice_version.id,
        storage_provider: "azure_blob",
        storage_key: "failed/photo.jpg",
        original_filename: "Photo.jpg",
        content_type: "image/jpeg",
        di_read_raw_json: {
          private_text: "sensitive OCR contents"
        }
      )
    succeeded_step =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "ocr_read",
        status: "succeeded",
        di_results_json: {
          private_text: "sensitive DI result"
        },
        context_window_json: [{ private_text: "sensitive prompt" }]
      )
    failed_step =
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "classifier_files",
        status: "failed",
        error_text: "Raw private provider response",
        genai_results_json: {
          "failure_status" => "package_needs_correction",
          "failure_status_subtype" => "package_unreadable_file",
          "error_code" => "genai_input_image_invalid",
          "error_category" => "provider_invalid_image",
          "retryable" => false,
          "diagnostic_id" => "diag-retained",
          "provider_status" => 400,
          "private_text" => "must be removed"
        },
        context_window_json: [{ private_text: "must be removed" }]
      )

    described_class.call(ingest_run: run)

    expect(Claims::Invoice.exists?(invoice.id)).to be(false)
    expect(Claims::InvoiceVersion.exists?(invoice_version.id)).to be(false)
    expect(Claims::IngestRun.exists?(run.id)).to be(true)
    expect(run.reload.status).to eq("failed")

    document.reload
    expect(document).to have_attributes(
      ingest_run_id: run.id,
      original_filename: "Photo.jpg",
      invoice_id: nil,
      resolved_invoice_id: nil,
      resolved_invoice_version_id: nil,
      promoted_supporting_document_id: nil,
      di_read_raw_json: nil,
      classifier_raw_json: nil
    )

    succeeded_step.reload
    failed_step.reload
    expect(succeeded_step.status).to eq("succeeded")
    expect(succeeded_step.ingest_document_id).to eq(document.id)
    expect(succeeded_step.completed_at).to be_present
    expect(succeeded_step.di_results_json).to be_nil
    expect(succeeded_step.context_window_json).to be_nil
    expect(succeeded_step.genai_results_json).to be_nil
    expect(succeeded_step.error_code).to be_nil

    expect(failed_step.status).to eq("failed")
    expect(failed_step.ingest_document_id).to eq(document.id)
    expect(failed_step.completed_at).to be_present
    expect(failed_step.context_window_json).to be_nil
    expect(failed_step.genai_results_json).to be_nil
    expect(failed_step).to have_attributes(
      failure_status: "package_needs_correction",
      failure_status_subtype: "package_unreadable_file",
      error_code: "genai_input_image_invalid",
      error_category: "provider_invalid_image",
      retryable: false,
      diagnostic_id: "diag-retained",
      provider_status: 400
    )
    expect(failed_step.error_text).not_to include(
      "Raw private provider response"
    )
  end
end
