# frozen_string_literal: true

module Claims
  module SupportingDocuments
    class PromoteFromIngestDocument
      def self.call(resolved_invoice_id:, ingest_document_id:)
        new(
          resolved_invoice_id: resolved_invoice_id,
          ingest_document_id: ingest_document_id
        ).call
      end

      def initialize(resolved_invoice_id:, ingest_document_id:)
        @resolved_invoice_id = resolved_invoice_id
        @ingest_document_id = ingest_document_id
      end

      def call
        ingest_document = ::Claims::IngestDocument.find(@ingest_document_id)

        document =
          ::Claims::SupportingDocument.find_or_initialize_by(
            invoice_id: @resolved_invoice_id,
            storage_key: ingest_document.storage_key
          )

        document.assign_attributes(
          supporting_document_type_id:
            ingest_document.supporting_document_type_id,
          storage_provider: ingest_document.storage_provider,
          original_filename: ingest_document.original_filename,
          content_type: ingest_document.content_type,
          byte_size: ingest_document.byte_size,
          sha256: ingest_document.sha256,
          di_read_raw_json: ingest_document.di_read_raw_json,
          classifier_raw_json: ingest_document.classifier_raw_json,
          classification_status: ingest_document.classification_status,
          classification_confidence: ingest_document.classification_confidence,
          classification_reason: ingest_document.classification_reason,
          supplement_routing_quality:
            ingest_document.supplement_routing_quality,
          supplement_routing_quality_reason:
            ingest_document.supplement_routing_quality_reason,
          classified_at: ingest_document.classified_at,
          updated_at: Time.current
        )
        document.created_at ||= Time.current
        document.save!

        located_result =
          ::Claims::SupportingDocuments::ApplyLocatedFields.call(
            supporting_document_id: document.id,
            classifier_payload: located_field_payload_for(ingest_document)
          )
        unless located_result[:ok]
          raise "ApplyLocatedFields failed: #{located_result.inspect}"
        end

        document
      end

      private

      def located_field_payload_for(ingest_document)
        extraction_payload =
          ::Claims::IngestStepRun
            .where(
              ingest_document_id: ingest_document.id,
              step_type: "supporting_document_extraction",
              status: "succeeded"
            )
            .order(created_at: :desc)
            .pick(:genai_results_json)

        extraction_payload.presence || ingest_document.classifier_raw_json
      end
    end
  end
end
