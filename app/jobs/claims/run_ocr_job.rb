# app/jobs/claims/run_ocr_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunOcrJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_ocr, retry: 3

    # args:
    # - invoice_version_id (required)
    # - ingest_run_id (optional)  => link to batch run
    # - model_id (optional) => DI model, default prebuilt-invoice
    # - enqueue_genai_after (optional) => whether to queue RunGenaiJob after OCR
    # - genai_mode (optional) => classifier payload handling when enqueueing GenAI
    # - step_type (optional) => ingest step type
    def perform(
      invoice_version_id,
      ingest_run_id = nil,
      model_id = "prebuilt-invoice",
      enqueue_genai_after = true,
      genai_mode = "use_existing_classifier",
      step_type = "ocr"
    )
      Rails.logger.info("[CLAIMS][INGEST][RUN_OCR]")

      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)
      sess = Claims::Session.find(inv.session_id)

      # 1) find/create queued step run for this invoice
      step = nil
      if ingest_run_id.present?
        step =
          Claims::IngestStepRun
            .where(
              ingest_run_id: ingest_run_id,
              invoice_version_id: iv.id,
              step_type: step_type
            )
            .where(status: %w[queued in_progress])
            .order(created_at: :asc)
            .first
      end

      step ||=
        Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version_id: iv.id,
          step_type: step_type,
          status: "queued",
          error_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )

      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      # OCR reruns make all AI-derived outputs stale for this invoice version.
      # Fresh uploads usually have nothing to clear, but admin/manual reruns do.
      ::Claims::InvoiceVersions::ResetAiOutputs.call(
        invoice_version_id: iv.id,
        preserve_classifier: (genai_mode == "use_existing_classifier")
      )

      # 2) set invoice status
      inv.update!(status: "ocr_in_progress", status_updated_at: Time.current)

      # 3) call node
      base = ENV.fetch("INV_NODE_BASE_URL") # e.g. http://host.docker.internal:3001
      uri = URI("#{base}/inv/ocr")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(storageKey: iv.storage_key, modelId: model_id)

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

        if model_id == "prebuilt-invoice"
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
      end

      # 5) mark succeeded
      step.update!(
        status: "succeeded",
        di_results_json: payload,
        error_text: nil,
        updated_at: Time.current
      )
      inv.update!(status: "ocr_complete", status_updated_at: Time.current)

      if enqueue_genai_after
        inv.update!(status: "genai_queued", status_updated_at: Time.current)

        Claims::RunGenaiJob.perform_async(
          sess.id,
          iv.id,
          ingest_run_id,
          genai_mode
        )
      end

      if ingest_run_id.present?
        if bundle_ingest_run?(ingest_run_id) &&
             %w[ocr_read ocr_invoice].include?(step_type)
          Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
        else
          Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id)
        end
      end
    rescue => e
      # mark failed (best-effort)
      begin
        step&.update!(
          status: "failed",
          error_text: e.message,
          updated_at: Time.current
        )
      rescue StandardError
        # ignore
      end

      begin
        inv&.update!(status: "ocr_failed", status_updated_at: Time.current)
      rescue StandardError
        # ignore
      end

      begin
        if ingest_run_id.present?
          if bundle_ingest_run?(ingest_run_id) &&
               %w[ocr_read ocr_invoice].include?(step_type)
            Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
          else
            Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id)
          end
        end
      rescue StandardError
        # ignore
      end

      raise
    end

    private

    def bundle_ingest_run?(ingest_run_id)
      Claims::IngestDocument.exists?(ingest_run_id: ingest_run_id)
    end
  end
end
