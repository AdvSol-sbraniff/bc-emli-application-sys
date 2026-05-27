require "json"
require "net/http"
require "securerandom"
require "uri"

module Claims
  module SupportingDocuments
    class UploadPdfs
      Result = Struct.new(:uploaded_count, :rows) do
        def to_h
          {
            ok: true,
            uploaded_count: uploaded_count,
            rows: rows
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

        invoice = ::Claims::Invoice.find(@invoice_id)
        session_id = invoice.session_id
        raise "Invoice is missing session_id." if session_id.blank?
        raise "No files received. Expected multipart field pdfs[] (or pdfs)." if @files.empty?

        rows = @files.map do |file|
          create_supporting_document!(invoice: invoice, session_id: session_id, file: file)
        end

        Result.new(rows.size, rows).to_h
      end

      private

      def create_supporting_document!(invoice:, session_id:, file:)
        filename = safe_call(file, :original_filename).presence || "supporting-document.pdf"
        content_type = safe_call(file, :content_type).presence || "application/pdf"
        raise "Only PDF files are supported." unless pdf_file?(filename, content_type)

        document_id = SecureRandom.uuid
        storage_key = build_storage_key(
          session_id: session_id,
          invoice_id: invoice.id,
          supporting_document_id: document_id,
          filename: filename
        )

        now = Time.current

        document = ::Claims::SupportingDocument.create!(
          id: document_id,
          invoice_id: invoice.id,
          storage_provider: "azure_blob",
          storage_key: storage_key,
          original_filename: filename,
          content_type: content_type,
          byte_size: safe_call(file, :size),
          created_at: now,
          updated_at: now
        )

        begin
          node_resp = node_upload_supporting_pdf!(
            session_id: session_id,
            invoice_id: invoice.id,
            supporting_document_id: document.id,
            file: file
          )

          document.update!(
            storage_provider: "azure_blob",
            storage_key: extract_storage_key(node_resp),
            byte_size: node_resp["byte_size"] || safe_call(file, :size),
            sha256: node_resp["sha256"],
            updated_at: Time.current
          )

          serialize_supporting_document(document.reload)
        rescue => e
          document.destroy if document&.persisted?
          raise e
        end
      end

      def serialize_supporting_document(document)
        display_type =
          document.supporting_document_type&.description ||
            document.supporting_document_type&.type_key || document.content_type

        {
          id: document.id,
          invoice_id: document.invoice_id,
          supporting_document_type_id: document.supporting_document_type_id,
          supporting_document_type_key: document.supporting_document_type&.type_key,
          supporting_document_type_description:
            document.supporting_document_type&.description,
          classification_status: document.classification_status,
          classification_confidence: document.classification_confidence,
          classification_reason: document.classification_reason,
          classified_at: document.classified_at,
          storage_provider: document.storage_provider,
          storage_key: document.storage_key,
          original_filename: document.original_filename,
          content_type: display_type,
          mime_content_type: document.content_type,
          byte_size: document.byte_size,
          sha256: document.sha256,
          created_at: document.created_at,
          updated_at: document.updated_at
        }
      end

      def build_storage_key(session_id:, invoice_id:, supporting_document_id:, filename:)
        safe_filename = File.basename(filename.to_s).gsub(/[^\w.\-]+/, "_")
        "sessions/#{session_id}/invoices/#{invoice_id}/supporting-documents/#{supporting_document_id}/#{safe_filename}"
      end

      def node_upload_supporting_pdf!(session_id:, invoice_id:, supporting_document_id:, file:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/upload-supporting-pdf")
        req = Net::HTTP::Post.new(uri)

        io = File.open(file.path, "rb")

        form = [
          ["sessionId", session_id.to_s],
          ["invoiceId", invoice_id.to_s],
          ["supportingDocumentId", supporting_document_id.to_s],
          ["file", io, { filename: safe_call(file, :original_filename) || File.basename(file.path), content_type: safe_call(file, :content_type) || "application/pdf" }]
        ]

        req.set_form(form, "multipart/form-data")

        res = Net::HTTP.start(uri.host, uri.port, use_ssl: (uri.scheme == "https"), read_timeout: 120) do |http|
          http.request(req)
        end

        body = res.body.to_s
        raise "Node upload failed HTTP=#{res.code} body=#{body}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(body)
      ensure
        io&.close
      end

      def extract_storage_key(node_resp)
        node_resp.fetch("storage_key")
      end

      def pdf_file?(filename, content_type)
        content_type.to_s == "application/pdf" || filename.to_s.downcase.end_with?(".pdf")
      end

      def safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)
        obj.public_send(method_name)
      rescue
        nil
      end
    end
  end
end
