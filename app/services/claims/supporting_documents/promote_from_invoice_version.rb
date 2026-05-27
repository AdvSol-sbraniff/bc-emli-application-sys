# frozen_string_literal: true

module Claims
  module SupportingDocuments
    class PromoteFromInvoiceVersion
      def self.call(resolved_invoice_id:, invoice_version_id:)
        new(
          resolved_invoice_id: resolved_invoice_id,
          invoice_version_id: invoice_version_id
        ).call
      end

      def initialize(resolved_invoice_id:, invoice_version_id:)
        @resolved_invoice_id = resolved_invoice_id
        @invoice_version_id = invoice_version_id
      end

      def call
        invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)
        payload = latest_triage_payload(invoice_version.id)

        type_key =
          (payload["supplement_type_key"] || payload[:supplement_type_key]).to_s.strip
        type = ::Claims::SupportingDocumentType.find_by(type_key: type_key) if type_key.present?

        document =
          ::Claims::SupportingDocument.find_or_initialize_by(
            invoice_id: @resolved_invoice_id,
            storage_key: invoice_version.storage_key
          )

        document.assign_attributes(
          supporting_document_type_id: type&.id,
          storage_provider: invoice_version.storage_provider,
          original_filename: invoice_version.original_filename,
          content_type: invoice_version.content_type,
          byte_size: invoice_version.byte_size,
          sha256: invoice_version.sha256,
          di_read_raw_json: invoice_version.di_raw_json,
          classifier_raw_json: payload,
          classification_status: classification_status_for(type_key: type_key, type: type),
          classification_confidence:
            coerce_confidence(
              payload["supplement_type_confidence"] ||
                payload[:supplement_type_confidence]
            ),
          classification_reason:
            (
              payload["supplement_type_reason"] ||
                payload[:supplement_type_reason] ||
                payload["document_kind_reason"] ||
                payload[:document_kind_reason]
            ).to_s.presence,
          classified_at: Time.current,
          updated_at: Time.current
        )
        document.created_at ||= Time.current
        document.save!

        document
      end

      private

      def latest_triage_payload(invoice_version_id)
        row =
          ::Claims::IngestStepRun
            .where(
              invoice_version_id: invoice_version_id,
              step_type: "triage_classifier",
              status: "succeeded"
            )
            .order(created_at: :desc)
            .first

        payload = row&.genai_results_json
        payload.is_a?(Hash) ? payload : {}
      end

      def classification_status_for(type_key:, type:)
        return "pending" if type_key.blank?
        return "classified" if type.present?

        "needs_review"
      end

      def coerce_confidence(value)
        n =
          begin
            Integer(value || 0)
          rescue StandardError
            0
          end
        [[n, 0].max, 100].min
      end
    end
  end
end
