require "rails_helper"
require "digest"

RSpec.describe "Claims fix-package end-to-end state flow" do
  it "processes the real demo3 replacement through the shared lifecycle" do
    contractor = Contractor.create!(business_name: "Demo3 fix contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "contractor_revision_inbox"
      )
    source =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "test",
        storage_key: "demo3/invoice_c1.PDF",
        original_filename: "invoice_c1.PDF",
        content_type: "application/pdf",
        di_raw_json: {
          "documents" => []
        }
      )
    upgrade =
      Claims::InvoiceUpgradeType.find_by!(
        upgrade_type_key: "electrical_service_upgrade"
      )
    common = Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
    Claims::InvoiceVersionUpgradeType.create!(
      invoice_version_id: source.id,
      invoice_upgrade_type_id: upgrade.id,
      confidence: 99
    )
    path =
      Rails.root.join(
        "claims_ai_service_documentation",
        "Test Data",
        "demo3_aug7_ESU",
        "invoice_c1_fixed.PDF"
      )
    upload = Rack::Test::UploadedFile.new(path, "application/pdf")

    allow(Claims::Ingest::UploadEvidenceFileToNode).to receive(:call) do |args|
      file = args.fetch(:file)
      {
        "storage_key" => "demo3/fix/#{args.fetch(:upload_scope_id)}.pdf",
        "byte_size" => file.size,
        "sha256" => Digest::SHA256.file(file.path).hexdigest
      }
    end
    allow(Claims::RunIngestReadOcrJob).to receive(:perform_async).and_return(
      "read-job"
    )
    allow(Claims::RunIngestTriageJob).to receive(:perform_async).and_return(
      "triage-job"
    )
    allow(Claims::RunOcrJob).to receive(:perform_async).and_return("ocr-job")
    allow(Claims::RunGenaiJob).to receive(:perform_async).and_return(
      "genai-job"
    )
    allow(Claims::FinalizeGenaiValidationJob).to receive(
      :perform_async
    ).and_return("final-job")

    result =
      Claims::Ingest::UploadFixPackage.call(
        invoice_id: invoice.id,
        files: [upload]
      )
    run = Claims::IngestRun.find(result.ingest_run_id)
    document = Claims::IngestDocument.find_by!(ingest_run_id: run.id)
    document.update!(di_read_raw_json: { "content" => "fixed invoice" })
    Claims::IngestStepRun.find_by!(
      ingest_run_id: run.id,
      ingest_document_id: document.id,
      step_type: "read_document"
    ).update!(status: "succeeded")
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

    classifier_payload = {
      "document_kind" => "invoice",
      "document_kind_confidence" => 99,
      "detected_upgrade_types" => [
        {
          "upgrade_type_key" => upgrade.upgrade_type_key,
          "confidence" => 99,
          "evidence_text" => "Electrical service upgrade"
        }
      ]
    }
    document.update!(
      classifier_raw_json: classifier_payload,
      document_kind: "invoice",
      document_kind_confidence: 99,
      document_kind_reason: "Replacement invoice",
      classification_confidence: 99,
      classification_reason: "Replacement invoice",
      classified_at: Time.current
    )
    Claims::IngestStepRun.find_by!(
      ingest_run_id: run.id,
      ingest_document_id: document.id,
      step_type: "classify_document"
    ).update!(status: "succeeded", genai_results_json: classifier_payload)
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

    replacement =
      Claims::InvoiceVersion.find(run.reload.resolved_invoice_version_id)
    expect(replacement.invoice_versionno).to eq(2)
    replacement.update!(di_raw_json: { "documents" => [] })
    Claims::IngestStepRun.find_by!(
      ingest_run_id: run.id,
      invoice_version_id: replacement.id,
      step_type: "extract_invoice"
    ).update!(status: "succeeded")
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

    Claims::IngestStepRun.find_by!(
      ingest_run_id: run.id,
      invoice_version_id: replacement.id,
      step_type: "case_facts"
    ).update!(status: "succeeded", genai_results_json: { "case_facts" => {} })
    [
      [common, "evaluate_genai_ruleset"],
      [upgrade, "evaluate_genai_ruleset"]
    ].each do |upgrade_type, step_type|
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: run.session_id,
        invoice_version_id: replacement.id,
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
      invoice_version_id: replacement.id,
      step_type: "finalize_validation"
    ).update!(status: "succeeded", genai_results_json: {})
    Claims::Ingest::AdvanceRun.call(ingest_run_id: run.id)

    expect(run.reload).to have_attributes(
      status: "succeeded",
      failure_category: nil,
      pipeline_error_code: nil
    )
    expect(invoice.reload.status).to eq("contractor_revision_inbox")
    expect(Claims::InvoiceVersion.where(invoice_id: invoice.id).count).to eq(2)
  ensure
    upload&.close
  end
end
