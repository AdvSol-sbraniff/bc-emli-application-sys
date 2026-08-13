# app/jobs/claims/run_genai_job.rb
# frozen_string_literal: true

require "net/http"
require "json"

module Claims
  class RunGenaiJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai,
                    retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

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
      if requested_mode == "finish_validation"
        raise "RunGenaiJob no longer performs fan-in. Use FinalizeGenaiValidationJob."
      end

      ingest_run = Claims::IngestRun.find(ingest_run_id)
      if ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
           ingest_run.status
         )
        return
      end

      iv = Claims::InvoiceVersion.find(invoice_version_id)
      inv = Claims::Invoice.find(iv.invoice_id)

      sess = Claims::Session.find(session_id)

      if iv.di_raw_json.blank?
        raise "Missing invoice_versions.di_raw_json. Run OCR first for invoice_version_id=#{iv.id}."
      end

      classifier_payload = classifier_payload_from_evidence(invoice_version: iv)

      case_facts_payload =
        run_case_facts_step!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version: iv,
          invoice: inv,
          claim_session: sess,
          classifier_payload: classifier_payload
        )
      return if case_facts_payload.nil?

      upgrade_types = detected_upgrade_types(classifier_payload)

      common_upgrade_type = upgrade_type_by_key!("common")

      enqueue_genai_ruleset_job!(
        ingest_run_id: ingest_run_id,
        session_id: sess.id,
        invoice_version: iv,
        step_type: "evaluate_genai_ruleset",
        upgrade_type: common_upgrade_type
      )

      upgrade_types.each do |upgrade_type|
        enqueue_genai_ruleset_job!(
          ingest_run_id: ingest_run_id,
          session_id: sess.id,
          invoice_version: iv,
          step_type: "evaluate_genai_ruleset",
          upgrade_type: upgrade_type
        )
      end
    rescue StandardError => e
      failed_step =
        ::Claims::Ingest::StepOutcome.for_target(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: "case_facts"
        ).effective_step
      failure_code =
        failure_subtype_from_step(
          failed_step,
          fallback: genai_failure_subtype(e)
        )
      begin
        if failed_step&.status.in?(%w[queued in_progress])
          failed_step.update!(
            status: "failed",
            error_text: "#{e.class}: #{e.message}",
            genai_results_json: nil,
            **failure_step_attributes(failure_code: failure_code, error: e),
            updated_at: Time.current
          )
        end
      rescue StandardError
        nil
      end

      raise if ::Claims::Ingest::RetryPolicy.retryable?(e)
    ensure
      if ingest_run_id.present?
        ::Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
      end
    end

    def run_genai_ruleset_child!(
      session_id:,
      invoice_version_id:,
      ingest_run_id:,
      invoice_upgrade_type_id:,
      step_type:
    )
      ingest_run = Claims::IngestRun.find(ingest_run_id)
      if ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
           ingest_run.status
         )
        return
      end

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
    rescue StandardError => e
      failed_step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type.to_s,
          invoice_upgrade_type_id: invoice_upgrade_type_id
        )
      failure_code =
        failure_subtype_from_step(
          failed_step,
          fallback: genai_failure_subtype(e)
        )
      begin
        if failed_step&.status.in?(%w[queued in_progress])
          failed_step.update!(
            status: "failed",
            error_text: "#{e.class}: #{e.message}",
            genai_results_json: nil,
            **failure_step_attributes(failure_code: failure_code, error: e),
            updated_at: Time.current
          )
        end
      rescue StandardError
        nil
      end
      raise if ::Claims::Ingest::RetryPolicy.retryable?(e)
    ensure
      if ingest_run_id.present?
        ::Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
      end
    end

    def finalize_validation!(session_id:, invoice_version_id:, ingest_run_id:)
      iv = Claims::InvoiceVersion.find(invoice_version_id)

      iv.with_lock do
        aggregate_outcome =
          ::Claims::Ingest::StepOutcome.for_target(
            ingest_run_id: ingest_run_id,
            invoice_version_id: iv.id,
            step_type: "finalize_validation"
          )
        return if aggregate_outcome.succeeded?

        classifier_payload =
          classifier_payload_from_evidence(invoice_version: iv)
        common_upgrade_type = upgrade_type_by_key!("common")
        upgrade_types = detected_upgrade_types(classifier_payload)
        required_genai_steps =
          [[common_upgrade_type, "evaluate_genai_ruleset"]] +
            upgrade_types.map do |upgrade_type|
              [upgrade_type, "evaluate_genai_ruleset"]
            end
        step_outcomes =
          required_genai_steps.map do |upgrade_type, step_type|
            ::Claims::Ingest::StepOutcome.for_target(
              ingest_run_id: ingest_run_id,
              invoice_version_id: iv.id,
              step_type: step_type,
              invoice_upgrade_type_id: upgrade_type.id
            )
          end
        return unless step_outcomes.all?(&:succeeded?)

        if code_rules_enabled_for_upgrade_type?(common_upgrade_type)
          run_code_ruleset_once!(
            ingest_run_id: ingest_run_id,
            session_id: session_id,
            invoice_version_id: iv.id,
            step_type: "evaluate_code_ruleset",
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
            step_type: "evaluate_code_ruleset",
            upgrade_type: upgrade_type
          ) do
            ::Claims::InvoiceVersionRulechecks::ApplyUpgradeCodeRulechecks.call(
              invoice_version_id: iv.id,
              invoice_upgrade_type_id: upgrade_type.id
            )
          end
        end

        run_finalize_validation_once!(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version: iv
        )
      end
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
      outcome =
        ::Claims::Ingest::StepOutcome.for_target(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version.id,
          step_type: "case_facts"
        )
      return outcome.effective_step.genai_results_json if outcome.succeeded?

      step =
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version.id,
          step_type: "case_facts"
        )
      return nil unless step

      # Clear prior common/upgrade outputs once, when this run actually claims
      # its case-facts root. Classifier evidence is the input to this run.
      ::Claims::InvoiceVersions::ResetAiOutputs.call(
        invoice_version_id: invoice_version.id
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
    rescue StandardError => e
      failure_code = runtime_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json: nil,
          **failure_step_attributes(failure_code: failure_code, error: e),
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def run_finalize_validation_step!(
      ingest_run_id:,
      session_id:,
      invoice_version:
    )
      step =
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version.id,
          step_type: "finalize_validation"
        )
      return nil unless step

      step.update!(
        status: "succeeded",
        genai_results_json: nil,
        error_text: nil,
        updated_at: Time.current
      )
    rescue StandardError => e
      failure_code = runtime_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json: nil,
          **failure_step_attributes(failure_code: failure_code, error: e),
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def genai_failure_subtype(error)
      ::Claims::Ingest::FailureClassifier.genai(error)
    end

    def runtime_failure_subtype(error)
      ::Claims::Ingest::FailureClassifier.runtime(error)
    end

    def failure_step_attributes(failure_code:, error:)
      ::Claims::Ingest::FailureClassifier.step_attributes(
        failure_category: "technical_failure",
        failure_code: failure_code,
        error: error
      )
    end

    def failure_subtype_from_step(step, fallback:)
      ::Claims::Ingest::FailureClassifier.from_step(step, fallback: fallback)
    end

    def enqueue_genai_ruleset_job!(
      ingest_run_id:,
      session_id:,
      invoice_version:,
      step_type:,
      upgrade_type:
    )
      existing_step =
        ::Claims::Ingest::StepOutcome.for_target(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version.id,
          step_type: step_type,
          invoice_upgrade_type_id: upgrade_type.id
        )
      return unless existing_step.missing?

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
        upgrade_type.id
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
      if invoice_upgrade_type_id.present?
        scope = scope.where(invoice_upgrade_type_id: invoice_upgrade_type_id)
      end
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
        evaluate_genai_ruleset
        evaluate_code_ruleset
        finalize_validation
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

    def run_finalize_validation_once!(
      ingest_run_id:,
      session_id:,
      invoice_version:
    )
      existing_step =
        latest_step(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version.id,
          step_type: "finalize_validation"
        )
      if existing_step&.status == "succeeded"
        return existing_step.genai_results_json
      end

      run_finalize_validation_step!(
        ingest_run_id: ingest_run_id,
        session_id: session_id,
        invoice_version: invoice_version
      )
    end

    def classifier_payload_from_evidence(invoice_version:)
      detected_rows =
        Claims::InvoiceVersionUpgradeType
          .where(invoice_version_id: invoice_version.id)
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
        if invoice_upgrade_type_id.present?
          scope = scope.where(invoice_upgrade_type_id: invoice_upgrade_type_id)
        end

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
      ::Claims::Genai::NodeClient.call(
        contextwindowjson: contextwindowjson,
        diagnostic_context: diagnostic_context
      )
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
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
          invoice_upgrade_type_id: upgrade_type.id
        )
      return nil unless step

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

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      { upgrade_type: upgrade_type, payload: payload }
    rescue StandardError => e
      failure_code = genai_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          context_window_json: contextwindowjson,
          error_text: "#{e.class}: #{e.message}",
          genai_results_json: nil,
          **failure_step_attributes(failure_code: failure_code, error: e),
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
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type,
          invoice_upgrade_type_id: upgrade_type.id
        )
      return nil unless step

      result = yield
      raise "Code rules failed: #{result.inspect}" unless result[:ok]

      step.update!(
        status: "succeeded",
        genai_results_json: result,
        error_text: nil,
        updated_at: Time.current
      )

      result
    rescue StandardError => e
      failure_code = runtime_failure_subtype(e)
      begin
        step&.update!(
          status: "failed",
          error_text: "#{e.class}: #{e.message}",
          genai_results_json: nil,
          **failure_step_attributes(failure_code: failure_code, error: e),
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end
      raise
    end

    def detected_upgrade_types(classifier_payload)
      if classifier_payload.is_a?(Hash)
        rows =
          classifier_payload["detected_upgrade_types"] ||
            classifier_payload[:detected_upgrade_types]
      end
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

      messages.push(
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
            [],
        other_documents:
          summary[:other_documents] || summary["other_documents"] || []
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
