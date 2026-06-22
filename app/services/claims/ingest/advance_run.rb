# frozen_string_literal: true

module Claims
  module Ingest
    class AdvanceRun
      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        if ::Claims::IngestDocument.exists?(ingest_run_id: @ingest_run_id)
          ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: @ingest_run_id)
        else
          ::Claims::Ingest::FinalizeInvoiceVersionRun.call(
            ingest_run_id: @ingest_run_id
          )
        end
      end
    end
  end
end
