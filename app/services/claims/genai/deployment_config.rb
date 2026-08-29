# frozen_string_literal: true

module Claims
  module Genai
    class DeploymentConfig
      ATTRIBUTES = %i[
        document_triage_deployment_name
        supporting_document_extraction_deployment_name
        upgrade_analysis_deployment_name
        comparison_deployment_name
      ].freeze

      def self.current
        config = ::Claims::ValidationgenaiConfig.order(:created_at).first
        fallback = ENV["GENAI_DEPLOYMENT"].to_s.strip.presence

        ATTRIBUTES.index_with do |attribute|
          config&.public_send(attribute).to_s.strip.presence || fallback
        end
      end

      def self.snapshot_attributes
        current.slice(
          :document_triage_deployment_name,
          :supporting_document_extraction_deployment_name,
          :upgrade_analysis_deployment_name
        )
      end

      def self.for_run(ingest_run_id, attribute)
        run = ::Claims::IngestRun.find(ingest_run_id)
        run.public_send(attribute).to_s.strip.presence ||
          current.fetch(attribute)
      end
    end
  end
end
