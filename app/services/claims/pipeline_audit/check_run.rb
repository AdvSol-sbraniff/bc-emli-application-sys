# frozen_string_literal: true

module Claims
  module PipelineAudit
    class CheckRun
      Result =
        Struct.new(
          :ok,
          :error_code,
          :error_description,
          :pipeline_kind,
          keyword_init: true
        )

      Failure = Struct.new(:code, :description, keyword_init: true)

      BRANCH_ROOT_STEPS = {
        "upload_package_stage" => "new_upload",
        "fix_upload_package_stage" => "fix",
        "ruleclone_clone_existing_evidence" => "rule_change_only"
      }.freeze

      NEW_BRANCH_FORBIDDEN_STEPS = %w[
        fix_upload_package_stage
        fix_ocr_read
        fix_classifier_files
        fix_clone_existing_evidence
        fix_supporting_document_extraction
        fix_ocr_invoice
        ruleclone_clone_existing_evidence
      ].freeze

      FIX_BRANCH_FORBIDDEN_STEPS = %w[
        upload_package_stage
        ocr_read
        classifier_files
        supporting_document_extraction
        ocr_invoice
        ruleclone_clone_existing_evidence
      ].freeze

      RULE_CHANGE_FORBIDDEN_STEPS = %w[
        upload_package_stage
        fix_upload_package_stage
        ocr_read
        fix_ocr_read
        classifier_files
        fix_classifier_files
        supporting_document_extraction
        fix_supporting_document_extraction
        ocr_invoice
        fix_ocr_invoice
        fix_clone_existing_evidence
      ].freeze

      PRE_RESOLUTION_DOCUMENT_STEPS = %w[
        ocr_read
        fix_ocr_read
        classifier_files
        fix_classifier_files
      ].freeze

      PACKAGE_STEPS = %w[upload_package_stage fix_upload_package_stage].freeze

      TYPE_STEPS = %w[
        supporting_document_extraction
        fix_supporting_document_extraction
      ].freeze

      REQUIRED_FINAL_STEPS = %w[case_facts aggregate_advice].freeze

      FIX_REPROCESS_DOCUMENT_STEPS = %w[
        fix_ocr_read
        fix_classifier_files
      ].freeze

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id.to_s.strip
      end

      def call
        return missing_run_result if @ingest_run_id.empty?

        @run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return missing_run_result unless @run

        @steps =
          ::Claims::IngestStepRun
            .where(ingest_run_id: @run.id)
            .order(created_at: :asc, id: :asc)
            .to_a
        @documents = ::Claims::IngestDocument.where(ingest_run_id: @run.id).to_a

        failure = first_failure
        persist_result!(failure)
        Result.new(
          ok: failure.nil?,
          error_code: failure&.code,
          error_description: failure&.description,
          pipeline_kind: pipeline_kind
        )
      rescue => e
        failure =
          Failure.new(
            code: "pipeline_checker_runtime_error",
            description:
              "Pipeline checker crashed for ingest_run_id=#{@ingest_run_id}: #{e.class}: #{e.message}"
          )
        persist_result!(failure) if @run
        Rails.logger.error(
          "[claims][pipeline_audit] #{failure.description}\n#{e.backtrace&.take(8)&.join("\n")}"
        )
        Result.new(
          ok: false,
          error_code: failure.code,
          error_description: failure.description,
          pipeline_kind: pipeline_kind
        )
      end

      private

      def first_failure
        if @steps.empty?
          return(
            failure(
              "pipeline_no_step_runs",
              "No ingest_step_runs exist for ingest_run_id=#{@run.id}."
            )
          )
        end

        branch_failure || resolved_invoice_failure || wrong_invoice_failure ||
          target_shape_failure || branch_purity_failure ||
          active_step_failure || final_step_failure || fix_reuse_failure ||
          rule_change_shape_failure
      end

      def branch_failure
        roots = present_branch_roots
        if roots.empty?
          return(
            failure(
              "pipeline_kind_unknown",
              "Could not classify ingest_run_id=#{@run.id}; expected one root step from #{BRANCH_ROOT_STEPS.keys.join(", ")}."
            )
          )
        end
        return nil if roots.one?

        failure(
          "pipeline_kind_ambiguous",
          "ingest_run_id=#{@run.id} has multiple pipeline root steps: #{roots.join(", ")}."
        )
      end

      def resolved_invoice_failure
        return nil if @run.resolved_invoice_version_id.present?

        failure(
          "resolved_invoice_version_missing",
          "ingest_run_id=#{@run.id} completed without resolved_invoice_version_id; pipeline_kind=#{pipeline_kind || "unknown"}."
        )
      end

      def wrong_invoice_failure
        return nil if @run.resolved_invoice_version_id.blank?

        wrong_steps =
          @steps.select do |step|
            step.invoice_version_id.present? &&
              step.invoice_version_id.to_s !=
                @run.resolved_invoice_version_id.to_s
          end
        return nil if wrong_steps.empty?

        failure(
          "step_targets_wrong_invoice_version",
          "ingest_run_id=#{@run.id} resolved_invoice_version_id=#{@run.resolved_invoice_version_id}, but #{wrong_steps.size} step row(s) target another invoice version. First: #{describe_step(wrong_steps.first)}."
        )
      end

      def target_shape_failure
        @steps.each do |step|
          if PACKAGE_STEPS.include?(step.step_type)
            if step.invoice_version_id.blank? &&
                 step.ingest_document_id.blank? &&
                 step.supporting_document_type_id.blank?
              next
            end

            return(
              failure(
                "package_step_has_target",
                "#{step.step_type} should be a package/run row with no document or invoice target. #{describe_step(step)}"
              )
            )
          end

          if PRE_RESOLUTION_DOCUMENT_STEPS.include?(step.step_type)
            if step.ingest_document_id.present? &&
                 step.invoice_version_id.blank? &&
                 step.supporting_document_type_id.blank?
              next
            end

            return(
              failure(
                "document_step_target_invalid",
                "#{step.step_type} should target exactly one ingest_document and no invoice/type target. #{describe_step(step)}"
              )
            )
          end

          if TYPE_STEPS.include?(step.step_type)
            if step.invoice_version_id.present? &&
                 step.supporting_document_type_id.present? &&
                 step.ingest_document_id.blank?
              next
            end

            return(
              failure(
                "type_step_target_invalid",
                "#{step.step_type} should target invoice_version_id plus supporting_document_type_id only. #{describe_step(step)}"
              )
            )
          end

          if step.invoice_version_id.present? &&
               step.ingest_document_id.blank? &&
               step.supporting_document_type_id.blank?
            next
          end

          return(
            failure(
              "invoice_step_target_invalid",
              "#{step.step_type} should target exactly one invoice_version and no ingest_document/type target. #{describe_step(step)}"
            )
          )
        end

        nil
      end

      def branch_purity_failure
        forbidden =
          case pipeline_kind
          when "new_upload"
            NEW_BRANCH_FORBIDDEN_STEPS
          when "fix"
            FIX_BRANCH_FORBIDDEN_STEPS
          when "rule_change_only"
            RULE_CHANGE_FORBIDDEN_STEPS
          else
            []
          end
        bad_step = @steps.find { |step| forbidden.include?(step.step_type) }
        return nil unless bad_step

        failure(
          "wrong_step_for_pipeline_kind",
          "ingest_run_id=#{@run.id} is pipeline_kind=#{pipeline_kind}, but contains forbidden step #{describe_step(bad_step)}."
        )
      end

      def active_step_failure
        return nil unless @run.status == "succeeded"

        active_step =
          @steps.find { |step| %w[queued in_progress].include?(step.status) }
        return nil unless active_step

        failure(
          "succeeded_run_has_active_step",
          "ingest_run_id=#{@run.id} is succeeded, but still has active step #{describe_step(active_step)}."
        )
      end

      def final_step_failure
        return nil if @run.resolved_invoice_version_id.blank?

        REQUIRED_FINAL_STEPS.each do |step_type|
          step = latest_invoice_step(step_type)
          next if step&.status == "succeeded"

          return(
            failure(
              "final_step_missing_or_not_succeeded",
              "ingest_run_id=#{@run.id} resolved_invoice_version_id=#{@run.resolved_invoice_version_id} expected latest #{step_type} to be succeeded. Found: #{step ? describe_step(step) : "no step row"}."
            )
          )
        end

        nil
      end

      def fix_reuse_failure
        return nil unless pipeline_kind == "fix"

        cloned_document_ids = cloned_documents.map(&:id).map(&:to_s)
        bad_doc_step =
          @steps.find do |step|
            FIX_REPROCESS_DOCUMENT_STEPS.include?(step.step_type) &&
              cloned_document_ids.include?(step.ingest_document_id.to_s)
          end
        if bad_doc_step
          return(
            failure(
              "fix_reprocessed_cloned_document",
              "Fix run should not OCR/classify cloned documents. Bad step: #{describe_step(bad_doc_step)}."
            )
          )
        end

        cloned_invoice =
          cloned_documents.find { |doc| doc.document_kind == "invoice" }
        if cloned_invoice &&
             @steps.any? { |step| step.step_type == "fix_ocr_invoice" }
          return(
            failure(
              "fix_ocr_invoice_for_cloned_invoice",
              "Fix run cloned invoice evidence, so no fix_ocr_invoice work row should exist. cloned_ingest_document_id=#{cloned_invoice.id}, ingest_run_id=#{@run.id}."
            )
          )
        end

        bad_type_step =
          @steps.find do |step|
            step.step_type == "fix_supporting_document_extraction" &&
              !changed_supporting_document_type_ids.include?(
                step.supporting_document_type_id.to_s
              )
          end
        if bad_type_step
          return(
            failure(
              "fix_extracted_cloned_only_support_type",
              "Fix support extraction should only run for support-doc types affected by new/replaced support docs. Bad step: #{describe_step(bad_type_step)}."
            )
          )
        end

        new_invoice_present =
          @documents.any? do |doc|
            doc.document_kind == "invoice" && !cloned_document?(doc)
          end
        if new_invoice_present
          step = latest_invoice_step("fix_ocr_invoice")
          return nil if step&.status == "succeeded"

          return(
            failure(
              "fix_new_invoice_missing_ocr_invoice",
              "Fix run has a new/replaced invoice document but latest fix_ocr_invoice is not succeeded. Found: #{step ? describe_step(step) : "no step row"}."
            )
          )
        end

        nil
      end

      def rule_change_shape_failure
        return nil unless pipeline_kind == "rule_change_only"
        return nil if @documents.empty?

        failure(
          "rule_change_run_has_ingest_documents",
          "Rule-change-only run should clone evidence directly and should not create ingest_documents. ingest_run_id=#{@run.id}, ingest_document_count=#{@documents.size}."
        )
      end

      def present_branch_roots
        return [] unless @steps

        @present_branch_roots ||=
          BRANCH_ROOT_STEPS.keys.select do |step_type|
            @steps.any? { |step| step.step_type == step_type }
          end
      end

      def pipeline_kind
        roots = present_branch_roots
        return nil unless roots.one?

        BRANCH_ROOT_STEPS.fetch(roots.first)
      end

      def latest_invoice_step(step_type)
        @steps
          .select do |step|
            step.step_type == step_type &&
              step.invoice_version_id.to_s ==
                @run.resolved_invoice_version_id.to_s
          end
          .max_by { |step| [step.created_at || Time.zone.at(0), step.id] }
      end

      def cloned_documents
        @cloned_documents ||= @documents.select { |doc| cloned_document?(doc) }
      end

      def cloned_document?(document)
        document.document_kind_reason.to_s.start_with?("Cloned from prior")
      end

      def changed_supporting_document_type_ids
        @changed_supporting_document_type_ids ||=
          @documents
            .select do |doc|
              doc.document_kind == "supporting_document" &&
                doc.supporting_document_type_id.present? &&
                !cloned_document?(doc)
            end
            .map { |doc| doc.supporting_document_type_id.to_s }
            .uniq
      end

      def describe_step(step)
        document =
          if step.ingest_document_id.present?
            @documents.find do |doc|
              doc.id.to_s == step.ingest_document_id.to_s
            end
          end
        filename = document&.original_filename
        [
          "step_id=#{step.id}",
          "step_type=#{step.step_type}",
          "status=#{step.status}",
          "invoice_version_id=#{step.invoice_version_id || "-"}",
          "ingest_document_id=#{step.ingest_document_id || "-"}",
          "supporting_document_type_id=#{step.supporting_document_type_id || "-"}",
          ("filename=#{filename}" if filename.present?)
        ].compact.join(", ")
      end

      def failure(code, description)
        Failure.new(code: code, description: description)
      end

      def persist_result!(failure)
        @run.update!(
          pipeline_error_code: failure&.code,
          pipeline_error_description: failure&.description,
          updated_at: Time.current
        )
      end

      def missing_run_result
        Result.new(
          ok: false,
          error_code: "pipeline_run_not_found",
          error_description:
            "Pipeline checker could not find ingest_run_id=#{@ingest_run_id}.",
          pipeline_kind: nil
        )
      end
    end
  end
end
