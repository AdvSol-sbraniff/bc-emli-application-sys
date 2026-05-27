# frozen_string_literal: true

module Claims
  module Ingest
    class ApplyDocumentTriageResult
      ALLOWED_DOCUMENT_KINDS = %w[invoice supplement unknown].freeze

      def self.call(ingest_document_id: nil, invoice_version_id: nil, triage_payload:)
        new(
          ingest_document_id: ingest_document_id,
          invoice_version_id: invoice_version_id,
          triage_payload: triage_payload
        ).call
      end

      def initialize(ingest_document_id:, invoice_version_id:, triage_payload:)
        @ingest_document_id = ingest_document_id
        @invoice_version_id = invoice_version_id
        @triage_payload = triage_payload
      end

      def call
        document_kind = normalized_document_kind
        type_key = supplement_type_key
        type =
          ::Claims::SupportingDocumentType.find_by(type_key: type_key) if type_key.present?

        if @ingest_document_id.blank? && @invoice_version_id.present?
          return apply_legacy_invoice_version_result(document_kind: document_kind)
        end

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
              @triage_payload["supplement_type_confidence"] ||
                @triage_payload[:supplement_type_confidence] ||
                @triage_payload["document_kind_confidence"] ||
                @triage_payload[:document_kind_confidence]
            ),
          classification_reason:
            (
              @triage_payload["supplement_type_reason"] ||
                @triage_payload[:supplement_type_reason] ||
                @triage_payload["document_kind_reason"] ||
                @triage_payload[:document_kind_reason]
            ).to_s.presence,
          classified_at: Time.current,
          updated_at: Time.current
        )

        {
          ok: true,
          document_kind: document_kind,
          document_kind_confidence: ingest_document.document_kind_confidence,
          supplement_type_key: type_key,
          supplement_type_confidence: ingest_document.classification_confidence
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

      def supplement_type_key
        (
          @triage_payload["supplement_type_key"] ||
            @triage_payload[:supplement_type_key]
        ).to_s.strip.presence
      end

      def classification_status_for(document_kind:, type_key:, type:)
        return "needs_review" if document_kind == "unknown"
        return "classified" if document_kind == "invoice"
        return "pending" if type_key.blank?
        return "classified" if type.present?

        "needs_review"
      end

      def apply_legacy_invoice_version_result(document_kind:)
        ::Claims::InvoiceVersionUpgradeType.transaction do
          if document_kind == "invoice"
            result =
              ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
                invoice_version_id: @invoice_version_id,
                classifier_payload: @triage_payload
              )
            raise "ApplyClassifierResult failed: #{result.inspect}" unless result[:ok]
          else
            ::Claims::InvoiceVersionUpgradeType.where(
              invoice_version_id: @invoice_version_id,
              source_engine: "classifier"
            ).delete_all
          end
        end

        {
          ok: true,
          document_kind: document_kind,
          document_kind_confidence:
            coerce_confidence(
              @triage_payload["document_kind_confidence"] ||
                @triage_payload[:document_kind_confidence]
            ),
          supplement_type_key: supplement_type_key,
          supplement_type_confidence:
            coerce_confidence(
              @triage_payload["supplement_type_confidence"] ||
                @triage_payload[:supplement_type_confidence]
            )
        }
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
