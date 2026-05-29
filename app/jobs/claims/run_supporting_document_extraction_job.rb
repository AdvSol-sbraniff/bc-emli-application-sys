# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunSupportingDocumentExtractionJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 0

    def perform(
      ingest_document_id,
      ingest_run_id = nil,
      validationgenai_ruleset_id = nil
    )
      document = ::Claims::IngestDocument.find(ingest_document_id)
      if document.di_read_raw_json.blank?
        raise "Missing ingest_documents.di_read_raw_json for ingest_document_id=#{document.id}"
      end
      unless document.document_kind == "supplement"
        raise "Document is not a supporting document: ingest_document_id=#{document.id}"
      end
      if document.supporting_document_type_id.blank?
        raise "Missing supporting_document_type_id for ingest_document_id=#{document.id}"
      end

      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          document: document,
          step_type: "supporting_document_extraction"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      contextwindowjson = build_contextwindowjson(document: document)
      payload = call_node_genai!(contextwindowjson: contextwindowjson)

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      advance_run!(
        ingest_run_id: ingest_run_id,
        validationgenai_ruleset_id: validationgenai_ruleset_id
      )
    rescue => e
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        updated_at: Time.current
      )
      advance_run!(
        ingest_run_id: ingest_run_id,
        validationgenai_ruleset_id: validationgenai_ruleset_id
      )
      raise
    end

    private

    def find_or_create_step!(ingest_run_id:, document:, step_type:)
      step = nil

      if ingest_run_id.present?
        step =
          ::Claims::IngestStepRun
            .where(
              ingest_run_id: ingest_run_id,
              ingest_document_id: document.id,
              step_type: step_type
            )
            .where(status: %w[queued in_progress])
            .order(created_at: :asc)
            .first
      end

      step ||=
        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run_id,
          session_id: document.session_id,
          ingest_document_id: document.id,
          step_type: step_type,
          status: "queued",
          error_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )
    end

    def build_contextwindowjson(document:)
      config = ::Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.supporting_document_extraction_system_record.to_s
      if sys.strip.empty?
        raise "validationgenai_config.supporting_document_extraction_system_record is empty"
      end

      type = document.supporting_document_type
      field_tasks =
        ::Claims::SupportingDocuments::LocatedFieldPrompt.call(
          supporting_document_type: type
        )
      if field_tasks.blank?
        raise "No supporting-document located-field tasks configured for #{type&.type_key || document.supporting_document_type_id}"
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
                User record: Supporting document to extract
                Document Intelligence raw json:
                #{document.di_read_raw_json.to_json}

                Actual ask:
                Extract the configured supporting_document_located_fields for supporting_document_type_key=#{type.type_key}.
                Reply must be strict JSON using the supporting-document extraction schema from the system record.
              TEXT
      ]
    end

    def call_node_genai!(contextwindowjson:)
      base = ENV.fetch("INV_NODE_BASE_URL")
      uri = URI("#{base}/inv/genai")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(contextwindowjson: contextwindowjson)

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 10
      http.read_timeout = 300

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Node GenAI failed #{resp.code}: #{resp.body.to_s[0, 500]}"
      end

      JSON.parse(resp.body)
    end

    def advance_run!(ingest_run_id:, validationgenai_ruleset_id:)
      return if ingest_run_id.blank?

      ::Claims::Ingest::AdvanceBundleRun.call(
        ingest_run_id: ingest_run_id,
        validationgenai_ruleset_id: validationgenai_ruleset_id
      )
    rescue StandardError
      nil
    end
  end
end
