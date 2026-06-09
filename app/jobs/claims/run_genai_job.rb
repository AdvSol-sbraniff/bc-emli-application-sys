# app/jobs/claims/run_genai_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunGenaiJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 0

    # args must match controller perform_async call order.
    # GenAI validation reruns always reuse the classifier payload persisted by
    # the upload triage phase; classifier execution belongs in RunIngestTriageJob.
    def perform(
      session_id,
      invoice_version_id,
      ingest_run_id = nil,
      mode = "use_existing_classifier"
    )
      Rails.logger.info(
        "[CLAIMS][RUN_GENAI_JOB] START session_id=#{session_id} invoice_version_id=#{invoice_version_id} mode=#{mode}"
      )

      requested_mode = mode.to_s.presence
      if %w[classifier_only triage_only].include?(requested_mode)
        raise "RunGenaiJob no longer runs classifier modes. Use RunIngestTriageJob through OCR/triage instead."
      end
      mode = "use_existing_classifier"

      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)
      sess = Claims::Session.find(session_id)

      step = nil

      if iv.di_raw_json.blank?
        raise "Missing invoice_versions.di_raw_json. Run OCR first for invoice_version_id=#{iv.id}."
      end

      # GenAI reruns must not leave stale common/upgrade outputs from a prior run.
      # Preserve classifier-derived upgrade mappings from the OCR/triage phase.
      ::Claims::InvoiceVersions::ResetAiOutputs.call(
        invoice_version_id: iv.id,
        preserve_classifier: true
      )

      classifier_payload =
        existing_classifier_payload_for(invoice_version_id: iv.id)
      if classifier_payload.blank?
        raise "Missing stored triage classifier payload for invoice_version_id=#{iv.id}"
      end
      classifier_result =
        ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
          invoice_version_id: iv.id,
          classifier_payload: classifier_payload
        )
      unless classifier_result[:ok]
        raise "ApplyClassifierResult failed: #{classifier_result.inspect}"
      end

      inv.update!(status: "genai_in_progress", status_updated_at: Time.current)

      case_facts_result =
        run_case_facts_step!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version: iv,
          invoice: inv,
          claim_session: sess,
          classifier_payload: classifier_payload
        )
      case_facts = case_facts_result.fetch(:case_facts)
      upgrade_types = detected_upgrade_types(classifier_payload)

      common_upgrade_type = upgrade_type_by_key!("common")
      common_user_record1 =
        compiled_user_record1_for_upgrade_type!(common_upgrade_type)
      ruleset_results = []

      ruleset_results << run_genai_ruleset!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version_id: iv.id,
        step_type: "genai_common",
        upgrade_type: common_upgrade_type,
        compiled_user_record1: common_user_record1,
        case_facts: case_facts,
        di_raw_json: iv.di_raw_json
      )

      upgrade_types.each do |upgrade_type|
        upgrade_type_case_facts =
          Claims::GenaiCaseFacts::Build.case_facts_for_upgrade_type(
            case_facts: case_facts,
            invoice_upgrade_type: upgrade_type
          )

        ruleset_results << run_genai_ruleset!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version_id: iv.id,
          step_type: "genai_upgrade",
          upgrade_type: upgrade_type,
          compiled_user_record1:
            compiled_user_record1_for_upgrade_type!(upgrade_type),
          case_facts: upgrade_type_case_facts,
          di_raw_json: iv.di_raw_json
        )
      end

      run_product_lookup_enrichment_step!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version: iv,
        invoice_upgrade_types: upgrade_types
      )

      if code_rules_enabled_for_upgrade_type?(common_upgrade_type)
        run_code_ruleset!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version_id: iv.id,
          step_type: "code_common",
          upgrade_type: common_upgrade_type
        ) do
          ::Claims::InvoiceVersionRulechecks::ApplyCodeRulechecks.call(
            invoice_version_id: iv.id
          )
        end
      end

      upgrade_types.each do |upgrade_type|
        next unless code_rules_enabled_for_upgrade_type?(upgrade_type)

        run_code_ruleset!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version_id: iv.id,
          step_type: "code_upgrade",
          upgrade_type: upgrade_type
        ) do
          ::Claims::InvoiceVersionRulechecks::ApplyUpgradeCodeRulechecks.call(
            invoice_version_id: iv.id,
            invoice_upgrade_type_id: upgrade_type.id
          )
        end
      end

      run_aggregate_advice_step!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version: iv
      ) do
        apply_combined_overall!(
          invoice_version: iv,
          classifier_payload: classifier_payload,
          ruleset_results: ruleset_results
        )
      end

      inv.update!(status: "genai_complete", status_updated_at: Time.current)

      advance_run!(ingest_run_id: ingest_run_id) if ingest_run_id.present?
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
        advance_run!(ingest_run_id: ingest_run_id) if ingest_run_id.present?
      rescue StandardError
        # ignore
      end

      raise
    end

    private

    def run_case_facts_step!(
      ingest_run_id:,
      session_id:,
      invoice_version:,
      invoice:,
      claim_session:,
      classifier_payload:
    )
      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version.id,
          step_type: "case_facts"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      classifier_eligibility_code =
        classifier_eligibility_code(classifier_payload)
      shared_context =
        Claims::GenaiCaseFacts::Build.build_shared_context(
          sess: claim_session,
          invoice: invoice,
          eligibility_code: classifier_eligibility_code
        )
      case_facts = shared_context.fetch(:case_facts)

      Claims::GenaiCaseFacts::Build.persist_code_located_fields!(
        invoice_version_id: invoice_version.id,
        case_facts: case_facts,
        classifier_eligibility_code:
          shared_context[:classifier_eligibility_code]
      )

      payload = {
        case_facts: case_facts,
        classifier_eligibility_code:
          shared_context[:classifier_eligibility_code]
      }

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        error_text: nil,
        updated_at: Time.current
      )

      payload
    rescue => e
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

    def run_product_lookup_enrichment_step!(
      ingest_run_id:,
      session_id:,
      invoice_version:,
      invoice_upgrade_types:
    )
      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version.id,
          step_type: "product_lookup_enrichment"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      result =
        ::Claims::ProductLookupEnrichment::Apply.call(
          invoice_version_id: invoice_version.id,
          invoice_upgrade_types: invoice_upgrade_types
        )
      unless result[:ok]
        raise "Product lookup enrichment failed: #{result.inspect}"
      end

      step.update!(
        status: "succeeded",
        genai_results_json: result,
        error_text: nil,
        updated_at: Time.current
      )

      result
    rescue => e
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

    def run_aggregate_advice_step!(
      ingest_run_id:,
      session_id:,
      invoice_version:
    )
      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version.id,
          step_type: "aggregate_advice"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      yield

      invoice_version.reload
      step.update!(
        status: "succeeded",
        genai_results_json: {
          genai_result: invoice_version.genai_result,
          genai_overall_confidence: invoice_version.genai_overall_confidence,
          genai_admin_advice_present:
            invoice_version.genai_admin_advice.to_s.strip.present?
        },
        error_text: nil,
        updated_at: Time.current
      )
    rescue => e
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

    def advance_run!(ingest_run_id:)
      Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
    end

    def existing_classifier_payload_for(invoice_version_id:)
      document =
        Claims::IngestDocument.find_by(
          resolved_invoice_version_id: invoice_version_id,
          document_kind: "invoice"
        )
      payload = document&.classifier_raw_json
      return payload if payload.is_a?(Hash)

      invoice_id =
        Claims::InvoiceVersion.where(id: invoice_version_id).pick(:invoice_id)
      document =
        Claims::IngestDocument
          .where(resolved_invoice_id: invoice_id, document_kind: "invoice")
          .order(created_at: :asc)
          .first
      payload = document&.classifier_raw_json
      return payload if payload.is_a?(Hash)

      step =
        Claims::IngestStepRun
          .where(
            invoice_version_id: invoice_version_id,
            step_type: "triage_classifier",
            status: "succeeded"
          )
          .order(created_at: :desc)
          .first

      payload = step&.genai_results_json
      payload.is_a?(Hash) ? payload : nil
    end

    def find_or_create_step!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      step_type:,
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

    def run_genai_ruleset!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      step_type:,
      upgrade_type:,
      compiled_user_record1:,
      case_facts:,
      di_raw_json:
    )
      contextwindowjson = nil
      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
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
        call_status: "in_progress"
      )

      contextwindowjson =
        build_contextwindowjson(
          compiled_user_record1: compiled_user_record1,
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

      { upgrade_type: upgrade_type, payload: payload }
    rescue => e
      begin
        upsert_genai_manifest!(
          invoice_version_id: invoice_version_id,
          upgrade_type: upgrade_type,
          call_status: "failed"
        )
      rescue StandardError
        nil
      end
      begin
        step&.update!(
          status: "failed",
          context_window_json: contextwindowjson,
          error_text: "#{e.class}: #{e.message}",
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def run_code_ruleset!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      step_type:,
      upgrade_type:
    )
      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
          invoice_upgrade_type_id: upgrade_type.id
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )

      result = yield
      raise "Code rules failed: #{result.inspect}" unless result[:ok]

      step.update!(
        status: "succeeded",
        genai_results_json: result,
        error_text: nil,
        updated_at: Time.current
      )

      result
    rescue => e
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
        raw_json: payload,
        admin_advice:
          payload ? advice_from_rulechecks(payload) : row.admin_advice,
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

    def code_rules_enabled_for_upgrade_type?(upgrade_type)
      ::Claims::CodeRuleUpgradeType
        .joins(:code_rule)
        .where(invoice_upgrade_type_id: upgrade_type.id)
        .where("#{::Claims::CodeRule.table_name}.enabled = ?", true)
        .exists?
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

    def compiled_user_record1_for_upgrade_type!(upgrade_type)
      text =
        Claims::GenaiRulesetCompiler::Compile.call(
          invoice_upgrade_type: upgrade_type
        ).to_s

      return text if text.strip.present?

      raise(
        "Compiled GenAI prompt is empty for upgrade_type_key=#{upgrade_type.upgrade_type_key}"
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
      code_result_values =
        code_result_values_for(invoice_version_id: invoice_version.id)
      code_advice_sections =
        code_advice_sections_for(invoice_version_id: invoice_version.id)
      advice =
        combined_admin_advice(
          config: config,
          invoice_version_id: invoice_version.id,
          extra_sections: code_advice_sections
        )

      invoice_version.update!(
        genai_raw_json: {
          classifier: classifier_payload,
          ruleset_results:
            ruleset_results.map do |result|
              {
                upgrade_type_key: result[:upgrade_type].upgrade_type_key,
                payload: result[:payload]
              }
            end
        },
        genai_overall_confidence: confidences.compact.min || 0,
        genai_result: combined_result(result_values + code_result_values),
        genai_admin_advice: advice
      )

      maybe_upsert_revision_request!(
        invoice_version: invoice_version,
        advice: advice
      )
    end

    def combined_admin_advice(config:, invoice_version_id:, extra_sections: [])
      sections =
        Claims::InvoiceVersionUpgradeType
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
          )
          .where(invoice_version_id: invoice_version_id, source_engine: "genai")
          .select(
            "claims.invoice_version_upgrade_types.*",
            "iut.description AS upgrade_type_description",
            "iut.upgrade_type_key AS upgrade_type_key"
          )
          .order(
            Arel.sql(
              "CASE WHEN iut.upgrade_type_key = 'common' THEN 0 ELSE 1 END, iut.upgrade_type_key"
            )
          )
          .filter_map do |row|
            advice = row.admin_advice.to_s.strip
            next if advice.blank?

            title =
              row.read_attribute("upgrade_type_description").presence ||
                "Upgrade type"
            "#{title}\n#{advice}"
          end

      sections.concat(Array(extra_sections).compact_blank)

      return nil if sections.empty?

      [
        config&.admin_advice_intro.to_s.strip.presence,
        sections.join("\n\n"),
        config&.admin_advice_closing.to_s.strip.presence
      ].compact.join("\n\n")
    end

    def code_advice_sections_for(invoice_version_id:)
      rows =
        Claims::InvoiceVersionRulecheck
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_rulechecks.invoice_upgrade_type_id"
          )
          .where(invoice_version_id: invoice_version_id, source_engine: "code")
          .where(rule_result: %w[warn fail])
          .select(
            "claims.invoice_version_rulechecks.*",
            "iut.description AS upgrade_type_description",
            "iut.upgrade_type_key AS upgrade_type_key"
          )
          .order(
            Arel.sql(
              "CASE WHEN iut.upgrade_type_key = 'common' THEN 0 ELSE 1 END, iut.upgrade_type_key, claims.invoice_version_rulechecks.rule_number"
            )
          )

      rows
        .group_by do |row|
          row.read_attribute("upgrade_type_description").presence ||
            "Code-owned checks"
        end
        .filter_map do |description, grouped_rows|
          advice = advice_from_rulecheck_rows(grouped_rows)
          next if advice.blank?

          "#{description} code checks\n#{advice}"
        end
    end

    def code_result_values_for(invoice_version_id:)
      Claims::InvoiceVersionRulecheck
        .where(invoice_version_id: invoice_version_id, source_engine: "code")
        .pluck(:rule_result)
        .filter_map { |result| coerce_rule_result(result) }
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

          label_parts = []
          label_parts << "Rule #{rule_number}" if rule_number.present?
          label_parts << "(#{rule_key})" if rule_key.present?
          if label_parts.empty? && rule_number.present?
            label_parts << "rule_#{rule_number}"
          end

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

    def advice_from_rulecheck_rows(rows)
      bullets =
        Array(rows).filter_map do |row|
          result = coerce_rule_result(row.rule_result)
          next unless %w[warn fail].include?(result)

          message = advice_message_for_rule(row)
          next if message.blank?

          rule_number = row.rule_number
          rule_key = row.rule_key.to_s.strip
          label_parts = []
          label_parts << "Code Rule #{rule_number}" if rule_number.present?
          label_parts << "(#{rule_key})" if rule_key.present?

          result_label =
            case result
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
      if row.respond_to?(:reason_and_likely_causes)
        [row.reason_and_likely_causes, row.evidence_text].map do |value|
            value.to_s.strip
          end
          .find(&:present?)
      else
        [
          row["reason_and_likely_causes"] || row[:reason_and_likely_causes],
          row["evidence_text"] || row[:evidence_text]
        ].map { |value| value.to_s.strip }.find(&:present?)
      end
    end

    def maybe_upsert_revision_request!(invoice_version:, advice:)
      requester_id = ENV["CLAIMS_GENAI_REVISION_REQUESTER_ID"].to_s.strip
      return if requester_id.empty? || advice.to_s.strip.empty?

      record =
        Claims::AdminRevisionRequest
          .where(
            invoice_version_id: invoice_version.id,
            requester_id: requester_id,
            message_type: "admin_revision_request"
          )
          .order(updated_at: :desc)
          .first

      if record
        record.update!(request_text: advice)
      else
        Claims::AdminRevisionRequest.create!(
          invoice_version_id: invoice_version.id,
          requester_id: requester_id,
          message_type: "admin_revision_request",
          request_text: advice,
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
          raw = value || 0
          numeric = Float(raw)
          numeric = numeric * 100 if numeric.positive? && numeric <= 1
          numeric.round
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
    #   3) user_record1 (compiled normalized located-field + rule tasks)
    #   4) user_record2 (case facts only)
    #   5) user_record3 (raw DI invoice JSON only)
    #   6) user_record4 (actual ask)
    # ============================================================
    def build_contextwindowjson(
      compiled_user_record1:,
      case_facts:,
      di_raw_json:
    )
      config = Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.system_record.to_s
      user0 = config&.user_record0.to_s
      gt = compiled_user_record1.to_s

      raise "validationgenai_config.system_record is empty" if sys.strip.empty?

      raise "compiled GenAI user_record1 is empty" if gt.strip.empty?

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
            User record 2 (case facts)
ESP database values:
#{case_facts.to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 3 (raw DI invoice JSON)
#{di_raw_json.to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] }
            User record 4 (Actual Ask)
            Please perform the location tasks and rulecheck tasks.
            Reply must be using the strict JSON output schema defined in the system record.
          TEXT
        ]
      )
    end
  end
end
