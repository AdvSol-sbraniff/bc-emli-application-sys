require "rails_helper"

RSpec.describe Claims::PipelineAudit::CheckRun do
  describe ".call" do
    it "clears checker fields when a completed new-upload trace is coherent" do
      context = build_context
      run =
        create_run(
          context: context,
          status: "succeeded",
          pipeline_error_code: "old_error",
          pipeline_error_description: "old description"
        )
      create_step(run: run, step_type: "upload_package_stage")
      create_final_steps(run: run, invoice_version: context[:invoice_version])

      result = described_class.call(ingest_run_id: run.id)

      expect(result.ok).to be(true)
      expect(result.pipeline_kind).to eq("new_upload")
      expect(run.reload.pipeline_error_code).to be_nil
      expect(run.pipeline_error_description).to be_nil
    end

    it "flags a fix run that creates fix_ocr_invoice for a cloned invoice" do
      context = build_context(versionno: 2)
      run = create_run(context: context, status: "succeeded", total_files: 1)
      create_step(run: run, step_type: "fix_upload_package_stage")
      create_step(
        run: run,
        invoice_version: context[:invoice_version],
        step_type: "fix_clone_existing_evidence"
      )
      create_cloned_ingest_document(
        context: context,
        run: run,
        document_kind: "invoice",
        original_filename: "Fenestration invoice.pdf"
      )
      create_step(
        run: run,
        invoice_version: context[:invoice_version],
        step_type: "fix_ocr_invoice"
      )
      create_final_steps(run: run, invoice_version: context[:invoice_version])

      result = described_class.call(ingest_run_id: run.id)

      expect(result.ok).to be(false)
      expect(run.reload.pipeline_error_code).to eq(
        "fix_ocr_invoice_for_cloned_invoice"
      )
      expect(run.pipeline_error_description).to include("cloned invoice")
    end

    it "flags fix support extraction for a cloned-only supporting document type" do
      context = build_context(versionno: 2)
      type =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "test_checker_cloned_only_label"
        ) do |row|
          row.description = "Checker Cloned Only Label"
          row.created_at = Time.current
          row.updated_at = Time.current
        end
      run = create_run(context: context, status: "succeeded", total_files: 2)
      create_step(run: run, step_type: "fix_upload_package_stage")
      create_step(
        run: run,
        invoice_version: context[:invoice_version],
        step_type: "fix_clone_existing_evidence"
      )
      create_cloned_ingest_document(
        context: context,
        run: run,
        document_kind: "invoice",
        original_filename: "Fenestration invoice.pdf"
      )
      create_cloned_ingest_document(
        context: context,
        run: run,
        document_kind: "supporting_document",
        original_filename: "Fenestration energy tag (1).jpeg",
        supporting_document_type: type
      )
      create_step(
        run: run,
        invoice_version: context[:invoice_version],
        supporting_document_type: type,
        step_type: "fix_supporting_document_extraction"
      )
      create_final_steps(run: run, invoice_version: context[:invoice_version])

      result = described_class.call(ingest_run_id: run.id)

      expect(result.ok).to be(false)
      expect(run.reload.pipeline_error_code).to eq(
        "fix_extracted_cloned_only_support_type"
      )
      expect(run.pipeline_error_description).to include(
        "affected by new/replaced support docs"
      )
    end
  end

  def build_context(versionno: 1)
    contractor = Contractor.create!(business_name: "Checker Contractor")
    session = Claims::Session.create!
    invoice =
      Claims::Invoice.create!(
        session_id: session.id,
        contractor_id: contractor.id,
        status: "genai_complete"
      )
    invoice_version =
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: versionno,
        storage_provider: "azure_blob",
        storage_key: "checker/invoice.pdf",
        original_filename: "Fenestration invoice.pdf",
        content_type: "application/pdf",
        di_raw_json: {
          "ok" => true
        }
      )

    {
      contractor: contractor,
      session: session,
      invoice: invoice,
      invoice_version: invoice_version
    }
  end

  def create_run(context:, status:, total_files: 1, **attrs)
    Claims::IngestRun.create!(
      {
        session_id: context[:session].id,
        contractor_id: context[:contractor].id,
        resolved_invoice_version_id: context[:invoice_version].id,
        status: status,
        total_files: total_files,
        completed_files: total_files,
        failed_files: 0,
        completed_at: Time.current
      }.merge(attrs)
    )
  end

  def create_step(
    run:,
    step_type:,
    invoice_version: nil,
    ingest_document: nil,
    supporting_document_type: nil,
    status: "succeeded"
  )
    Claims::IngestStepRun.create!(
      ingest_run_id: run.id,
      session_id: run.session_id,
      invoice_version_id: invoice_version&.id,
      ingest_document_id: ingest_document&.id,
      supporting_document_type_id: supporting_document_type&.id,
      step_type: step_type,
      status: status,
      error_text: status == "failed" ? "failed" : nil,
      created_at: Time.current,
      updated_at: Time.current
    )
  end

  def create_final_steps(run:, invoice_version:)
    %w[case_facts aggregate_advice].each do |step_type|
      create_step(
        run: run,
        invoice_version: invoice_version,
        step_type: step_type
      )
    end
  end

  def create_cloned_ingest_document(
    context:,
    run:,
    document_kind:,
    original_filename:,
    supporting_document_type: nil
  )
    Claims::IngestDocument.create!(
      ingest_run_id: run.id,
      session_id: context[:session].id,
      contractor_id: context[:contractor].id,
      invoice_id: context[:invoice].id,
      resolved_invoice_id: context[:invoice].id,
      resolved_invoice_version_id: context[:invoice_version].id,
      storage_provider: "azure_blob",
      storage_key: "cloned/#{original_filename}",
      original_filename: original_filename,
      content_type:
        (
          if original_filename.downcase.end_with?(".pdf")
            "application/pdf"
          else
            "image/jpeg"
          end
        ),
      di_read_raw_json: {
        "cloned" => true
      },
      classifier_raw_json: {
        "cloned" => true
      },
      document_kind: document_kind,
      document_kind_reason: "Cloned from prior invoice version.",
      supporting_document_type_id: supporting_document_type&.id,
      classification_status: "classified",
      classification_confidence: 100,
      classification_reason: "Cloned from prior invoice version.",
      classified_at: Time.current
    )
  end
end
