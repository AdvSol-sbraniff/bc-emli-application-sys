# frozen_string_literal: true

module Claims
  module Ingest
    class ValidationScheduler
      def self.start!(run:, invoice_version:)
        queued = false
        invoice_version.with_lock do
          outcome =
            ::Claims::Ingest::ValidationOutcome.call(
              ingest_run_id: run.id,
              invoice_version_id: invoice_version.id
            )
          next unless outcome.missing?

          ::Claims::IngestStepRun.create!(
            ingest_run_id: run.id,
            session_id: invoice_version.invoice.session_id,
            invoice_version_id: invoice_version.id,
            step_type: "case_facts",
            status: "queued",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )
          queued = true
        end
        return false unless queued

        ::Claims::RunGenaiJob.perform_async(
          invoice_version.invoice.session_id,
          invoice_version.id,
          run.id,
          "use_existing_classifier"
        )
      end

      def self.finalize!(run:, invoice_version:)
        queued = false
        invoice_version.with_lock do
          outcome =
            ::Claims::Ingest::ValidationOutcome.call(
              ingest_run_id: run.id,
              invoice_version_id: invoice_version.id
            )
          next unless outcome.ready_to_finalize?

          ::Claims::IngestStepRun.create!(
            ingest_run_id: run.id,
            session_id: invoice_version.invoice.session_id,
            invoice_version_id: invoice_version.id,
            step_type: "finalize_validation",
            status: "queued",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )
          queued = true
        end
        return false unless queued

        ::Claims::FinalizeGenaiValidationJob.perform_async(
          invoice_version.invoice.session_id,
          invoice_version.id,
          run.id
        )
      end
    end
  end
end
