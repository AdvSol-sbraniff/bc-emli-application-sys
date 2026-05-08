# /app/services/claims/invoice_version_located_fields/apply_genai_located_fields.rb]
# frozen_string_literal: true

module Claims
  module InvoiceVersionLocatedFields
    class ApplyGenaiLocatedFields
      def self.call(
        invoice_version_id:,
        genai_payload:,
        invoice_upgrade_type_id: nil
      )
        new(
          invoice_version_id: invoice_version_id,
          genai_payload: genai_payload,
          invoice_upgrade_type_id: invoice_upgrade_type_id
        ).call
      end

      def initialize(
        invoice_version_id:,
        genai_payload:,
        invoice_upgrade_type_id: nil
      )
        @invoice_version_id = invoice_version_id
        @genai_payload = genai_payload
        @invoice_upgrade_type_id =
          invoice_upgrade_type_id || common_upgrade_type_id
      end

      def call
        located_fields = extract_located_fields(@genai_payload)
        now = Time.current
        rows = located_fields.map { |f| build_row(f, now: now) }.compact

        Claims::InvoiceVersionLocatedField.transaction do
          Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: @invoice_version_id,
            invoice_upgrade_type_id: @invoice_upgrade_type_id,
            source_engine: "genai"
          ).delete_all

          Claims::InvoiceVersionLocatedField.insert_all!(rows) if rows.any?
        end

        { ok: true, replaced: rows.size }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def extract_located_fields(payload)
        return [] unless payload.is_a?(Hash)
        lf = payload["located_fields"] || payload[:located_fields]
        lf.is_a?(Array) ? lf : []
      end

      def build_row(f, now:)
        return nil unless f.is_a?(Hash)

        field_key = (f["field_key"] || f[:field_key]).to_s.strip
        return nil if field_key.empty?

        line_number = coerce_int_or_nil(f["line_number"] || f[:line_number])
        line_number = 0 if line_number.nil? || line_number < 0

        value = f.key?("value") ? f["value"] : f[:value]
        value_type, value_text, value_json = coerce_value(value)

        confidence = coerce_confidence(f["confidence"] || f[:confidence])

        page = coerce_int_or_nil(f["page"] || f[:page])
        polygon = polygon_to_flat_float_array(f["polygon"] || f[:polygon])

        {
          invoice_version_id: @invoice_version_id,
          invoice_upgrade_type_id: @invoice_upgrade_type_id,
          source_engine: "genai",
          field_key: field_key,
          line_number: line_number,
          value_type: value_type,
          value_text: value_text,
          value_json: value_json,
          confidence: confidence,
          page: page,
          polygon: polygon,
          evidence_text: (f["evidence_text"] || f[:evidence_text]),
          created_at: now,
          updated_at: now
        }
      end

      def coerce_value(v)
        return "text", nil, nil if v.nil? # "not found" row allowed (both null)

        case v
        when TrueClass, FalseClass
          ["bool", v.to_s, nil]
        when Integer, Float, BigDecimal
          ["number", v.to_s, nil]
        when String
          ["text", v, nil]
        when Hash, Array
          ["json", nil, v]
        else
          # fallback: store as text
          ["text", v.to_s, nil]
        end
      end

      def coerce_int_or_nil(v)
        return nil if v.nil?
        s = v.is_a?(String) ? v.strip : v
        return nil if s == ""
        Integer(s)
      rescue StandardError
        nil
      end

      def coerce_confidence(v)
        n =
          begin
            Float(v || 0)
          rescue StandardError
            0
          end
        n *= 100 if n > 0 && n <= 1
        n = n.round
        [[n, 0].max, 100].min
      end

      # Store polygon like ApplyDiResult: flat floats [x1,y1,x2,y2,...]
      def polygon_to_flat_float_array(raw)
        return nil if raw.nil?

        if raw.is_a?(String)
          s = raw.strip
          return nil if s.empty?
          raw =
            begin
              JSON.parse(s)
            rescue StandardError
              (return nil)
            end
        end

        raw =
          raw["polygon"] || raw[:polygon] || raw["points"] ||
            raw[:points] if raw.is_a?(Hash)
        return nil unless raw.is_a?(Array)
        return nil if raw.empty?

        # A) already flat
        if raw.all? { |v| numericish?(v) }
          return raw.map { |x| x.nil? ? nil : x.to_f }
        end

        # B) DI-style points: [{x,y},...]
        if raw.all? { |p|
             p.is_a?(Hash) &&
               (p.key?("x") || p.key?(:x) || p.key?("X") || p.key?(:X))
           }
          flat = []
          raw.each do |p|
            x = p["x"] || p[:x] || p["X"] || p[:X]
            y = p["y"] || p[:y] || p["Y"] || p[:Y]
            next unless numericish?(x) && numericish?(y)
            flat << x.to_f
            flat << y.to_f
          end
          return flat.empty? ? nil : flat
        end

        # C) pairs: [[x,y],...]
        if raw.all? { |p|
             p.is_a?(Array) && p.length == 2 && numericish?(p[0]) &&
               numericish?(p[1])
           }
          return raw.flat_map { |p| [p[0].to_f, p[1].to_f] }
        end

        nil
      end

      def numericish?(v)
        return true if v.is_a?(Numeric)
        return false unless v.is_a?(String)
        v.strip.match?(/\A-?\d+(\.\d+)?\z/)
      end

      def common_upgrade_type_id
        Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common").id
      end
    end
  end
end
