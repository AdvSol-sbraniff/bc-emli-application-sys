# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  module Ingest
    class UploadEvidenceFileToNode
      def self.call(
        session_id:,
        upload_scope_id:,
        file:,
        ingest_document_id: nil
      )
        new(
          session_id: session_id,
          upload_scope_id: upload_scope_id,
          file: file,
          ingest_document_id: ingest_document_id
        ).call
      end

      def initialize(session_id:, upload_scope_id:, file:, ingest_document_id:)
        @session_id = session_id
        @upload_scope_id = upload_scope_id
        @file = file
        @ingest_document_id = ingest_document_id
      end

      def call
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        uri = URI("#{base.sub(%r{/\z}, "")}/inv/upload-pdf")
        req = Net::HTTP::Post.new(uri)
        io = File.open(@file.path, "rb")

        form = [
          ["sessionId", @session_id.to_s],
          ["invoiceVersionId", @upload_scope_id.to_s]
        ]
        if @ingest_document_id.present?
          form << ["ingestDocumentId", @ingest_document_id.to_s]
        end
        form << [
          "file",
          io,
          {
            filename:
              ::Claims::Ingest::EvidenceFile.original_filename(
                @file,
                fallback: File.basename(@file.path)
              ),
            content_type: ::Claims::Ingest::EvidenceFile.content_type(@file)
          }
        ]

        req.set_form(form, "multipart/form-data")

        response =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }
        body = response.body.to_s
        unless response.is_a?(Net::HTTPSuccess)
          raise "Node upload failed HTTP=#{response.code} body=#{body}"
        end

        JSON.parse(body)
      ensure
        io&.close
      end
    end
  end
end
