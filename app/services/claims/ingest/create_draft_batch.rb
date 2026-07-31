# frozen_string_literal: true

require "json"
require "securerandom"

module Claims
  module Ingest
    class CreateDraftBatch
      def self.call(
        contractor_id:,
        files:,
        log_prefix: "draft_batch",
        cleanup_failed_invoice_artifacts: false
      )
        new(
          contractor_id: contractor_id,
          files: files,
          log_prefix: log_prefix,
          cleanup_failed_invoice_artifacts: cleanup_failed_invoice_artifacts
        ).call
      end

      def initialize(
        contractor_id:,
        files:,
        log_prefix:,
        cleanup_failed_invoice_artifacts:
      )
        @contractor_id = contractor_id.to_s.strip
        @files = Array(files).flatten.compact
        @log_prefix = log_prefix
        @cleanup_failed_invoice_artifacts = cleanup_failed_invoice_artifacts
      end

      def call
        session_id = nil
        ingest_run = nil
        shell_invoice = nil
        stage_step = nil

        if contractor_id.empty?
          raise ::Claims::Ingest::UploadErrors::ValidationError.new(
                  "A contractor is required to start an upload."
                )
        end
        if files.empty?
          raise ::Claims::Ingest::UploadErrors::ValidationError.new(
                  "Select at least one invoice or supporting document to upload."
                )
        end

        session_result =
          ::Claims::Sessions::Create.call(contractor_id: contractor_id)
        session_id = session_result.session.id

        ingest_run =
          ::Claims::IngestRun.create!(
            session_id: session_id,
            contractor_id: contractor_id,
            status: "queued",
            cleanup_failed_invoice_artifacts: cleanup_failed_invoice_artifacts,
            total_files: files.size,
            completed_files: 0,
            failed_files: 0,
            created_at: Time.current,
            updated_at: Time.current
          )

        shell_invoice =
          ::Claims::Invoice.create!(
            session_id: session_id,
            contractor_id: contractor_id,
            submitter_id: nil,
            status: "upload_in_progress",
            status_updated_at: Time.current,
            submitted_at: nil,
            created_at: Time.current,
            updated_at: Time.current
          )

        stage_step =
          ::Claims::IngestStepRun.create!(
            ingest_run_id: ingest_run.id,
            session_id: session_id,
            step_type: "upload_package_stage",
            status: "in_progress",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )

        results =
          files.each_with_index.map do |file, index|
            process_file(file, index, session_id, ingest_run, shell_invoice.id)
          end

        failed_results = results.select { |row| row[:status].to_s == "failed" }
        if failed_results.any?
          failure_status, failure_subtype =
            staging_failure_status_and_subtype(failed_results)
          shell_invoice.set_workflow_status!(
            failure_status,
            status_subtype: failure_subtype
          )
          failure_payload =
            contractor_failure_payload(
              status: failure_status,
              status_subtype: shell_invoice.status_subtype
            )
          stage_step.update!(
            status: "failed",
            error_text:
              "One or more evidence files failed during upload package staging.",
            **::Claims::Invoices::FailureSubtypes.step_attributes(
              status: failure_status,
              status_subtype: shell_invoice.status_subtype
            ),
            updated_at: Time.current
          )
          ingest_run.update!(
            status: "failed",
            failed_files: failed_results.size,
            failure_status: failure_status,
            failure_status_subtype: shell_invoice.status_subtype,
            pipeline_error_code: shell_invoice.status_subtype,
            pipeline_error_description:
              "Upload package staging failed: #{shell_invoice.status_subtype}.",
            completed_at: Time.current,
            updated_at: Time.current
          )
          cleanup_failed_contractor_upload!(ingest_run)
          return(
            {
              ok: true,
              ingest_run_id: ingest_run.id,
              session_id: session_id,
              invoice_id: shell_invoice.id,
              created_session: true,
              status: ingest_run.status,
              total_files: ingest_run.total_files,
              completed_files: ingest_run.completed_files,
              failed_files: ingest_run.failed_files,
              results: results
            }.merge(failure_payload)
          )
        else
          stage_step.update!(
            status: "succeeded",
            error_text: nil,
            updated_at: Time.current
          )
        end

        shell_invoice.set_workflow_status!("ocr_in_progress")

        ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run.id)
        ingest_run.reload
        mark_orphaned_ingest_failures!(ingest_run: ingest_run, results: results)
        ingest_run.reload

        {
          ok: true,
          ingest_run_id: ingest_run.id,
          session_id: session_id,
          invoice_id: shell_invoice.id,
          created_session: true,
          status: ingest_run.status,
          total_files: ingest_run.total_files,
          completed_files: ingest_run.completed_files,
          failed_files: ingest_run.failed_files,
          results: results
        }
      rescue ::Claims::Ingest::UploadErrors::ValidationError
        raise
      rescue StandardError => error
        diagnostic_id = SecureRandom.uuid
        error_code =
          finalize_unexpected_failure!(
            error: error,
            diagnostic_id: diagnostic_id,
            ingest_run: ingest_run,
            shell_invoice: shell_invoice,
            stage_step: stage_step
          )
        raise(
          ::Claims::Ingest::UploadErrors::UnexpectedError.new(
            diagnostic_id: diagnostic_id,
            error_code: error_code,
            ingest_run_id: ingest_run&.id,
            session_id: session_id,
            invoice_id: shell_invoice&.id
          ),
          cause: error
        )
      end

      private

      attr_reader :contractor_id,
                  :files,
                  :log_prefix,
                  :cleanup_failed_invoice_artifacts

      def finalize_unexpected_failure!(
        error:,
        diagnostic_id:,
        ingest_run:,
        shell_invoice:,
        stage_step:
      )
        error_code =
          ::Claims::Invoices::FailureSubtypes.upload(error).presence ||
            "upload_unexpected_exception"
        now = Time.current
        diagnostic_attributes =
          ::Claims::Invoices::FailureSubtypes.step_attributes(
            status: "technical_failure",
            status_subtype: error_code,
            error: error
          )
        diagnostic_attributes[:diagnostic_id] ||= diagnostic_id
        diagnostic_attributes[:retryable] = false

        safely_finalize_unexpected_failure!(
          label: "stage step",
          diagnostic_id: diagnostic_id
        ) do
          stage_step&.update_columns(
            status: "failed",
            error_text: "Upload package staging failed: #{error_code}.",
            genai_results_json: nil,
            context_window_json: nil,
            completed_at: now,
            **diagnostic_attributes,
            updated_at: now
          )
        end
        safely_finalize_unexpected_failure!(
          label: "invoice",
          diagnostic_id: diagnostic_id
        ) do
          shell_invoice&.update_columns(
            status: "technical_failure",
            status_subtype: error_code,
            status_updated_at: now,
            updated_at: now
          )
        end
        safely_finalize_unexpected_failure!(
          label: "ingest run",
          diagnostic_id: diagnostic_id
        ) do
          ingest_run&.update_columns(
            status: "failed",
            failed_files: [ingest_run.failed_files.to_i, 1].max,
            failure_status: "technical_failure",
            failure_status_subtype: error_code,
            pipeline_error_code: error_code,
            pipeline_error_description:
              "Upload package staging failed before processing completed.",
            completed_at: now,
            updated_at: now
          )
        end
        cleanup_failed_contractor_upload!(ingest_run) if ingest_run&.id
        error_code
      end

      def safely_finalize_unexpected_failure!(label:, diagnostic_id:)
        yield
      rescue StandardError => finalization_error
        Rails.logger.error(
          "[claims][ingest][#{log_prefix}] diagnostic_id=#{diagnostic_id} " \
            "failed to finalize #{label}: " \
            "#{finalization_error.class}: #{finalization_error.message}"
        )
      end

      def process_file(file, index, session_id, ingest_run, shell_invoice_id)
        name =
          ::Claims::Ingest::EvidenceFile.original_filename(
            file,
            fallback: "unknown"
          )
        content_type = ::Claims::Ingest::EvidenceFile.content_type(file)
        size = ::Claims::Ingest::EvidenceFile.byte_size(file)
        ingest_document = nil

        begin
          unless ::Claims::Ingest::EvidenceFile.supported?(
                   filename: name,
                   content_type: content_type
                 )
            raise "Only PDF, JPG, JPEG, and PNG evidence files are supported."
          end

          ingest_document =
            ::Claims::IngestDocument.create!(
              ingest_run_id: ingest_run.id,
              session_id: session_id,
              contractor_id: contractor_id,
              invoice_id: shell_invoice_id,
              resolved_invoice_id: shell_invoice_id,
              storage_provider: "azure_blob",
              storage_key:
                pending_storage_key(
                  session_id: session_id,
                  filename: name,
                  content_type: content_type
                ),
              original_filename: name,
              content_type: content_type,
              byte_size: size,
              classification_status: "pending",
              classification_confidence: 0,
              document_kind_confidence: 0,
              created_at: Time.current,
              updated_at: Time.current
            )

          node_resp =
            ::Claims::Ingest::UploadEvidenceFileToNode.call(
              session_id: session_id,
              upload_scope_id: ingest_document.id,
              file: file
            )

          final_storage_key = node_resp.fetch("storage_key").to_s.strip
          if final_storage_key.empty?
            raise "Node upload returned no storage_key"
          end

          ingest_document.update!(
            storage_key: final_storage_key,
            byte_size:
              (
                if node_resp.key?("byte_size")
                  node_resp["byte_size"]
                else
                  ingest_document.byte_size
                end
              ),
            sha256: node_resp["sha256"],
            updated_at: Time.current
          )

          ::Claims::IngestStepRun.create!(
            ingest_run_id: ingest_run.id,
            session_id: session_id,
            ingest_document_id: ingest_document.id,
            step_type: "ocr_read",
            status: "queued",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )

          jid =
            ::Claims::RunIngestReadOcrJob.perform_async(
              ingest_document.id,
              ingest_run.id
            )

          {
            index: index + 1,
            original_filename: name,
            content_type: content_type,
            byte_size: size,
            status: "queued_ocr",
            job_id: jid,
            ingest_document_id: ingest_document.id
          }
        rescue StandardError => e
          Rails.logger.error(
            "[claims][ingest][#{log_prefix}] file failed index=#{index + 1} filename=#{name.inspect} " \
              "ingest_document_id=#{ingest_document&.id}: #{e.class}: #{e.message}"
          )

          create_failed_step(ingest_run, session_id, ingest_document, e)

          {
            index: index + 1,
            original_filename: name,
            content_type: content_type,
            byte_size: size,
            status: "failed",
            error: e.message,
            ingest_document_id: ingest_document&.id
          }
        end
      end

      def package_failure_subtype(failed_results)
        errors =
          failed_results.map { |row| row[:error].to_s.downcase }.join(" ")
        return "package_unsupported_file_type" if errors.include?("supported")
        return "package_unreadable_file" if errors.include?("read")

        "package_no_processable_files"
      end

      def staging_failure_status_and_subtype(failed_results)
        errors =
          failed_results.map { |row| row[:error].to_s.downcase }.join(" ")

        if upload_technical_failure?(errors)
          return [
            "technical_failure",
            ::Claims::Invoices::FailureSubtypes.upload(errors)
          ]
        end

        ["package_needs_correction", package_failure_subtype(failed_results)]
      end

      def upload_technical_failure?(message)
        [
          "node upload failed",
          "storage_key",
          "missing env",
          "failed to open tcp connection",
          "connection refused",
          "getaddrinfo",
          "no route to host",
          "network is unreachable",
          "timed out",
          "timeout",
          "json::parsererror",
          "unexpected token",
          "malformed response"
        ].any? { |marker| message.include?(marker) }
      end

      def contractor_failure_payload(status:, status_subtype:)
        {
          failure_status: status,
          failure_status_subtype: status_subtype,
          failure_message:
            ::Claims::Invoices::StatusSubtypes.contractor_failure_message(
              status,
              status_subtype
            ),
          retry_guidance:
            ::Claims::Invoices::StatusSubtypes.retry_guidance(
              status,
              status_subtype
            )
        }
      end

      def cleanup_failed_contractor_upload!(ingest_run)
        return unless cleanup_failed_invoice_artifacts

        ::Claims::Ingest::CleanupFailedContractorUpload.call(
          ingest_run: ingest_run
        )
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][#{log_prefix}] cleanup failed ingest_run_id=#{ingest_run.id}: #{e.class}: #{e.message}"
        )
      end

      def create_failed_step(ingest_run, session_id, ingest_document, error)
        return unless ingest_document&.id

        status_subtype = ::Claims::Invoices::FailureSubtypes.upload(error)
        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run.id,
          session_id: session_id,
          ingest_document_id: ingest_document.id,
          step_type: "ocr_read",
          status: "failed",
          error_text: "ocr_enqueue_or_upload_failed: #{error.message}",
          **::Claims::Invoices::FailureSubtypes.step_attributes(
            status: "technical_failure",
            status_subtype: status_subtype,
            error: error
          ),
          created_at: Time.current,
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end

      def pending_storage_key(session_id:, filename:, content_type:)
        extension =
          ::Claims::Ingest::EvidenceFile.storage_extension_for(
            filename: filename,
            content_type: content_type
          )
        "PENDING/session=#{session_id}/ingest_document=#{SecureRandom.uuid}/#{SecureRandom.uuid}#{extension}"
      end

      def mark_orphaned_ingest_failures!(ingest_run:, results:)
        orphaned_failures =
          results.count do |result|
            result[:status] == "failed" &&
              result[:ingest_document_id].to_s.strip.empty?
          end

        return if orphaned_failures.zero?

        failed_files = ingest_run.failed_files.to_i + orphaned_failures
        completed_files = ingest_run.completed_files.to_i
        processed_files = completed_files + failed_files
        total_files = [ingest_run.total_files.to_i, results.size].max
        status =
          if total_files.positive? && processed_files >= total_files
            completed_files.positive? ? "partial" : "failed"
          else
            "running"
          end

        ingest_run.update!(
          status: status,
          total_files: total_files,
          failed_files: failed_files,
          pipeline_error_code: "upload_unexpected_exception",
          pipeline_error_description:
            "#{orphaned_failures} file upload #{"failure".pluralize(orphaned_failures)} could not be attached to an ingest document.",
          completed_at:
            %w[succeeded failed partial].include?(status) ? Time.current : nil,
          updated_at: Time.current
        )
      end
    end
  end
end
