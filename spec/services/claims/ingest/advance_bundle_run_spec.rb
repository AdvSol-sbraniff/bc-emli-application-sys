require "rails_helper"

RSpec.describe Claims::Ingest::AdvanceBundleRun do
  describe ".call" do
    around do |example|
      previous = ENV["CLAIMS_INGEST_STEP_ATTEMPT_LIMIT"]
      ENV["CLAIMS_INGEST_STEP_ATTEMPT_LIMIT"] = "4"
      example.run
    ensure
      ENV["CLAIMS_INGEST_STEP_ATTEMPT_LIMIT"] = previous
    end

    it "treats cloned invoice evidence as reused and gates fix OCR/classifier on new files" do
      now = Time.zone.parse("2026-06-22 10:07:24")
      contractor = Contractor.create!(business_name: "Test Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      source_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "source/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: {
            "source" => "invoice-di"
          },
          created_at: now,
          updated_at: now
        )
      new_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 2,
          storage_provider: "azure_blob",
          storage_key: "cloned/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: source_version.di_raw_json,
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 3,
          completed_files: 0,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      type =
        Claims::SupportingDocumentType.find_or_create_by!(
          type_key: "test_fenestration_label_no_fields"
        ) do |row|
          row.description = "Test Fenestration Label With No Fields"
          row.created_at = now
          row.updated_at = now
        end

      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        step_type: "fix_upload_package_stage",
        status: "succeeded",
        created_at: now,
        updated_at: now
      )
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        invoice_version_id: new_version.id,
        step_type: "fix_clone_existing_evidence",
        status: "queued",
        created_at: now,
        updated_at: now
      )
      cloned_invoice_document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: new_version.id,
          storage_provider: "azure_blob",
          storage_key: new_version.storage_key,
          original_filename: new_version.original_filename,
          content_type: new_version.content_type,
          di_read_raw_json: source_version.di_raw_json,
          document_kind: "invoice",
          document_kind_reason: "Cloned from prior invoice version.",
          classification_status: "classified",
          classification_confidence: 100,
          classification_reason: "Cloned from prior invoice version.",
          classified_at: now,
          created_at: now,
          updated_at: now
        )
      new_support_document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: new_version.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/tag-1.jpg",
          original_filename: "Fenestration energy tag (1).jpeg",
          content_type: "image/jpeg",
          di_read_raw_json: {
            "read" => "tag"
          },
          classifier_raw_json: {
            "classified" => true
          },
          document_kind: "supporting_document",
          document_kind_reason: "Classified from new fix evidence.",
          supporting_document_type_id: type.id,
          classification_status: "classified",
          classification_confidence: 99,
          classification_reason: "Fenestration label.",
          classified_at: now + 20.seconds,
          created_at: now,
          updated_at: now + 20.seconds
        )
      %w[fix_ocr_read fix_classifier_files].each do |step_type|
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          ingest_document_id: new_support_document.id,
          step_type: step_type,
          status: "succeeded",
          created_at: now + 10.seconds,
          updated_at: now + 20.seconds
        )
      end

      allow(Claims::RunOcrJob).to receive(:perform_async)
      allow(Claims::RunGenaiJob).to receive(:perform_async)

      described_class.call(ingest_run_id: run.id)

      expect(run.reload.resolved_invoice_version_id).to eq(new_version.id)
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          ingest_document_id: cloned_invoice_document.id
        )
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          step_type: "fix_clone_existing_evidence"
        ).pick(:status)
      ).to eq("succeeded")
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          invoice_version_id: new_version.id,
          step_type: "fix_ocr_invoice"
        )
      ).to be_empty
      expect(Claims::RunOcrJob).not_to have_received(:perform_async)
      expect(Claims::RunGenaiJob).to have_received(:perform_async).with(
        session.id,
        new_version.id,
        run.id,
        "use_existing_classifier"
      )
    end

    it "does not rerun supporting-document extraction for unchanged cloned fix evidence" do
      now = Time.zone.parse("2026-06-22 11:00:00")
      contractor = Contractor.create!(business_name: "No-op Fix Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      source_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "source/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: {
            "source" => "invoice-di"
          },
          created_at: now,
          updated_at: now
        )
      new_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 2,
          storage_provider: "azure_blob",
          storage_key: "cloned/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: source_version.di_raw_json,
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 2,
          completed_files: 0,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      type =
        Claims::SupportingDocumentType.create!(
          type_key: "test_noop_fix_label",
          description: "Test No-op Fix Label",
          created_at: now,
          updated_at: now
        )
      Claims::SupportingDocumentTypeLocatedField.create!(
        supporting_document_type_id: type.id,
        field_key: "model_number",
        prompt_text: "Find the model number.",
        field_number: 1,
        created_at: now,
        updated_at: now
      )

      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        step_type: "fix_upload_package_stage",
        status: "succeeded",
        created_at: now,
        updated_at: now
      )
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        resolved_invoice_version_id: new_version.id,
        storage_provider: "azure_blob",
        storage_key: new_version.storage_key,
        original_filename: new_version.original_filename,
        content_type: new_version.content_type,
        di_read_raw_json: source_version.di_raw_json,
        document_kind: "invoice",
        document_kind_reason: "Cloned from prior invoice version.",
        classification_status: "classified",
        classification_confidence: 100,
        classification_reason: "Cloned from prior invoice version.",
        classified_at: now,
        created_at: now,
        updated_at: now
      )
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        resolved_invoice_version_id: new_version.id,
        storage_provider: "azure_blob",
        storage_key: "cloned/tag-1.jpg",
        original_filename: "Fenestration energy tag (1).jpeg",
        content_type: "image/jpeg",
        di_read_raw_json: {
          "read" => "tag"
        },
        classifier_raw_json: {
          "classified" => true
        },
        document_kind: "supporting_document",
        document_kind_reason: "Cloned from prior supporting document.",
        supporting_document_type_id: type.id,
        classification_status: "classified",
        classification_confidence: 99,
        classification_reason: "Cloned from prior supporting document.",
        classified_at: now,
        created_at: now,
        updated_at: now
      )

      allow(Claims::RunSupportingDocumentTypeExtractionJob).to receive(
        :perform_async
      )
      allow(Claims::RunOcrJob).to receive(:perform_async)
      allow(Claims::RunGenaiJob).to receive(:perform_async)

      described_class.call(ingest_run_id: run.id)

      expect(
        Claims::RunSupportingDocumentTypeExtractionJob
      ).not_to have_received(:perform_async)
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          step_type: "fix_supporting_document_extraction"
        )
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          step_type: "fix_ocr_invoice"
        )
      ).to be_empty
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          step_type: "fix_clone_existing_evidence"
        ).pick(:status)
      ).to eq("succeeded")
      expect(Claims::RunOcrJob).not_to have_received(:perform_async)
      expect(Claims::RunGenaiJob).to have_received(:perform_async).with(
        session.id,
        new_version.id,
        run.id,
        "use_existing_classifier"
      )
    end

    it "extracts only supporting-document types affected by new fix evidence" do
      now = Time.zone.parse("2026-06-22 11:30:00")
      contractor = Contractor.create!(business_name: "Changed Fix Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      source_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 1,
          storage_provider: "azure_blob",
          storage_key: "source/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: {
            "source" => "invoice-di"
          },
          created_at: now,
          updated_at: now
        )
      new_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 2,
          storage_provider: "azure_blob",
          storage_key: "cloned/invoice.pdf",
          original_filename: "Fenestration invoice.pdf",
          content_type: "application/pdf",
          di_raw_json: source_version.di_raw_json,
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 3,
          completed_files: 0,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      cloned_only_type =
        Claims::SupportingDocumentType.create!(
          type_key: "test_cloned_only_label",
          description: "Test Cloned-only Label",
          created_at: now,
          updated_at: now
        )
      changed_type =
        Claims::SupportingDocumentType.create!(
          type_key: "test_changed_fix_label",
          description: "Test Changed Fix Label",
          created_at: now,
          updated_at: now
        )
      [cloned_only_type, changed_type].each_with_index do |type, index|
        Claims::SupportingDocumentTypeLocatedField.create!(
          supporting_document_type_id: type.id,
          field_key: "field_#{index + 1}",
          prompt_text: "Find field #{index + 1}.",
          field_number: 1,
          created_at: now,
          updated_at: now
        )
      end

      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        step_type: "fix_upload_package_stage",
        status: "succeeded",
        created_at: now,
        updated_at: now
      )
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        resolved_invoice_version_id: new_version.id,
        storage_provider: "azure_blob",
        storage_key: new_version.storage_key,
        original_filename: new_version.original_filename,
        content_type: new_version.content_type,
        di_read_raw_json: source_version.di_raw_json,
        document_kind: "invoice",
        document_kind_reason: "Cloned from prior invoice version.",
        classification_status: "classified",
        classification_confidence: 100,
        classification_reason: "Cloned from prior invoice version.",
        classified_at: now,
        created_at: now,
        updated_at: now
      )
      Claims::IngestDocument.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        contractor_id: contractor.id,
        invoice_id: invoice.id,
        resolved_invoice_id: invoice.id,
        resolved_invoice_version_id: new_version.id,
        storage_provider: "azure_blob",
        storage_key: "cloned/cloned-only.jpg",
        original_filename: "Prior unchanged label.jpeg",
        content_type: "image/jpeg",
        di_read_raw_json: {
          "read" => "cloned"
        },
        classifier_raw_json: {
          "classified" => true
        },
        document_kind: "supporting_document",
        document_kind_reason: "Cloned from prior supporting document.",
        supporting_document_type_id: cloned_only_type.id,
        classification_status: "classified",
        classification_confidence: 99,
        classification_reason: "Cloned from prior supporting document.",
        classified_at: now,
        created_at: now,
        updated_at: now
      )
      new_support_document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: new_version.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/new-label.jpg",
          original_filename: "New fenestration label.jpeg",
          content_type: "image/jpeg",
          di_read_raw_json: {
            "read" => "new"
          },
          classifier_raw_json: {
            "classified" => true
          },
          document_kind: "supporting_document",
          document_kind_reason: "Classified from new fix evidence.",
          supporting_document_type_id: changed_type.id,
          classification_status: "classified",
          classification_confidence: 99,
          classification_reason: "New supporting document.",
          classified_at: now + 20.seconds,
          created_at: now,
          updated_at: now + 20.seconds
        )
      %w[fix_ocr_read fix_classifier_files].each do |step_type|
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          ingest_document_id: new_support_document.id,
          step_type: step_type,
          status: "succeeded",
          created_at: now + 10.seconds,
          updated_at: now + 20.seconds
        )
      end

      allow(Claims::RunSupportingDocumentTypeExtractionJob).to receive(
        :perform_async
      )

      described_class.call(ingest_run_id: run.id)

      expect(Claims::RunSupportingDocumentTypeExtractionJob).to have_received(
        :perform_async
      ).once.with(
        new_version.id,
        changed_type.id,
        run.id,
        "fix_supporting_document_extraction"
      )
      expect(
        Claims::IngestStepRun.where(
          ingest_run_id: run.id,
          step_type: "fix_supporting_document_extraction"
        ).pluck(:supporting_document_type_id)
      ).to eq([changed_type.id])
    end

    it "keeps the run active after a failed classifier attempt that still has worker retries" do
      now = Time.zone.parse("2026-06-22 13:03:12")
      contractor = Contractor.create!(business_name: "Retry Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 1,
          completed_files: 0,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/tag-1.jpg",
          original_filename: "Fenestration energy tag (1).jpeg",
          content_type: "image/jpeg",
          di_read_raw_json: {
            "read" => "tag"
          },
          created_at: now,
          updated_at: now
        )

      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "ocr_read",
        status: "succeeded",
        created_at: now - 30.seconds,
        updated_at: now - 20.seconds
      )
      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "classifier_files",
        status: "failed",
        error_text: "RuntimeError: Node GenAI failed 502: Request timed out.",
        created_at: now,
        updated_at: now
      )

      described_class.call(ingest_run_id: run.id)

      expect(run.reload.status).to eq("running")
      expect(run.failed_files).to eq(0)
      expect(run.completed_at).to be_nil
      expect(invoice.reload.status).to eq("ocr_in_progress")
    end

    it "marks the run failed once classifier attempts for the same file are exhausted" do
      now = Time.zone.parse("2026-06-22 13:03:12")
      contractor = Contractor.create!(business_name: "Retry Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "running",
          total_files: 1,
          completed_files: 0,
          failed_files: 0,
          created_at: now,
          updated_at: now
        )
      document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/tag-1.jpg",
          original_filename: "Fenestration energy tag (1).jpeg",
          content_type: "image/jpeg",
          di_read_raw_json: {
            "read" => "tag"
          },
          created_at: now,
          updated_at: now
        )

      Claims::IngestStepRun.create!(
        ingest_run_id: run.id,
        session_id: session.id,
        ingest_document_id: document.id,
        step_type: "ocr_read",
        status: "succeeded",
        created_at: now - 30.seconds,
        updated_at: now - 20.seconds
      )
      4.times do |index|
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          ingest_document_id: document.id,
          step_type: "classifier_files",
          status: "failed",
          error_text: "RuntimeError: Node GenAI failed 502: Request timed out.",
          created_at: now + index.seconds,
          updated_at: now + index.seconds
        )
      end

      described_class.call(ingest_run_id: run.id)

      expect(run.reload.status).to eq("failed")
      expect(run.failed_files).to eq(1)
      expect(run.completed_at).to be_present
    end
  end
end
