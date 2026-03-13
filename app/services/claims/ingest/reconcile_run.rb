# frozen_string_literal: true

module Claims
  module Ingest
    class ReconcileRun
      TERMINAL_STATUSES = %w[succeeded failed partial].freeze

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

        invoice_version_ids = ::Claims::IngestStepRun
          .where(ingest_run_id: run.id)
          .distinct
          .pluck(:invoice_version_id)

        total_files = run.total_files.to_i
        total_files = invoice_version_ids.size if total_files <= 0

        succeeded = 0
        failed = 0
        running = 0

        invoice_version_ids.each do |invoice_version_id|
          ocr = latest_step(run.id, invoice_version_id, "ocr")
          genai = latest_step(run.id, invoice_version_id, "genai")

          if ocr.nil?
            running += 1
            next
          end

          if ocr.status == "failed"
            failed += 1
            next
          end

          if ocr.status != "succeeded"
            running += 1
            next
          end

          # OCR succeeded
          if genai.nil?
            running += 1
          elsif genai.status == "succeeded"
            succeeded += 1
          elsif genai.status == "failed"
            failed += 1
          else
            running += 1
          end
        end

        processed = succeeded + failed

        status = if total_files.positive? && processed >= total_files
          if failed.zero?
            "succeeded"
          elsif succeeded.zero?
            "failed"
          else
            "partial"
          end
        elsif processed.positive? || running.positive?
          "running"
        else
          "queued"
        end

        completed_at = TERMINAL_STATUSES.include?(status) ? Time.current : nil

        run.update!(
          status: status,
          total_files: total_files,
          completed_files: succeeded,
          failed_files: failed,
          completed_at: completed_at,
          updated_at: Time.current
        )
      end

      private

      def latest_step(ingest_run_id, invoice_version_id, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: step_type
          )
          .order(created_at: :desc)
          .first
      end
    end
  end
end
