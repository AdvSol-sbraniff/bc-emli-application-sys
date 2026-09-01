# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceBundleRun
      BUNDLE_INVALID_ERROR_CODE = "invoice_bundle_count_invalid"
      BUNDLE_UNKNOWN_ERROR_CODE = "invoice_bundle_unknown_documents"
      BUNDLE_NO_SUPPORTED_UPGRADE_ERROR_CODE =
        "invoice_bundle_no_supported_upgrade_type"

      Context =
        Struct.new(
          :run,
          :documents,
          :total_files,
          :resolved_document,
          :resolved_invoice_version_id,
          keyword_init: true
        )

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        context = load_context
        return unless context
        if ::Claims::Ingest::RunTransition::TERMINAL_STATUSES.include?(
             context.run.status
           )
          ::Claims::Ingest::RunTransition.reconcile_terminal_cleanup!(
            run: context.run
          )
          return
        end

        return unless advance_document_read(context)
        return unless advance_classification(context)
        return unless resolve_invoice(context)
        return unless advance_extractions(context)
        return unless advance_validation(context)

        complete_run(context)
      end

      private

      def load_context
        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return if run.nil?

        documents =
          ::Claims::IngestDocument.where(ingest_run_id: run.id).order(
            created_at: :asc
          )
        document_ids = documents.pluck(:id)
        total_files = run.total_files.to_i
        total_files = document_ids.size if total_files <= 0

        Context.new(run: run, documents: documents, total_files: total_files)
      end

      def advance_document_read(context)
        read_documents =
          documents_requiring_read(
            run: context.run,
            documents: context.documents
          )
        read_document_ids = read_documents.map(&:id)
        read_steps =
          latest_document_steps_map(
            context.run.id,
            read_document_ids,
            "read_document"
          )
        return wait_for_work!(context) if read_steps.size < read_documents.size

        failed = read_steps.values.find { |row| row.status == "failed" }
        if failed.nil? &&
             read_steps.values.all? { |row| row.status == "succeeded" }
          return true
        end
        if failed.nil? || step_failure_retry_pending?(failed)
          return wait_for_work!(context)
        end

        fail_context!(
          context,
          failed_step: failed,
          failure_category: "technical_failure",
          fallback_subtype: "ocr_unexpected_exception",
          fallback_code: "bundle_read_ocr_failed"
        )
      end

      def advance_classification(context)
        documents =
          documents_requiring_classifier(
            run: context.run,
            documents: context.documents
          )
        steps = latest_classifier_steps_map(context.run.id, documents)
        missing = documents.reject { |document| steps.key?(document.id) }
        if missing.any?
          enqueue_classifier_jobs!(
            documents: missing,
            step_type: "classify_document"
          )
          return wait_for_work!(context)
        end

        failed = steps.values.find { |row| row.status == "failed" }
        if failed.nil? && steps.values.all? { |row| row.status == "succeeded" }
          return true
        end
        if failed.nil? || step_failure_retry_pending?(failed)
          return wait_for_work!(context)
        end

        fail_context!(
          context,
          failed_step: failed,
          failure_category:
            failure_category_from_step(failed, fallback: "technical_failure"),
          fallback_subtype: "genai_unexpected_exception",
          fallback_code: "bundle_triage_failed"
        )
      end

      def resolve_invoice(context)
        unknown =
          context.documents.select { |doc| doc.document_kind == "unknown" }
        if unknown.any?
          return(
            fail_context!(
              context,
              failed_files: unknown.size,
              failure_category: "package_needs_correction",
              fallback_subtype: "package_invoice_classification_conflict",
              fallback_code: BUNDLE_UNKNOWN_ERROR_CODE
            )
          )
        end

        invoice_docs =
          context.documents.select { |doc| doc.document_kind == "invoice" }
        if invoice_docs.size != 1
          subtype =
            (
              if invoice_docs.empty?
                "package_no_invoice_pdf"
              else
                "package_multiple_invoice_pdfs"
              end
            )
          return(
            fail_context!(
              context,
              failed_files: [invoice_docs.size, 1].max,
              failure_category: "package_needs_correction",
              fallback_subtype: subtype,
              fallback_code: BUNDLE_INVALID_ERROR_CODE
            )
          )
        end

        non_pdf = invoice_docs.reject { |document| pdf_document?(document) }
        if non_pdf.any?
          return(
            fail_context!(
              context,
              failed_files: non_pdf.size,
              failure_category: "package_needs_correction",
              fallback_subtype: "package_invoice_not_pdf",
              fallback_code: BUNDLE_INVALID_ERROR_CODE
            )
          )
        end

        context.resolved_document = invoice_docs.first
        if fix_upload?(context.run)
          context.resolved_invoice_version_id =
            context.run.resolved_invoice_version_id.presence
          if context.resolved_invoice_version_id.blank?
            scope_guard =
              ::Claims::Ingest::FixUpgradeTypeScopeGuard.call(
                ingest_run: context.run,
                replacement_document: context.resolved_document
              )
            return false if scope_guard.changed

            unless fix_document_has_supported_upgrade_type?(
                     run: context.run,
                     document: context.resolved_document
                   )
              return fail_unsupported_upgrade!(context)
            end

            context.resolved_invoice_version_id =
              ::Claims::Ingest::PromoteFixPackage.call(
                ingest_run: context.run,
                resolved_document: context.resolved_document
              )
          end
        else
          context.resolved_invoice_version_id =
            ensure_resolved_invoice!(
              run: context.run,
              resolved_document: context.resolved_document
            )
          mark_run_resolved_invoice_version!(
            run: context.run,
            resolved_invoice_version_id: context.resolved_invoice_version_id
          )
        end

        unless supported_upgrade_type_detected?(
                 context.resolved_invoice_version_id
               )
          return fail_unsupported_upgrade!(context)
        end
        mark_run_resolved_invoice_version!(
          run: context.run,
          resolved_invoice_version_id: context.resolved_invoice_version_id
        )
        if fix_upload?(context.run)
          mark_clone_existing_evidence_succeeded!(
            run: context.run,
            documents: context.documents.reload
          )
        end
        true
      end

      def advance_extractions(context)
        supporting_state = advance_supporting_extraction(context)
        return false if supporting_state == :failed

        invoice_state = advance_invoice_ocr(context)
        return false if invoice_state == :failed

        if supporting_state == :succeeded && invoice_state == :succeeded
          return true
        end

        wait_for_work!(context)
      end

      def advance_supporting_extraction(context)
        documents =
          context.documents.select do |doc|
            doc.document_kind == "supporting_document"
          end
        documents.each do |document|
          ::Claims::SupportingDocuments::CreateOrUpdateFromIngestDocument.call(
            resolved_invoice_version_id: context.resolved_invoice_version_id,
            ingest_document_id: document.id
          )
        end
        type_ids =
          supporting_document_type_ids_requiring_extraction(
            run: context.run,
            supporting_document_rows: documents
          )
        steps =
          latest_type_steps_map(
            context.run.id,
            context.resolved_invoice_version_id,
            type_ids,
            "extract_supporting_document"
          )
        missing = type_ids.reject { |type_id| steps.key?(type_id) }
        if missing.any?
          enqueue_extract_supporting_document_jobs!(
            invoice_version_id: context.resolved_invoice_version_id,
            supporting_document_type_ids: missing,
            step_type: "extract_supporting_document"
          )
          return :waiting
        end
        return :waiting if steps.size < type_ids.size

        failed = steps.values.find { |row| row.status == "failed" }
        if failed.nil? && steps.values.all? { |row| row.status == "succeeded" }
          return :succeeded
        end
        return :waiting if failed.nil? || step_failure_retry_pending?(failed)

        fail_context!(
          context,
          failed_step: failed,
          failure_category:
            failure_category_from_step(failed, fallback: "technical_failure"),
          fallback_subtype: "genai_unexpected_exception",
          fallback_code: "bundle_extract_supporting_document_failed"
        )
        :failed
      end

      def advance_invoice_ocr(context)
        step =
          latest_invoice_step(
            context.run.id,
            context.resolved_invoice_version_id,
            "extract_invoice"
          )
        reused =
          step.nil? &&
            invoice_ocr_satisfied_by_cloned_evidence?(
              run: context.run,
              invoice_version_id: context.resolved_invoice_version_id,
              step_type: "extract_invoice"
            )
        if step.nil? && !reused
          enqueue_invoice_finalize_ocr!(
            invoice_version_id: context.resolved_invoice_version_id,
            step_type: "extract_invoice"
          )
          return :waiting
        end
        return :succeeded if reused || step&.status == "succeeded"
        if step.nil? || step.status != "failed" ||
             step_failure_retry_pending?(step)
          return :waiting
        end

        fail_context!(
          context,
          failed_step: step,
          failure_category: "technical_failure",
          fallback_subtype: "ocr_unexpected_exception",
          fallback_code: "bundle_invoice_ocr_failed"
        )
        :failed
      end

      def advance_validation(context)
        invoice_version =
          ::Claims::InvoiceVersion.find(context.resolved_invoice_version_id)
        validation =
          ::Claims::Ingest::ValidationOutcome.call(
            ingest_run_id: context.run.id,
            invoice_version_id: invoice_version.id
          )
        if validation.missing?
          ::Claims::Ingest::ValidationScheduler.start!(
            run: context.run,
            invoice_version: invoice_version
          )
          return wait_for_work!(context)
        end
        if validation.failed?
          status =
            failure_category_from_step(
              validation.failed_step,
              fallback: "technical_failure"
            )
          subtype =
            (
              if status == "package_needs_correction"
                "package_invoice_classification_conflict"
              else
                "genai_unexpected_exception"
              end
            )
          return(
            fail_context!(
              context,
              failed_step: validation.failed_step,
              failure_category: status,
              fallback_subtype: subtype,
              fallback_code: "bundle_invoice_genai_failed"
            )
          )
        end
        if validation.ready_to_finalize?
          ::Claims::Ingest::ValidationScheduler.finalize!(
            run: context.run,
            invoice_version: invoice_version
          )
        end
        return true if validation.succeeded?

        wait_for_work!(context)
      end

      def complete_run(context)
        ::Claims::Ingest::RunTransition.mark_succeeded!(
          run: context.run,
          total_files: context.total_files
        )
      end

      def wait_for_work!(context)
        update_running!(run: context.run, total_files: context.total_files)
        false
      end

      def fail_context!(
        context,
        failed_step: nil,
        failed_files: 1,
        failure_category:,
        fallback_subtype:,
        fallback_code:
      )
        subtype =
          failure_subtype_from_step(failed_step, fallback: fallback_subtype)
        update_failed!(
          run: context.run,
          total_files: context.total_files,
          failed_files: failed_files,
          failure_category: failure_category,
          failure_code: subtype,
          fallback_error_code: fallback_code
        )
        false
      end

      def fail_unsupported_upgrade!(context)
        fail_context!(
          context,
          failure_category: "package_needs_correction",
          fallback_subtype: "package_no_supported_upgrade_type",
          fallback_code: BUNDLE_NO_SUPPORTED_UPGRADE_ERROR_CODE
        )
      end

      def fix_upload?(run)
        run.run_kind == "fix_upload"
      end

      def documents_requiring_read(run:, documents:)
        return documents.to_a unless fix_upload?(run)

        documents.reject { |document| reused_ingest_document?(document) }
      end

      def documents_requiring_classifier(run:, documents:)
        return documents.to_a unless fix_upload?(run)

        documents.reject { |document| reused_ingest_document?(document) }
      end

      def reused_ingest_document?(document)
        document.document_kind_reason.to_s.start_with?("Cloned from prior")
      end

      def mark_clone_existing_evidence_succeeded!(run:, documents:)
        step =
          ::Claims::IngestStepRun
            .where(ingest_run_id: run.id, step_type: "clone_evidence")
            .order(created_at: :asc, id: :asc)
            .first
        step ||=
          ::Claims::IngestStepRun.create!(
            ingest_run_id: run.id,
            session_id: run.session_id,
            invoice_version_id:
              documents.map(&:resolved_invoice_version_id).compact.first,
            step_type: "clone_evidence",
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
        return false unless step_type == "extract_invoice"

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
          .transform_values do |steps|
            ::Claims::Ingest::StepOutcome.for_attempts(steps).effective_step
          end
      end

      def latest_invoice_step(ingest_run_id, invoice_version_id, step_type)
        ::Claims::Ingest::StepOutcome.for_attempts(
          ::Claims::IngestStepRun.where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type
          ).to_a
        ).effective_step
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
          .transform_values do |steps|
            ::Claims::Ingest::StepOutcome.for_attempts(steps).effective_step
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
            @ingest_run_id
          )
        end
      end

      def enqueue_extract_supporting_document_jobs!(
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
            @ingest_run_id
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
          if fix_upload?(run)
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
        ::Claims::Ingest::StepOutcome.for_attempts(steps).effective_step
      end

      def classifier_step_types_for_lookup
        %w[classify_document]
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

        ::Claims::RunOcrJob.perform_async(invoice_version_id, @ingest_run_id)
      end

      def supported_upgrade_type_detected?(invoice_version_id)
        ::Claims::InvoiceVersionUpgradeType
          .joins(
            "INNER JOIN claims.invoice_upgrade_types iut " \
              "ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
          )
          .where(invoice_version_id: invoice_version_id)
          .where.not("iut.upgrade_type_key" => "common")
          .exists?
      end

      def fix_document_has_supported_upgrade_type?(run:, document:)
        if reused_ingest_document?(document)
          source =
            ::Claims::Ingest::FixPackageContext.new(
              ingest_run: run
            ).source_invoice_version
          return supported_upgrade_type_detected?(source.id)
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

      def failure_subtype_from_step(step, fallback:)
        ::Claims::Ingest::FailureClassifier.from_step(step, fallback: fallback)
      end

      def failure_category_from_step(step, fallback:)
        ::Claims::Ingest::FailureClassifier.category_from_step(
          step,
          fallback: fallback
        )
      end

      def step_failure_retry_pending?(step)
        ::Claims::Ingest::StepOutcome.for_step(step).retrying?
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

      def update_running!(run:, total_files:)
        ::Claims::Ingest::RunTransition.mark_running!(
          run: run,
          total_files: total_files
        )
      end

      def update_failed!(
        run:,
        total_files:,
        failed_files:,
        fallback_error_code:,
        failure_category:,
        failure_code:
      )
        failed_steps =
          ::Claims::IngestStepRun
            .where(ingest_run_id: run.id, status: "failed")
            .order(created_at: :asc, id: :asc)
            .to_a
        failed_step =
          ::Claims::Ingest::FailureClassifier.primary_failed_step(failed_steps)
        analytics =
          ::Claims::Ingest::FailureClassifier.analytics_from_step(failed_step)
        attempt_count =
          failed_step.present? ? same_target_step_attempts(failed_step) : nil
        pipeline_error_code =
          analytics["error_code"].presence || fallback_error_code
        ::Claims::Ingest::RunTransition.mark_failed!(
          run: run,
          total_files: total_files,
          failed_files: [failed_files, 0].max,
          failure_category: failure_category,
          failure_code: failure_code,
          pipeline_error_code: pipeline_error_code,
          pipeline_error_description:
            pipeline_error_description(
              step: failed_step,
              analytics: analytics,
              attempt_count: attempt_count,
              fallback_code: pipeline_error_code
            )
        )
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
    end
  end
end
