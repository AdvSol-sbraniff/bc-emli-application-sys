# app/jobs/claims/run_ocr_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunOcrJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_ocr,
                    retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

    # args:
    # - invoice_version_id (required)
    # - ingest_run_id (required)  => parent pipeline run
    def perform(invoice_version_id, ingest_run_id)
      raise "Missing ingest_run_id for invoice OCR." if ingest_run_id.blank?
      return if terminal_run?(ingest_run_id)

      Rails.logger.info("[CLAIMS][INGEST][RUN_OCR]")

      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)
      step =
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: inv.session_id,
          invoice_version_id: iv.id,
          step_type: "extract_invoice"
        )
      return unless step

      # OCR reruns make all AI-derived outputs stale for this invoice version.
      # Fresh uploads usually have nothing to clear, but admin/manual reruns do.
      ::Claims::InvoiceVersions::ResetAiOutputs.call(invoice_version_id: iv.id)

      # 2) call node
      base = ENV.fetch("INV_NODE_BASE_URL") # e.g. http://host.docker.internal:3001
      uri = URI("#{base}/inv/ocr")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body =
        JSON.generate(storageKey: iv.storage_key, modelId: "prebuilt-invoice")

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 180

      resp = http.request(req)
      unless resp.is_a?(Net::HTTPSuccess)
        raise "Node OCR failed #{resp.code}: #{resp.body.to_s[0, 500]}"
      end

      payload = JSON.parse(resp.body)
      di_raw = payload.fetch("di_raw_json")

      Claims::InvoiceVersion.transaction do
        # 4) persist DI payload
        iv.update!(di_raw_json: di_raw)

        # 4b) populate first-class fields on invoice_versions from di_raw_json
        result =
          ::Claims::InvoiceVersions::ApplyDiResult.call(
            invoice_version_id: iv.id,
            di_json: di_raw
          )

        # 4c) fail if mapping failed
        unless result[:ok] || result["ok"]
          raise "ApplyDiResult failed: #{result[:error] || result["error"] || "unknown error"}"
        end

        # 4d) populate lineitems from di_raw_json
        li_result =
          ::Claims::Lineitems::ApplyDiLineitems.call(
            invoice_version_id: iv.id,
            di_json: di_raw
          )

        unless li_result[:ok] || li_result["ok"]
          raise "ApplyDiLineitems failed: #{li_result[:error] || li_result["error"] || "unknown error"}"
        end
      end

      # 5) mark succeeded
      step.update!(
        status: "succeeded",
        di_results_json: payload,
        error_text: nil,
        updated_at: Time.current
      )
    rescue StandardError => e
      failure_code = ocr_failure_subtype(e)
      # mark failed (best-effort)
      begin
        step&.update!(
          status: "failed",
          error_text: e.message,
          di_results_json: nil,
          **::Claims::Ingest::FailureClassifier.step_attributes(
            failure_category: "technical_failure",
            failure_code: failure_code,
            error: e
          ),
          updated_at: Time.current
        )
      rescue StandardError
        # ignore
      end

      raise if ::Claims::Ingest::RetryPolicy.retryable?(e)
    ensure
      if ingest_run_id.present?
        ::Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
      end
    end

    private

    def terminal_run?(ingest_run_id)
      ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
        ::Claims::IngestRun.find(ingest_run_id).status
      )
    end

    def ocr_failure_subtype(error)
      ::Claims::Ingest::FailureClassifier.ocr(error)
    end
  end
end
