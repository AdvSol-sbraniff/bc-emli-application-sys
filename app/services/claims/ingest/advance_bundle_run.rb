# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceBundleRun
      BUNDLE_INVALID_ERROR_CODE = "invoice_bundle_count_invalid"
      BUNDLE_UNKNOWN_ERROR_CODE = "invoice_bundle_unknown_documents"
      SUPPORTING_DOCUMENTS_ATTACHED_INFO_CODE = "supporting_documents_attached"

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return unless run

        documents =
          ::Claims::IngestDocument.where(ingest_run_id: run.id).order(
            created_at: :asc
          )
        shell_invoice_id =
          documents
            .where.not(resolved_invoice_id: nil)
            .limit(1)
            .pick(:resolved_invoice_id)
        document_ids = documents.pluck(:id)
        total_files = run.total_files.to_i
        total_files = document_ids.size if total_files <= 0
        messages = sanitize_bundle_messages(parse_messages(run.messages))

        read_steps = latest_document_steps_map(run.id, document_ids, "ocr_read")
        if read_steps.size < total_files
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if failed_row = read_steps.values.find { |row| row.status == "failed" }
          failed_doc =
            documents.detect { |doc| doc.id == failed_row.ingest_document_id }
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype: "ocr_unexpected_exception",
              extra_messages: [
                {
                  code: "bundle_read_ocr_failed",
                  level: "error",
                  message: "One or more files failed during initial OCR read.",
                  ingest_document_id: failed_row.ingest_document_id,
                  filename: failed_doc&.original_filename
                }
              ]
            )
          )
        end
        if read_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        triage_steps = latest_classifier_steps_map(run.id, documents)
        if triage_steps.empty?
          enqueue_classifier_jobs!(documents: documents)
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if triage_steps.size < total_files
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if failed_row =
             triage_steps.values.find { |row| row.status == "failed" }
          failed_doc =
            documents.detect { |doc| doc.id == failed_row.ingest_document_id }
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype: "genai_unexpected_exception",
              extra_messages: [
                {
                  code: "bundle_triage_failed",
                  level: "error",
                  message: "One or more files failed during document triage.",
                  ingest_document_id: failed_row.ingest_document_id,
                  filename: failed_doc&.original_filename
                }
              ]
            )
          )
        end
        if triage_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        unknown_docs = documents.select { |doc| doc.document_kind == "unknown" }
        unless unknown_docs.empty?
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: unknown_docs.size,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "package_needs_correction",
              shell_invoice_status_subtype:
                "package_invoice_classification_conflict",
              extra_messages: [
                {
                  code: BUNDLE_UNKNOWN_ERROR_CODE,
                  level: "error",
                  message:
                    "One or more uploaded files could not be classified as either an invoice or a supporting document.",
                  filenames: unknown_docs.map(&:original_filename).compact.sort
                }
              ]
            )
          )
        end

        invoice_docs = documents.select { |doc| doc.document_kind == "invoice" }
        if invoice_docs.size != 1
          package_status_subtype =
            (
              if invoice_docs.empty?
                "package_no_invoice_pdf"
              else
                "package_multiple_invoice_pdfs"
              end
            )
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: [invoice_docs.size, 1].max,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "package_needs_correction",
              shell_invoice_status_subtype: package_status_subtype,
              extra_messages: [
                {
                  code: BUNDLE_INVALID_ERROR_CODE,
                  level: "error",
                  message:
                    "Exactly one invoice is required in the upload bundle; detected #{invoice_docs.size} invoice candidates.",
                  invoice_candidate_count: invoice_docs.size,
                  invoice_candidate_filenames:
                    invoice_docs.map(&:original_filename).compact.sort
                }
              ]
            )
          )
        end

        non_pdf_invoice_docs =
          invoice_docs.reject { |document| pdf_document?(document) }
        unless non_pdf_invoice_docs.empty?
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: non_pdf_invoice_docs.size,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "package_needs_correction",
              shell_invoice_status_subtype: "package_invoice_not_pdf",
              extra_messages: [
                {
                  code: BUNDLE_INVALID_ERROR_CODE,
                  level: "error",
                  message: "The primary invoice must be uploaded as a PDF.",
                  invoice_candidate_filenames:
                    non_pdf_invoice_docs.map(&:original_filename).compact.sort
                }
              ]
            )
          )
        end

        resolved_document = invoice_docs.first
        resolved_invoice_version_id =
          ensure_resolved_invoice!(
            run: run,
            resolved_document: resolved_document
          )
        resolved_invoice_id = resolved_document.reload.resolved_invoice_id
        supporting_document_rows =
          documents.select { |doc| doc.document_kind == "supporting_document" }

        supporting_document_rows.each do |document|
          ::Claims::SupportingDocuments::PromoteFromIngestDocument.call(
            resolved_invoice_id: resolved_invoice_id,
            ingest_document_id: document.id
          )
        end

        extraction_type_ids =
          supporting_document_type_ids_requiring_extraction(
            supporting_document_rows
          )
        extraction_steps =
          latest_type_steps_map(
            run.id,
            extraction_type_ids,
            "supporting_document_type_extraction"
          )

        missing_extraction_type_ids =
          extraction_type_ids.reject do |type_id|
            extraction_steps.key?(type_id)
          end

        if missing_extraction_type_ids.any?
          enqueue_supporting_document_type_extraction_jobs!(
            invoice_id: resolved_invoice_id,
            supporting_document_type_ids: missing_extraction_type_ids
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if extraction_steps.size < extraction_type_ids.size
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if failed_row =
             extraction_steps.values.find { |row| row.status == "failed" }
          failed_type =
            ::Claims::SupportingDocumentType.find_by(
              id: failed_row.supporting_document_type_id
            )
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype: "genai_unexpected_exception",
              extra_messages: [
                {
                  code: "bundle_supporting_document_extraction_failed",
                  level: "error",
                  message:
                    "One or more supporting document types failed during located-field extraction.",
                  supporting_document_type_id:
                    failed_row.supporting_document_type_id,
                  supporting_document_type_key: failed_type&.type_key
                }
              ]
            )
          )
        end

        if extraction_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        invoice_ocr_step =
          latest_invoice_step(
            run.id,
            resolved_invoice_version_id,
            "ocr_invoice"
          )
        if invoice_ocr_step.nil?
          enqueue_invoice_finalize_ocr!(
            invoice_version_id: resolved_invoice_version_id
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if invoice_ocr_step.status == "failed"
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype: "ocr_unexpected_exception",
              extra_messages: [
                {
                  code: "bundle_invoice_ocr_failed",
                  level: "error",
                  message:
                    "The resolved invoice failed during the invoice-model OCR pass.",
                  invoice_version_id: resolved_invoice_version_id
                }
              ]
            )
          )
        end
        unless invoice_ocr_step.status == "succeeded"
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        resolved_invoice_status =
          invoice_status_for(resolved_invoice_version_id)
        validation_steps =
          latest_validation_steps(run.id, resolved_invoice_version_id)
        if validation_steps.any? { |row| row.status == "failed" } ||
             %w[
               genai_failed
               package_needs_correction
               technical_failure
             ].include?(resolved_invoice_status)
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype: "genai_unexpected_exception",
              extra_messages: [
                {
                  code: "bundle_invoice_genai_failed",
                  level: "error",
                  message:
                    "The resolved invoice failed during the validation runtime.",
                  invoice_version_id: resolved_invoice_version_id
                }
              ]
            )
          )
        end

        unless resolved_invoice_status == "genai_complete" &&
                 validation_steps.present? &&
                 validation_steps.all? { |row| row.status == "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status:
                running_shell_invoice_status_for(
                  resolved_invoice_status: resolved_invoice_status
                )
            )
          )
        end

        info_messages = []
        if supporting_document_rows.any?
          info_messages << {
            code: SUPPORTING_DOCUMENTS_ATTACHED_INFO_CODE,
            level: "info",
            message:
              "#{supporting_document_rows.size} supporting document#{"s" unless supporting_document_rows.size == 1} attached to the resolved invoice.",
            attached_supporting_documents_count: supporting_document_rows.size
          }
        end

        run.update!(
          status: "succeeded",
          total_files: total_files,
          completed_files: total_files,
          failed_files: 0,
          messages: messages + info_messages,
          completed_at: Time.current,
          updated_at: Time.current
        )
      end

      private

      def latest_document_steps_map(ingest_run_id, document_ids, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            ingest_document_id: document_ids,
            step_type: step_type
          )
          .order(created_at: :desc)
          .to_a
          .group_by(&:ingest_document_id)
          .transform_values(&:first)
      end

      def latest_invoice_step(ingest_run_id, invoice_version_id, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type
          )
          .order(created_at: :desc)
          .first
      end

      def latest_type_steps_map(
        ingest_run_id,
        supporting_document_type_ids,
        step_type
      )
        return {} if supporting_document_type_ids.empty?

        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            supporting_document_type_id: supporting_document_type_ids,
            step_type: step_type
          )
          .order(created_at: :desc)
          .to_a
          .group_by(&:supporting_document_type_id)
          .transform_values(&:first)
      end

      def latest_validation_steps(ingest_run_id, invoice_version_id)
        ::Claims::IngestStepRun.where(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: %w[
            case_facts
            product_lookup_enrichment
            genai_common
            genai_upgrade
            code_common
            code_upgrade
            aggregate_advice
          ]
        ).order(created_at: :desc)
      end

      def enqueue_classifier_jobs!(documents:)
        documents.each do |document|
          step_type = classifier_step_type_for(document)
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            ingest_document_id: document.id,
            step_type: step_type
          ) do |step|
            step.session_id = document.session_id
            step.status = "queued"
            step.error_text = nil
            step.created_at = Time.current
            step.updated_at = Time.current
          end

          ::Claims::RunIngestTriageJob.perform_async(
            document.id,
            @ingest_run_id,
            step_type
          )
        end
      end

      def enqueue_supporting_document_type_extraction_jobs!(
        invoice_id:,
        supporting_document_type_ids:
      )
        invoice = ::Claims::Invoice.find(invoice_id)

        supporting_document_type_ids.each do |type_id|
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            supporting_document_type_id: type_id,
            step_type: "supporting_document_type_extraction"
          ) do |step|
            step.session_id = invoice.session_id
            step.status = "queued"
            step.error_text = nil
            step.created_at = Time.current
            step.updated_at = Time.current
          end

          ::Claims::RunSupportingDocumentTypeExtractionJob.perform_async(
            invoice.id,
            type_id,
            @ingest_run_id
          )
        end
      end

      def supporting_document_type_ids_requiring_extraction(documents)
        supporting_document_rows =
          documents.select do |doc|
            doc.document_kind == "supporting_document" &&
              doc.supporting_document_type_id.present?
          end
        return [] if supporting_document_rows.empty?

        candidate_type_ids =
          supporting_document_rows
            .map { |row| row.supporting_document_type_id.to_s }
            .uniq

        type_ids_with_fields =
          ::Claims::SupportingDocumentTypeLocatedField
            .where(
              supporting_document_type_id: candidate_type_ids,
              enabled: true
            )
            .distinct
            .pluck(:supporting_document_type_id)
            .map(&:to_s)

        candidate_type_ids.select do |type_id|
          type_ids_with_fields.include?(type_id)
        end
      end

      def latest_classifier_steps_map(ingest_run_id, documents)
        documents
          .map do |document|
            step =
              ::Claims::IngestStepRun
                .where(
                  ingest_run_id: ingest_run_id,
                  ingest_document_id: document.id,
                  step_type: classifier_step_types_for_lookup(document)
                )
                .order(created_at: :desc)
                .first
            [document.id, step]
          end
          .select { |_document_id, step| step.present? }
          .to_h
      end

      def classifier_step_type_for(document)
        image_document?(document) ? "classifier_imagefiles" : "classifier_pdfs"
      end

      def classifier_step_types_for_lookup(document)
        [classifier_step_type_for(document), "triage_classifier"]
      end

      def image_document?(document)
        content_type = document.content_type.to_s.downcase
        return true if content_type.start_with?("image/")

        filename = document.original_filename.to_s.downcase
        filename.end_with?(".jpg", ".jpeg", ".png")
      end

      def pdf_document?(document)
        content_type = document.content_type.to_s.downcase
        return true if content_type == "application/pdf"

        document.original_filename.to_s.downcase.end_with?(".pdf")
      end

      def ensure_resolved_invoice!(run:, resolved_document:)
        resolved_document.with_lock do
          if resolved_document.resolved_invoice_version_id.present?
            return resolved_document.resolved_invoice_version_id
          end

          invoice =
            ::Claims::Invoice.find_by(id: resolved_document.resolved_invoice_id)
          if invoice.nil?
            raise "Missing shell invoice for resolved ingest document #{resolved_document.id}"
          end

          existing_invoice_version =
            ::Claims::InvoiceVersion.find_by(
              invoice_id: invoice.id,
              storage_key: resolved_document.storage_key
            )
          if existing_invoice_version.present?
            existing_invoice_version.update!(
              storage_provider:
                resolved_document.storage_provider.presence ||
                  existing_invoice_version.storage_provider,
              original_filename:
                resolved_document.original_filename.presence ||
                  existing_invoice_version.original_filename,
              content_type:
                resolved_document.content_type.presence ||
                  existing_invoice_version.content_type,
              byte_size:
                resolved_document.byte_size.presence ||
                  existing_invoice_version.byte_size,
              sha256:
                resolved_document.sha256.presence ||
                  existing_invoice_version.sha256,
              updated_at: Time.current
            )

            apply_classifier_evidence!(
              invoice_version_id: existing_invoice_version.id,
              classifier_payload: resolved_document.classifier_raw_json
            )

            resolved_document.update!(
              resolved_invoice_id: invoice.id,
              resolved_invoice_version_id: existing_invoice_version.id,
              updated_at: Time.current
            )

            return existing_invoice_version.id
          end

          invoice_version =
            ::Claims::InvoiceVersion.create!(
              invoice_id: invoice.id,
              invoice_versionno: next_invoice_versionno(invoice.id),
              storage_provider: resolved_document.storage_provider,
              storage_key: resolved_document.storage_key,
              original_filename: resolved_document.original_filename,
              content_type: resolved_document.content_type,
              byte_size: resolved_document.byte_size,
              sha256: resolved_document.sha256,
              created_at: Time.current,
              updated_at: Time.current
            )

          apply_classifier_evidence!(
            invoice_version_id: invoice_version.id,
            classifier_payload: resolved_document.classifier_raw_json
          )

          resolved_document.update!(
            resolved_invoice_id: invoice.id,
            resolved_invoice_version_id: invoice_version.id,
            updated_at: Time.current
          )

          invoice_version.id
        end
      end

      def apply_classifier_evidence!(invoice_version_id:, classifier_payload:)
        result =
          ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
            invoice_version_id: invoice_version_id,
            classifier_payload: classifier_payload
          )

        return if result[:ok] || result["ok"]

        raise "ApplyClassifierResult failed: #{result.inspect}"
      end

      def next_invoice_versionno(invoice_id)
        (
          ::Claims::InvoiceVersion.where(invoice_id: invoice_id).maximum(
            :invoice_versionno
          ) || 0
        ) + 1
      end

      def enqueue_invoice_finalize_ocr!(invoice_version_id:)
        iv = ::Claims::InvoiceVersion.find(invoice_version_id)
        inv = ::Claims::Invoice.find(iv.invoice_id)
        inv.set_workflow_status!("ocr_queued")

        ::Claims::IngestStepRun.find_or_create_by!(
          ingest_run_id: @ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: "ocr_invoice"
        ) do |step|
          step.session_id = inv.session_id
          step.status = "queued"
          step.error_text = nil
          step.created_at = Time.current
          step.updated_at = Time.current
        end

        ::Claims::RunOcrJob.perform_async(
          invoice_version_id,
          @ingest_run_id,
          "prebuilt-invoice",
          true,
          "use_existing_classifier",
          "ocr_invoice"
        )
      end

      def invoice_status_for(invoice_version_id)
        ::Claims::InvoiceVersion
          .joins(
            "JOIN claims.invoices i ON i.id = claims.invoice_versions.invoice_id"
          )
          .where(id: invoice_version_id)
          .pick("i.status")
          .to_s
      end

      def update_running!(
        run:,
        total_files:,
        messages:,
        shell_invoice_id: nil,
        shell_invoice_status: "ocr_in_progress",
        shell_invoice_status_subtype: nil
      )
        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status,
          status_subtype: shell_invoice_status_subtype
        )
        run.update!(
          status: "running",
          total_files: total_files,
          completed_files: 0,
          failed_files: 0,
          messages: messages,
          completed_at: nil,
          updated_at: Time.current
        )
      end

      def update_failed!(
        run:,
        total_files:,
        failed_files:,
        messages:,
        extra_messages:,
        shell_invoice_id: nil,
        shell_invoice_status: "ocr_failed",
        shell_invoice_status_subtype: nil
      )
        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status,
          status_subtype: shell_invoice_status_subtype
        )
        final_messages =
          contractor_failure_messages(
            run: run,
            shell_invoice_id: shell_invoice_id,
            messages: messages + extra_messages
          )
        run.update!(
          status: "failed",
          total_files: total_files,
          completed_files: 0,
          failed_files: [failed_files, 0].max,
          messages: final_messages,
          completed_at: Time.current,
          updated_at: Time.current
        )
        cleanup_failed_contractor_upload!(run)
      end

      def sync_shell_invoice_status!(
        shell_invoice_id:,
        status:,
        status_subtype: nil
      )
        return if shell_invoice_id.blank? || status.blank?

        invoice = ::Claims::Invoice.find_by(id: shell_invoice_id)
        return if invoice.nil?
        subtype =
          ::Claims::Invoices::StatusSubtypes.normalize(status, status_subtype)
        return if invoice.status == status && invoice.status_subtype == subtype

        invoice.set_workflow_status!(status, status_subtype: status_subtype)
      rescue StandardError
        nil
      end

      def running_shell_invoice_status_for(resolved_invoice_status:)
        status = resolved_invoice_status.to_s
        return "genai_in_progress" if status.blank?
        if %w[genai_queued genai_in_progress genai_complete].include?(status)
          return status
        end

        "genai_in_progress"
      end

      def contractor_failure_messages(run:, shell_invoice_id:, messages:)
        return messages unless run.cleanup_failed_invoice_artifacts
        return messages if shell_invoice_id.blank?
        if Array(messages).any? { |row| row["contractor_message"].present? }
          return messages
        end

        invoice = ::Claims::Invoice.find_by(id: shell_invoice_id)
        return messages unless invoice
        unless %w[package_needs_correction technical_failure].include?(
                 invoice.status.to_s
               )
          return messages
        end

        messages +
          [
            {
              level: "error",
              status: invoice.status,
              status_subtype: invoice.status_subtype,
              code: invoice.status_subtype,
              contractor_message:
                ::Claims::Invoices::StatusSubtypes.contractor_failure_message(
                  invoice.status,
                  invoice.status_subtype
                ),
              message: "Invoice package processing failed."
            }
          ]
      end

      def cleanup_failed_contractor_upload!(run)
        return unless run.cleanup_failed_invoice_artifacts
        return if run.contractor_id.blank?

        ::Claims::Ingest::CleanupFailedContractorUpload.call(ingest_run: run)
      rescue => e
        Rails.logger.error(
          "[claims][ingest][advance_bundle_run] cleanup failed ingest_run_id=#{run.id}: #{e.class}: #{e.message}"
        )
      end

      def parse_messages(messages)
        return messages if messages.is_a?(Array)

        JSON.parse(messages.to_s)
      rescue JSON::ParserError, TypeError
        []
      end

      def sanitize_bundle_messages(messages)
        Array(messages).reject do |row|
          next false unless row.is_a?(Hash)

          code = row["code"].to_s.presence || row[:code].to_s
          [
            BUNDLE_INVALID_ERROR_CODE,
            BUNDLE_UNKNOWN_ERROR_CODE,
            SUPPORTING_DOCUMENTS_ATTACHED_INFO_CODE,
            "bundle_read_ocr_failed",
            "bundle_triage_failed",
            "bundle_supporting_document_extraction_failed",
            "bundle_invoice_ocr_failed",
            "bundle_invoice_genai_failed"
          ].include?(code)
        end
      end
    end
  end
end
