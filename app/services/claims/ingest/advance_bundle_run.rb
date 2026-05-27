# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceBundleRun
      BUNDLE_INVALID_ERROR_CODE = "invoice_bundle_count_invalid"
      BUNDLE_UNKNOWN_ERROR_CODE = "invoice_bundle_unknown_documents"
      SUPPLEMENTS_ATTACHED_INFO_CODE = "supplements_attached"

      def self.call(ingest_run_id:, validationgenai_ruleset_id:)
        new(
          ingest_run_id: ingest_run_id,
          validationgenai_ruleset_id: validationgenai_ruleset_id
        ).call
      end

      def initialize(ingest_run_id:, validationgenai_ruleset_id:)
        @ingest_run_id = ingest_run_id
        @validationgenai_ruleset_id = validationgenai_ruleset_id
      end

      def call
        return if @ingest_run_id.blank?

        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return unless run

        documents =
          ::Claims::IngestDocument.where(ingest_run_id: run.id).order(created_at: :asc)
        shell_invoice_id =
          documents.where.not(resolved_invoice_id: nil).limit(1).pick(:resolved_invoice_id)
        document_ids = documents.pluck(:id)
        total_files = run.total_files.to_i
        total_files = document_ids.size if total_files <= 0
        messages = sanitize_bundle_messages(parse_messages(run.messages))

        read_steps = latest_document_steps_map(run.id, document_ids, "ocr_read")
        return update_running!(
                 run: run,
                 total_files: total_files,
                 messages: messages,
                 shell_invoice_id: shell_invoice_id
               ) if read_steps.size < total_files
        if failed_row = read_steps.values.find { |row| row.status == "failed" }
          failed_doc = documents.detect { |doc| doc.id == failed_row.ingest_document_id }
          return update_failed!(
                   run: run,
                   total_files: total_files,
                   failed_files: 1,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id,
                   shell_invoice_status: "ocr_failed",
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
        end
        return update_running!(
                 run: run,
                 total_files: total_files,
                 messages: messages,
                 shell_invoice_id: shell_invoice_id
               ) if read_steps.values.any? { |row| row.status != "succeeded" }

        triage_steps =
          latest_document_steps_map(run.id, document_ids, "triage_classifier")
        if triage_steps.empty?
          enqueue_triage_jobs!(documents: documents)
          return update_running!(
                   run: run,
                   total_files: total_files,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id
                 )
        end
        return update_running!(
                 run: run,
                 total_files: total_files,
                 messages: messages,
                 shell_invoice_id: shell_invoice_id
               ) if triage_steps.size < total_files
        if failed_row = triage_steps.values.find { |row| row.status == "failed" }
          failed_doc = documents.detect { |doc| doc.id == failed_row.ingest_document_id }
          return update_failed!(
                   run: run,
                   total_files: total_files,
                   failed_files: 1,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id,
                   shell_invoice_status: "ocr_failed",
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
        end
        return update_running!(
                 run: run,
                 total_files: total_files,
                 messages: messages,
                 shell_invoice_id: shell_invoice_id
               ) if triage_steps.values.any? { |row| row.status != "succeeded" }

        unknown_docs = documents.select { |doc| doc.document_kind == "unknown" }
        unless unknown_docs.empty?
          return update_failed!(
                   run: run,
                   total_files: total_files,
                   failed_files: unknown_docs.size,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id,
                   shell_invoice_status: "ocr_failed",
                   extra_messages: [
                     {
                       code: BUNDLE_UNKNOWN_ERROR_CODE,
                       level: "error",
                       message: "One or more uploaded files could not be classified as either an invoice or a supporting document.",
                       filenames: unknown_docs.map(&:original_filename).compact.sort
                     }
                   ]
                 )
        end

        invoice_docs = documents.select { |doc| doc.document_kind == "invoice" }
        if invoice_docs.size != 1
          return update_failed!(
                   run: run,
                   total_files: total_files,
                   failed_files: [invoice_docs.size, 1].max,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id,
                   shell_invoice_status: "ocr_failed",
                   extra_messages: [
                     {
                       code: BUNDLE_INVALID_ERROR_CODE,
                       level: "error",
                       message: "Exactly one invoice is required in the upload bundle; detected #{invoice_docs.size} invoice candidates.",
                       invoice_candidate_count: invoice_docs.size,
                       invoice_candidate_filenames:
                         invoice_docs.map(&:original_filename).compact.sort
                     }
                   ]
                 )
        end

        resolved_document = invoice_docs.first
        resolved_invoice_version_id =
          ensure_resolved_invoice!(run: run, resolved_document: resolved_document)
        resolved_invoice_id = resolved_document.reload.resolved_invoice_id
        supplement_documents =
          documents.select { |doc| doc.document_kind == "supplement" }

        supplement_documents.each do |document|
          ::Claims::SupportingDocuments::PromoteFromIngestDocument.call(
            resolved_invoice_id: resolved_invoice_id,
            ingest_document_id: document.id
          )
        end

        invoice_ocr_step =
          latest_invoice_step(run.id, resolved_invoice_version_id, "ocr_invoice")
        if invoice_ocr_step.nil?
          enqueue_invoice_finalize_ocr!(invoice_version_id: resolved_invoice_version_id)
          return update_running!(
                   run: run,
                   total_files: total_files,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id
                 )
        end

        if invoice_ocr_step.status == "failed"
          return update_failed!(
                   run: run,
                   total_files: total_files,
                   failed_files: 1,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id,
                   shell_invoice_status: "ocr_failed",
                   extra_messages: [
                     {
                       code: "bundle_invoice_ocr_failed",
                       level: "error",
                       message: "The resolved invoice failed during the invoice-model OCR pass.",
                       invoice_version_id: resolved_invoice_version_id
                     }
                   ]
                 )
        end
        return update_running!(
                 run: run,
                 total_files: total_files,
                 messages: messages,
                 shell_invoice_id: shell_invoice_id
               ) unless invoice_ocr_step.status == "succeeded"

        resolved_invoice_status = invoice_status_for(resolved_invoice_version_id)
        genai_steps = latest_genai_steps(run.id, resolved_invoice_version_id)
        if genai_steps.any? { |row| row.status == "failed" } ||
             resolved_invoice_status == "genai_failed"
          return update_failed!(
                   run: run,
                   total_files: total_files,
                   failed_files: 1,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id,
                   shell_invoice_status: "genai_failed",
                   extra_messages: [
                     {
                       code: "bundle_invoice_genai_failed",
                       level: "error",
                       message: "The resolved invoice failed during GenAI validation.",
                       invoice_version_id: resolved_invoice_version_id
                     }
                   ]
                 )
        end

        unless resolved_invoice_status == "genai_complete" &&
                 genai_steps.present? &&
                 genai_steps.all? { |row| row.status == "succeeded" }
          return update_running!(
                   run: run,
                   total_files: total_files,
                   messages: messages,
                   shell_invoice_id: shell_invoice_id
                 )
        end

        info_messages = []
        if supplement_documents.any?
          info_messages << {
            code: SUPPLEMENTS_ATTACHED_INFO_CODE,
            level: "info",
            message:
              "#{supplement_documents.size} supporting document#{'s' unless supplement_documents.size == 1} attached to the resolved invoice.",
            attached_supporting_documents_count: supplement_documents.size
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

      def latest_genai_steps(ingest_run_id, invoice_version_id)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: %w[genai_common genai_upgrade]
          )
          .order(created_at: :desc)
      end

      def enqueue_triage_jobs!(documents:)
        documents.each do |document|
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            ingest_document_id: document.id,
            step_type: "triage_classifier"
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
            @validationgenai_ruleset_id
          )
        end
      end

      def ensure_resolved_invoice!(run:, resolved_document:)
        resolved_document.with_lock do
          if resolved_document.resolved_invoice_version_id.present?
            return resolved_document.resolved_invoice_version_id
          end

          invoice =
            ::Claims::Invoice.find_by(id: resolved_document.resolved_invoice_id)
          raise "Missing shell invoice for resolved ingest document #{resolved_document.id}" if invoice.nil?

          invoice_version =
            ::Claims::InvoiceVersion.create!(
              invoice_id: invoice.id,
              invoice_versionno: 1,
              storage_provider: resolved_document.storage_provider,
              storage_key: resolved_document.storage_key,
              original_filename: resolved_document.original_filename,
              content_type: resolved_document.content_type,
              byte_size: resolved_document.byte_size,
              sha256: resolved_document.sha256,
              created_at: Time.current,
              updated_at: Time.current
            )

          classifier_payload = resolved_document.classifier_raw_json || {}
          classifier_result =
            ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
              invoice_version_id: invoice_version.id,
              classifier_payload: classifier_payload
            )
          unless classifier_result[:ok]
            raise "ApplyClassifierResult failed: #{classifier_result.inspect}"
          end

          ::Claims::IngestStepRun.create!(
            ingest_run_id: run.id,
            session_id: resolved_document.session_id,
            invoice_version_id: invoice_version.id,
            step_type: "classifier",
            status: "succeeded",
            error_text: nil,
            genai_results_json: classifier_payload,
            created_at: Time.current,
            updated_at: Time.current
          )

          resolved_document.update!(
            resolved_invoice_id: invoice.id,
            resolved_invoice_version_id: invoice_version.id,
            updated_at: Time.current
          )

          invoice_version.id
        end
      end

      def enqueue_invoice_finalize_ocr!(invoice_version_id:)
        iv = ::Claims::InvoiceVersion.find(invoice_version_id)
        inv = ::Claims::Invoice.find(iv.invoice_id)
        inv.update!(status: "ocr_queued", status_updated_at: Time.current)

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
          @validationgenai_ruleset_id,
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

      def update_running!(run:, total_files:, messages:, shell_invoice_id: nil)
        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: "ocr_in_progress"
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
        shell_invoice_status: "ocr_failed"
      )
        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status
        )
        run.update!(
          status: "failed",
          total_files: total_files,
          completed_files: 0,
          failed_files: [failed_files, 0].max,
          messages: messages + extra_messages,
          completed_at: Time.current,
          updated_at: Time.current
        )
      end

      def sync_shell_invoice_status!(shell_invoice_id:, status:)
        return if shell_invoice_id.blank? || status.blank?

        invoice = ::Claims::Invoice.find_by(id: shell_invoice_id)
        return if invoice.nil? || invoice.status == status

        invoice.update!(
          status: status,
          status_updated_at: Time.current,
          updated_at: Time.current
        )
      rescue StandardError
        nil
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
            SUPPLEMENTS_ATTACHED_INFO_CODE,
            "bundle_read_ocr_failed",
            "bundle_triage_failed",
            "bundle_invoice_ocr_failed",
            "bundle_invoice_genai_failed"
          ].include?(code)
        end
      end
    end
  end
end
