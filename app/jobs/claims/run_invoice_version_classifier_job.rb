# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunInvoiceVersionClassifierJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 3

    def perform(invoice_version_id, ingest_run_id = nil)
      invoice_version = ::Claims::InvoiceVersion.find(invoice_version_id)
      invoice = invoice_version.invoice

      read_step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          invoice_version: invoice_version,
          step_type: "plus1fix_ocr_read"
        )
      read_step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )
      invoice.update!(
        status: "ocr_in_progress",
        status_updated_at: Time.current
      )

      read_payload =
        call_node_ocr!(
          storage_key: invoice_version.storage_key,
          model_id: "prebuilt-read"
        )
      di_read_raw_json = read_payload.fetch("di_raw_json")
      read_step.update!(
        status: "succeeded",
        di_results_json: read_payload,
        error_text: nil,
        updated_at: Time.current
      )

      classifier_step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          invoice_version: invoice_version,
          step_type: "plus1fix_classifier"
        )
      classifier_step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      contextwindowjson =
        build_classifier_contextwindowjson(
          invoice_version: invoice_version,
          di_read_raw_json: di_read_raw_json
        )
      classifier_payload =
        call_node_genai!(
          contextwindowjson: contextwindowjson,
          diagnostic_context:
            genai_diagnostic_context(
              invoice_version: invoice_version,
              ingest_run_id: ingest_run_id
            )
        )

      unless classifier_payload.fetch("document_kind", nil).to_s == "invoice"
        raise "Replacement PDF classified as #{classifier_payload["document_kind"].inspect}, expected \"invoice\"."
      end

      result =
        ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
          invoice_version_id: invoice_version.id,
          classifier_payload: classifier_payload
        )
      unless result[:ok] || result["ok"]
        raise "ApplyClassifierResult failed: #{result.inspect}"
      end

      classifier_step.update!(
        status: "succeeded",
        genai_results_json: classifier_payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      enqueue_invoice_ocr!(
        invoice_version: invoice_version,
        ingest_run_id: ingest_run_id
      )
      reconcile_run!(ingest_run_id: ingest_run_id)
    rescue => e
      target_step = classifier_step || read_step
      target_step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        updated_at: Time.current
      )
      invoice&.update!(status: "ocr_failed", status_updated_at: Time.current)
      reconcile_run!(ingest_run_id: ingest_run_id)
      raise
    end

    private

    def find_or_create_step!(ingest_run_id:, invoice_version:, step_type:)
      step = nil

      if ingest_run_id.present?
        step =
          ::Claims::IngestStepRun
            .where(
              ingest_run_id: ingest_run_id,
              invoice_version_id: invoice_version.id,
              step_type: step_type
            )
            .where(status: %w[queued in_progress])
            .order(created_at: :asc)
            .first
      end

      step ||=
        begin
          invoice = invoice_version.invoice
          ::Claims::IngestStepRun.create!(
            ingest_run_id: ingest_run_id,
            session_id: invoice.session_id,
            invoice_version_id: invoice_version.id,
            step_type: step_type,
            status: "queued",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )
        end
    end

    def build_classifier_contextwindowjson(invoice_version:, di_read_raw_json:)
      config = ::Claims::ValidationgenaiConfig.order(:created_at).first
      sys =
        config&.classifier_pdf_system_record.to_s.presence ||
          config&.classifier_system_record.to_s
      user0 = config&.user_record0.to_s

      if sys.to_s.strip.empty?
        raise "validationgenai_config.classifier_pdf_system_record is empty"
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
              User record: Replacement invoice PDF to classify
              classifier_step_type: plus1fix_classifier
              File metadata:
              original_filename: #{invoice_version.original_filename}
              content_type: #{invoice_version.content_type}
              byte_size: #{invoice_version.byte_size}

              Document Intelligence raw json:
              #{di_read_raw_json.to_json}

              Actual ask:
              Classify this replacement invoice PDF from DI-read JSON only.
              Verify document_kind is invoice, then detect upgrade types,
              eligibility code, and product references. Do not extract
              supporting-document located fields in this call.
              Reply must be strict JSON using the classifier schema from the
              system record.
            TEXT
      }

      messages
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

    def call_node_genai!(contextwindowjson:, diagnostic_context: {})
      base = ENV.fetch("INV_NODE_BASE_URL")
      uri = URI("#{base}/inv/genai")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body =
        JSON.generate(
          contextwindowjson: contextwindowjson,
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

    def genai_diagnostic_context(invoice_version:, ingest_run_id:)
      {
        step_type: "plus1fix_classifier",
        ingest_run_id: ingest_run_id,
        invoice_version_id: invoice_version.id,
        original_filename: invoice_version.original_filename,
        content_type: invoice_version.content_type
      }.compact
    end

    def enqueue_invoice_ocr!(invoice_version:, ingest_run_id:)
      invoice = invoice_version.invoice
      invoice.update!(status: "ocr_queued", status_updated_at: Time.current)

      ::Claims::IngestStepRun.find_or_create_by!(
        ingest_run_id: ingest_run_id,
        invoice_version_id: invoice_version.id,
        step_type: "ocr_invoice"
      ) do |step|
        step.session_id = invoice.session_id
        step.status = "queued"
        step.error_text = nil
        step.created_at = Time.current
        step.updated_at = Time.current
      end

      ::Claims::RunOcrJob.perform_async(
        invoice_version.id,
        ingest_run_id,
        "prebuilt-invoice",
        true,
        "use_existing_classifier",
        "ocr_invoice"
      )
    end

    def reconcile_run!(ingest_run_id:)
      return if ingest_run_id.blank?

      ::Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id)
    rescue StandardError
      nil
    end
  end
end
