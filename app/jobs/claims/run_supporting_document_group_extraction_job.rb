# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  class RunSupportingDocumentGroupExtractionJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 0

    def perform(supporting_document_group_id, ingest_run_id = nil)
      group =
        ::Claims::SupportingDocumentGroup.find(supporting_document_group_id)
      if group.supporting_document_type_id.blank?
        raise "Missing supporting_document_type_id for supporting_document_group_id=#{group.id}"
      end

      step =
        find_or_create_step!(
          ingest_run_id: ingest_run_id,
          group: group,
          step_type: "supporting_document_group_extraction"
        )
      step.update!(
        status: "in_progress",
        error_text: nil,
        updated_at: Time.current
      )
      group.update!(group_status: "pending", updated_at: Time.current)

      contextwindowjson = build_contextwindowjson(group: group)
      attachments = build_attachments(group: group)
      payload =
        call_node_genai!(
          contextwindowjson: contextwindowjson,
          attachments: attachments
        )

      located_result =
        ::Claims::SupportingDocumentGroups::ApplyLocatedFields.call(
          supporting_document_group_id: group.id,
          located_fields_payload: payload
        )
      unless located_result[:ok]
        raise "ApplySupportingDocumentGroupLocatedFields failed: #{located_result.inspect}"
      end
      child_payload_count =
        Array(payload["supporting_document_located_fields_by_document"]).size
      child_evidence_count =
        located_result[:child_located_fields_replaced].to_i +
          located_result[:child_visual_findings_replaced].to_i
      if child_payload_count.positive? && child_evidence_count.zero?
        raise "ApplySupportingDocumentGroupLocatedFields wrote no child evidence rows despite #{child_payload_count} child payloads: #{located_result.inspect}"
      end

      step.update!(
        status: "succeeded",
        genai_results_json: payload,
        context_window_json: contextwindowjson,
        error_text: nil,
        updated_at: Time.current
      )

      advance_run!(ingest_run_id: ingest_run_id)
    rescue => e
      step&.update!(
        status: "failed",
        error_text: "#{e.class}: #{e.message}",
        updated_at: Time.current
      )
      group&.update!(group_status: "failed", updated_at: Time.current)
      advance_run!(ingest_run_id: ingest_run_id)
      raise
    end

    private

    def find_or_create_step!(ingest_run_id:, group:, step_type:)
      step = nil

      if ingest_run_id.present?
        step =
          ::Claims::IngestStepRun
            .where(
              ingest_run_id: ingest_run_id,
              supporting_document_group_id: group.id,
              step_type: step_type
            )
            .where(status: %w[queued in_progress])
            .order(created_at: :asc)
            .first
      end

      step ||=
        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run_id,
          session_id: group.invoice.session_id,
          supporting_document_group_id: group.id,
          step_type: step_type,
          status: "queued",
          error_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )
    end

    def build_contextwindowjson(group:)
      config = ::Claims::ValidationgenaiConfig.order(:created_at).first
      sys = config&.supporting_document_group_extraction_system_record.to_s
      if sys.strip.empty?
        raise "validationgenai_config.supporting_document_group_extraction_system_record is empty"
      end

      type = group.supporting_document_type
      group_field_tasks =
        ::Claims::SupportingDocumentGroups::LocatedFieldPrompt.call(
          supporting_document_type: type
        )
      child_field_tasks =
        ::Claims::SupportingDocuments::LocatedFieldPrompt.call(
          supporting_document_type: type
        )
      if group_field_tasks.blank?
        raise "No supporting-document group located-field tasks configured for #{type&.type_key || group.supporting_document_type_id}"
      end

      [
        { role: "system", content: [{ type: "input_text", text: sys }] },
        { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
                User record: Selected supporting document group
                supporting_document_group_id: #{group.id}
                supporting_document_type_key: #{type.type_key}
                supporting_document_type_description: #{type.description}
                group_label: #{group.group_label}

                #{group_field_tasks}
              TEXT
        { role: "user", content: [{ type: "input_text", text: <<~TEXT }] },
                User record: Child supporting-document file located-field tasks
                These tasks are applied separately to each child supporting document in this group.
                Return the child-file results under supporting_document_located_fields_by_document[].

                #{child_field_tasks.presence || "No child-file located-field tasks are configured for this supporting document type."}
              TEXT
        { role: "user", content: [{ type: "input_text", text: <<~TEXT }] }
                User record: Child supporting documents in this group
                #{child_document_context(group).to_json}

                Actual ask:
                Extract the configured child-file supporting_document_located_fields, child-file visual_findings, and supporting_document_group_located_fields.
                Use child DI-read text, filenames, and the attached file visuals.
                Reply must be strict JSON using the system record schema.
              TEXT
      ]
    end

    def child_document_context(group)
      group
        .supporting_documents
        .includes(
          :supporting_document_type,
          :supporting_document_located_fields,
          :supporting_document_visual_findings
        )
        .order(:created_at, :id)
        .map do |doc|
          {
            supporting_document_id: doc.id,
            original_filename: doc.original_filename,
            content_type: doc.content_type,
            classification_status: doc.classification_status,
            classification_confidence: doc.classification_confidence,
            supporting_document_routing_quality:
              doc.supporting_document_routing_quality,
            supporting_document_routing_quality_reason:
              doc.supporting_document_routing_quality_reason,
            di_read_raw_json: doc.di_read_raw_json,
            located_fields:
              doc
                .supporting_document_located_fields
                .order(:field_key)
                .map do |field|
                  {
                    field_key: field.field_key,
                    value_text: field.value_text,
                    value_json: field.value_json,
                    confidence: field.confidence,
                    evidence_text: field.evidence_text
                  }
                end,
            visual_findings:
              doc
                .supporting_document_visual_findings
                .order(:finding_seqno)
                .map do |finding|
                  {
                    finding_type: finding.finding_type,
                    page: finding.page,
                    summary: finding.summary,
                    legibility: finding.legibility,
                    relevant_text_seen: finding.relevant_text_seen,
                    confidence: finding.confidence
                  }
                end
          }
        end
    end

    def build_attachments(group:)
      group
        .supporting_documents
        .order(:created_at, :id)
        .filter_map do |document|
          next if document.storage_key.blank?

          {
            type: "input_file",
            storageKey: document.storage_key,
            container: ENV["AZURE_BLOB_CONTAINER"].presence,
            filename:
              document.original_filename.presence || "supporting_document"
          }.compact
        end
    end

    def call_node_genai!(contextwindowjson:, attachments: [])
      base = ENV.fetch("INV_NODE_BASE_URL")
      uri = URI("#{base}/inv/genai")

      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body =
        JSON.generate(
          contextwindowjson: contextwindowjson,
          attachments: attachments
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

    def advance_run!(ingest_run_id:)
      return if ingest_run_id.blank?

      ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run_id)
    rescue StandardError
      nil
    end
  end
end
