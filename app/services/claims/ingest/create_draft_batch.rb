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

        ::Claims::Invoice.transaction do
          now = Time.current
          shell_invoice =
            ::Claims::Invoice.create!(
              session_id: session_id,
              contractor_id: contractor_id,
              submitter_id: nil,
              status: "contractor_precheck",
              status_updated_at: now,
              submitted_at: nil,
              created_at: now,
              updated_at: now
            )

          ingest_run =
            ::Claims::IngestRun.create!(
              session_id: session_id,
              contractor_id: contractor_id,
              invoice_id: shell_invoice.id,
              run_kind: "initial_upload",
              status: "queued",
              cleanup_failed_invoice_artifacts:
                cleanup_failed_invoice_artifacts,
              total_files: files.size,
              completed_files: 0,
              failed_files: 0,
              **::Claims::Genai::DeploymentConfig.snapshot_attributes,
              created_at: now,
              updated_at: now
            )

          stage_step =
            ::Claims::IngestStepRun.create!(
              ingest_run_id: ingest_run.id,
              session_id: session_id,
              step_type: "stage_package",
              status: "in_progress",
              error_text: nil,
              created_at: now,
              updated_at: now
            )
        end

        results =
          files.each_with_index.map do |file, index|
            process_file(file, index, session_id, ingest_run, shell_invoice.id)
          end

        failed_results = results.select { |row| row[:status].to_s == "failed" }
        if failed_results.any?
          failure_category, failure_subtype =
            staging_failure_category_and_subtype(failed_results)
          normalized_subtype =
            ::Claims::Ingest::FailureCatalog.normalize(
              failure_category,
              failure_subtype
            ).presence || failure_subtype
          failure_payload =
            contractor_failure_payload(
              failure_category: failure_category,
              failure_code: normalized_subtype
            )
          stage_step.update!(
            status: "failed",
            error_text:
              "One or more evidence files failed during upload package staging.",
            **::Claims::Ingest::FailureClassifier.step_attributes(
              failure_category: failure_category,
              failure_code: normalized_subtype
            ),
            updated_at: Time.current
          )
          ::Claims::Ingest::RunTransition.mark_failed!(
            run: ingest_run,
            total_files: files.size,
            failed_files: failed_results.size,
            failure_category: failure_category,
            failure_code: normalized_subtype,
            pipeline_error_code: normalized_subtype,
            pipeline_error_description:
              "Upload package staging failed: #{normalized_subtype}."
          )
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

        ::Claims::Ingest::RunTransition.mark_running!(
          run: ingest_run,
          total_files: files.size
        )
        ::Claims::Ingest::AdvanceRun.call(ingest_run_id: ingest_run.id)
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
          ::Claims::Ingest::FailureClassifier.upload(error).presence ||
            "upload_unexpected_exception"
        now = Time.current
        diagnostic_attributes =
          ::Claims::Ingest::FailureClassifier.step_attributes(
            failure_category: "technical_failure",
            failure_code: error_code,
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
          label: "run transition",
          diagnostic_id: diagnostic_id
        ) do
          if ingest_run&.id
            ::Claims::Ingest::RunTransition.mark_failed!(
              run: ingest_run,
              total_files: [ingest_run.total_files.to_i, files.size].max,
              failed_files: [ingest_run.failed_files.to_i, 1].max,
              failure_category: "technical_failure",
              failure_code: error_code,
              pipeline_error_code: error_code,
              pipeline_error_description:
                "Upload package staging failed before processing completed."
            )
          end
        end
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
            step_type: "read_document",
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

      def staging_failure_category_and_subtype(failed_results)
        errors =
          failed_results.map { |row| row[:error].to_s.downcase }.join(" ")

        if upload_technical_failure?(errors)
          return [
            "technical_failure",
            ::Claims::Ingest::FailureClassifier.upload(errors)
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

      def contractor_failure_payload(failure_category:, failure_code:)
        {
          failure_category: failure_category,
          failure_code: failure_code,
          failure_message:
            ::Claims::Ingest::FailureCatalog.contractor_failure_message(
              failure_category,
              failure_code
            ),
          retry_guidance:
            ::Claims::Ingest::FailureCatalog.retry_guidance(
              failure_category,
              failure_code
            )
        }
      end

      def create_failed_step(ingest_run, session_id, ingest_document, error)
        return unless ingest_document&.id

        failure_code = ::Claims::Ingest::FailureClassifier.upload(error)
        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run.id,
          session_id: session_id,
          ingest_document_id: ingest_document.id,
          step_type: "read_document",
          status: "failed",
          error_text: "ocr_enqueue_or_upload_failed: #{error.message}",
          **::Claims::Ingest::FailureClassifier.step_attributes(
            failure_category: "technical_failure",
            failure_code: failure_code,
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
    end
  end
end
