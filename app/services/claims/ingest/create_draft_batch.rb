# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"

module Claims
  module Ingest
    class CreateDraftBatch
      def self.call(contractor_id:, files:, log_prefix: "draft_batch")
        new(
          contractor_id: contractor_id,
          files: files,
          log_prefix: log_prefix
        ).call
      end

      def initialize(contractor_id:, files:, log_prefix:)
        @contractor_id = contractor_id.to_s.strip
        @files = Array(files).flatten.compact
        @log_prefix = log_prefix
      end

      def call
        raise "Missing contractor_id" if contractor_id.empty?
        if files.empty?
          raise "No files received. Expected multipart field files[] (or files)."
        end

        session_result =
          ::Claims::Sessions::Create.call(contractor_id: contractor_id)
        session_id = session_result.session.id

        ingest_run =
          ::Claims::IngestRun.create!(
            session_id: session_id,
            status: "queued",
            total_files: files.size,
            completed_files: 0,
            failed_files: 0,
            messages: [],
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
          stage_step.update!(
            status: "failed",
            error_text:
              "One or more evidence files failed during upload package staging.",
            updated_at: Time.current
          )
          ingest_run.update!(
            status: "failed",
            failed_files: failed_results.size,
            messages:
              parse_ingest_messages(ingest_run.messages) +
                [
                  {
                    level: "error",
                    code: shell_invoice.status_subtype,
                    message:
                      "One or more evidence files failed during upload package staging."
                  }
                ],
            completed_at: Time.current,
            updated_at: Time.current
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
            }
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
      end

      private

      attr_reader :contractor_id, :files, :log_prefix

      def process_file(file, index, session_id, ingest_run, shell_invoice_id)
        name = file_safe_call(file, :original_filename) || "unknown"
        content_type =
          file_safe_call(file, :content_type) || "application/octet-stream"
        size = file_safe_call(file, :size)
        ingest_document = nil

        begin
          unless supported_evidence_file?(name, content_type)
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
                "PENDING/session=#{session_id}/ingest_document=#{SecureRandom.uuid}/#{SecureRandom.uuid}#{storage_extension_for(name, content_type)}",
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
            ingest_node_upload_pdf!(
              session_id: session_id,
              ingest_document_id: ingest_document.id,
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
        rescue => e
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
        if errors.include?("node upload failed")
          return "technical_failure", "upload_service_error"
        end
        if errors.include?("storage_key")
          return "technical_failure", "upload_storage_key_missing"
        end
        if errors.include?("missing env")
          return "technical_failure", "configuration_missing"
        end

        ["package_needs_correction", package_failure_subtype(failed_results)]
      end

      def create_failed_step(ingest_run, session_id, ingest_document, error)
        return unless ingest_document&.id

        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run.id,
          session_id: session_id,
          ingest_document_id: ingest_document.id,
          step_type: "ocr_read",
          status: "failed",
          error_text: "ocr_enqueue_or_upload_failed: #{error.message}",
          created_at: Time.current,
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end

      def file_safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)

        obj.public_send(method_name)
      rescue StandardError
        nil
      end

      def ingest_node_upload_pdf!(session_id:, ingest_document_id:, file:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/upload-pdf")
        req = Net::HTTP::Post.new(uri)

        io = File.open(file.path, "rb")
        filename =
          file_safe_call(file, :original_filename) || File.basename(file.path)
        content_type =
          file_safe_call(file, :content_type) || "application/octet-stream"

        req.set_form(
          [
            ["sessionId", session_id.to_s],
            ["invoiceVersionId", ingest_document_id.to_s],
            ["file", io, { filename: filename, content_type: content_type }]
          ],
          "multipart/form-data"
        )

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node upload failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      ensure
        io&.close
      end

      def supported_evidence_file?(filename, content_type)
        supported_content_type?(content_type) ||
          %w[.pdf .jpg .jpeg .png].include?(
            File.extname(filename.to_s).downcase
          )
      end

      def supported_content_type?(content_type)
        %w[application/pdf image/jpeg image/png].include?(
          content_type.to_s.downcase
        )
      end

      def storage_extension_for(filename, content_type)
        ext = File.extname(filename.to_s).downcase
        return ext if %w[.pdf .jpg .jpeg .png].include?(ext)

        case content_type.to_s.downcase
        when "application/pdf"
          ".pdf"
        when "image/jpeg"
          ".jpg"
        when "image/png"
          ".png"
        else
          ".bin"
        end
      end

      def mark_orphaned_ingest_failures!(ingest_run:, results:)
        orphaned_failures =
          results.count do |result|
            result[:status] == "failed" &&
              result[:ingest_document_id].to_s.strip.empty?
          end

        return if orphaned_failures.zero?

        messages = parse_ingest_messages(ingest_run.messages)
        messages +=
          results
            .select do |result|
              result[:status] == "failed" &&
                result[:ingest_document_id].to_s.strip.empty?
            end
            .map do |result|
              {
                level: "error",
                file: result[:original_filename],
                message: result[:error]
              }
            end

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
          messages: messages,
          completed_at:
            %w[succeeded failed partial].include?(status) ? Time.current : nil,
          updated_at: Time.current
        )
      end

      def parse_ingest_messages(messages)
        return messages if messages.is_a?(Array)

        JSON.parse(messages.to_s)
      rescue JSON::ParserError, TypeError
        []
      end
    end
  end
end
