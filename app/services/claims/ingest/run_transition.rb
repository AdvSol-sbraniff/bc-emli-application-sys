# frozen_string_literal: true

module Claims
  module Ingest
    class RunTransition
      TERMINAL_STATUSES = ::Claims::IngestRun::TERMINAL_STATUSES

      def self.mark_running!(run:, total_files:)
        changed = false
        run.with_lock do
          break if TERMINAL_STATUSES.include?(run.status)

          run.update!(
            status: "running",
            total_files: total_files,
            completed_files: 0,
            failed_files: 0,
            failure_category: nil,
            failure_code: nil,
            pipeline_error_code: nil,
            pipeline_error_description: nil,
            completed_at: nil,
            updated_at: Time.current
          )
          changed = true
        end
        changed
      end

      def self.mark_succeeded!(run:, total_files:)
        changed = false
        run.with_lock do
          break if TERMINAL_STATUSES.include?(run.status)

          run.update!(
            status: "succeeded",
            total_files: total_files,
            completed_files: total_files,
            failed_files: 0,
            failure_category: nil,
            failure_code: nil,
            pipeline_error_code: nil,
            pipeline_error_description: nil,
            completed_at: Time.current,
            updated_at: Time.current
          )
          changed = true
        end

        ::Claims::PipelineAudit::CheckRun.call(ingest_run_id: run.id) if changed
        changed
      end

      def self.mark_failed!(
        run:,
        total_files:,
        failed_files:,
        failure_category:,
        failure_code:,
        pipeline_error_code:,
        pipeline_error_description:
      )
        changed = false
        run.with_lock do
          break if TERMINAL_STATUSES.include?(run.status)

          run.update!(
            status: "failed",
            total_files: total_files,
            completed_files: 0,
            failed_files: [failed_files.to_i, 0].max,
            failure_category: failure_category,
            failure_code: failure_code,
            pipeline_error_code: pipeline_error_code,
            pipeline_error_description: pipeline_error_description,
            completed_at: Time.current,
            updated_at: Time.current
          )
          changed = true
        end

        cleanup_failed_contractor_upload!(run) if changed
        changed
      end

      def self.reconcile_terminal_cleanup!(run:)
        return false unless run.reload.status == "failed"

        cleanup_failed_contractor_upload!(run)
        true
      end

      def self.cleanup_failed_contractor_upload!(run)
        return unless run.cleanup_failed_invoice_artifacts
        return if run.contractor_id.blank?
        if ::Claims::IngestStepRun.where(
             ingest_run_id: run.id,
             status: %w[queued in_progress]
           ).exists?
          return
        end

        ::Claims::Ingest::CleanupFailedContractorUpload.call(ingest_run: run)
      rescue StandardError => e
        Rails.logger.error(
          "[claims][ingest][run_transition] cleanup failed " \
            "ingest_run_id=#{run.id}: #{e.class}: #{e.message}"
        )
      end
      private_class_method :cleanup_failed_contractor_upload!
    end
  end
end
