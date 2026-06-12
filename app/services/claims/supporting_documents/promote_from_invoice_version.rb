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
          (
            payload["supporting_document_type_key"] ||
              payload[:supporting_document_type_key]
          ).to_s.strip
        type =
          ::Claims::SupportingDocumentType.find_by(
            type_key: type_key
          ) if type_key.present?

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
          classification_status:
            classification_status_for(type_key: type_key, type: type),
          classification_confidence:
            coerce_confidence(
              payload["supporting_document_type_confidence"] ||
                payload[:supporting_document_type_confidence]
            ),
          classification_reason:
            (
              payload["supporting_document_type_reason"] ||
                payload[:supporting_document_type_reason] ||
                payload["document_kind_reason"] ||
                payload[:document_kind_reason]
            ).to_s.presence,
          supporting_document_routing_quality:
            supporting_document_routing_quality(payload),
          supporting_document_routing_quality_reason:
            supporting_document_routing_quality_reason(payload),
          classified_at: Time.current,
          updated_at: Time.current
        )
        document.created_at ||= Time.current
        document.save!

        located_result =
          ::Claims::SupportingDocuments::ApplyLocatedFields.call(
            supporting_document_id: document.id,
            located_fields_payload: {
            }
          )
        unless located_result[:ok]
          raise "ApplyLocatedFields failed: #{located_result.inspect}"
        end

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

      def supporting_document_routing_quality(payload)
        value =
          (
            payload["supporting_document_routing_quality"] ||
              payload[:supporting_document_routing_quality]
          ).to_s.strip.presence
        if %w[usable needs_review requires_visual_review unusable].include?(
             value
           )
          return value
        end

        nil
      end

      def supporting_document_routing_quality_reason(payload)
        (
          payload["supporting_document_routing_quality_reason"] ||
            payload[:supporting_document_routing_quality_reason]
        ).to_s.presence
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
