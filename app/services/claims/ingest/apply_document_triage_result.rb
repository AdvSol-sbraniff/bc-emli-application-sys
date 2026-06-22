# frozen_string_literal: true

module Claims
  module Ingest
    class ApplyDocumentTriageResult
      ALLOWED_DOCUMENT_KINDS = %w[invoice supporting_document unknown].freeze

      def self.call(ingest_document_id:, triage_payload:)
        new(
          ingest_document_id: ingest_document_id,
          triage_payload: triage_payload
        ).call
      end

      def initialize(ingest_document_id:, triage_payload:)
        @ingest_document_id = ingest_document_id
        @triage_payload = triage_payload
      end

      def call
        document_kind = normalized_document_kind
        type_key = supporting_document_type_key
        type =
          ::Claims::SupportingDocumentType.find_by(
            type_key: type_key
          ) if type_key.present?

        ingest_document = ::Claims::IngestDocument.find(@ingest_document_id)
        ingest_document.update!(
          classifier_raw_json: @triage_payload,
          document_kind: document_kind,
          document_kind_confidence:
            coerce_confidence(
              @triage_payload["document_kind_confidence"] ||
                @triage_payload[:document_kind_confidence]
            ),
          document_kind_reason:
            (
              @triage_payload["document_kind_reason"] ||
                @triage_payload[:document_kind_reason]
            ).to_s.presence,
          supporting_document_type_id: type&.id,
          classification_status:
            classification_status_for(
              document_kind: document_kind,
              type_key: type_key,
              type: type
            ),
          classification_confidence:
            coerce_confidence(
              @triage_payload["supporting_document_type_confidence"] ||
                @triage_payload[:supporting_document_type_confidence] ||
                @triage_payload["document_kind_confidence"] ||
                @triage_payload[:document_kind_confidence]
            ),
          classification_reason:
            (
              @triage_payload["supporting_document_type_reason"] ||
                @triage_payload[:supporting_document_type_reason] ||
                @triage_payload["document_kind_reason"] ||
                @triage_payload[:document_kind_reason]
            ).to_s.presence,
          supporting_document_routing_quality:
            supporting_document_routing_quality(document_kind: document_kind),
          supporting_document_routing_quality_reason:
            supporting_document_routing_quality_reason(
              document_kind: document_kind
            ),
          classified_at: Time.current,
          updated_at: Time.current
        )

        {
          ok: true,
          document_kind: document_kind,
          document_kind_confidence: ingest_document.document_kind_confidence,
          supporting_document_type_key: type_key,
          supporting_document_type_confidence:
            ingest_document.classification_confidence,
          supporting_document_routing_quality:
            ingest_document.supporting_document_routing_quality
        }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def normalized_document_kind
        kind =
          (
            @triage_payload["document_kind"] || @triage_payload[:document_kind]
          ).to_s.strip
        return kind if ALLOWED_DOCUMENT_KINDS.include?(kind)

        "unknown"
      end

      def supporting_document_type_key
        (
          @triage_payload["supporting_document_type_key"] ||
            @triage_payload[:supporting_document_type_key]
        ).to_s.strip.presence
      end

      def classification_status_for(document_kind:, type_key:, type:)
        return "needs_review" if document_kind == "unknown"
        return "classified" if document_kind == "invoice"
        return "pending" if type_key.blank?
        return "classified" if type.present?

        "needs_review"
      end

      def supporting_document_routing_quality(document_kind:)
        return nil unless document_kind == "supporting_document"

        value =
          (
            @triage_payload["supporting_document_routing_quality"] ||
              @triage_payload[:supporting_document_routing_quality]
          ).to_s.strip.presence
        if %w[usable needs_review requires_visual_review unusable].include?(
             value
           )
          return value
        end

        nil
      end

      def supporting_document_routing_quality_reason(document_kind:)
        return nil unless document_kind == "supporting_document"

        (
          @triage_payload["supporting_document_routing_quality_reason"] ||
            @triage_payload[:supporting_document_routing_quality_reason]
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
