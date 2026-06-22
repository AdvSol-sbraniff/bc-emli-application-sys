# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunIngestTriageJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 3

    def perform(
      ingest_document_id,
      ingest_run_id = nil,
      requested_step_type = nil
    )
      document = ::Claims::IngestDocument.find(ingest_document_id)
      if document.di_read_raw_json.blank?
        raise "Missing ingest_documents.di_read_raw_json for ingest_document_id=#{document.id}"
      end
      step_type = classifier_step_type_for(document, requested_step_type)

      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          document: document,
          step_type: step_type
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      contextwindowjson =
        build_classifier_contextwindowjson(
          document: document,
          step_type: step_type
        )
      attachments = build_attachments(document: document, step_type: step_type)
      triage_payload =
        call_node_genai!(
          contextwindowjson: contextwindowjson,
          attachments: attachments,
          diagnostic_context:
            genai_diagnostic_context(
              document: document,
              step_type: step_type,
              ingest_run_id: ingest_run_id
            )
        )
      result =
        ::Claims::Ingest::ApplyDocumentTriageResult.call(
          ingest_document_id: document.id,
          triage_payload: triage_payload
        )
      unless result[:ok]
        raise "ApplyDocumentTriageResult failed: #{result.inspect}"
      end

      step.update!(
        status: "succeeded",
        genai_results_json: triage_payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      advance_run!(ingest_run_id: ingest_run_id)
    rescue => e
      status_subtype = ::Claims::Invoices::FailureSubtypes.genai(e)
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        genai_results_json:
          ::Claims::Invoices::FailureSubtypes.payload(
            status: "technical_failure",
            status_subtype: status_subtype,
            error: e
          ),
        updated_at: Time.current
      )
      advance_run!(ingest_run_id: ingest_run_id)
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

    def build_classifier_contextwindowjson(document:, step_type:)
      config = ::Claims::ValidationgenaiConfig.order(:created_at).first
      sys =
        classifier_system_record(
          config: config,
          step_type: step_type,
          document: document
        )
      user0 = config&.user_record0.to_s

      if sys.strip.empty?
        raise "validationgenai_config.#{classifier_config_field(document)} is empty"
      end

      messages = [
        { role: "system", content: [{ type: "input_text", text: sys }] }
      ]
      if user0.strip.present?
        messages << {
          role: "user",
          content: [{ type: "input_text", text: user0 }]
        }
      end
      messages << {
        role: "user",
        content: [{ type: "input_text", text: <<~TEXT }]
              User record: Document to classify
              classifier_step_type: #{step_type}
              File metadata:
              original_filename: #{document.original_filename}
              content_type: #{document.content_type}
              byte_size: #{document.byte_size}

              Document Intelligence raw json:
              #{document.di_read_raw_json.to_json}

              Actual ask:
              #{classifier_actual_ask(document)}
              Reply must be strict JSON using the classifier schema from the system record.
            TEXT
      }

      messages
    end

    def build_attachments(document:, step_type:)
      return [] if document.storage_key.blank?

      [
        {
          type: "input_file",
          storageKey: document.storage_key,
          container: ENV["AZURE_BLOB_CONTAINER"].presence,
          filename: document.original_filename.presence || "image_document"
        }.compact
      ]
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

    def genai_diagnostic_context(document:, step_type:, ingest_run_id:)
      {
        step_type: step_type,
        ingest_run_id: ingest_run_id,
        ingest_document_id: document.id,
        original_filename: document.original_filename,
        content_type: document.content_type
      }.compact
    end

    def classifier_step_type_for(document, requested_step_type)
      requested = requested_step_type.to_s
      if %w[classifier_files fix_classifier_files].include?(requested)
        return requested
      end

      "classifier_files"
    end

    def image_document?(document)
      content_type = document.content_type.to_s.downcase
      return true if content_type.start_with?("image/")

      filename = document.original_filename.to_s.downcase
      filename.end_with?(".jpg", ".jpeg", ".png")
    end

    def classifier_config_field(document)
      if image_document?(document)
        :classifier_image_system_record
      else
        :classifier_pdf_system_record
      end
    end

    def classifier_system_record(config:, step_type:, document:)
      return "" if config.nil?

      field = classifier_config_field(document)
      value = config.respond_to?(field) ? config.public_send(field).to_s : ""
      value.presence || config.classifier_system_record.to_s
    end

    def classifier_actual_ask(document)
      return <<~TEXT.squish if image_document?(document)
          Classify this image file. Use the attached image as primary evidence.
          Treat filename, MIME type, and DI-read JSON as weak hints only.
          If it is a supporting document, classify the supporting document type
          and assess routing quality. Do not return official visual_findings or
          supporting-document located fields in this call; those are extracted in
          separate downstream calls after routing.
        TEXT

      <<~TEXT.squish
        Classify this PDF/document using both the attached file and DI-read JSON.
        Treat DI-read text as the primary structured source for text values, and
        use the attached file as visual/context backup when useful. If it is an
        invoice, detect upgrade types, eligibility code, and product references.
        If it is a supporting document, classify the supporting document type and
        assess routing quality. Do not extract supporting-document located fields
        in this call; those are extracted in separate downstream calls after
        routing.
      TEXT
    end

    def advance_run!(ingest_run_id:)
      return if ingest_run_id.blank?

      ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
    rescue StandardError
      nil
    end
  end
end
