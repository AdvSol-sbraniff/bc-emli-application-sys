# frozen_string_literal: true

module Claims
  module Ingest
    class StepClaim
      TARGET_COLUMNS = ::Claims::Ingest::StepOutcome::TARGET_COLUMNS

      def self.call(ingest_run_id:, session_id:, step_type:, **target)
        attributes = {
          ingest_run_id: ingest_run_id,
          session_id: session_id,
          step_type: step_type
        }
        TARGET_COLUMNS.each { |column| attributes[column] = target[column] }

        2.times do
          outcome =
            ::Claims::Ingest::StepOutcome.for_target(
              ingest_run_id: ingest_run_id,
              step_type: step_type,
              **target.slice(*TARGET_COLUMNS)
            )
          if outcome.succeeded? || outcome.failed? ||
               outcome.active? && outcome.effective_step.status == "in_progress"
            return nil
          end

          step =
            (
              if outcome.active?
                outcome.effective_step
              else
                create_queued!(attributes)
              end
            )
          claimed = false
          step.with_lock do
            if step.status == "queued"
              step.update!(
                status: "in_progress",
                error_text: nil,
                completed_at: nil,
                updated_at: Time.current
              )
              claimed = true
            end
          end
          return step if claimed
        rescue ActiveRecord::RecordNotUnique
          next
        end

        nil
      end

      def self.create_queued!(attributes)
        ::Claims::IngestStepRun.create!(
          **attributes,
          status: "queued",
          error_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )
      end
      private_class_method :create_queued!
    end
  end
end
