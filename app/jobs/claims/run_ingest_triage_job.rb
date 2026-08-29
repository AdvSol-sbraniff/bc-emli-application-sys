# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunIngestTriageJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai,
                    retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

    def perform(ingest_document_id, ingest_run_id)
      raise "Missing ingest_run_id for ingest triage." if ingest_run_id.blank?
      return if terminal_run?(ingest_run_id)

      document = ::Claims::IngestDocument.find(ingest_document_id)
      step =
        ::Claims::Ingest::StepClaim.call(
          ingest_run_id: ingest_run_id,
          session_id: document.session_id,
          ingest_document_id: document.id,
          step_type: "classify_document"
        )
      return unless step

      if document.di_read_raw_json.blank?
        raise "Missing ingest_documents.di_read_raw_json for ingest_document_id=#{document.id}"
      end

      contextwindowjson =
        build_classifier_contextwindowjson(
          document: document,
          step_type: "classify_document"
        )
      attachments = build_attachments(document: document)
      triage_payload =
        call_node_genai!(
          contextwindowjson: contextwindowjson,
          attachments: attachments,
          ingest_run_id: ingest_run_id,
          diagnostic_context:
            genai_diagnostic_context(
              document: document,
              step_type: "classify_document",
              ingest_run_id: ingest_run_id
            )
        )
      result =
        ::Claims::Ingest::ApplyDocumentTriageResult.call(
          ingest_document_id: document.id,
          triage_payload: triage_payload
        )
      unless result[:ok]
        raise "ApplyDocumentTriageResult failed: #{result.inspect}"
      end

      step.update!(
        status: "succeeded",
        genai_results_json: triage_payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )
    rescue StandardError => e
      failure_category = ::Claims::Ingest::FailureClassifier.genai_status(e)
      failure_code = ::Claims::Ingest::FailureClassifier.genai(e)
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        genai_results_json: nil,
        **::Claims::Ingest::FailureClassifier.step_attributes(
          failure_category: failure_category,
          failure_code: failure_code,
          error: e
        ),
        updated_at: Time.current
      )
      if ::Claims::Ingest::RetryPolicy.retryable?(e)
        scheduled =
          ::Claims::TestHarness::Scheduling.retry_job(
            self.class,
            ingest_run_id,
            ingest_document_id,
            ingest_run_id,
            attempt_count:
              ::Claims::Ingest::StepOutcome.for_step(step).attempt_count
          )
        raise unless scheduled
      end
    ensure
      advance_run!(ingest_run_id: ingest_run_id)
    end

    private

    def terminal_run?(ingest_run_id)
      ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
        ::Claims::IngestRun.find(ingest_run_id).status
      )
    end

    def build_classifier_contextwindowjson(document:, step_type:)
      config = ::Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.document_triage_system_record.to_s
      user0 = config&.user_record0.to_s

      if sys.strip.empty?
        raise "validationgenai_config.document_triage_system_record is empty"
      end

      sys = "#{sys.rstrip}\n\n#{personal_information_classifier_config}"

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
          User record: Document to classify
          classifier_step_type: #{step_type}
          File metadata:
          original_filename: #{document.original_filename}
          content_type: #{document.content_type}
          byte_size: #{document.byte_size}

          Document Intelligence raw json:
          #{document.di_read_raw_json.to_json}

          Actual ask:
          #{classifier_actual_ask}
          Reply must be strict JSON using the classifier schema from the system record.
        TEXT
      }

      messages
    end

    def build_attachments(document:)
      return [] if document.storage_key.blank?

      [
        {
          type: "input_file",
          storageKey: document.storage_key,
          container: ENV["AZURE_BLOB_CONTAINER"].presence,
          filename: document.original_filename.presence || "image_document"
        }.compact
      ]
    end

    def call_node_genai!(
      contextwindowjson:,
      attachments: [],
      ingest_run_id:,
      diagnostic_context: {}
    )
      ::Claims::Genai::NodeClient.call(
        contextwindowjson: contextwindowjson,
        attachments: attachments,
        diagnostic_context: diagnostic_context,
        deployment_name:
          ::Claims::Genai::DeploymentConfig.for_run(
            ingest_run_id,
            :document_triage_deployment_name
          )
      )
    end

    def genai_diagnostic_context(document:, step_type:, ingest_run_id:)
      {
        step_type: step_type,
        ingest_run_id: ingest_run_id,
        ingest_document_id: document.id,
        original_filename: document.original_filename,
        content_type: document.content_type
      }.compact
    end

    def classifier_actual_ask
      <<~TEXT.squish
        Classify this supplied file using both the attached file and DI-read JSON.
        Do not infer document kind from the file extension. Treat DI-read text as
        the authoritative source for textual evidence and polygons, and use the
        attached file for visual and document context. If it is an invoice, detect
        upgrade types and the eligibility code. If it is a supporting document,
        classify its type and routing quality. Use other_supporting_document when
        the file is clearly supplementary evidence but no more specific allowed
        supporting-document type applies; do not use unknown solely for that reason.
        Do not extract official supporting-document evidence in this call; that
        happens in the downstream supporting-document extraction step. Also assess
        this individual file for unnecessary or high-risk personal information using
        the supplied PI type configuration.
      TEXT
    end

    def personal_information_classifier_config
      types = ::Claims::PersonalInformationType.enabled.classifier_order.to_a
      if types.empty?
        raise "No enabled personal_information_types are configured."
      end

      type_lines =
        types.map do |type|
          "- #{type.type_key} (priority #{type.sort_order}): #{type.description}"
        end

      <<~TEXT
        Enabled personal-information type configuration:
        #{type_lines.join("\n")}

        When more than one inappropriate PI type is visible, return the enabled type
        with the lowest priority number as personal_information_type_key and summarize
        secondary concerns without reproducing sensitive values.
      TEXT
    end

    def advance_run!(ingest_run_id:)
      return if ingest_run_id.blank?

      ::Claims::TestHarness::Scheduling.advance_run(ingest_run_id)
    end
  end
end
