# frozen_string_literal: true

module Claims
  module Ingest
    class ContractorRunPresenter
      def self.call(run:, contractor_id:)
        new(run: run, contractor_id: contractor_id).call
      end

      def initialize(run:, contractor_id:)
        @run = run
        @contractor_id = contractor_id
      end

      def call
        invoice_version, invoice = resolved_invoice_context
        ready = @run.status == "succeeded" && invoice_version.present?
        state, failure = lifecycle(ready: ready)

        {
          presentation_state: state,
          failure_category: failure[:failure_category],
          failure_code: failure[:failure_code],
          failure_message: failure[:failure_message],
          retry_guidance: failure[:retry_guidance],
          invoice_id: invoice&.id,
          invoice_status: invoice&.status,
          invoice_status_updated_at: invoice&.status_updated_at,
          invoice_version_id: invoice_version&.id,
          invoice_versionno: invoice_version&.invoice_versionno,
          original_filename: invoice_version&.original_filename,
          can_continue: state == "ready"
        }
      end

      private

      def resolved_invoice_context
        invoice = @run.invoice
        invoice = nil if invoice&.contractor_id.to_s != @contractor_id.to_s

        invoice_version =
          ::Claims::InvoiceVersion.includes(:invoice).find_by(
            id: @run.resolved_invoice_version_id
          )
        invoice_version = nil if invoice_version&.invoice_id != invoice&.id

        if invoice && invoice_version.nil?
          invoice_version =
            ::Claims::InvoiceVersion
              .where(invoice_id: invoice.id)
              .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
              .first
        end
        [invoice_version, invoice]
      end

      def lifecycle(ready:)
        return "processing", {} if %w[queued running].include?(@run.status)
        return "ready", {} if ready

        if @run.status == "failed"
          failure = terminal_failure
          state =
            if failure[:failure_category] == "package_needs_correction"
              "needs_correction"
            else
              "failed"
            end
          return state, failure
        end

        Rails.logger.error(
          "[claims][ingest][contractor_presenter] inconsistent terminal run " \
            "ingest_run_id=#{@run.id} status=#{@run.status.inspect}"
        )
        ["failed", safe_invariant_failure]
      end

      def terminal_failure
        status =
          @run.failure_category.to_s.strip.presence || "technical_failure"
        subtype =
          ::Claims::Ingest::FailureCatalog.normalize(
            status,
            @run.failure_code
          ).presence || "unknown_runtime_failure"
        failure_payload(status, subtype)
      end

      def safe_invariant_failure
        failure_payload("technical_failure", "unknown_runtime_failure")
      end

      def failure_payload(status, subtype)
        {
          failure_category: status,
          failure_code: subtype,
          failure_message:
            ::Claims::Ingest::FailureCatalog.contractor_failure_message(
              status,
              subtype
            ),
          retry_guidance:
            ::Claims::Ingest::FailureCatalog.retry_guidance(status, subtype)
        }
      end
    end
  end
end
