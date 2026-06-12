# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceBundleRun
      BUNDLE_INVALID_ERROR_CODE = "invoice_bundle_count_invalid"
      BUNDLE_UNKNOWN_ERROR_CODE = "invoice_bundle_unknown_documents"
      SUPPORTING_DOCUMENTS_ATTACHED_INFO_CODE = "supporting_documents_attached"

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return unless run

        documents =
          ::Claims::IngestDocument.where(ingest_run_id: run.id).order(
            created_at: :asc
          )
        shell_invoice_id =
          documents
            .where.not(resolved_invoice_id: nil)
            .limit(1)
            .pick(:resolved_invoice_id)
        document_ids = documents.pluck(:id)
        total_files = run.total_files.to_i
        total_files = document_ids.size if total_files <= 0
        messages = sanitize_bundle_messages(parse_messages(run.messages))

        read_steps = latest_document_steps_map(run.id, document_ids, "ocr_read")
        if read_steps.size < total_files
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if failed_row = read_steps.values.find { |row| row.status == "failed" }
          failed_doc =
            documents.detect { |doc| doc.id == failed_row.ingest_document_id }
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: "bundle_read_ocr_failed",
                  level: "error",
                  message: "One or more files failed during initial OCR read.",
                  ingest_document_id: failed_row.ingest_document_id,
                  filename: failed_doc&.original_filename
                }
              ]
            )
          )
        end
        if read_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        triage_steps =
          latest_document_steps_map(run.id, document_ids, "triage_classifier")
        if triage_steps.empty?
          enqueue_triage_jobs!(documents: documents)
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if triage_steps.size < total_files
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if failed_row =
             triage_steps.values.find { |row| row.status == "failed" }
          failed_doc =
            documents.detect { |doc| doc.id == failed_row.ingest_document_id }
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: "bundle_triage_failed",
                  level: "error",
                  message: "One or more files failed during document triage.",
                  ingest_document_id: failed_row.ingest_document_id,
                  filename: failed_doc&.original_filename
                }
              ]
            )
          )
        end
        if triage_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        unknown_docs = documents.select { |doc| doc.document_kind == "unknown" }
        unless unknown_docs.empty?
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: unknown_docs.size,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: BUNDLE_UNKNOWN_ERROR_CODE,
                  level: "error",
                  message:
                    "One or more uploaded files could not be classified as either an invoice or a supporting document.",
                  filenames: unknown_docs.map(&:original_filename).compact.sort
                }
              ]
            )
          )
        end

        extraction_documents =
          documents_requiring_supporting_document_extraction(documents)
        extraction_ids = extraction_documents.map(&:id)
        extraction_steps =
          latest_document_steps_map(
            run.id,
            extraction_ids,
            "supporting_document_extraction"
          )

        missing_extraction_documents =
          extraction_documents.reject do |document|
            extraction_steps.key?(document.id)
          end

        if missing_extraction_documents.any?
          enqueue_supporting_document_extraction_jobs!(
            documents: missing_extraction_documents
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if extraction_steps.size < extraction_documents.size
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if failed_row =
             extraction_steps.values.find { |row| row.status == "failed" }
          failed_doc =
            extraction_documents.detect do |doc|
              doc.id == failed_row.ingest_document_id
            end
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: "bundle_supporting_document_extraction_failed",
                  level: "error",
                  message:
                    "One or more supporting documents failed during located-field extraction.",
                  ingest_document_id: failed_row.ingest_document_id,
                  filename: failed_doc&.original_filename
                }
              ]
            )
          )
        end

        if extraction_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        invoice_docs = documents.select { |doc| doc.document_kind == "invoice" }
        if invoice_docs.size != 1
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: [invoice_docs.size, 1].max,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: BUNDLE_INVALID_ERROR_CODE,
                  level: "error",
                  message:
                    "Exactly one invoice is required in the upload bundle; detected #{invoice_docs.size} invoice candidates.",
                  invoice_candidate_count: invoice_docs.size,
                  invoice_candidate_filenames:
                    invoice_docs.map(&:original_filename).compact.sort
                }
              ]
            )
          )
        end

        resolved_document = invoice_docs.first
        resolved_invoice_version_id =
          ensure_resolved_invoice!(
            run: run,
            resolved_document: resolved_document
          )
        resolved_invoice_id = resolved_document.reload.resolved_invoice_id
        supporting_document_rows =
          documents.select { |doc| doc.document_kind == "supporting_document" }

        supporting_document_rows.each do |document|
          ::Claims::SupportingDocuments::PromoteFromIngestDocument.call(
            resolved_invoice_id: resolved_invoice_id,
            ingest_document_id: document.id
          )
        end

        supporting_document_groups =
          ::Claims::SupportingDocumentGroups::EnsureForInvoice.call(
            invoice_id: resolved_invoice_id
          )

        group_extraction_groups =
          groups_requiring_supporting_document_group_extraction(
            supporting_document_groups
          )
        group_extraction_steps =
          latest_group_steps_map(
            run.id,
            group_extraction_groups.map(&:id),
            "supporting_document_group_extraction"
          )
        missing_group_extraction_groups =
          group_extraction_groups.reject do |group|
            group_extraction_steps.key?(group.id)
          end

        if missing_group_extraction_groups.any?
          enqueue_supporting_document_group_extraction_jobs!(
            groups: missing_group_extraction_groups
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if group_extraction_steps.size < group_extraction_groups.size
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if failed_row =
             group_extraction_steps.values.find { |row| row.status == "failed" }
          failed_group =
            group_extraction_groups.detect do |group|
              group.id == failed_row.supporting_document_group_id
            end
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: "bundle_supporting_document_group_extraction_failed",
                  level: "error",
                  message:
                    "One or more supporting document groups failed during group-level extraction.",
                  supporting_document_group_id:
                    failed_row.supporting_document_group_id,
                  group_label: failed_group&.group_label
                }
              ]
            )
          )
        end

        if group_extraction_steps.values.any? { |row|
             row.status != "succeeded"
           }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        invoice_ocr_step =
          latest_invoice_step(
            run.id,
            resolved_invoice_version_id,
            "ocr_invoice"
          )
        if invoice_ocr_step.nil?
          enqueue_invoice_finalize_ocr!(
            invoice_version_id: resolved_invoice_version_id
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if invoice_ocr_step.status == "failed"
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "ocr_failed",
              extra_messages: [
                {
                  code: "bundle_invoice_ocr_failed",
                  level: "error",
                  message:
                    "The resolved invoice failed during the invoice-model OCR pass.",
                  invoice_version_id: resolved_invoice_version_id
                }
              ]
            )
          )
        end
        unless invoice_ocr_step.status == "succeeded"
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        apply_succeeded_group_extraction_payloads!(
          ingest_run_id: run.id,
          groups: group_extraction_groups
        )

        resolved_invoice_status =
          invoice_status_for(resolved_invoice_version_id)
        validation_steps =
          latest_validation_steps(run.id, resolved_invoice_version_id)
        if validation_steps.any? { |row| row.status == "failed" } ||
             resolved_invoice_status == "genai_failed"
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "genai_failed",
              extra_messages: [
                {
                  code: "bundle_invoice_genai_failed",
                  level: "error",
                  message:
                    "The resolved invoice failed during the validation runtime.",
                  invoice_version_id: resolved_invoice_version_id
                }
              ]
            )
          )
        end

        unless resolved_invoice_status == "genai_complete" &&
                 validation_steps.present? &&
                 validation_steps.all? { |row| row.status == "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              messages: messages,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status:
                running_shell_invoice_status_for(
                  resolved_invoice_status: resolved_invoice_status
                )
            )
          )
        end

        info_messages = []
        if supporting_document_rows.any?
          info_messages << {
            code: SUPPORTING_DOCUMENTS_ATTACHED_INFO_CODE,
            level: "info",
            message:
              "#{supporting_document_rows.size} supporting document#{"s" unless supporting_document_rows.size == 1} attached to the resolved invoice.",
            attached_supporting_documents_count: supporting_document_rows.size
          }
        end

        run.update!(
          status: "succeeded",
          total_files: total_files,
          completed_files: total_files,
          failed_files: 0,
          messages: messages + info_messages,
          completed_at: Time.current,
          updated_at: Time.current
        )
      end

      private

      def latest_document_steps_map(ingest_run_id, document_ids, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            ingest_document_id: document_ids,
            step_type: step_type
          )
          .order(created_at: :desc)
          .to_a
          .group_by(&:ingest_document_id)
          .transform_values(&:first)
      end

      def latest_invoice_step(ingest_run_id, invoice_version_id, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type
          )
          .order(created_at: :desc)
          .first
      end

      def latest_group_steps_map(ingest_run_id, group_ids, step_type)
        return {} if group_ids.empty?

        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            supporting_document_group_id: group_ids,
            step_type: step_type
          )
          .order(created_at: :desc)
          .to_a
          .group_by(&:supporting_document_group_id)
          .transform_values(&:first)
      end

      def latest_validation_steps(ingest_run_id, invoice_version_id)
        ::Claims::IngestStepRun.where(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: %w[
            case_facts
            genai_common
            genai_upgrade
            product_lookup_enrichment
            code_common
            code_upgrade
            aggregate_advice
          ]
        ).order(created_at: :desc)
      end

      def enqueue_triage_jobs!(documents:)
        documents.each do |document|
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            ingest_document_id: document.id,
            step_type: "triage_classifier"
          ) do |step|
            step.session_id = document.session_id
            step.status = "queued"
            step.error_text = nil
            step.created_at = Time.current
            step.updated_at = Time.current
          end

          ::Claims::RunIngestTriageJob.perform_async(
            document.id,
            @ingest_run_id
          )
        end
      end

      def enqueue_supporting_document_extraction_jobs!(documents:)
        documents.each do |document|
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            ingest_document_id: document.id,
            step_type: "supporting_document_extraction"
          ) do |step|
            step.session_id = document.session_id
            step.status = "queued"
            step.error_text = nil
            step.created_at = Time.current
            step.updated_at = Time.current
          end

          ::Claims::RunSupportingDocumentExtractionJob.perform_async(
            document.id,
            @ingest_run_id
          )
        end
      end

      def enqueue_supporting_document_group_extraction_jobs!(groups:)
        groups.each do |group|
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            supporting_document_group_id: group.id,
            step_type: "supporting_document_group_extraction"
          ) do |step|
            step.session_id = group.invoice.session_id
            step.status = "queued"
            step.error_text = nil
            step.created_at = Time.current
            step.updated_at = Time.current
          end

          ::Claims::RunSupportingDocumentGroupExtractionJob.perform_async(
            group.id,
            @ingest_run_id
          )
        end
      end

      def documents_requiring_supporting_document_extraction(documents)
        supporting_document_rows =
          documents.select do |doc|
            doc.document_kind == "supporting_document" &&
              doc.supporting_document_type_id.present?
          end
        return [] if supporting_document_rows.empty?

        # Group-capable supporting-document types are extracted by one group
        # GenAI call, which also writes child-file fields and visual findings.
        grouped_type_ids = group_capable_supporting_document_type_ids
        supporting_document_rows =
          supporting_document_rows.reject do |doc|
            grouped_type_ids.include?(doc.supporting_document_type_id.to_s)
          end
        return [] if supporting_document_rows.empty?

        type_ids_with_fields =
          ::Claims::SupportingDocumentTypeLocatedField
            .where(
              supporting_document_type_id:
                supporting_document_rows.map(&:supporting_document_type_id),
              enabled: true
            )
            .distinct
            .pluck(:supporting_document_type_id)
            .map(&:to_s)

        supporting_document_rows.select do |doc|
          type_ids_with_fields.include?(doc.supporting_document_type_id.to_s)
        end
      end

      def group_capable_supporting_document_type_ids
        ::Claims::SupportingDocumentType
          .where(
            type_key:
              ::Claims::SupportingDocumentGroups::EnsureForInvoice::GROUP_CAPABLE_TYPE_KEYS,
            enabled: true
          )
          .pluck(:id)
          .map(&:to_s)
      end

      def groups_requiring_supporting_document_group_extraction(groups)
        return [] if groups.empty?

        type_ids_with_fields =
          ::Claims::SupportingDocumentGroupTypeLocatedField
            .where(
              supporting_document_type_id:
                groups.map(&:supporting_document_type_id),
              enabled: true
            )
            .distinct
            .pluck(:supporting_document_type_id)
            .map(&:to_s)

        groups.select do |group|
          type_ids_with_fields.include?(group.supporting_document_type_id.to_s)
        end
      end

      def apply_succeeded_group_extraction_payloads!(ingest_run_id:, groups:)
        return if groups.empty?

        latest_group_steps_map(
          ingest_run_id,
          groups.map(&:id),
          "supporting_document_group_extraction"
        ).each_value do |step|
          next unless step.status == "succeeded"
          next unless step.genai_results_json.is_a?(Hash)

          result =
            ::Claims::SupportingDocumentGroups::ApplyLocatedFields.call(
              supporting_document_group_id: step.supporting_document_group_id,
              located_fields_payload: step.genai_results_json
            )
          unless result[:ok] || result["ok"]
            raise "ApplySupportingDocumentGroupLocatedFields failed during bundle advance: #{result.inspect}"
          end

          child_payload_count =
            Array(
              step.genai_results_json[
                "supporting_document_located_fields_by_document"
              ]
            ).size
          child_evidence_count =
            (result[:child_located_fields_replaced] || 0).to_i +
              (result[:child_visual_findings_replaced] || 0).to_i
          if child_payload_count.positive? && child_evidence_count.zero?
            raise "ApplySupportingDocumentGroupLocatedFields wrote no child evidence rows during bundle advance despite #{child_payload_count} child payloads: #{result.inspect}"
          end
        end
      end

      def ensure_resolved_invoice!(run:, resolved_document:)
        resolved_document.with_lock do
          if resolved_document.resolved_invoice_version_id.present?
            return resolved_document.resolved_invoice_version_id
          end

          invoice =
            ::Claims::Invoice.find_by(id: resolved_document.resolved_invoice_id)
          if invoice.nil?
            raise "Missing shell invoice for resolved ingest document #{resolved_document.id}"
          end

          existing_invoice_version =
            ::Claims::InvoiceVersion.find_by(
              invoice_id: invoice.id,
              storage_key: resolved_document.storage_key
            )
          if existing_invoice_version.present?
            existing_invoice_version.update!(
              storage_provider:
                resolved_document.storage_provider.presence ||
                  existing_invoice_version.storage_provider,
              original_filename:
                resolved_document.original_filename.presence ||
                  existing_invoice_version.original_filename,
              content_type:
                resolved_document.content_type.presence ||
                  existing_invoice_version.content_type,
              byte_size:
                resolved_document.byte_size.presence ||
                  existing_invoice_version.byte_size,
              sha256:
                resolved_document.sha256.presence ||
                  existing_invoice_version.sha256,
              updated_at: Time.current
            )

            apply_classifier_evidence!(
              invoice_version_id: existing_invoice_version.id,
              classifier_payload: resolved_document.classifier_raw_json
            )

            resolved_document.update!(
              resolved_invoice_id: invoice.id,
              resolved_invoice_version_id: existing_invoice_version.id,
              updated_at: Time.current
            )

            return existing_invoice_version.id
          end

          invoice_version =
            ::Claims::InvoiceVersion.create!(
              invoice_id: invoice.id,
              invoice_versionno: next_invoice_versionno(invoice.id),
              storage_provider: resolved_document.storage_provider,
              storage_key: resolved_document.storage_key,
              original_filename: resolved_document.original_filename,
              content_type: resolved_document.content_type,
              byte_size: resolved_document.byte_size,
              sha256: resolved_document.sha256,
              created_at: Time.current,
              updated_at: Time.current
            )

          apply_classifier_evidence!(
            invoice_version_id: invoice_version.id,
            classifier_payload: resolved_document.classifier_raw_json
          )

          resolved_document.update!(
            resolved_invoice_id: invoice.id,
            resolved_invoice_version_id: invoice_version.id,
            updated_at: Time.current
          )

          invoice_version.id
        end
      end

      def apply_classifier_evidence!(invoice_version_id:, classifier_payload:)
        result =
          ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
            invoice_version_id: invoice_version_id,
            classifier_payload: classifier_payload
          )

        return if result[:ok] || result["ok"]

        raise "ApplyClassifierResult failed: #{result.inspect}"
      end

      def next_invoice_versionno(invoice_id)
        (
          ::Claims::InvoiceVersion.where(invoice_id: invoice_id).maximum(
            :invoice_versionno
          ) || 0
        ) + 1
      end

      def enqueue_invoice_finalize_ocr!(invoice_version_id:)
        iv = ::Claims::InvoiceVersion.find(invoice_version_id)
        inv = ::Claims::Invoice.find(iv.invoice_id)
        inv.update!(status: "ocr_queued", status_updated_at: Time.current)

        ::Claims::IngestStepRun.find_or_create_by!(
          ingest_run_id: @ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: "ocr_invoice"
        ) do |step|
          step.session_id = inv.session_id
          step.status = "queued"
          step.error_text = nil
          step.created_at = Time.current
          step.updated_at = Time.current
        end

        ::Claims::RunOcrJob.perform_async(
          invoice_version_id,
          @ingest_run_id,
          "prebuilt-invoice",
          true,
          "use_existing_classifier",
          "ocr_invoice"
        )
      end

      def invoice_status_for(invoice_version_id)
        ::Claims::InvoiceVersion
          .joins(
            "JOIN claims.invoices i ON i.id = claims.invoice_versions.invoice_id"
          )
          .where(id: invoice_version_id)
          .pick("i.status")
          .to_s
      end

      def update_running!(
        run:,
        total_files:,
        messages:,
        shell_invoice_id: nil,
        shell_invoice_status: "ocr_in_progress"
      )
        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status
        )
        run.update!(
          status: "running",
          total_files: total_files,
          completed_files: 0,
          failed_files: 0,
          messages: messages,
          completed_at: nil,
          updated_at: Time.current
        )
      end

      def update_failed!(
        run:,
        total_files:,
        failed_files:,
        messages:,
        extra_messages:,
        shell_invoice_id: nil,
        shell_invoice_status: "ocr_failed"
      )
        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status
        )
        run.update!(
          status: "failed",
          total_files: total_files,
          completed_files: 0,
          failed_files: [failed_files, 0].max,
          messages: messages + extra_messages,
          completed_at: Time.current,
          updated_at: Time.current
        )
      end

      def sync_shell_invoice_status!(shell_invoice_id:, status:)
        return if shell_invoice_id.blank? || status.blank?

        invoice = ::Claims::Invoice.find_by(id: shell_invoice_id)
        return if invoice.nil? || invoice.status == status

        invoice.update!(
          status: status,
          status_updated_at: Time.current,
          updated_at: Time.current
        )
      rescue StandardError
        nil
      end

      def running_shell_invoice_status_for(resolved_invoice_status:)
        status = resolved_invoice_status.to_s
        return "genai_in_progress" if status.blank?
        if %w[genai_queued genai_in_progress genai_complete].include?(status)
          return status
        end

        "genai_in_progress"
      end

      def parse_messages(messages)
        return messages if messages.is_a?(Array)

        JSON.parse(messages.to_s)
      rescue JSON::ParserError, TypeError
        []
      end

      def sanitize_bundle_messages(messages)
        Array(messages).reject do |row|
          next false unless row.is_a?(Hash)

          code = row["code"].to_s.presence || row[:code].to_s
          [
            BUNDLE_INVALID_ERROR_CODE,
            BUNDLE_UNKNOWN_ERROR_CODE,
            SUPPORTING_DOCUMENTS_ATTACHED_INFO_CODE,
            "bundle_read_ocr_failed",
            "bundle_triage_failed",
            "bundle_supporting_document_extraction_failed",
            "bundle_invoice_ocr_failed",
            "bundle_invoice_genai_failed"
          ].include?(code)
        end
      end
    end
  end
end
