# frozen_string_literal: true

require "json"

module Claims
  module InvoiceVersionLocatedFields
    class ApplyClassifierLocatedFields
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
        return unless classifier_payload.is_a?(Hash)

        invoice_version = Claims::InvoiceVersion.find(invoice_version_id)
        common_type =
          Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")
        now = Time.current
        rows = []
        add_common_rows(rows, invoice_version, common_type, now)

        Claims::InvoiceVersionLocatedField.transaction do
          Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: invoice_version.id,
            source_engine: "classifier"
          ).delete_all

          Claims::InvoiceVersionLocatedField.insert_all!(rows) if rows.any?
        end
      end

      private

      attr_reader :invoice_version_id, :classifier_payload

      def add_common_rows(rows, invoice_version, common_type, now)
        eligibility_code =
          located_payload(
            classifier_payload["eligibility_code"] ||
              classifier_payload[:eligibility_code]
          )

        add_row(
          rows,
          invoice_version_id: invoice_version.id,
          invoice_upgrade_type_id: common_type.id,
          field_key: "classifier.eligibility_code",
          value_type: "text",
          value: eligibility_code.fetch(:value),
          confidence: eligibility_code.fetch(:confidence) || 100,
          page: eligibility_code.fetch(:page),
          polygon: eligibility_code.fetch(:polygon),
          evidence_text: eligibility_code.fetch(:evidence_text),
          now: now
        )
      end

      def add_row(
        rows,
        invoice_version_id:,
        invoice_upgrade_type_id:,
        field_key:,
        value_type:,
        value:,
        confidence:,
        page:,
        polygon:,
        evidence_text:,
        now:
      )
        value_present =
          value_type == "json" ? !value.nil? : value.to_s.strip.present?
        return unless value_present

        rows << {
          invoice_version_id: invoice_version_id,
          invoice_upgrade_type_id: invoice_upgrade_type_id,
          source_engine: "classifier",
          field_key: field_key,
          value_type: value_type,
          value_text: value_type == "json" ? nil : value.to_s.strip,
          value_json: value_type == "json" ? value : nil,
          confidence: coerce_confidence(confidence),
          page: coerce_int_or_nil(page),
          polygon: polygon_to_flat_float_array(polygon),
          evidence_text: evidence_text.presence || "Triage classifier",
          created_at: now,
          updated_at: now
        }
      end

      def located_payload(raw)
        if raw.is_a?(Hash)
          value =
            raw["value"] || raw[:value] || raw["text"] || raw[:text] ||
              raw["value_text"] || raw[:value_text]
          {
            value: value.to_s.strip.presence,
            confidence: raw["confidence"] || raw[:confidence],
            page: coerce_int_or_nil(raw["page"] || raw[:page]),
            polygon:
              polygon_to_flat_float_array(raw["polygon"] || raw[:polygon]),
            evidence_text:
              (raw["evidence_text"] || raw[:evidence_text]).to_s.strip.presence
          }
        else
          {
            value: raw.to_s.strip.presence,
            confidence: nil,
            page: nil,
            polygon: nil,
            evidence_text: nil
          }
        end
      end

      def coerce_int_or_nil(value)
        return nil if value.nil?

        text = value.is_a?(String) ? value.strip : value
        return nil if text == ""

        Integer(text)
      rescue StandardError
        nil
      end

      def coerce_confidence(value)
        number =
          begin
            Float(value || 0)
          rescue StandardError
            0
          end
        number *= 100 if number.positive? && number <= 1
        number.round.clamp(0, 100)
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
