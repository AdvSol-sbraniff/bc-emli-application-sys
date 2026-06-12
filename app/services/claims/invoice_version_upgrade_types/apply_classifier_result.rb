# frozen_string_literal: true

module Claims
  module InvoiceVersionUpgradeTypes
    class ApplyClassifierResult
      def self.call(invoice_version_id:, classifier_payload:)
        new(
          invoice_version_id: invoice_version_id,
          classifier_payload: classifier_payload
        ).call
      end

      def initialize(invoice_version_id:, classifier_payload:)
        @invoice_version_id = invoice_version_id
        @classifier_payload = classifier_payload
      end

      def call
        detected = extract_detected_upgrade_types
        now = Time.current

        rows =
          detected.filter_map do |row|
            upgrade_type = upgrade_type_for(row)
            next unless upgrade_type

            {
              invoice_version_id: @invoice_version_id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "classifier",
              call_status: "classified",
              confidence:
                coerce_confidence(row["confidence"] || row[:confidence]),
              raw_json: row,
              created_at: now,
              updated_at: now
            }
          end

        Claims::InvoiceVersionUpgradeType.transaction do
          Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: @invoice_version_id,
            source_engine: "classifier"
          ).delete_all

          Claims::InvoiceVersionUpgradeType.insert_all!(rows) if rows.any?
          Claims::GenaiCaseFacts::Build.persist_classifier_located_fields!(
            invoice_version_id: @invoice_version_id,
            classifier_payload: @classifier_payload
          )
        end

        { ok: true, replaced: rows.size }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def extract_detected_upgrade_types
        return [] unless @classifier_payload.is_a?(Hash)

        rows =
          @classifier_payload["detected_upgrade_types"] ||
            @classifier_payload[:detected_upgrade_types]
        rows.is_a?(Array) ? rows : []
      end

      def upgrade_type_for(row)
        key = (row["upgrade_type_key"] || row[:upgrade_type_key]).to_s.strip
        return nil if key.empty? || key == "common"

        Claims::InvoiceUpgradeType.find_by(upgrade_type_key: key)
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
