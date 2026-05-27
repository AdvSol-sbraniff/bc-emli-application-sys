# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"

module Claims
  module Ingest
    class CreateDraftBatch
      def self.call(
        contractor_id:,
        files:,
        validationgenai_ruleset_id: nil,
        log_prefix: "draft_batch"
      )
        new(
          contractor_id: contractor_id,
          files: files,
          validationgenai_ruleset_id: validationgenai_ruleset_id,
          log_prefix: log_prefix
        ).call
      end

      def initialize(
        contractor_id:,
        files:,
        validationgenai_ruleset_id:,
        log_prefix:
      )
        @contractor_id = contractor_id.to_s.strip
        @files = Array(files).flatten.compact
        @validationgenai_ruleset_id = validationgenai_ruleset_id.to_s.strip
        @log_prefix = log_prefix
      end

      def call
        raise "Missing contractor_id" if contractor_id.empty?
        raise "No files received. Expected multipart field pdfs[] (or pdfs)." if files.empty?

        ruleset_id =
          validationgenai_ruleset_id.presence || resolve_default_ruleset_id!
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

        results =
          files.each_with_index.map do |file, index|
            process_file(
              file,
              index,
              session_id,
              ingest_run,
              ruleset_id,
              shell_invoice.id
            )
          end

        shell_invoice.update!(
          status: "ocr_in_progress",
          status_updated_at: Time.current,
          updated_at: Time.current
        )

        ::Claims::Ingest::AdvanceBundleRun.call(
          ingest_run_id: ingest_run.id,
          validationgenai_ruleset_id: ruleset_id
        )
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

      attr_reader :contractor_id,
                  :files,
                  :validationgenai_ruleset_id,
                  :log_prefix

      def process_file(
        file,
        index,
        session_id,
        ingest_run,
        ruleset_id,
        shell_invoice_id
      )
        name = file_safe_call(file, :original_filename) || "unknown.pdf"
        content_type = file_safe_call(file, :content_type) || "application/pdf"
        size = file_safe_call(file, :size)
        ingest_document = nil

        begin
          ingest_document =
            ::Claims::IngestDocument.create!(
              ingest_run_id: ingest_run.id,
              session_id: session_id,
              contractor_id: contractor_id,
              resolved_invoice_id: shell_invoice_id,
              storage_provider: "azure_blob",
              storage_key:
                "PENDING/session=#{session_id}/ingest_document=#{SecureRandom.uuid}/#{SecureRandom.uuid}.pdf",
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
          raise "Node upload returned no storage_key" if final_storage_key.empty?

          ingest_document.update!(
            storage_key: final_storage_key,
            byte_size: node_resp.key?("byte_size") ? node_resp["byte_size"] : ingest_document.byte_size,
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
              ingest_run.id,
              ruleset_id
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

      def resolve_default_ruleset_id!
        row =
          ::Claims::ValidationgenaiRuleset
            .joins(
              "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.validationgenai_rulesets.invoice_upgrade_type_id"
            )
            .where(
              "iut.upgrade_type_key = ? OR claims.validationgenai_rulesets.ruleset_shortname = ?",
              "common",
              "common"
            )
            .order(
              Arel.sql(
                "claims.validationgenai_rulesets.updated_at DESC, claims.validationgenai_rulesets.created_at DESC, claims.validationgenai_rulesets.id DESC"
              )
            )
            .first

        raise "No default/common validationgenai_ruleset found for full GenAI run." if row.nil?

        row.id
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
        content_type = file_safe_call(file, :content_type) || "application/pdf"

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
        raise "Node upload failed HTTP=#{res.code} body=#{body}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(body)
      ensure
        io&.close
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
