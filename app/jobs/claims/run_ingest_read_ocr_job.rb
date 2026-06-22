# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunIngestReadOcrJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_ocr, retry: 3

    def perform(ingest_document_id, ingest_run_id = nil, step_type = "ocr_read")
      document = ::Claims::IngestDocument.find(ingest_document_id)

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

      payload =
        call_node_ocr!(
          storage_key: document.storage_key,
          model_id: "prebuilt-read"
        )

      document.update!(
        di_read_raw_json: payload.fetch("di_raw_json"),
        updated_at: Time.current
      )
      step.update!(
        status: "succeeded",
        di_results_json: payload,
        error_text: nil,
        updated_at: Time.current
      )

      advance_run!(ingest_run_id: ingest_run_id)
    rescue => e
      status_subtype = ::Claims::Invoices::FailureSubtypes.ocr(e)
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        di_results_json:
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

    def call_node_ocr!(storage_key:, model_id:)
      base = ENV.fetch("INV_NODE_BASE_URL")
      uri = URI("#{base}/inv/ocr")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(storageKey: storage_key, modelId: model_id)

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 180

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Node OCR failed #{resp.code}: #{resp.body.to_s[0, 500]}"
      end

      JSON.parse(resp.body)
    end

    def advance_run!(ingest_run_id:)
      return if ingest_run_id.blank?

      ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
    rescue StandardError
      nil
    end
  end
end
