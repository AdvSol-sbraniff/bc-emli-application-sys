# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunSupportingDocumentTypeExtractionJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 3

    def perform(invoice_id, supporting_document_type_id, ingest_run_id = nil)
      invoice = ::Claims::Invoice.find(invoice_id)
      type = ::Claims::SupportingDocumentType.find(supporting_document_type_id)
      documents = documents_for(invoice: invoice, type: type)
      if documents.empty?
        raise "No supporting documents found for #{type.type_key}"
      end

      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          invoice: invoice,
          supporting_document_type: type,
          step_type: "supporting_document_type_extraction"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      contextwindowjson =
        build_contextwindowjson(type: type, documents: documents)
      attachments = build_attachments(documents: documents)
      payload =
        call_node_genai!(
          contextwindowjson: contextwindowjson,
          attachments: attachments,
          diagnostic_context:
            genai_diagnostic_context(
              invoice: invoice,
              type: type,
              documents: documents,
              step_type: step.step_type,
              ingest_run_id: ingest_run_id
            )
        )

      located_result =
        ::Claims::SupportingDocuments::ApplyTypeLocatedFields.call(
          invoice_id: invoice.id,
          supporting_document_type_id: type.id,
          located_fields_payload: payload
        )
      unless located_result[:ok] || located_result["ok"]
        raise "ApplySupportingDocumentTypeLocatedFields failed: #{located_result.inspect}"
      end

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      advance_run!(ingest_run_id: ingest_run_id)
    rescue => e
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        updated_at: Time.current
      )
      advance_run!(ingest_run_id: ingest_run_id)
      raise
    end

    private

    def documents_for(invoice:, type:)
      invoice
        .supporting_documents
        .where(supporting_document_type_id: type.id)
        .order(:created_at, :id)
        .to_a
    end

    def find_or_create_step!(
      ingest_run_id:,
      invoice:,
      supporting_document_type:,
      step_type:
    )
      step = nil

      if ingest_run_id.present?
        step =
          ::Claims::IngestStepRun
            .where(
              ingest_run_id: ingest_run_id,
              supporting_document_type_id: supporting_document_type.id,
              step_type: step_type
            )
            .where(status: %w[queued in_progress])
            .order(created_at: :asc)
            .first
      end

      step ||=
        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run_id,
          session_id: invoice.session_id,
          supporting_document_type_id: supporting_document_type.id,
          step_type: step_type,
          status: "queued",
          error_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )
    end

    def build_contextwindowjson(type:, documents:)
      config = ::Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.supporting_document_extraction_system_record.to_s
      if sys.strip.empty?
        raise "validationgenai_config.supporting_document_extraction_system_record is empty"
      end

      field_tasks =
        ::Claims::SupportingDocuments::LocatedFieldPrompt.call(
          supporting_document_type: type
        )
      if field_tasks.blank?
        raise "No supporting-document located-field tasks configured for #{type.type_key}"
      end

      [
        { role: "system", content: [{ type: "input_text", text: sys }] },
        { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
                User record: Selected supporting document type
                supporting_document_type_key: #{type.type_key}
                supporting_document_type_description: #{type.description}

                #{field_tasks}
              TEXT
        { role: "user", content: [{ type: "input_text", text: <<~TEXT }] }
                User record: Supporting documents to extract as one type-level set
                #{document_context(documents).to_json}

                Actual ask:
                Extract the configured supporting_document_located_fields and relevant visual_findings separately for each supplied supporting document.
                Use each file's DI-read text, filename, metadata, and attached file visuals when available.
                Return one supporting_document_located_fields_by_document[] object for every supplied supporting document.
                Copy each supporting_document_id exactly.
                Do not return group-level located fields or final eligibility decisions.
                Reply must be strict JSON using the supporting-document type extraction schema from the system record.
              TEXT
      ]
    end

    def document_context(documents)
      documents.map do |document|
        {
          supporting_document_id: document.id,
          original_filename: document.original_filename,
          content_type: document.content_type,
          classification_status: document.classification_status,
          classification_confidence: document.classification_confidence,
          classification_reason: document.classification_reason,
          supporting_document_routing_quality:
            document.supporting_document_routing_quality,
          supporting_document_routing_quality_reason:
            document.supporting_document_routing_quality_reason,
          di_read_raw_json: document.di_read_raw_json
        }
      end
    end

    def build_attachments(documents:)
      documents.filter_map do |document|
        next if document.storage_key.blank?

        {
          type: "input_file",
          storageKey: document.storage_key,
          container: ENV["AZURE_BLOB_CONTAINER"].presence,
          filename: document.original_filename.presence || "supporting_document"
        }.compact
      end
    end

    def call_node_genai!(
      contextwindowjson:,
      attachments: [],
      diagnostic_context: {}
    )
      base = ENV.fetch("INV_NODE_BASE_URL")
      uri = URI("#{base}/inv/genai")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body =
        JSON.generate(
          contextwindowjson: contextwindowjson,
          attachments: attachments,
          diagnostic_context: diagnostic_context
        )

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 300

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Node GenAI failed #{resp.code}: #{resp.body.to_s[0, 500]}"
      end

      JSON.parse(resp.body)
    end

    def genai_diagnostic_context(
      invoice:,
      type:,
      documents:,
      step_type:,
      ingest_run_id:
    )
      {
        step_type: step_type,
        ingest_run_id: ingest_run_id,
        invoice_id: invoice.id,
        supporting_document_type_id: type.id,
        supporting_document_type_key: type.type_key,
        supporting_document_count: documents.size,
        original_filenames: documents.map(&:original_filename).compact
      }.compact
    end

    def advance_run!(ingest_run_id:)
      return if ingest_run_id.blank?

      ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
    rescue StandardError
      nil
    end
  end
end
