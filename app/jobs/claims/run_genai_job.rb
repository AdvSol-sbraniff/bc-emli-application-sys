# app/jobs/claims/run_genai_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunGenaiJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 0

    # args must match controller perform_async call order:
    # perform(session_id, invoice_version_id, validationgenai_ruleset_id, ingest_run_id=nil, mode="normal")
    def perform(
      session_id,
      invoice_version_id,
      validationgenai_ruleset_id,
      ingest_run_id = nil,
      mode = "normal"
    )
      Rails.logger.info(
        "[CLAIMS][RUN_GENAI_JOB] START session_id=#{session_id} invoice_version_id=#{invoice_version_id} ruleset_id=#{validationgenai_ruleset_id} mode=#{mode}"
      )

      mode = mode.to_s.presence || "normal"
      unless %w[normal classifier_only].include?(mode)
        raise "Invalid RunGenaiJob mode=#{mode}"
      end

      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)
      sess = Claims::Session.find(session_id)

      step = nil

      if iv.di_raw_json.blank?
        raise "Missing invoice_versions.di_raw_json. Run OCR first for invoice_version_id=#{iv.id}."
      end

      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version_id: iv.id,
          step_type: "classifier"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      classifier_contextwindowjson =
        build_classifier_contextwindowjson(di_raw_json: iv.di_raw_json)
      classifier_payload =
        call_node_genai!(contextwindowjson: classifier_contextwindowjson)

      classifier_result =
        ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
          invoice_version_id: iv.id,
          classifier_payload: classifier_payload
        )
      unless classifier_result[:ok]
        raise "ApplyClassifierResult failed: #{classifier_result.inspect}"
      end

      step.update!(
        status: "succeeded",
        genai_results_json: classifier_payload,
        context_window_json: classifier_contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      if mode == "classifier_only"
        if ingest_run_id.present?
          Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id)
        end
        return
      end
      step = nil

      inv.update!(status: "genai_in_progress", status_updated_at: Time.current)

      classifier_eligibility_code =
        classifier_eligibility_code(classifier_payload)
      shared_context =
        Claims::GenaiCaseFacts::Build.build_shared_context(
          sess: sess,
          invoice: inv,
          eligibility_code: classifier_eligibility_code
        )
      case_facts = shared_context.fetch(:case_facts)

      Claims::GenaiCaseFacts::Build.persist_code_located_fields!(
        invoice_version_id: iv.id,
        case_facts: case_facts,
        classifier_eligibility_code:
          shared_context[:classifier_eligibility_code]
      )

      common_upgrade_type = upgrade_type_by_key!("common")
      common_ruleset = ruleset_for_upgrade_type!(common_upgrade_type)
      ruleset_results = []

      ruleset_results << run_genai_ruleset!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version_id: iv.id,
        step_type: "genai_common",
        upgrade_type: common_upgrade_type,
        ruleset: common_ruleset,
        case_facts: case_facts,
        di_raw_json: iv.di_raw_json
      )

      detected_upgrade_types(classifier_payload).each do |upgrade_type|
        ruleset_results << run_genai_ruleset!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version_id: iv.id,
          step_type: "genai_upgrade",
          upgrade_type: upgrade_type,
          ruleset: ruleset_for_upgrade_type!(upgrade_type),
          case_facts: case_facts,
          di_raw_json: iv.di_raw_json
        )
      end

      apply_combined_overall!(
        invoice_version: iv,
        classifier_payload: classifier_payload,
        ruleset_results: ruleset_results
      )

      inv.update!(status: "genai_complete", status_updated_at: Time.current)

      if ingest_run_id.present?
        Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id)
      end
    rescue => e
      # mark failed (best-effort)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          updated_at: Time.current
        )
      rescue StandardError
        # ignore
      end

      begin
        inv&.update!(status: "genai_failed", status_updated_at: Time.current)
      rescue StandardError
        # ignore
      end

      begin
        if ingest_run_id.present?
          Claims::Ingest::ReconcileRun.call(ingest_run_id: ingest_run_id)
        end
      rescue StandardError
        # ignore
      end

      raise
    end

    private

    def find_or_create_step!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      step_type:,
      validationgenai_ruleset_id: nil,
      invoice_upgrade_type_id: nil
    )
      step = nil

      if ingest_run_id.present?
        scope =
          Claims::IngestStepRun.where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type
          ).where(status: %w[queued in_progress])
        scope =
          scope.where(
            validationgenai_ruleset_id: validationgenai_ruleset_id
          ) if validationgenai_ruleset_id.present?
        scope =
          scope.where(
            invoice_upgrade_type_id: invoice_upgrade_type_id
          ) if invoice_upgrade_type_id.present?

        step = scope.order(created_at: :asc).first
      end

      step ||=
        Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
          status: "queued",
          error_text: nil,
          validationgenai_ruleset_id: validationgenai_ruleset_id,
          invoice_upgrade_type_id: invoice_upgrade_type_id,
          created_at: Time.current,
          updated_at: Time.current
        )

      step
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

    def build_classifier_contextwindowjson(di_raw_json:)
      config = Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.classifier_system_record.to_s
      user0 = config&.user_record0.to_s

      if sys.strip.empty?
        raise "validationgenai_config.classifier_system_record is empty"
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

      messages.concat(
        [
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 1 (the case)
            Document Intelligence raw json:
            #{di_raw_json.to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] }
            User record 2 (Actual Ask)
            Locate the visible eligibility code, classify which invoice upgrade types appear to be present, and map clear invoice line items to those upgrade types.
            Reply must be strict JSON using the classifier schema from the system record.
          TEXT
        ]
      )
    end

    def run_genai_ruleset!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      step_type:,
      upgrade_type:,
      ruleset:,
      case_facts:,
      di_raw_json:
    )
      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
          validationgenai_ruleset_id: ruleset.id,
          invoice_upgrade_type_id: upgrade_type.id
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      upsert_genai_manifest!(
        invoice_version_id: invoice_version_id,
        upgrade_type: upgrade_type,
        ruleset: ruleset,
        call_status: "in_progress"
      )

      contextwindowjson =
        build_contextwindowjson(
          ruleset: ruleset,
          case_facts: case_facts,
          di_raw_json: di_raw_json
        )
      payload = call_node_genai!(contextwindowjson: contextwindowjson)

      rulecheck_result =
        ::Claims::InvoiceVersionRulechecks::ApplyGenaiRulechecks.call(
          invoice_version_id: invoice_version_id,
          invoice_upgrade_type_id: upgrade_type.id,
          genai_payload: payload
        )
      unless rulecheck_result[:ok]
        raise "ApplyGenaiRulechecks failed: #{rulecheck_result.inspect}"
      end

      located_field_result =
        ::Claims::InvoiceVersionLocatedFields::ApplyGenaiLocatedFields.call(
          invoice_version_id: invoice_version_id,
          invoice_upgrade_type_id: upgrade_type.id,
          genai_payload: payload
        )
      Rails.logger.info(
        "[CLAIMS][RUN_GENAI_JOB] ApplyGenaiLocatedFields=#{located_field_result.inspect}"
      )
      unless located_field_result[:ok]
        raise "ApplyGenaiLocatedFields failed: #{located_field_result.inspect}"
      end

      upsert_genai_manifest!(
        invoice_version_id: invoice_version_id,
        upgrade_type: upgrade_type,
        ruleset: ruleset,
        call_status: "succeeded",
        payload: payload
      )

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      { upgrade_type: upgrade_type, ruleset: ruleset, payload: payload }
    rescue => e
      begin
        upsert_genai_manifest!(
          invoice_version_id: invoice_version_id,
          upgrade_type: upgrade_type,
          ruleset: ruleset,
          call_status: "failed"
        )
      rescue StandardError
        nil
      end
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def upsert_genai_manifest!(
      invoice_version_id:,
      upgrade_type:,
      ruleset:,
      call_status:,
      payload: nil
    )
      overall =
        (
          if payload.is_a?(Hash)
            (payload["overall"] || payload[:overall] || {})
          else
            {}
          end
        )
      row =
        Claims::InvoiceVersionUpgradeType.find_or_initialize_by(
          invoice_version_id: invoice_version_id,
          invoice_upgrade_type_id: upgrade_type.id,
          source_engine: "genai"
        )
      row.assign_attributes(
        call_status: call_status,
        confidence:
          coerce_confidence(
            overall["overall_confidence"] || overall[:overall_confidence]
          ),
        validationgenai_ruleset_id: ruleset.id,
        raw_json: payload,
        result:
          (
            if payload
              coerce_overall_result(overall)
            else
              row.result
            end
          ),
        updated_at: Time.current
      )
      row.save!
    end

    def detected_upgrade_types(classifier_payload)
      rows =
        classifier_payload["detected_upgrade_types"] ||
          classifier_payload[
            :detected_upgrade_types
          ] if classifier_payload.is_a?(Hash)
      Array(rows)
        .filter_map do |row|
          row["upgrade_type_key"] || row[:upgrade_type_key] if row.is_a?(Hash)
        end
        .map { |key| key.to_s.strip }
        .reject { |key| key.empty? || key == "common" }
        .uniq
        .map { |key| upgrade_type_by_key!(key) }
    end

    def classifier_eligibility_code(classifier_payload)
      return nil unless classifier_payload.is_a?(Hash)

      value =
        classifier_payload["eligibility_code"] ||
          classifier_payload[:eligibility_code]
      value.to_s.strip.presence
    end

    def upgrade_type_by_key!(key)
      Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: key)
    end

    def ruleset_for_upgrade_type!(upgrade_type)
      Claims::ValidationgenaiRuleset
        .where(invoice_upgrade_type_id: upgrade_type.id)
        .order(Arel.sql("updated_at DESC, created_at DESC, id DESC"))
        .first ||
        raise(
          "No validationgenai_ruleset found for upgrade_type_key=#{upgrade_type.upgrade_type_key}"
        )
    end

    def apply_combined_overall!(
      invoice_version:,
      classifier_payload:,
      ruleset_results:
    )
      config = Claims::ValidationgenaiConfig.order(:created_at).first
      payloads =
        ruleset_results.map { |r| r[:payload] }.select { |p| p.is_a?(Hash) }
      overall_rows =
        payloads.map { |payload| payload["overall"] || payload[:overall] || {} }

      confidences =
        overall_rows.map do |overall|
          coerce_confidence(
            overall["overall_confidence"] || overall[:overall_confidence]
          )
        end
      result_values =
        overall_rows.map { |overall| coerce_overall_result(overall) }.compact
      advice =
        combined_admin_advice(config: config, ruleset_results: ruleset_results)

      invoice_version.update!(
        genai_raw_json: {
          classifier: classifier_payload,
          ruleset_results:
            ruleset_results.map do |result|
              {
                upgrade_type_key: result[:upgrade_type].upgrade_type_key,
                validationgenai_ruleset_id: result[:ruleset].id,
                payload: result[:payload]
              }
            end
        },
        genai_overall_confidence: confidences.compact.min || 0,
        genai_result: combined_result(result_values),
        genai_admin_advice: advice
      )

      maybe_upsert_revision_request!(
        invoice_version: invoice_version,
        advice: advice
      )
    end

    def combined_admin_advice(config:, ruleset_results:)
      sections =
        ruleset_results.filter_map do |result|
          advice = advice_from_rulechecks(result[:payload])
          next if advice.blank?

          "#{result[:upgrade_type].description}\n#{advice}"
        end

      return nil if sections.empty?

      [
        config&.admin_advice_intro.to_s.strip.presence,
        sections.join("\n\n"),
        config&.admin_advice_closing.to_s.strip.presence
      ].compact.join("\n\n")
    end

    def advice_from_rulechecks(payload)
      return nil unless payload.is_a?(Hash)

      rows = payload["rulechecks"] || payload[:rulechecks]
      bullets =
        Array(rows).filter_map do |row|
          next unless row.is_a?(Hash)

          result = coerce_rule_result(row["rule_result"] || row[:rule_result])
          next if result.blank? || result == "pass"

          message = advice_message_for_rule(row)
          next if message.blank?

          rule_number = row["rule_number"] || row[:rule_number]
          rule_key = (row["rule_key"] || row[:rule_key]).to_s.strip
          rule_name = (row["rule_name"] || row[:rule_name]).to_s.strip

          label_parts = []
          label_parts << "Rule #{rule_number}" if rule_number.present?
          label_parts << "(#{rule_key})" if rule_key.present?
          label_parts << rule_name if label_parts.empty? && rule_name.present?

          result_label =
            case result
            when "info"
              "Helpful note"
            when "warn"
              "Please verify"
            when "fail"
              "Correction needed"
            end

          "- #{[label_parts.join(" ").presence, result_label].compact.join(": ")}: #{message}"
        end

      bullets.empty? ? nil : bullets.join("\n")
    end

    def advice_message_for_rule(row)
      [
        row["reason_and_likely_causes"] || row[:reason_and_likely_causes],
        row["evidence_text"] || row[:evidence_text]
      ].map { |value| value.to_s.strip }.find(&:present?)
    end

    def maybe_upsert_revision_request!(invoice_version:, advice:)
      requester_id = ENV["CLAIMS_GENAI_REVISION_REQUESTER_ID"].to_s.strip
      return if requester_id.empty? || advice.to_s.strip.empty?

      record =
        Claims::AdminRevisionRequest
          .where(
            invoice_version_id: invoice_version.id,
            requester_id: requester_id,
            status: "OPEN"
          )
          .order(updated_at: :desc)
          .first

      if record
        record.update!(request_text: advice, response_text: nil, closed_at: nil)
      else
        Claims::AdminRevisionRequest.create!(
          invoice_version_id: invoice_version.id,
          requester_id: requester_id,
          status: "OPEN",
          request_text: advice,
          response_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )
      end
    rescue => e
      Rails.logger.warn(
        "[CLAIMS][RUN_GENAI_JOB] Revision request sync skipped: #{e.class}: #{e.message}"
      )
    end

    def coerce_confidence(value)
      n =
        begin
          Integer(value || 0)
        rescue StandardError
          0
        end
      [[n, 0].max, 100].min
    end

    def coerce_overall_result(overall)
      result =
        (
          overall["overall_result"] || overall[:overall_result] ||
            overall["result"] || overall[:result]
        ).to_s.strip.downcase
      return result if %w[pass info warn fail].include?(result)

      nil
    end

    def combined_result(results)
      return nil if results.empty?
      return "fail" if results.include?("fail")
      return "warn" if results.include?("warn")
      return "info" if results.include?("info")

      "pass"
    end

    def coerce_rule_result(value)
      result = value.to_s.strip.downcase
      return result if %w[pass info warn fail].include?(result)

      nil
    end

    # ============================================================
    # SECTION B - CONTEXT WINDOW JSON BUILDER
    # PURPOSE:
    # - Ensure model sees:
    #   1) system_record (schema + constraints)
    #   2) user_record0 (shared DI/OCR reading guidance)
    #   3) user_record1 (ruleset-specific tasks)
    #   4) user_record2 (case facts + DI raw json)
    #   5) user_record3 (actual ask)
    # ============================================================
    def build_contextwindowjson(ruleset:, case_facts:, di_raw_json:)
      config = Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.system_record.to_s
      user0 = config&.user_record0.to_s
      gt = ruleset.user_record1.to_s

      raise "validationgenai_config.system_record is empty" if sys.strip.empty?

      if gt.strip.empty?
        raise "validationgenai_rulesets.user_record1 is empty for ruleset_id=#{ruleset.id}"
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

      messages.concat(
        [
          { role: "user", content: [{ type: "input_text", text: gt }] },
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 2 (the case)
Esp database values:
#{case_facts.to_json}

Document intelligence raw json:
#{di_raw_json.to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] }
            User record 3 (Actual Ask)
            Please perform the location tasks and rulecheck tasks.
            Reply must be using the strict JSON output schema defined in the system record.
          TEXT
        ]
      )
    end
  end
end
