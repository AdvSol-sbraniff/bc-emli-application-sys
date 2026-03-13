# app/jobs/claims/run_ocr_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunOcrJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_ocr, retry: 5

    # args:
    # - invoice_version_id (required)
    # - ingest_run_id (optional)  => link to batch run
    # - validationgenai_ruleset_id (optional) => enqueue GenAI after OCR success
    def perform(invoice_version_id, ingest_run_id = nil, validationgenai_ruleset_id = nil)
Rails.logger.info("[CLAIMS][INGEST][RUN_OCR]")

      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)
      sess = Claims::Session.find(inv.session_id)

      # 1) find/create queued step run for this invoice
      step = nil
      if ingest_run_id.present?
        step = Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: iv.id,
            step_type: "ocr"
          )
          .where(status: %w[queued in_progress])
          .order(created_at: :asc)
          .first
      end

      step ||= Claims::IngestStepRun.create!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version_id: iv.id,
        step_type: "ocr",
        status: "queued",
        error_text: nil,
        created_at: Time.current,
        updated_at: Time.current
      )

      step.update!(status: "in_progress", error_text: nil, updated_at: Time.current)

      # 2) set invoice status
      inv.update!(status: "ocr_in_progress", status_updated_at: Time.current)

      # 3) call node
      base = ENV.fetch("INV_NODE_BASE_URL") # e.g. http://host.docker.internal:3001
      uri  = URI("#{base}/inv/ocr")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(
        storageKey: iv.storage_key,
        modelId: "prebuilt-invoice"
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 180

      resp = http.request(req)
      raise "Node OCR failed #{resp.code}: #{resp.body.to_s[0, 500]}" unless resp.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(resp.body)
      di_raw  = payload.fetch("di_raw_json")


Claims::InvoiceVersion.transaction do
  # 4) persist DI payload
  iv.update!(di_raw_json: di_raw)

  # 4b) populate first-class fields on invoice_versions from di_raw_json
  result = ::Claims::InvoiceVersions::ApplyDiResult.call(
    invoice_version_id: iv.id,
    di_json: di_raw
  )

  # 4c) fail if mapping failed
  unless result[:ok] || result["ok"]
    raise "ApplyDiResult failed: #{result[:error] || result['error'] || 'unknown error'}"
  end

  # 4d) populate lineitems from di_raw_json
  li_result = ::Claims::Lineitems::ApplyDiLineitems.call(
    invoice_version_id: iv.id,
    di_json: di_raw
  )

  unless li_result[:ok] || li_result["ok"]
    raise "ApplyDiLineitems failed: #{li_result[:error] || li_result['error'] || 'unknown error'}"
  end
end

      # 5) mark succeeded
      step.update!(status: "succeeded", di_results_json: payload, error_text: nil, updated_at: Time.current)
      inv.update!(status: "ocr_complete", status_updated_at: Time.current)

      if validationgenai_ruleset_id.present?
        Claims::RunGenaiJob.perform_async(
          sess.id,
          iv.id,
          validationgenai_ruleset_id,
          ingest_run_id
        )
      end

      Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id) if ingest_run_id.present?
    rescue => e
      # mark failed (best-effort)
      begin
        step&.update!(status: "failed", error_text: e.message, updated_at: Time.current)
      rescue
        # ignore
      end

      begin
        inv&.update!(status: "ocr_failed", status_updated_at: Time.current)
      rescue
        # ignore
      end

      begin
        Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id) if ingest_run_id.present?
      rescue
        # ignore
      end

      raise
    end
  end
end
