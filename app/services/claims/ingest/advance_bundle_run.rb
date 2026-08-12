# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceBundleRun
      BUNDLE_INVALID_ERROR_CODE = "invoice_bundle_count_invalid"
      BUNDLE_UNKNOWN_ERROR_CODE = "invoice_bundle_unknown_documents"
      BUNDLE_NO_SUPPORTED_UPGRADE_ERROR_CODE =
        "invoice_bundle_no_supported_upgrade_type"
      DEFAULT_WORKER_ATTEMPT_LIMIT = 4
      STEP_STATUS_RANK = {
        "queued" => 1,
        "failed" => 2,
        "in_progress" => 3,
        "succeeded" => 4
      }.freeze

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
        read_step_type = read_step_type_for(run)
        classifier_step_type = classifier_step_type_for(run)
        supporting_document_extraction_step_type =
          supporting_document_extraction_step_type_for(run)
        invoice_ocr_step_type = invoice_ocr_step_type_for(run)
        read_documents =
          documents_requiring_read(run: run, documents: documents)
        read_document_ids = read_documents.map(&:id)

        read_steps =
          latest_document_steps_map(run.id, read_document_ids, read_step_type)
        if read_steps.size < read_documents.size
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if (
             failed_row =
               read_steps.values.find { |row| row.status == "failed" }
           )
          if step_failure_retry_pending?(failed_row)
            return(
              update_running!(
                run: run,
                total_files: total_files,
                shell_invoice_id: shell_invoice_id
              )
            )
          end

          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype:
                failure_subtype_from_step(
                  failed_row,
                  fallback: "ocr_unexpected_exception"
                ),
              fallback_error_code: "bundle_read_ocr_failed"
            )
          )
        end
        if read_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        classifier_documents =
          documents_requiring_classifier(run: run, documents: documents)
        triage_steps = latest_classifier_steps_map(run.id, classifier_documents)
        missing_triage_documents =
          classifier_documents.reject do |document|
            triage_steps.key?(document.id)
          end
        if missing_triage_documents.any?
          enqueue_classifier_jobs!(
            documents: missing_triage_documents,
            step_type: classifier_step_type
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end
        if (
             failed_row =
               triage_steps.values.find { |row| row.status == "failed" }
           )
          if step_failure_retry_pending?(failed_row)
            return(
              update_running!(
                run: run,
                total_files: total_files,
                shell_invoice_id: shell_invoice_id
              )
            )
          end

          failure_status =
            failure_status_from_step(failed_row, fallback: "technical_failure")
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: failure_status,
              shell_invoice_status_subtype:
                failure_subtype_from_step(
                  failed_row,
                  fallback: "genai_unexpected_exception"
                ),
              fallback_error_code: "bundle_triage_failed"
            )
          )
        end
        if triage_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
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
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "package_needs_correction",
              shell_invoice_status_subtype:
                "package_invoice_classification_conflict",
              fallback_error_code: BUNDLE_UNKNOWN_ERROR_CODE
            )
          )
        end

        invoice_docs = documents.select { |doc| doc.document_kind == "invoice" }
        if invoice_docs.size != 1
          package_status_subtype =
            (
              if invoice_docs.empty?
                "package_no_invoice_pdf"
              else
                "package_multiple_invoice_pdfs"
              end
            )
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: [invoice_docs.size, 1].max,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "package_needs_correction",
              shell_invoice_status_subtype: package_status_subtype,
              fallback_error_code: BUNDLE_INVALID_ERROR_CODE
            )
          )
        end

        non_pdf_invoice_docs =
          invoice_docs.reject { |document| pdf_document?(document) }
        unless non_pdf_invoice_docs.empty?
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: non_pdf_invoice_docs.size,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "package_needs_correction",
              shell_invoice_status_subtype: "package_invoice_not_pdf",
              fallback_error_code: BUNDLE_INVALID_ERROR_CODE
            )
          )
        end

        resolved_document = invoice_docs.first
        if fix_run?(run)
          legacy_resolved_version_id =
            run.resolved_invoice_version_id.presence ||
              resolved_document.resolved_invoice_version_id.presence
          if legacy_resolved_version_id.present?
            mark_run_resolved_invoice_version!(
              run: run,
              resolved_invoice_version_id: legacy_resolved_version_id
            )
            resolved_invoice_version_id =
              ensure_resolved_invoice!(
                run: run,
                resolved_document: resolved_document
              )
            scope_guard =
              ::Claims::Ingest::FixUpgradeTypeScopeGuard.call(
                ingest_run: run,
                replacement_invoice_version_id: resolved_invoice_version_id
              )
            return if scope_guard.changed
          else
            scope_guard =
              ::Claims::Ingest::FixUpgradeTypeScopeGuard.call(
                ingest_run: run,
                replacement_document: resolved_document
              )
            return if scope_guard.changed

            unless fix_document_has_supported_upgrade_type?(
                     run: run,
                     document: resolved_document
                   )
              return(
                update_failed!(
                  run: run,
                  total_files: total_files,
                  failed_files: 1,
                  shell_invoice_id: shell_invoice_id,
                  shell_invoice_status: "package_needs_correction",
                  shell_invoice_status_subtype:
                    "package_no_supported_upgrade_type",
                  fallback_error_code: BUNDLE_NO_SUPPORTED_UPGRADE_ERROR_CODE
                )
              )
            end

            resolved_invoice_version_id =
              ::Claims::Ingest::PromoteFixPackage.call(
                ingest_run: run,
                resolved_document: resolved_document
              )
          end

          unless supported_upgrade_type_detected?(resolved_invoice_version_id)
            return(
              update_failed!(
                run: run,
                total_files: total_files,
                failed_files: 1,
                shell_invoice_id: shell_invoice_id,
                shell_invoice_status: "package_needs_correction",
                shell_invoice_status_subtype:
                  "package_no_supported_upgrade_type",
                fallback_error_code: BUNDLE_NO_SUPPORTED_UPGRADE_ERROR_CODE
              )
            )
          end
        else
          resolved_invoice_version_id =
            ensure_resolved_invoice!(
              run: run,
              resolved_document: resolved_document
            )
          mark_run_resolved_invoice_version!(
            run: run,
            resolved_invoice_version_id: resolved_invoice_version_id
          )
          resolved_invoice_id = resolved_document.reload.resolved_invoice_id

          unless supported_upgrade_type_detected?(resolved_invoice_version_id)
            return(
              update_failed!(
                run: run,
                total_files: total_files,
                failed_files: 1,
                shell_invoice_id: resolved_invoice_id || shell_invoice_id,
                shell_invoice_status: "package_needs_correction",
                shell_invoice_status_subtype:
                  "package_no_supported_upgrade_type",
                fallback_error_code: BUNDLE_NO_SUPPORTED_UPGRADE_ERROR_CODE
              )
            )
          end
        end

        mark_run_resolved_invoice_version!(
          run: run,
          resolved_invoice_version_id: resolved_invoice_version_id
        )
        resolved_invoice_id = resolved_document.reload.resolved_invoice_id

        if fix_run?(run)
          mark_clone_existing_evidence_succeeded!(
            run: run,
            documents: documents.reload
          )
        end

        supporting_document_rows =
          documents.select { |doc| doc.document_kind == "supporting_document" }

        supporting_document_rows.each do |document|
          ::Claims::SupportingDocuments::CreateOrUpdateFromIngestDocument.call(
            resolved_invoice_version_id: resolved_invoice_version_id,
            ingest_document_id: document.id
          )
        end

        extraction_type_ids =
          supporting_document_type_ids_requiring_extraction(
            run: run,
            supporting_document_rows: supporting_document_rows
          )
        extraction_steps =
          latest_type_steps_map(
            run.id,
            resolved_invoice_version_id,
            extraction_type_ids,
            supporting_document_extraction_step_type
          )

        missing_extraction_type_ids =
          extraction_type_ids.reject do |type_id|
            extraction_steps.key?(type_id)
          end

        if missing_extraction_type_ids.any?
          enqueue_supporting_document_extraction_jobs!(
            invoice_version_id: resolved_invoice_version_id,
            supporting_document_type_ids: missing_extraction_type_ids,
            step_type: supporting_document_extraction_step_type
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if extraction_steps.size < extraction_type_ids.size
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if (
             failed_row =
               extraction_steps.values.find { |row| row.status == "failed" }
           )
          if step_failure_retry_pending?(failed_row)
            return(
              update_running!(
                run: run,
                total_files: total_files,
                shell_invoice_id: shell_invoice_id
              )
            )
          end

          failure_status =
            failure_status_from_step(failed_row, fallback: "technical_failure")
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: failure_status,
              shell_invoice_status_subtype:
                failure_subtype_from_step(
                  failed_row,
                  fallback: "genai_unexpected_exception"
                ),
              fallback_error_code:
                "bundle_supporting_document_extraction_failed"
            )
          )
        end

        if extraction_steps.values.any? { |row| row.status != "succeeded" }
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        invoice_ocr_step =
          latest_invoice_step(
            run.id,
            resolved_invoice_version_id,
            invoice_ocr_step_type
          )
        invoice_ocr_satisfied_by_cloned_evidence =
          invoice_ocr_step.nil? &&
            invoice_ocr_satisfied_by_cloned_evidence?(
              run: run,
              invoice_version_id: resolved_invoice_version_id,
              step_type: invoice_ocr_step_type
            )

        if invoice_ocr_step.nil? && !invoice_ocr_satisfied_by_cloned_evidence
          enqueue_invoice_finalize_ocr!(
            invoice_version_id: resolved_invoice_version_id,
            step_type: invoice_ocr_step_type
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        if invoice_ocr_step&.status == "failed"
          if step_failure_retry_pending?(invoice_ocr_step)
            return(
              update_running!(
                run: run,
                total_files: total_files,
                shell_invoice_id: shell_invoice_id
              )
            )
          end

          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "technical_failure",
              shell_invoice_status_subtype:
                failure_subtype_from_step(
                  invoice_ocr_step,
                  fallback: "ocr_unexpected_exception"
                ),
              fallback_error_code: "bundle_invoice_ocr_failed"
            )
          )
        end
        if invoice_ocr_step && invoice_ocr_step.status != "succeeded"
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id
            )
          )
        end

        resolved_invoice_status =
          invoice_status_for(resolved_invoice_version_id)
        validation_steps =
          latest_validation_steps(run.id, resolved_invoice_version_id)
        if validation_steps.empty? &&
             (
               invoice_ocr_satisfied_by_cloned_evidence ||
                 cloned_invoice_ocr_step?(invoice_ocr_step)
             )
          enqueue_validation_for_cloned_invoice!(
            run: run,
            invoice_version_id: resolved_invoice_version_id
          )
          return(
            update_running!(
              run: run,
              total_files: total_files,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: "genai_queued"
            )
          )
        end
        resolved_invoice_status =
          normalize_stale_validation_failure!(
            invoice_version_id: resolved_invoice_version_id,
            invoice_status: resolved_invoice_status,
            validation_steps: validation_steps
          )
        if validation_steps.any? { |row| row.status == "failed" } ||
             %w[
               genai_failed
               package_needs_correction
               technical_failure
             ].include?(resolved_invoice_status)
          failed_validation_step =
            validation_steps.find { |row| row.status == "failed" }
          if failed_validation_step &&
               step_failure_retry_pending?(failed_validation_step)
            return(
              update_running!(
                run: run,
                total_files: total_files,
                shell_invoice_id: shell_invoice_id,
                shell_invoice_status: "genai_in_progress"
              )
            )
          end

          failure_status =
            if %w[package_needs_correction technical_failure].include?(
                 resolved_invoice_status
               )
              resolved_invoice_status
            else
              "technical_failure"
            end
          failure_subtype =
            if failure_status == "package_needs_correction"
              invoice_status_subtype_for(resolved_invoice_version_id) ||
                "package_invoice_classification_conflict"
            else
              invoice_status_subtype_for(resolved_invoice_version_id) ||
                failure_subtype_from_step(
                  failed_validation_step,
                  fallback: "genai_unexpected_exception"
                )
            end
          return(
            update_failed!(
              run: run,
              total_files: total_files,
              failed_files: 1,
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status: failure_status,
              shell_invoice_status_subtype: failure_subtype,
              fallback_error_code: "bundle_invoice_genai_failed"
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
              shell_invoice_id: shell_invoice_id,
              shell_invoice_status:
                running_shell_invoice_status_for(
                  resolved_invoice_status: resolved_invoice_status
                )
            )
          )
        end

        run.update!(
          status: "succeeded",
          total_files: total_files,
          completed_files: total_files,
          failed_files: 0,
          failure_status: nil,
          failure_status_subtype: nil,
          completed_at: Time.current,
          updated_at: Time.current
        )
        ::Claims::PipelineAudit::CheckRun.call(ingest_run_id: run.id)
      end

      private

      def fix_run?(run)
        @fix_run_cache ||= {}
        @fix_run_cache[run.id] ||= ::Claims::IngestStepRun.exists?(
          ingest_run_id: run.id,
          step_type: "fix_upload_package_stage"
        )
      end

      def read_step_type_for(run)
        fix_run?(run) ? "fix_ocr_read" : "ocr_read"
      end

      def classifier_step_type_for(run)
        fix_run?(run) ? "fix_classifier_files" : "classifier_files"
      end

      def supporting_document_extraction_step_type_for(run)
        if fix_run?(run)
          "fix_supporting_document_extraction"
        else
          "supporting_document_extraction"
        end
      end

      def invoice_ocr_step_type_for(run)
        fix_run?(run) ? "fix_ocr_invoice" : "ocr_invoice"
      end

      def documents_requiring_read(run:, documents:)
        return documents.to_a unless fix_run?(run)

        documents.reject { |document| reused_ingest_document?(document) }
      end

      def documents_requiring_classifier(run:, documents:)
        return documents.to_a unless fix_run?(run)

        documents.reject { |document| reused_ingest_document?(document) }
      end

      def reused_ingest_document?(document)
        document.document_kind_reason.to_s.start_with?("Cloned from prior")
      end

      def mark_clone_existing_evidence_succeeded!(run:, documents:)
        step =
          ::Claims::IngestStepRun
            .where(
              ingest_run_id: run.id,
              step_type: "fix_clone_existing_evidence"
            )
            .order(created_at: :asc, id: :asc)
            .first
        step ||=
          ::Claims::IngestStepRun.create!(
            ingest_run_id: run.id,
            session_id: run.session_id,
            invoice_version_id:
              documents.map(&:resolved_invoice_version_id).compact.first,
            step_type: "fix_clone_existing_evidence",
            status: "queued",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )
        return if step.status == "succeeded"
        return if step.status == "failed"

        step.update!(
          status: "succeeded",
          genai_results_json: clone_existing_evidence_payload(documents),
          error_text: nil,
          updated_at: Time.current
        )
      end

      def clone_existing_evidence_payload(documents)
        reused_documents =
          documents.select { |doc| reused_ingest_document?(doc) }
        {
          reused_evidence: true,
          reused_document_count: reused_documents.size,
          reused_original_filenames:
            reused_documents.map(&:original_filename).compact
        }
      end

      def mark_run_resolved_invoice_version!(run:, resolved_invoice_version_id:)
        return if resolved_invoice_version_id.blank?
        if run.resolved_invoice_version_id.to_s ==
             resolved_invoice_version_id.to_s
          return
        end

        run.update!(
          resolved_invoice_version_id: resolved_invoice_version_id,
          updated_at: Time.current
        )
      end

      def invoice_ocr_satisfied_by_cloned_evidence?(
        run:,
        invoice_version_id:,
        step_type:
      )
        return false unless step_type == "fix_ocr_invoice"

        invoice_version = ::Claims::InvoiceVersion.find(invoice_version_id)
        return false if invoice_version.di_raw_json.blank?

        cloned_document =
          ::Claims::IngestDocument.find_by(
            ingest_run_id: run.id,
            resolved_invoice_version_id: invoice_version.id,
            document_kind: "invoice"
          )
        cloned_document.present? && reused_ingest_document?(cloned_document)
      end

      def latest_document_steps_map(ingest_run_id, document_ids, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            ingest_document_id: document_ids,
            step_type: step_type
          )
          .to_a
          .group_by(&:ingest_document_id)
          .transform_values { |steps| best_step_for_target(steps) }
      end

      def latest_invoice_step(ingest_run_id, invoice_version_id, step_type)
        best_step_for_target(
          ::Claims::IngestStepRun.where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type
          ).to_a
        )
      end

      def latest_type_steps_map(
        ingest_run_id,
        invoice_version_id,
        supporting_document_type_ids,
        step_type
      )
        return {} if supporting_document_type_ids.empty?

        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            supporting_document_type_id: supporting_document_type_ids,
            step_type: step_type
          )
          .to_a
          .group_by(&:supporting_document_type_id)
          .transform_values { |steps| best_step_for_target(steps) }
      end

      def latest_validation_steps(ingest_run_id, invoice_version_id)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: %w[
              case_facts
              genai_common
              genai_upgrade
              code_common
              code_upgrade
              aggregate_advice
            ]
          )
          .order(created_at: :desc)
          .to_a
          .group_by { |step| [step.step_type, step.invoice_upgrade_type_id] }
          .transform_values(&:first)
          .values
      end

      def normalize_stale_validation_failure!(
        invoice_version_id:,
        invoice_status:,
        validation_steps:
      )
        unless %w[technical_failure genai_failed].include?(invoice_status)
          return invoice_status
        end
        return invoice_status unless validation_complete?(validation_steps)

        invoice =
          ::Claims::InvoiceVersion
            .includes(:invoice)
            .find(invoice_version_id)
            .invoice
        invoice.set_workflow_status!("genai_complete")
        "genai_complete"
      rescue StandardError
        invoice_status
      end

      def validation_complete?(validation_steps)
        validation_steps.present? &&
          validation_steps.all? { |row| row.status == "succeeded" } &&
          validation_steps.any? do |row|
            row.step_type == "aggregate_advice" && row.status == "succeeded"
          end
      end

      def enqueue_classifier_jobs!(documents:, step_type:)
        documents.each do |document|
          created_step = nil

          document.with_lock do
            existing_step =
              best_step_for_target(
                ::Claims::IngestStepRun.where(
                  ingest_run_id: @ingest_run_id,
                  ingest_document_id: document.id,
                  step_type: classifier_step_types_for_lookup,
                  status: %w[queued in_progress succeeded]
                ).to_a
              )
            next if existing_step

            created_step =
              ::Claims::IngestStepRun.create!(
                ingest_run_id: @ingest_run_id,
                session_id: document.session_id,
                ingest_document_id: document.id,
                step_type: step_type,
                status: "queued",
                error_text: nil,
                created_at: Time.current,
                updated_at: Time.current
              )
          end
          next unless created_step

          ::Claims::RunIngestTriageJob.perform_async(
            document.id,
            @ingest_run_id,
            step_type
          )
        end
      end

      def enqueue_supporting_document_extraction_jobs!(
        invoice_version_id:,
        supporting_document_type_ids:,
        step_type:
      )
        invoice_version = ::Claims::InvoiceVersion.find(invoice_version_id)
        invoice = invoice_version.invoice

        supporting_document_type_ids.each do |type_id|
          ::Claims::IngestStepRun.find_or_create_by!(
            ingest_run_id: @ingest_run_id,
            invoice_version_id: invoice_version.id,
            supporting_document_type_id: type_id,
            step_type: step_type
          ) do |step|
            step.session_id = invoice.session_id
            step.status = "queued"
            step.error_text = nil
            step.created_at = Time.current
            step.updated_at = Time.current
          end

          ::Claims::RunSupportingDocumentTypeExtractionJob.perform_async(
            invoice_version.id,
            type_id,
            @ingest_run_id,
            step_type
          )
        end
      end

      def cloned_invoice_ocr_step?(step)
        payload = step&.di_results_json
        return false unless payload.is_a?(Hash)

        payload.key?("cloned_from_invoice_version_id") ||
          payload.key?(:cloned_from_invoice_version_id) ||
          payload.key?("reused_from_invoice_version_id") ||
          payload.key?(:reused_from_invoice_version_id) ||
          payload.key?("reused_invoice_ocr") ||
          payload.key?(:reused_invoice_ocr)
      end

      def enqueue_validation_for_cloned_invoice!(run:, invoice_version_id:)
        invoice_version = ::Claims::InvoiceVersion.find(invoice_version_id)
        invoice_version.invoice.set_workflow_status!("genai_queued")
        ::Claims::RunGenaiJob.perform_async(
          invoice_version.invoice.session_id,
          invoice_version.id,
          run.id,
          "use_existing_classifier"
        )
      end

      def supporting_document_type_ids_requiring_extraction(
        run:,
        supporting_document_rows:
      )
        candidate_rows =
          supporting_document_rows.select do |doc|
            doc.supporting_document_type_id.present?
          end
        return [] if candidate_rows.empty?

        affected_rows =
          if fix_run?(run)
            candidate_rows.reject { |doc| reused_ingest_document?(doc) }
          else
            candidate_rows
          end
        return [] if affected_rows.empty?

        type_ids_with_affected_evidence =
          affected_rows.map { |row| row.supporting_document_type_id.to_s }.uniq

        supporting_document_type_ids_configured_for_extraction(
          type_ids_with_affected_evidence
        )
      end

      def supporting_document_type_ids_configured_for_extraction(type_ids)
        return [] if type_ids.empty?

        type_ids_with_fields =
          ::Claims::SupportingDocumentTypeLocatedField
            .where(supporting_document_type_id: type_ids, enabled: true)
            .distinct
            .pluck(:supporting_document_type_id)
            .map(&:to_s)

        type_ids.select { |type_id| type_ids_with_fields.include?(type_id) }
      end

      def latest_classifier_steps_map(ingest_run_id, documents)
        documents
          .map do |document|
            step =
              best_step_for_target(
                ::Claims::IngestStepRun.where(
                  ingest_run_id: ingest_run_id,
                  ingest_document_id: document.id,
                  step_type: classifier_step_types_for_lookup
                ).to_a
              )
            [document.id, step]
          end
          .select { |_document_id, step| step.present? }
          .to_h
      end

      def best_step_for_target(steps)
        steps.compact.max_by do |step|
          [
            STEP_STATUS_RANK.fetch(step.status.to_s, 0),
            step.updated_at || step.created_at,
            step.created_at,
            step.id
          ]
        end
      end

      def classifier_step_types_for_lookup
        %w[classifier_files fix_classifier_files]
      end

      def image_document?(document)
        content_type = document.content_type.to_s.downcase
        return true if content_type.start_with?("image/")

        filename = document.original_filename.to_s.downcase
        filename.end_with?(".jpg", ".jpeg", ".png")
      end

      def pdf_document?(document)
        content_type = document.content_type.to_s.downcase
        return true if content_type == "application/pdf"

        document.original_filename.to_s.downcase.end_with?(".pdf")
      end

      def ensure_resolved_invoice!(run:, resolved_document:)
        resolved_document.with_lock do
          if resolved_document.resolved_invoice_version_id.present?
            existing_invoice_version =
              ::Claims::InvoiceVersion.find(
                resolved_document.resolved_invoice_version_id
              )
            existing_invoice_version.update!(
              storage_provider:
                resolved_document.storage_provider.presence ||
                  existing_invoice_version.storage_provider,
              storage_key:
                resolved_document.storage_key.presence ||
                  existing_invoice_version.storage_key,
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
            if resolved_document.classifier_raw_json.present?
              apply_classifier_evidence!(
                invoice_version_id: existing_invoice_version.id,
                classifier_payload: resolved_document.classifier_raw_json
              )
            end

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

        unless result[:ok] || result["ok"]
          raise "ApplyClassifierResult failed: #{result.inspect}"
        end

        personal_information_attributes =
          ::Claims::PersonalInformation::NormalizeClassifierResult.call(
            classifier_payload: classifier_payload || {}
          )
        return if personal_information_attributes.empty?

        ::Claims::InvoiceVersion.find(invoice_version_id).update!(
          personal_information_attributes.merge(updated_at: Time.current)
        )
      end

      def next_invoice_versionno(invoice_id)
        (
          ::Claims::InvoiceVersion.where(invoice_id: invoice_id).maximum(
            :invoice_versionno
          ) || 0
        ) + 1
      end

      def enqueue_invoice_finalize_ocr!(invoice_version_id:, step_type:)
        iv = ::Claims::InvoiceVersion.find(invoice_version_id)
        inv = ::Claims::Invoice.find(iv.invoice_id)
        inv.set_workflow_status!("ocr_queued")

        ::Claims::IngestStepRun.find_or_create_by!(
          ingest_run_id: @ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: step_type
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
          step_type
        )
      end

      def supported_upgrade_type_detected?(invoice_version_id)
        ::Claims::InvoiceVersionUpgradeType
          .joins(
            "INNER JOIN claims.invoice_upgrade_types iut " \
              "ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
          )
          .where(
            invoice_version_id: invoice_version_id,
            source_engine: "classifier"
          )
          .where.not("iut.upgrade_type_key" => "common")
          .exists?
      end

      def fix_document_has_supported_upgrade_type?(run:, document:)
        if reused_ingest_document?(document)
          source_id =
            fix_upload_context(run)["source_invoice_version_id"].presence
          return false if source_id.blank?

          return supported_upgrade_type_detected?(source_id)
        end

        rows =
          if document.classifier_raw_json.is_a?(Hash)
            document.classifier_raw_json["detected_upgrade_types"] ||
              document.classifier_raw_json[:detected_upgrade_types]
          end
        keys =
          Array(rows)
            .filter_map do |row|
              next unless row.respond_to?(:[])

              key =
                (row["upgrade_type_key"] || row[:upgrade_type_key]).to_s.strip
              key.presence unless key == "common"
            end
            .uniq
        return false if keys.empty?

        ::Claims::InvoiceUpgradeType.where(upgrade_type_key: keys).exists?
      end

      def fix_upload_context(run)
        Array(run.messages).reverse_each do |message|
          payload =
            message.respond_to?(:to_h) ? message.to_h.stringify_keys : {}
          return payload if payload["code"] == "fix_upload_context"
        end
        {}
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

      def invoice_status_subtype_for(invoice_version_id)
        ::Claims::InvoiceVersion
          .joins(
            "JOIN claims.invoices i ON i.id = claims.invoice_versions.invoice_id"
          )
          .where(id: invoice_version_id)
          .pick("i.status_subtype")
          .to_s
          .presence
      end

      def failure_subtype_from_step(step, fallback:)
        ::Claims::Invoices::FailureSubtypes.from_step(step, fallback: fallback)
      end

      def failure_status_from_step(step, fallback:)
        ::Claims::Invoices::FailureSubtypes.status_from_step(
          step,
          fallback: fallback
        )
      end

      def step_failure_retry_pending?(step)
        return false unless step&.status == "failed"

        analytics =
          ::Claims::Invoices::FailureSubtypes.analytics_from_step(step)
        return false if analytics["retryable"] == false

        same_target_step_attempts(step) < worker_attempt_limit
      end

      def worker_attempt_limit
        raw =
          ENV.fetch(
            "CLAIMS_INGEST_STEP_ATTEMPT_LIMIT",
            DEFAULT_WORKER_ATTEMPT_LIMIT
          )
        value =
          begin
            Integer(raw)
          rescue StandardError
            DEFAULT_WORKER_ATTEMPT_LIMIT
          end
        [value, 1].max
      end

      def same_target_step_attempts(step)
        scope =
          ::Claims::IngestStepRun.where(
            ingest_run_id: step.ingest_run_id,
            step_type: step.step_type
          )

        %i[
          ingest_document_id
          invoice_version_id
          supporting_document_type_id
          invoice_upgrade_type_id
        ].each do |column|
          scope = scope.where(column => step.public_send(column))
        end

        scope.count
      end

      def update_running!(
        run:,
        total_files:,
        shell_invoice_id: nil,
        shell_invoice_status: "ocr_in_progress",
        shell_invoice_status_subtype: nil
      )
        sync_run_invoice_status!(
          run: run,
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status,
          status_subtype: shell_invoice_status_subtype
        )
        run.update!(
          status: "running",
          total_files: total_files,
          completed_files: 0,
          failed_files: 0,
          failure_status: nil,
          failure_status_subtype: nil,
          pipeline_error_code: nil,
          pipeline_error_description: nil,
          completed_at: nil,
          updated_at: Time.current
        )
      end

      def update_failed!(
        run:,
        total_files:,
        failed_files:,
        fallback_error_code:,
        shell_invoice_id: nil,
        shell_invoice_status: "technical_failure",
        shell_invoice_status_subtype: nil
      )
        sync_run_invoice_status!(
          run: run,
          shell_invoice_id: shell_invoice_id,
          status: shell_invoice_status,
          status_subtype: shell_invoice_status_subtype
        )
        failed_steps =
          ::Claims::IngestStepRun
            .where(ingest_run_id: run.id, status: "failed")
            .order(created_at: :asc, id: :asc)
            .to_a
        failed_step =
          ::Claims::Invoices::FailureSubtypes.primary_failed_step(failed_steps)
        analytics =
          ::Claims::Invoices::FailureSubtypes.analytics_from_step(failed_step)
        attempt_count =
          failed_step.present? ? same_target_step_attempts(failed_step) : nil
        pipeline_error_code =
          analytics["error_code"].presence || fallback_error_code
        run.update!(
          status: "failed",
          total_files: total_files,
          completed_files: 0,
          failed_files: [failed_files, 0].max,
          failure_status: shell_invoice_status,
          failure_status_subtype: shell_invoice_status_subtype,
          pipeline_error_code: pipeline_error_code,
          pipeline_error_description:
            pipeline_error_description(
              step: failed_step,
              analytics: analytics,
              attempt_count: attempt_count,
              fallback_code: pipeline_error_code
            ),
          completed_at: Time.current,
          updated_at: Time.current
        )
        cleanup_failed_contractor_upload!(run)
      end

      def pipeline_error_description(
        step:,
        analytics:,
        attempt_count:,
        fallback_code:
      )
        return fallback_code.to_s.humanize if step.blank?

        code = analytics["error_code"].presence || fallback_code
        parts = ["#{step.step_type} failed"]
        parts << code if code.present?
        if analytics["provider_status"].present?
          parts << "provider HTTP #{analytics["provider_status"]}"
        end
        parts << "non-retryable" if analytics["retryable"] == false
        if analytics["diagnostic_id"].present?
          parts << "diagnostic #{analytics["diagnostic_id"]}"
        end
        provider_attempts = analytics["provider_attempt_count"].to_i
        if provider_attempts > 1
          parts << "#{provider_attempts} provider attempts"
        elsif attempt_count.to_i > 1 && step_target_present?(step)
          parts << "#{attempt_count} step attempts"
        end

        "#{parts.join("; ")}."
      end

      def step_target_present?(step)
        step.ingest_document_id.present? || step.invoice_version_id.present? ||
          step.supporting_document_type_id.present? ||
          step.invoice_upgrade_type_id.present?
      end

      def sync_shell_invoice_status!(
        shell_invoice_id:,
        status:,
        status_subtype: nil
      )
        return if shell_invoice_id.blank? || status.blank?

        invoice = ::Claims::Invoice.find_by(id: shell_invoice_id)
        return if invoice.nil?

        subtype =
          ::Claims::Invoices::StatusSubtypes.normalize(status, status_subtype)
        return if invoice.status == status && invoice.status_subtype == subtype

        invoice.set_workflow_status!(status, status_subtype: status_subtype)
      rescue StandardError
        nil
      end

      def sync_run_invoice_status!(
        run:,
        shell_invoice_id:,
        status:,
        status_subtype: nil
      )
        return if fix_run?(run) && run.resolved_invoice_version_id.blank?

        sync_shell_invoice_status!(
          shell_invoice_id: shell_invoice_id,
          status: status,
          status_subtype: status_subtype
        )
      end

      def running_shell_invoice_status_for(resolved_invoice_status:)
        status = resolved_invoice_status.to_s
        return "genai_in_progress" if status.blank?
        if %w[genai_queued genai_in_progress genai_complete].include?(status)
          return status
        end

        "genai_in_progress"
      end

      def cleanup_failed_contractor_upload!(run)
        return unless run.cleanup_failed_invoice_artifacts
        return if run.contractor_id.blank?
        if ::Claims::IngestStepRun.where(
             ingest_run_id: run.id,
             status: "in_progress"
           ).exists?
          return
        end

        ::Claims::Ingest::CleanupFailedContractorUpload.call(ingest_run: run)
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][advance_bundle_run] cleanup failed ingest_run_id=#{run.id}: #{e.class}: #{e.message}"
        )
      end
    end
  end
end
