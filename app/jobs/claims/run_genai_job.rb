# app/jobs/claims/run_genai_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunGenaiJob
    include Sidekiq::Job
    sidekiq_options retry: 5

    # args must match controller perform_async call order:
    # perform(session_id, invoice_version_id, validationgenai_ruleset_id, ingest_run_id=nil)
    def perform(session_id, invoice_version_id, validationgenai_ruleset_id, ingest_run_id = nil)
Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START")
Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] session_id=#{session_id}")
Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] invoice_version_id=#{invoice_version_id}")
Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] ruleset_id=#{validationgenai_ruleset_id}")

      iv      = Claims::InvoiceVersion.find(invoice_version_id)
      Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step0.1")

      inv     = Claims::Invoice.find(iv.invoice_id)
      Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step0.2")

      sess    = Claims::Session.find(session_id)
      Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step0.3 yep")

begin
  ruleset = Claims::ValidationgenaiRuleset.find(validationgenai_ruleset_id)
rescue => e
  Rails.logger.error("[CLAIMS][RUN_GENAI_JOB] FAIL before step0.4 ruleset_id=#{validationgenai_ruleset_id} #{e.class}: #{e.message}")
  Rails.logger.error(e.backtrace.first(15).join("\n"))
  raise
end

Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step0.4")


      # Guardrails: GenAI relies on DI raw JSON being present (from OCR step)
      if iv.di_raw_json.blank?
        raise "Missing invoice_versions.di_raw_json. Run OCR first for invoice_version_id=#{iv.id}."
      end

            Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step0.5")



      # 1) create step run (queued/in_progress == ok: NULL)
      Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step1.0")

      step = Claims::IngestStepRun.create!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version_id: iv.id,
        step_type: "genai",
        ok: nil,
        error_text: nil,
        validationgenai_ruleset_id: validationgenai_ruleset_id,
        created_at: Time.current,
        updated_at: Time.current
      )

      # 2) set invoice status
      Rails.logger.info("[CLAIMS][RUN_GENAI_JOB] START step2")

      inv.update!(status: "genai_in_progress", status_updated_at: Time.current)

      # 3) build context window JSON (GenAI must use DI RAW JSON + case facts + ruleset)
      # NOTE: for now, the "case facts" can be hardcoded sample data per your milestone.
      # Later milestone: replace with DB joins (contractors, users, users_eligibilitycodes, etc.)
      case_facts = build_case_facts(sess: sess, invoice_version: iv)

      contextwindowjson = build_contextwindowjson(
        ruleset: ruleset,
        case_facts: case_facts,
        di_raw_json: iv.di_raw_json
      )

      # 4) call ultra-thin Node endpoint: POST /inv/genai
      base = ENV.fetch("INV_NODE_BASE_URL") # e.g. http://host.docker.internal:3001
      uri  = URI("#{base}/inv/genai")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate(contextwindowjson: contextwindowjson)

      http = Net::HTTP.new(uri.host, uri.port)
      http.open_timeout = 5
      http.read_timeout = 180

      resp = http.request(req)
      raise "Node GenAI failed #{resp.code}: #{resp.body.to_s[0, 500]}" unless resp.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(resp.body) # should already match your strict output schema

     # 4.5) persist located_fields -> claims.invoice_version_located_fields
::Claims::InvoiceVersionLocatedFields::ApplyGenaiLocatedFields.call(
  invoice_version_id: iv.id,
  genai_payload: payload
)

      # 5) persist artifacts on the STEP (per-run history)
      step.update!(
        ok: true,
        genai_results_json: payload,
        context_window_json: contextwindowjson,
        updated_at: Time.current
      )

      # 6) persist latest on invoice_versions (per-version latest only)
      iv.update!(genai_raw_json: payload)

      # 7) finalize invoice status
      inv.update!(status: "genai_complete", status_updated_at: Time.current)
    rescue => e
      # mark failed (best-effort)
      begin
        step&.update!(ok: false, error_text: "#{e.class}: #{e.message}", updated_at: Time.current)
      rescue
        # ignore
      end

      begin
        inv&.update!(status: "genai_failed", status_updated_at: Time.current)
      rescue
        # ignore
      end

      raise
    end

    private

    # ============================================================
    # SECTION A — CASE FACTS (milestone 1)
    # PURPOSE:
    # - Provide the “ESP database values” as a single JSON blob
    # - Hardcoded/sample now; later replaced with DB joins
    # ============================================================
    def build_case_facts(sess:, invoice_version:)
      {
        esp_database_values: {
          # from DB (or nil if not submitted yet)
          sessions: {
            submitted_at: sess.submitted_at
          },

          # hardcoded sample data (milestone 1)
          invoice_versions: {
            # NOTE: you previously listed these as “ESP database values”
            # They are NOT DI-flat fields in the prompt; they’re just “case facts”
            # you want the model to compare against. Keep them here.
            di_ocr_invoice_date: "2025-03-31",
            di_ocr_vendor_name: "Centra®\nWINDOWS",
            di_ocr_vendor_address: "4705 102 Ave SE\nCalgary, AB T2C 2X7",
            di_ocr_customer_name: "EBY, JESSE & ERIN",
            di_ocr_billing_address: "561 6 AVENUE\nCAMPBELL RIVER, BC V9W 3Z6\nCanada"
          },

          contractors: {
            business_name: "Centra",
            address: "4705 102 Ave SE, Cal Canada"
          },

          validationgenai_rulesets: {
            env_esp1_rebate: 95,
            env_esp2_rebate: 60
          },

          users_eligibilitycodes: {
            approved_at: "2025-01-01"
          },

          users: {
            participant_name: "stuff",
            participant_address: "stuff"
          }
        }
      }
    end

    # ============================================================
    # SECTION B — CONTEXT WINDOW JSON BUILDER
    # PURPOSE:
    # - Ensure model sees:
    #   1) system_record (schema + constraints)
    #   2) user_record1 (DI schema + tasks)
    #   3) user_record2 (case facts + DI raw json)
    #   4) user_record3 (actual ask)
    # ============================================================
    def build_contextwindowjson(ruleset:, case_facts:, di_raw_json:)
      sys = ruleset.system_record.to_s
      gt  = ruleset.user_record1.to_s

      if sys.strip.empty?
        raise "validationgenai_rulesets.system_record is empty for ruleset_id=#{ruleset.id}"
      end

      if gt.strip.empty?
        raise "validationgenai_rulesets.user_record1 is empty for ruleset_id=#{ruleset.id}"
      end

      [
        {
          role: "system",
          content: [{ type: "input_text", text: sys }]
        },
        {
          role: "user",
          content: [{ type: "input_text", text: gt }]
        },
        {
          role: "user",
          content: [{ type: "input_text", text: <<~TEXT }]
            User record 2 (the case)
            Esp database values:
            #{JSON.pretty_generate(case_facts)}

            Document intelligence raw json:
            #{JSON.pretty_generate(di_raw_json)}
          TEXT
        },
        {
          role: "user",
          content: [{ type: "input_text", text: <<~TEXT }]
            User record 3 (Actual Ask)
            Please perform the location tasks and rulecheck tasks.
            Reply must be using the strict JSON output schema defined in the system record.
          TEXT
        }
      ]
    end



  end
end