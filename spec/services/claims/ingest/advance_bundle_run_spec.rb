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

    def windows_doors_upgrade_type(now)
      Claims::InvoiceUpgradeType.find_or_create_by!(
        upgrade_type_key: "windows_doors"
      ) do |row|
        row.description = "Windows and doors"
        row.created_at = now
        row.updated_at = now
      end
    end

    def add_detected_windows_doors_upgrade!(invoice_version, now)
      upgrade_type = windows_doors_upgrade_type(now)

      Claims::InvoiceVersionUpgradeType.create!(
        invoice_version_id: invoice_version.id,
        invoice_upgrade_type_id: upgrade_type.id,
        source_engine: "classifier",
        call_status: "classified",
        confidence: 98,
        evidence_text: "Window rebate line",
        raw_json: {
          "upgrade_type_key" => "windows_doors"
        },
        created_at: now,
        updated_at: now
      )
    end

    it "does not let a stale queued classifier row hide a succeeded classifier row" do
      now = Time.zone.parse("2026-06-23 15:41:05")
      service = described_class.new(ingest_run_id: SecureRandom.uuid)
      succeeded_step =
        Claims::IngestStepRun.new(
          id: SecureRandom.uuid,
          status: "succeeded",
          created_at: now,
          updated_at: now + 10.seconds
        )
      stale_queued_step =
        Claims::IngestStepRun.new(
          id: SecureRandom.uuid,
          status: "queued",
          created_at: now + 20.seconds,
          updated_at: now + 20.seconds
        )

      expect(
        service.send(:best_step_for_target, [succeeded_step, stale_queued_step])
      ).to eq(succeeded_step)
    end

    it "binds a classifier-detected replacement invoice to the pending fix version" do
      now = Time.zone.parse("2026-06-24 08:30:00")
      contractor = Contractor.create!(business_name: "Replacement Contractor")
      session = Claims::Session.create!(created_at: now, updated_at: now)
      invoice =
        Claims::Invoice.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "ocr_in_progress",
          created_at: now,
          updated_at: now
        )
      Claims::InvoiceVersion.create!(
        invoice_id: invoice.id,
        invoice_versionno: 1,
        storage_provider: "azure_blob",
        storage_key: "source/original-invoice.pdf",
        original_filename: "Original invoice.pdf",
        content_type: "application/pdf",
        created_at: now,
        updated_at: now
      )
      pending_version =
        Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: 2,
          storage_provider: "azure_blob",
          storage_key: "PENDING/replacement-invoice.pdf",
          created_at: now,
          updated_at: now
        )
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          resolved_invoice_version_id: pending_version.id,
          status: "running",
          total_files: 1,
          completed_files: 0,
          failed_files: 0,
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
      classifier_payload = {
        "document_kind" => "invoice",
        "document_kind_confidence" => 99,
        "detected_upgrade_types" => [
          {
            "upgrade_type_key" => "windows_doors",
            "confidence" => 98,
            "evidence_text" => "Eligible window installation"
          }
        ]
      }
      windows_doors_upgrade_type(now)
      replacement_document =
        Claims::IngestDocument.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          contractor_id: contractor.id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: pending_version.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/replacement-claim-document.pdf",
          original_filename: "Replacement claim document.pdf",
          content_type: "application/pdf",
          byte_size: 3456,
          sha256: SecureRandom.hex(32),
          di_read_raw_json: {
            "read" => "replacement invoice"
          },
          classifier_raw_json: classifier_payload,
          document_kind: "invoice",
          document_kind_confidence: 99,
          document_kind_reason: "Primary replacement contractor invoice.",
          classification_status: "classified",
          classification_confidence: 99,
          classification_reason: "Invoice content detected.",
          classified_at: now,
          created_at: now,
          updated_at: now
        )
      %w[fix_ocr_read fix_classifier_files].each do |step_type|
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          ingest_document_id: replacement_document.id,
          step_type: step_type,
          status: "succeeded",
          created_at: now,
          updated_at: now
        )
      end

      allow(Claims::RunOcrJob).to receive(:perform_async)

      described_class.call(ingest_run_id: run.id)

      pending_version.reload
      expect(pending_version.storage_key).to eq(
        replacement_document.storage_key
      )
      expect(pending_version.original_filename).to eq(
        replacement_document.original_filename
      )
      expect(pending_version.content_type).to eq("application/pdf")
      expect(
        Claims::InvoiceVersionUpgradeType.exists?(
          invoice_version_id: pending_version.id,
          source_engine: "classifier"
        )
      ).to be(true)
      expect(Claims::RunOcrJob).to have_received(:perform_async).with(
        pending_version.id,
        run.id,
        "prebuilt-invoice",
        true,
        "use_existing_classifier",
        "fix_ocr_invoice"
      )
    end

    it "marks an invoice with no supported detected upgrade type as package needs correction" do
      now = Time.zone.parse("2026-06-24 09:15:00")
      contractor =
        Contractor.create!(business_name: "Unknown Upgrade Contractor")
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
          resolved_invoice_id: invoice.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/car-repair-invoice.pdf",
          original_filename: "Car repair invoice.pdf",
          content_type: "application/pdf",
          di_read_raw_json: {
            "read" => "car repair"
          },
          classifier_raw_json: {
            "document_kind" => "invoice",
            "document_kind_confidence" => 99,
            "detected_upgrade_types" => [],
            "eligibility_code" => {
              "value" => nil
            },
            "product_references" => {
            }
          },
          document_kind: "invoice",
          document_kind_confidence: 99,
          document_kind_reason: "Primary contractor invoice.",
          classification_status: "classified",
          classification_confidence: 99,
          classification_reason: "Invoice with no ESP rebate upgrade.",
          classified_at: now,
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
        status: "succeeded",
        created_at: now - 10.seconds,
        updated_at: now
      )

      allow(Claims::RunOcrJob).to receive(:perform_async)
      allow(Claims::RunGenaiJob).to receive(:perform_async)

      described_class.call(ingest_run_id: run.id)

      expect(run.reload.status).to eq("failed")
      expect(run.failed_files).to eq(1)
      expect(run.resolved_invoice_version_id).to be_present
      expect(invoice.reload.status).to eq("package_needs_correction")
      expect(invoice.status_subtype).to eq("package_no_supported_upgrade_type")
      expect(
        Claims::InvoiceVersionUpgradeType.where(
          invoice_version_id: run.resolved_invoice_version_id
        )
      ).to be_empty
      expect(Claims::RunOcrJob).not_to have_received(:perform_async)
      expect(Claims::RunGenaiJob).not_to have_received(:perform_async)
      expect(run.pipeline_error_code).to eq(
        "invoice_bundle_no_supported_upgrade_type"
      )
      expect(run.failure_status).to eq("package_needs_correction")
      expect(run.failure_status_subtype).to eq(
        "package_no_supported_upgrade_type"
      )
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
      add_detected_windows_doors_upgrade!(new_version, now)
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
      add_detected_windows_doors_upgrade!(new_version, now)
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
        contractor_display_name: "Model number",
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
      add_detected_windows_doors_upgrade!(new_version, now)
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
          contractor_display_name: "Field #{index + 1}",
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

    it "fails immediately when a classifier error is explicitly permanent" do
      now = Time.zone.parse("2026-06-22 13:03:12")
      contractor = Contractor.create!(business_name: "Permanent Failure")
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
          resolved_invoice_id: invoice.id,
          storage_provider: "azure_blob",
          storage_key: "uploaded/corrupt.jpg",
          original_filename: "Corrupt image.jpg",
          content_type: "image/jpeg",
          di_read_raw_json: {
            "read" => "image"
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
        error_text: "Node GenAI request failed.",
        failure_status: "package_needs_correction",
        failure_status_subtype: "package_unreadable_file",
        error_code: "genai_input_image_invalid",
        error_category: "provider_invalid_image",
        retryable: false,
        diagnostic_id: "diag-permanent",
        provider_status: 400,
        created_at: now,
        updated_at: now
      )

      described_class.call(ingest_run_id: run.id)

      expect(run.reload.status).to eq("failed")
      expect(run.failed_files).to eq(1)
      expect(run.pipeline_error_code).to eq("genai_input_image_invalid")
      expect(run.pipeline_error_description).to eq(
        "classifier_files failed; genai_input_image_invalid; provider HTTP 400; non-retryable; diagnostic diag-permanent."
      )
      expect(invoice.reload.status).to eq("package_needs_correction")
      expect(invoice.status_subtype).to eq("package_unreadable_file")
    end

    it "waits for active parallel steps before cleaning failed contractor artifacts" do
      contractor = Contractor.create!(business_name: "Parallel Cleanup")
      session = Claims::Session.create!
      run =
        Claims::IngestRun.create!(
          session_id: session.id,
          contractor_id: contractor.id,
          status: "failed",
          cleanup_failed_invoice_artifacts: true,
          total_files: 2,
          completed_files: 0,
          failed_files: 1
        )
      active_step =
        Claims::IngestStepRun.create!(
          ingest_run_id: run.id,
          session_id: session.id,
          step_type: "upload_package_stage",
          status: "in_progress"
        )
      service = described_class.new(ingest_run_id: run.id)
      allow(Claims::Ingest::CleanupFailedContractorUpload).to receive(:call)

      service.send(:cleanup_failed_contractor_upload!, run)

      expect(
        Claims::Ingest::CleanupFailedContractorUpload
      ).not_to have_received(:call)

      active_step.update!(
        status: "failed",
        error_text: "Cancelled after another parallel step failed.",
        failure_status: "technical_failure",
        failure_status_subtype: "unknown_runtime_failure",
        error_code: "pipeline_cancelled_after_failure",
        error_category: "pipeline_cancelled",
        retryable: false
      )

      service.send(:cleanup_failed_contractor_upload!, run)

      expect(Claims::Ingest::CleanupFailedContractorUpload).to have_received(
        :call
      ).with(ingest_run: run)
    end
  end
end
