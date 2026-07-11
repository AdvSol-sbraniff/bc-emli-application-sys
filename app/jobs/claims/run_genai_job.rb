# app/jobs/claims/run_genai_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunGenaiJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 3

    # args must match controller perform_async call order.
    # GenAI validation reads classifier facts from evidence tables. Classifier
    # execution belongs in RunIngestTriageJob; ingest_documents is staging only.
    def perform(
      session_id,
      invoice_version_id,
      ingest_run_id,
      mode = "use_existing_classifier"
    )
      if ingest_run_id.blank?
        raise "Missing ingest_run_id for GenAI validation."
      end

      Rails.logger.info(
        "[CLAIMS][RUN_GENAI_JOB] START session_id=#{session_id} invoice_version_id=#{invoice_version_id} mode=#{mode}"
      )

      requested_mode = mode.to_s.presence || "use_existing_classifier"
      if %w[classifier_only triage_only].include?(requested_mode)
        raise "RunGenaiJob no longer runs classifier modes. Use RunIngestTriageJob through OCR/triage instead."
      end
      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)

      if requested_mode == "finish_validation"
        finish_validation_if_ready!(
          session_id: session_id,
          invoice_version_id: iv.id,
          ingest_run_id: ingest_run_id
        )
        return
      end

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

      classifier_payload = classifier_payload_from_evidence(invoice_version: iv)

      inv.set_workflow_status!("genai_in_progress")

      run_case_facts_step!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version: iv,
        invoice: inv,
        claim_session: sess,
        classifier_payload: classifier_payload
      )
      upgrade_types = detected_upgrade_types(classifier_payload)

      common_upgrade_type = upgrade_type_by_key!("common")

      enqueue_genai_ruleset_job!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version: iv,
        step_type: "genai_common",
        upgrade_type: common_upgrade_type
      )

      upgrade_types.each do |upgrade_type|
        enqueue_genai_ruleset_job!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version: iv,
          step_type: "genai_upgrade",
          upgrade_type: upgrade_type
        )
      end
    rescue => e
      failed_step =
        latest_failed_validation_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: iv&.id
        )
      status_subtype =
        failure_subtype_from_step(
          failed_step,
          fallback:
            (
              if requested_mode == "finish_validation"
                runtime_failure_subtype(e)
              else
                genai_failure_subtype(e)
              end
            )
        )
      # mark failed (best-effort)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json:
            failure_payload(status_subtype: status_subtype, error: e),
          updated_at: Time.current
        )
      rescue StandardError
        # ignore
      end

      begin
        inv&.set_workflow_status!(
          "technical_failure",
          status_subtype: status_subtype
        )
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

    def run_genai_ruleset_child!(
      session_id:,
      invoice_version_id:,
      ingest_run_id:,
      invoice_upgrade_type_id:,
      step_type:
    )
      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)
      upgrade_type = Claims::InvoiceUpgradeType.find(invoice_upgrade_type_id)
      classifier_payload = classifier_payload_from_evidence(invoice_version: iv)
      case_facts = case_facts_from_step!(iv.id, ingest_run_id)

      run_genai_ruleset!(
        ingest_run_id: ingest_run_id,
        session_id: session_id,
        invoice_version_id: iv.id,
        invoice: inv,
        step_type: step_type,
        upgrade_type: upgrade_type,
        compiled_user_record1:
          compiled_user_record1_for_upgrade_type!(upgrade_type),
        case_facts: case_facts,
        classifier_payload: classifier_payload,
        di_raw_json: iv.di_raw_json
      )

      Claims::RunGenaiJob.perform_async(
        session_id,
        invoice_version_id,
        ingest_run_id,
        "finish_validation"
      )
    rescue => e
      failed_step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type.to_s,
          invoice_upgrade_type_id: invoice_upgrade_type_id
        )
      status_subtype =
        failure_subtype_from_step(
          failed_step,
          fallback: genai_failure_subtype(e)
        )
      begin
        inv&.set_workflow_status!(
          "technical_failure",
          status_subtype: status_subtype
        )
      rescue StandardError
        nil
      end
      begin
        advance_run!(ingest_run_id: ingest_run_id) if ingest_run_id.present?
      rescue StandardError
        nil
      end
      raise
    end

    def finish_validation_if_ready!(
      session_id:,
      invoice_version_id:,
      ingest_run_id:
    )
      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)

      iv.with_lock do
        if latest_step(
             ingest_run_id: ingest_run_id,
             invoice_version_id: iv.id,
             step_type: "aggregate_advice"
           )&.status == "succeeded" && inv.reload.status == "genai_complete"
          return
        end

        classifier_payload =
          classifier_payload_from_evidence(invoice_version: iv)
        common_upgrade_type = upgrade_type_by_key!("common")
        upgrade_types = detected_upgrade_types(classifier_payload)
        required_genai_steps =
          [[common_upgrade_type, "genai_common"]] +
            upgrade_types.map { |upgrade_type| [upgrade_type, "genai_upgrade"] }
        step_rows =
          required_genai_steps.map do |upgrade_type, step_type|
            latest_step(
              ingest_run_id: ingest_run_id,
              invoice_version_id: iv.id,
              step_type: step_type,
              invoice_upgrade_type_id: upgrade_type.id
            )
          end

        if failed_step = step_rows.compact.find { |row| row.status == "failed" }
          status_subtype =
            failure_subtype_from_step(
              failed_step,
              fallback: "genai_unexpected_exception"
            )
          inv.set_workflow_status!(
            "technical_failure",
            status_subtype: status_subtype
          )
          raise(
            "GenAI validation step failed: " \
              "#{failed_step.step_type} #{failed_step.invoice_upgrade_type_id}"
          )
        end

        return if step_rows.size != required_genai_steps.size
        return unless step_rows.all? { |row| row&.status == "succeeded" }

        if code_rules_enabled_for_upgrade_type?(common_upgrade_type)
          run_code_ruleset_once!(
            ingest_run_id: ingest_run_id,
            session_id: session_id,
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

          run_code_ruleset_once!(
            ingest_run_id: ingest_run_id,
            session_id: session_id,
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

        run_aggregate_advice_once!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version: iv
        ) do
          apply_combined_overall!(
            invoice_version: iv,
            classifier_payload: classifier_payload,
            ruleset_results:
              ruleset_results_from_steps!(
                invoice_version_id: iv.id,
                ingest_run_id: ingest_run_id,
                upgrade_types: [common_upgrade_type] + upgrade_types
              )
          )
        end

        inv.set_workflow_status!("genai_complete")
      end

      advance_run!(ingest_run_id: ingest_run_id) if ingest_run_id.present?
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
      Claims::GenaiCaseFacts::Build.persist_identity_references!(
        invoice_version_id: invoice_version.id,
        identity_references: shared_context.fetch(:identity_references)
      )

      payload = {
        case_facts: case_facts,
        classifier_eligibility_code:
          shared_context[:classifier_eligibility_code],
        identity_references: shared_context[:identity_references]
      }

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        error_text: nil,
        updated_at: Time.current
      )

      payload
    rescue => e
      status_subtype = runtime_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json:
            failure_payload(status_subtype: status_subtype, error: e),
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
          contractor_advice_present:
            Claims::InvoiceVersions::BuildContractorAdvice
              .call(invoice_version_id: invoice_version.id)
              .to_s
              .strip
              .present?
        },
        error_text: nil,
        updated_at: Time.current
      )
    rescue => e
      status_subtype = runtime_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json:
            failure_payload(status_subtype: status_subtype, error: e),
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def advance_run!(ingest_run_id:)
      Claims::Ingest::AdvanceRun.call(ingest_run_id: ingest_run_id)
    end

    def genai_failure_subtype(error)
      ::Claims::Invoices::FailureSubtypes.genai(error)
    end

    def runtime_failure_subtype(error)
      ::Claims::Invoices::FailureSubtypes.runtime(error)
    end

    def failure_payload(status_subtype:, error:)
      ::Claims::Invoices::FailureSubtypes.payload(
        status: "technical_failure",
        status_subtype: status_subtype,
        error: error
      )
    end

    def failure_subtype_from_step(step, fallback:)
      ::Claims::Invoices::FailureSubtypes.from_step(step, fallback: fallback)
    end

    def enqueue_genai_ruleset_job!(
      ingest_run_id:,
      session_id:,
      invoice_version:,
      step_type:,
      upgrade_type:
    )
      existing_step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version.id,
          step_type: step_type,
          invoice_upgrade_type_id: upgrade_type.id
        )
      return if existing_step&.status.in?(%w[queued in_progress succeeded])

      find_or_create_step!(
        ingest_run_id: ingest_run_id,
        session_id: session_id,
        invoice_version_id: invoice_version.id,
        step_type: step_type,
        invoice_upgrade_type_id: upgrade_type.id
      )

      Claims::RunGenaiRulesetJob.perform_async(
        session_id,
        invoice_version.id,
        ingest_run_id,
        upgrade_type.id,
        step_type
      )
    end

    def latest_step(
      ingest_run_id:,
      invoice_version_id:,
      step_type:,
      invoice_upgrade_type_id: nil
    )
      scope =
        Claims::IngestStepRun.where(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type
        )
      scope =
        scope.where(
          invoice_upgrade_type_id: invoice_upgrade_type_id
        ) if invoice_upgrade_type_id.present?
      scope.order(created_at: :desc).first
    end

    def latest_failed_validation_step(ingest_run_id:, invoice_version_id:)
      return nil if ingest_run_id.blank? || invoice_version_id.blank?

      Claims::IngestStepRun
        .where(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: validation_step_types,
          status: "failed"
        )
        .order(created_at: :desc)
        .first
    end

    def validation_step_types
      %w[
        case_facts
        genai_common
        genai_upgrade
        code_common
        code_upgrade
        aggregate_advice
      ]
    end

    def case_facts_from_step!(invoice_version_id, ingest_run_id)
      step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: "case_facts"
        )
      unless step&.status == "succeeded"
        raise "Missing succeeded case_facts step for invoice_version_id=#{invoice_version_id}"
      end
      payload = step&.genai_results_json
      case_facts = payload&.dig("case_facts") || payload&.dig(:case_facts)
      return case_facts if case_facts.is_a?(Hash)

      raise "Missing succeeded case_facts step for invoice_version_id=#{invoice_version_id}"
    end

    def run_code_ruleset_once!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      step_type:,
      upgrade_type:
    )
      existing_step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
          invoice_upgrade_type_id: upgrade_type.id
        )
      if existing_step&.status == "succeeded"
        return existing_step.genai_results_json
      end

      run_code_ruleset!(
        ingest_run_id: ingest_run_id,
        session_id: session_id,
        invoice_version_id: invoice_version_id,
        step_type: step_type,
        upgrade_type: upgrade_type
      ) { yield }
    end

    def run_aggregate_advice_once!(
      ingest_run_id:,
      session_id:,
      invoice_version:
    )
      existing_step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version.id,
          step_type: "aggregate_advice"
        )
      if existing_step&.status == "succeeded"
        return existing_step.genai_results_json
      end

      run_aggregate_advice_step!(
        ingest_run_id: ingest_run_id,
        session_id: session_id,
        invoice_version: invoice_version
      ) { yield }
    end

    def ruleset_results_from_steps!(
      invoice_version_id:,
      ingest_run_id:,
      upgrade_types:
    )
      upgrade_types.map do |upgrade_type|
        step_type =
          (
            if upgrade_type.upgrade_type_key == "common"
              "genai_common"
            else
              "genai_upgrade"
            end
          )
        step =
          latest_step(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type,
            invoice_upgrade_type_id: upgrade_type.id
          )
        payload = step&.genai_results_json
        unless step&.status == "succeeded" && payload.is_a?(Hash)
          raise(
            "Missing succeeded #{step_type} step for " \
              "upgrade_type_key=#{upgrade_type.upgrade_type_key}"
          )
        end

        { upgrade_type: upgrade_type, payload: payload }
      end
    end

    def classifier_payload_from_evidence(invoice_version:)
      detected_rows =
        Claims::InvoiceVersionUpgradeType
          .where(
            invoice_version_id: invoice_version.id,
            source_engine: "classifier"
          )
          .order(created_at: :asc, id: :asc)
          .to_a
      upgrade_types_by_id =
        Claims::InvoiceUpgradeType.where(
          id: detected_rows.map(&:invoice_upgrade_type_id).compact
        ).index_by(&:id)
      detected_rows =
        detected_rows.reject do |row|
          upgrade_types_by_id[row.invoice_upgrade_type_id]&.upgrade_type_key ==
            "common"
        end
      detected_rows =
        detected_rows.sort_by do |row|
          upgrade_types_by_id[
            row.invoice_upgrade_type_id
          ]&.upgrade_type_key.to_s
        end

      if detected_rows.empty?
        raise "Missing classifier evidence rows for invoice_version_id=#{invoice_version.id}"
      end

      fields =
        Claims::InvoiceVersionLocatedField.where(
          invoice_version_id: invoice_version.id,
          source_engine: "classifier"
        ).index_by(&:field_key)

      {
        "document_kind" => "invoice",
        "detected_upgrade_types" =>
          detected_rows.map do |row|
            upgrade_type = upgrade_types_by_id[row.invoice_upgrade_type_id]
            raw = row.raw_json.is_a?(Hash) ? row.raw_json : {}
            raw.merge(
              "upgrade_type_key" => upgrade_type&.upgrade_type_key,
              "upgrade_type_description" => upgrade_type&.description,
              "confidence" => row.confidence
            ).compact
          end,
        "eligibility_code" => field_value(fields["classifier.eligibility_code"])
      }
    end

    def field_value(field)
      return nil unless field

      if field.value_json.present?
        field.value_json
      else
        field.value_text.to_s.strip.presence
      end
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

    def run_genai_ruleset!(
      ingest_run_id:,
      session_id:,
      invoice_version_id:,
      invoice:,
      step_type:,
      upgrade_type:,
      compiled_user_record1:,
      case_facts:,
      classifier_payload:,
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
          invoice_version_id: invoice_version_id,
          invoice: invoice,
          upgrade_type: upgrade_type,
          classifier_payload: classifier_payload,
          di_raw_json: di_raw_json
        )
      payload =
        call_node_genai!(
          contextwindowjson: contextwindowjson,
          diagnostic_context:
            genai_diagnostic_context(
              step_type: step_type,
              ingest_run_id: ingest_run_id,
              invoice_version_id: invoice_version_id,
              invoice_upgrade_type_id: upgrade_type.id
            )
        )

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
      status_subtype = genai_failure_subtype(e)
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
          genai_results_json:
            failure_payload(status_subtype: status_subtype, error: e),
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def genai_diagnostic_context(
      step_type:,
      ingest_run_id:,
      invoice_version_id:,
      invoice_upgrade_type_id:
    )
      {
        step_type: step_type,
        ingest_run_id: ingest_run_id,
        invoice_version_id: invoice_version_id,
        invoice_upgrade_type_id: invoice_upgrade_type_id
      }.compact
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
      status_subtype = runtime_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json:
            failure_payload(status_subtype: status_subtype, error: e),
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
      if value.is_a?(Hash)
        value = value["value"] || value[:value] || value["text"] || value[:text]
      end
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
        genai_result: combined_result(result_values + code_result_values)
      )
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
              "CASE WHEN iut.upgrade_type_key = 'common' THEN 0 ELSE 1 END, iut.upgrade_type_key, claims.invoice_version_rulechecks.rule_key"
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

          rule_key = (row["rule_key"] || row[:rule_key]).to_s.strip

          label_parts = []
          label_parts << rule_key if rule_key.present?

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

          rule_key = row.rule_key.to_s.strip
          label_parts = []
          label_parts << rule_key if rule_key.present?

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
    #   4) user_record2/3 (supporting-document context built just in time)
    #   5) user_record4 (pre-existing DB facts from the case_facts step)
    #   6) user_record5 (classifier keys)
    #   7) user_record6/7 (raw DI invoice JSON and actual ask)
    # ============================================================
    def build_contextwindowjson(
      compiled_user_record1:,
      case_facts:,
      invoice_version_id:,
      invoice:,
      upgrade_type:,
      classifier_payload:,
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

      supporting_document_context =
        Claims::GenaiCaseFacts::Build.supporting_document_context_for_upgrade_type(
          invoice_version: Claims::InvoiceVersion.find(invoice_version_id),
          invoice_upgrade_type: upgrade_type
        )

      if user0.strip.present?
        messages << {
          role: "user",
          content: [{ type: "input_text", text: user0 }]
        }
      end

      messages.concat(
        [
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
                  User record 1 (fields to locate and rules to evaluate)
                  #{gt}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 2 (supporting documents possible)
#{supporting_documents_possible_record(supporting_document_context).to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 3 (supporting documents actually attached)
#{supporting_documents_attached_record(supporting_document_context).to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 4 (pre-existing database values)
#{pre_existing_database_values_record(case_facts).to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 5 (classifier-located key fields)
#{classifier_located_key_fields_record(classifier_payload).to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
            User record 6 (raw DI invoice JSON)
#{di_raw_json.to_json}
          TEXT
          { role: "user", content: [{ type: "input_text", text: <<~TEXT }] }
            User record 7 (one-line actual ask)
            Please perform the location tasks and rulecheck tasks.
            Reply must be using the strict JSON output schema defined in the system record.
          TEXT
        ]
      )
    end

    def supporting_documents_possible_record(summary)
      summary ||= {}
      {
        record_name: "supporting_documents_possible",
        upgrade_type_key:
          summary[:upgrade_type_key] || summary["upgrade_type_key"],
        upgrade_type_description:
          summary[:upgrade_type_description] ||
            summary["upgrade_type_description"],
        configured_type_keys:
          summary[:configured_type_keys] || summary["configured_type_keys"] ||
            [],
        configured_types:
          summary[:configured_types] || summary["configured_types"] || [],
        not_present_applicable_type_keys:
          summary[:not_present_applicable_type_keys] ||
            summary["not_present_applicable_type_keys"] ||
            summary[:missing_configured_type_keys] ||
            summary["missing_configured_type_keys"] || []
      }
    end

    def supporting_documents_attached_record(summary)
      summary ||= {}
      {
        record_name: "supporting_documents_attached",
        upgrade_type_key:
          summary[:upgrade_type_key] || summary["upgrade_type_key"],
        present_configured_type_keys:
          summary[:present_configured_type_keys] ||
            summary["present_configured_type_keys"] || [],
        present_configured_type_counts:
          summary[:present_configured_type_counts] ||
            summary["present_configured_type_counts"] || {},
        documents:
          summary[:configured_documents] || summary["configured_documents"] ||
            []
      }
    end

    def pre_existing_database_values_record(case_facts)
      {
        record_name: "pre_existing_database_values",
        values:
          case_facts[:esp_database_values] ||
            case_facts["esp_database_values"] || {}
      }
    end

    def classifier_located_key_fields_record(classifier_payload)
      payload = classifier_payload.is_a?(Hash) ? classifier_payload : {}

      {
        record_name: "classifier_located_key_fields",
        document_kind: payload["document_kind"] || payload[:document_kind],
        document_kind_confidence:
          payload["document_kind_confidence"] ||
            payload[:document_kind_confidence],
        eligibility_code:
          payload["eligibility_code"] || payload[:eligibility_code],
        detected_upgrade_types:
          payload["detected_upgrade_types"] ||
            payload[:detected_upgrade_types] || []
      }
    end
  end
end
