# frozen_string_literal: true

module Claims
  module SupportingDocuments
    class CreateOrUpdateFromIngestDocument
      def self.call(resolved_invoice_version_id:, ingest_document_id:)
        new(
          resolved_invoice_version_id: resolved_invoice_version_id,
          ingest_document_id: ingest_document_id
        ).call
      end

      def initialize(resolved_invoice_version_id:, ingest_document_id:)
        @resolved_invoice_version_id = resolved_invoice_version_id
        @ingest_document_id = ingest_document_id
      end

      def call
        invoice_version =
          ::Claims::InvoiceVersion.select(:id, :invoice_id).find(
            @resolved_invoice_version_id
          )
        ingest_document = ::Claims::IngestDocument.find(@ingest_document_id)
        personal_information_attributes =
          ::Claims::PersonalInformation::NormalizeClassifierResult.call(
            classifier_payload: ingest_document.classifier_raw_json || {}
          )

        document =
          ::Claims::SupportingDocument.find_or_initialize_by(
            invoice_version_id: invoice_version.id,
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
          classification_confidence: ingest_document.classification_confidence,
          classification_reason: ingest_document.classification_reason,
          supporting_document_routing_quality:
            ingest_document.supporting_document_routing_quality,
          supporting_document_routing_quality_reason:
            ingest_document.supporting_document_routing_quality_reason,
          classified_at: ingest_document.classified_at,
          **personal_information_attributes,
          updated_at: Time.current
        )
        document.created_at ||= Time.current
        document.save!

        ingest_document.update!(
          resolved_invoice_id: invoice_version.invoice_id,
          resolved_invoice_version_id: invoice_version.id,
          promoted_supporting_document_id: document.id,
          updated_at: Time.current
        )

        document
      end
    end
  end
end
