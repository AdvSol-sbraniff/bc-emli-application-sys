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

      PIPELINE_KIND_BY_RUN_KIND = {
        "initial_upload" => "new_upload",
        "fix_upload" => "fix",
        "rules_rerun" => "rule_change_only"
      }.freeze

      ALLOWED_STEPS_BY_RUN_KIND = {
        "initial_upload" => %w[
          stage_package
          read_document
          classify_document
          extract_supporting_document
          extract_invoice
          case_facts
          evaluate_genai_ruleset
          evaluate_code_ruleset
          finalize_validation
        ],
        "fix_upload" => %w[
          stage_package
          read_document
          classify_document
          extract_supporting_document
          extract_invoice
          clone_evidence
          case_facts
          evaluate_genai_ruleset
          evaluate_code_ruleset
          finalize_validation
        ],
        "rules_rerun" => %w[
          clone_evidence
          case_facts
          evaluate_genai_ruleset
          evaluate_code_ruleset
          finalize_validation
        ]
      }.transform_values(&:freeze).freeze

      PRE_RESOLUTION_DOCUMENT_STEPS = %w[read_document classify_document].freeze

      PACKAGE_STEPS = %w[stage_package].freeze

      TYPE_STEPS = %w[extract_supporting_document].freeze

      RULESET_STEPS = %w[evaluate_genai_ruleset evaluate_code_ruleset].freeze

      REQUIRED_FINAL_STEPS = %w[case_facts finalize_validation].freeze

      FIX_REPROCESS_DOCUMENT_STEPS = %w[read_document classify_document].freeze

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

        resolved_invoice_failure || wrong_invoice_failure ||
          target_shape_failure || branch_purity_failure ||
          active_step_failure || final_step_failure || fix_reuse_failure ||
          rule_change_shape_failure
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

          if RULESET_STEPS.include?(step.step_type)
            if step.invoice_version_id.present? &&
                 step.invoice_upgrade_type_id.present? &&
                 step.ingest_document_id.blank? &&
                 step.supporting_document_type_id.blank?
              next
            end

            return(
              failure(
                "ruleset_step_target_invalid",
                "#{step.step_type} should target an invoice version and upgrade type only. #{describe_step(step)}"
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
        allowed = ALLOWED_STEPS_BY_RUN_KIND.fetch(@run.run_kind)
        bad_step = @steps.find { |step| !allowed.include?(step.step_type) }
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
             @steps.any? { |step| step.step_type == "extract_invoice" }
          return(
            failure(
              "extract_invoice_for_cloned_invoice",
              "Fix run cloned invoice evidence, so no extract_invoice work row should exist. cloned_ingest_document_id=#{cloned_invoice.id}, ingest_run_id=#{@run.id}."
            )
          )
        end

        bad_type_step =
          @steps.find do |step|
            step.step_type == "extract_supporting_document" &&
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
          step = latest_invoice_step("extract_invoice")
          return nil if step&.status == "succeeded"

          return(
            failure(
              "fix_new_invoice_missing_extract_invoice",
              "Fix run has a new/replaced invoice document but latest extract_invoice is not succeeded. Found: #{step ? describe_step(step) : "no step row"}."
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

      def pipeline_kind
        PIPELINE_KIND_BY_RUN_KIND[@run&.run_kind]
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
