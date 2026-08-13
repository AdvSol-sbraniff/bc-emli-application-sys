# frozen_string_literal: true

module Claims
  module Ingest
    class ValidationOutcome
      Result =
        Struct.new(
          :state,
          :failed_step,
          :required_rulesets,
          keyword_init: true
        ) do
          def missing?
            state == :missing
          end

          def active?
            state == :active
          end

          def retrying?
            state == :retrying
          end

          def ready_to_finalize?
            state == :ready_to_finalize
          end

          def succeeded?
            state == :succeeded
          end

          def failed?
            state == :failed
          end
        end

      CODE_STEP_TYPES = %w[evaluate_code_ruleset].freeze

      def self.call(ingest_run_id:, invoice_version_id:)
        new(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id
        ).call
      end

      def initialize(ingest_run_id:, invoice_version_id:)
        @ingest_run_id = ingest_run_id
        @invoice_version_id = invoice_version_id
      end

      def call
        case_facts = outcome(step_type: "case_facts")
        return result(:missing) if case_facts.missing?
        if case_facts.retrying?
          return result(:retrying, failed_step: case_facts.effective_step)
        end
        if case_facts.failed?
          return result(:failed, failed_step: case_facts.effective_step)
        end
        return result(:active) unless case_facts.succeeded?

        code_outcomes = existing_code_outcomes
        failed_code = code_outcomes.find(&:failed?)
        if failed_code
          return result(:failed, failed_step: failed_code.effective_step)
        end

        retrying_code = code_outcomes.find(&:retrying?)
        if retrying_code
          return result(:retrying, failed_step: retrying_code.effective_step)
        end

        finalization = outcome(step_type: "finalize_validation")
        return result(:succeeded) if finalization.succeeded?
        if finalization.failed?
          return result(:failed, failed_step: finalization.effective_step)
        end
        if finalization.retrying?
          return result(:retrying, failed_step: finalization.effective_step)
        end

        return result(:active) if finalization.active?

        ruleset_outcomes =
          required_rulesets.map do |target|
            outcome(
              step_type: target.fetch(:step_type),
              invoice_upgrade_type_id: target.fetch(:invoice_upgrade_type_id)
            )
          end
        failed_ruleset = ruleset_outcomes.find(&:failed?)
        if failed_ruleset
          return result(:failed, failed_step: failed_ruleset.effective_step)
        end

        retrying_ruleset = ruleset_outcomes.find(&:retrying?)
        if retrying_ruleset
          return result(:retrying, failed_step: retrying_ruleset.effective_step)
        end
        return result(:active) unless ruleset_outcomes.all?(&:succeeded?)
        return result(:active) if code_outcomes.any?(&:active?)

        result(:ready_to_finalize)
      end

      def required_rulesets
        @required_rulesets ||=
          begin
            upgrade_types =
              ::Claims::InvoiceUpgradeType.where(
                id: classifier_upgrade_type_ids
              ).index_by(&:id)
            common =
              ::Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
            targets = [
              {
                step_type: "evaluate_genai_ruleset",
                invoice_upgrade_type_id: common.id
              }
            ]
            classifier_upgrade_type_ids.each do |upgrade_type_id|
              upgrade_type = upgrade_types[upgrade_type_id]
              if upgrade_type.nil? || upgrade_type.upgrade_type_key == "common"
                next
              end

              targets << {
                step_type: "evaluate_genai_ruleset",
                invoice_upgrade_type_id: upgrade_type.id
              }
            end
            targets.uniq
          end
      end

      private

      def classifier_upgrade_type_ids
        @classifier_upgrade_type_ids ||=
          ::Claims::InvoiceVersionUpgradeType
            .where(invoice_version_id: @invoice_version_id)
            .order(:created_at, :id)
            .pluck(:invoice_upgrade_type_id)
            .compact
            .uniq
      end

      def existing_code_outcomes
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: @ingest_run_id,
            invoice_version_id: @invoice_version_id,
            step_type: CODE_STEP_TYPES
          )
          .to_a
          .group_by { |step| [step.step_type, step.invoice_upgrade_type_id] }
          .values
          .map do |attempts|
            ::Claims::Ingest::StepOutcome.for_attempts(attempts)
          end
      end

      def outcome(step_type:, invoice_upgrade_type_id: nil)
        ::Claims::Ingest::StepOutcome.for_target(
          ingest_run_id: @ingest_run_id,
          invoice_version_id: @invoice_version_id,
          invoice_upgrade_type_id: invoice_upgrade_type_id,
          step_type: step_type
        )
      end

      def result(state, failed_step: nil)
        Result.new(
          state: state,
          failed_step: failed_step,
          required_rulesets: required_rulesets
        )
      end
    end
  end
end
