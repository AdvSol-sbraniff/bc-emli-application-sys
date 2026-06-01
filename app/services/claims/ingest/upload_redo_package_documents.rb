# frozen_string_literal: true

require "json"
require "net/http"
require "securerandom"
require "uri"

module Claims
  module Ingest
    class UploadRedoPackageDocuments
      Result =
        Struct.new(
          :ok,
          :ingest_run_id,
          :invoice_id,
          :uploaded_count,
          :rows,
          :messages
        ) do
          def to_h
            {
              ok: ok,
              ingest_run_id: ingest_run_id,
              invoice_id: invoice_id,
              uploaded_count: uploaded_count,
              rows: rows,
              messages: messages
            }
          end
        end

      def self.call(invoice_id:, files:)
        new(invoice_id: invoice_id, files: files).call
      end

      def initialize(invoice_id:, files:)
        @invoice_id = invoice_id.to_s.strip
        @files = Array(files).flatten.compact
      end

      def call
        raise "Missing invoice_id." if @invoice_id.empty?
        if @files.empty?
          raise "No files received. Expected multipart field pdfs[] (or pdfs)."
        end

        invoice = ::Claims::Invoice.find(@invoice_id)
        session_id = invoice.session_id
        contractor_id = invoice.contractor_id
        raise "Invoice is missing session_id." if session_id.blank?
        raise "Invoice is missing contractor_id." if contractor_id.blank?

        ingest_run =
          ::Claims::IngestRun.create!(
            session_id: session_id,
            status: "queued",
            total_files: @files.size,
            completed_files: 0,
            failed_files: 0,
            messages: [],
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

        rows = []
        messages = []

        @files.each_with_index do |file, index|
          rows << create_ingest_document!(
            invoice: invoice,
            ingest_run: ingest_run,
            file: file,
            index: index
          )
        rescue => e
          messages << "file#{index + 1}: #{e.class}: #{e.message}"
          rows << {
            index: index + 1,
            original_filename:
              safe_call(file, :original_filename).presence || "unknown.pdf",
            status: "failed",
            error: e.message
          }
        end

        uploaded_count = rows.count { |row| row[:status] == "staged" }
        failed_count = rows.size - uploaded_count
        status =
          if failed_count.zero?
            "succeeded"
          elsif uploaded_count.zero?
            "failed"
          else
            "partial"
          end

        ingest_run.update!(
          status: status,
          total_files: rows.size,
          completed_files: uploaded_count,
          failed_files: failed_count,
          messages: messages,
          completed_at:
            %w[succeeded failed partial].include?(status) ? Time.current : nil,
          updated_at: Time.current
        )

        if failed_count.zero?
          stage_step.update!(
            status: "succeeded",
            error_text: nil,
            updated_at: Time.current
          )
        else
          stage_step.update!(
            status: "failed",
            error_text:
              "One or more PDFs failed during upload package staging.",
            updated_at: Time.current
          )
        end

        Result.new(
          uploaded_count.positive?,
          ingest_run.id,
          invoice.id,
          uploaded_count,
          rows,
          messages
        ).to_h
      end

      private

      def create_ingest_document!(invoice:, ingest_run:, file:, index:)
        filename =
          safe_call(file, :original_filename).presence || "package-document.pdf"
        content_type =
          safe_call(file, :content_type).presence || "application/pdf"
        unless pdf_file?(filename, content_type)
          raise "Only PDF files are supported."
        end

        document_id = SecureRandom.uuid
        document =
          ::Claims::IngestDocument.create!(
            id: document_id,
            ingest_run_id: ingest_run.id,
            session_id: invoice.session_id,
            contractor_id: invoice.contractor_id,
            invoice_id: invoice.id,
            resolved_invoice_id: invoice.id,
            storage_provider: "azure_blob",
            storage_key:
              "PENDING/session=#{invoice.session_id}/ingest_document=#{document_id}/#{SecureRandom.uuid}.pdf",
            original_filename: filename,
            content_type: content_type,
            byte_size: safe_call(file, :size),
            classification_status: "pending",
            classification_confidence: 0,
            document_kind_confidence: 0,
            created_at: Time.current,
            updated_at: Time.current
          )

        node_resp =
          node_upload_pdf!(
            session_id: invoice.session_id,
            ingest_document_id: document.id,
            file: file
          )

        document.update!(
          storage_key: node_resp.fetch("storage_key"),
          byte_size:
            (
              if node_resp.key?("byte_size")
                node_resp["byte_size"]
              else
                document.byte_size
              end
            ),
          sha256: node_resp["sha256"],
          updated_at: Time.current
        )

        {
          index: index + 1,
          id: document.id,
          ingest_document_id: document.id,
          original_filename: document.original_filename,
          content_type: document.content_type,
          byte_size: document.byte_size,
          storage_key: document.storage_key,
          status: "staged"
        }
      rescue => e
        document&.destroy
        raise e
      end

      def node_upload_pdf!(session_id:, ingest_document_id:, file:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/upload-pdf")
        req = Net::HTTP::Post.new(uri)
        io = File.open(file.path, "rb")

        req.set_form(
          [
            ["sessionId", session_id.to_s],
            ["invoiceVersionId", ingest_document_id.to_s],
            [
              "file",
              io,
              {
                filename:
                  safe_call(file, :original_filename) ||
                    File.basename(file.path),
                content_type:
                  safe_call(file, :content_type) || "application/pdf"
              }
            ]
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

      def pdf_file?(filename, content_type)
        content_type.to_s == "application/pdf" ||
          filename.to_s.downcase.end_with?(".pdf")
      end

      def safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)
        obj.public_send(method_name)
      rescue StandardError
        nil
      end
    end
  end
end
