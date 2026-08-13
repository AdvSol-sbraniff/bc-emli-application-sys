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

        run = ::Claims::IngestRun.find(@ingest_run_id)

        case run.run_kind
        when "initial_upload", "fix_upload"
          ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: @ingest_run_id)
        when "rules_rerun"
          ::Claims::Ingest::AdvanceExistingEvidenceRun.call(
            ingest_run_id: @ingest_run_id
          )
        else
          raise "Unsupported ingest run kind: #{run.run_kind.inspect}"
        end
      end
    end
  end
end
