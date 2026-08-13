# frozen_string_literal: true

require "json"

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
              confidence:
                coerce_confidence(row["confidence"] || row[:confidence]),
              evidence_text:
                (row["evidence_text"] || row[:evidence_text])
                  .to_s
                  .strip
                  .presence,
              classification_explanation:
                (
                  row["classification_explanation"] ||
                    row[:classification_explanation]
                ).to_s.strip.presence,
              page: coerce_int_or_nil(row["page"] || row[:page]),
              polygon:
                polygon_to_flat_float_array(row["polygon"] || row[:polygon]),
              raw_json: row,
              created_at: now,
              updated_at: now
            }
          end

        Claims::InvoiceVersionUpgradeType.transaction do
          Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: @invoice_version_id
          ).delete_all

          Claims::InvoiceVersionUpgradeType.insert_all!(rows) if rows.any?
          Claims::InvoiceVersionLocatedFields::ApplyClassifierLocatedFields.call(
            invoice_version_id: @invoice_version_id,
            classifier_payload: @classifier_payload
          )
        end

        { ok: true, replaced: rows.size }
      rescue StandardError => e
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
        n.clamp(0, 100)
      end

      def coerce_int_or_nil(value)
        return nil if value.nil?

        text = value.is_a?(String) ? value.strip : value
        return nil if text == ""

        Integer(text)
      rescue StandardError
        nil
      end

      def polygon_to_flat_float_array(raw)
        return nil if raw.nil?

        if raw.is_a?(String)
          raw =
            begin
              JSON.parse(raw.strip)
            rescue StandardError
              nil
            end
        end

        if raw.is_a?(Hash)
          raw = raw["polygon"] || raw[:polygon] || raw["points"] || raw[:points]
        end
        return nil unless raw.is_a?(Array) && raw.any?

        return raw.map(&:to_f) if raw.all? { |value| numericish?(value) }

        if raw.all? { |point|
             point.is_a?(Hash) &&
               (
                 point.key?("x") || point.key?(:x) || point.key?("X") ||
                   point.key?(:X)
               )
           }
          flat = []
          raw.each do |point|
            x = point["x"] || point[:x] || point["X"] || point[:X]
            y = point["y"] || point[:y] || point["Y"] || point[:Y]
            next unless numericish?(x) && numericish?(y)

            flat << x.to_f
            flat << y.to_f
          end
          return flat.presence
        end

        if raw.all? { |point|
             point.is_a?(Array) && point.length == 2 && numericish?(point[0]) &&
               numericish?(point[1])
           }
          return raw.flat_map { |point| [point[0].to_f, point[1].to_f] }
        end

        nil
      end

      def numericish?(value)
        return true if value.is_a?(Numeric)
        return false unless value.is_a?(String)

        value.strip.match?(/\A-?\d+(\.\d+)?\z/)
      end
    end
  end
end
