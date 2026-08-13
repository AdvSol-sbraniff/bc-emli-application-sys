# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunIngestReadOcrJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_ocr,
                    retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

    def perform(ingest_document_id, ingest_run_id)
      raise "Missing ingest_run_id for ingest read OCR." if ingest_run_id.blank?
      return if terminal_run?(ingest_run_id)

      document = ::Claims::IngestDocument.find(ingest_document_id)

      step =
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: document.session_id,
          ingest_document_id: document.id,
          step_type: "read_document"
        )
      return unless step

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
    rescue StandardError => e
      failure_code = ::Claims::Ingest::FailureClassifier.ocr(e)
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        di_results_json: nil,
        **::Claims::Ingest::FailureClassifier.step_attributes(
          failure_category: "technical_failure",
          failure_code: failure_code,
          error: e
        ),
        updated_at: Time.current
      )
      raise if ::Claims::Ingest::RetryPolicy.retryable?(e)
    ensure
      advance_run!(ingest_run_id: ingest_run_id)
    end

    private

    def terminal_run?(ingest_run_id)
      ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
        ::Claims::IngestRun.find(ingest_run_id).status
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

      ::Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
    end
  end
end
