# frozen_string_literal: true

module Claims
  module Ingest
    class StepOutcome
      Result =
        Struct.new(
          :state,
          :effective_step,
          :attempt_count,
          :attempt_limit,
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

          def succeeded?
            state == :succeeded
          end

          def failed?
            state == :failed
          end
        end

      TARGET_COLUMNS = %i[
        ingest_document_id
        invoice_version_id
        invoice_upgrade_type_id
        supporting_document_type_id
      ].freeze

      def self.for_step(step)
        return result(state: :missing, attempts: []) if step.nil?

        attributes = {
          ingest_run_id: step.ingest_run_id,
          step_type: step.step_type
        }
        TARGET_COLUMNS.each do |column|
          attributes[column] = step.public_send(column)
        end

        for_target(**attributes)
      end

      def self.for_target(ingest_run_id:, step_type:, **target)
        scope =
          ::Claims::IngestStepRun.where(
            ingest_run_id: ingest_run_id,
            step_type: step_type
          )
        TARGET_COLUMNS.each do |column|
          scope = scope.where(column => target[column])
        end

        for_attempts(scope.order(:created_at, :id).to_a)
      end

      def self.for_attempts(attempts)
        rows = Array(attempts).compact
        return result(state: :missing, attempts: rows) if rows.empty?

        succeeded = latest(rows.select { |row| row.status == "succeeded" })
        if succeeded
          return result(state: :succeeded, attempts: rows, step: succeeded)
        end

        active =
          latest(
            rows.select { |row| %w[queued in_progress].include?(row.status) }
          )
        return result(state: :active, attempts: rows, step: active) if active

        failed = latest(rows.select { |row| row.status == "failed" })
        return result(state: :missing, attempts: rows) if failed.nil?

        state =
          if ::Claims::Ingest::RetryPolicy.retry_pending?(
               attempt_count: rows.size,
               step: failed
             )
            :retrying
          else
            :failed
          end
        result(state: state, attempts: rows, step: failed)
      end

      def self.latest(rows)
        rows.max_by do |row|
          [row.updated_at || row.created_at, row.created_at, row.id.to_s]
        end
      end
      private_class_method :latest

      def self.result(state:, attempts:, step: nil)
        Result.new(
          state: state,
          effective_step: step,
          attempt_count: attempts.size,
          attempt_limit: ::Claims::Ingest::RetryPolicy::MAX_ATTEMPTS
        )
      end
      private_class_method :result
    end
  end
end
