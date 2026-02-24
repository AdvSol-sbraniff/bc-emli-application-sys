# frozen_string_literal: true

module Claims
  module InvoiceVersionLocatedFields
    class ApplyGenaiLocatedFields
      def self.call(invoice_version_id:, genai_payload:)
        new(invoice_version_id: invoice_version_id, genai_payload: genai_payload).call
      end

      def initialize(invoice_version_id:, genai_payload:)
        @invoice_version_id = invoice_version_id
        @genai_payload = genai_payload
      end


def call
  located_fields = extract_located_fields(@genai_payload)
  return { ok: true, replaced: 0 } if located_fields.blank?

  now = Time.current
  rows = located_fields.map { |f| build_row(f, now: now) }.compact
  return { ok: true, replaced: 0 } if rows.empty?

  Claims::InvoiceVersionLocatedField.transaction do
    Claims::InvoiceVersionLocatedField.where(
      invoice_version_id: @invoice_version_id,
      source_engine: "genai"
    ).delete_all

    # no need for upsert now; we just replaced
    Claims::InvoiceVersionLocatedField.insert_all!(rows)
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

        # IMPORTANT: your system constraints say: never use 0
        line_number = coerce_int_or_nil(f["line_number"] || f[:line_number])
        line_number = nil if line_number == 0

        value = f.key?("value") ? f["value"] : f[:value]
        value_type, value_text, value_json = coerce_value(value)

        confidence = coerce_confidence(f["confidence"] || f[:confidence])

        page = coerce_int_or_nil(f["page"] || f[:page])
        polygon = polygon_to_flat_float_array(f["polygon"] || f[:polygon])

        {
          invoice_version_id: @invoice_version_id,

          source_engine: "genai",
          field_key: field_key,
          line_number: line_number,

          value_type: value_type,
          value_text: value_text,
          value_json: value_json,
          normalized_value: (f["normalized_value"] || f[:normalized_value]),

          confidence: confidence,

          page: page,
          polygon: polygon,

          evidence_text: (f["evidence_text"] || f[:evidence_text]),
          evidence_hint: (f["evidence_hint"] || f[:evidence_hint]),
          notes: (f["notes"] || f[:notes]),

          created_at: now,
          updated_at: now
        }
      end

      def coerce_value(v)
        return ["text", nil, nil] if v.nil? # "not found" row allowed (both null)

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
      rescue
        nil
      end

      def coerce_confidence(v)
        n = Integer(v || 0) rescue 0
        [[n, 0].max, 100].min
      end

      # Store polygon like ApplyDiResult: flat floats [x1,y1,x2,y2,...]
      def polygon_to_flat_float_array(raw)
        return nil if raw.nil?

        if raw.is_a?(String)
          s = raw.strip
          return nil if s.empty?
          raw = JSON.parse(s) rescue (return nil)
        end

        raw = raw["polygon"] || raw[:polygon] || raw["points"] || raw[:points] if raw.is_a?(Hash)
        return nil unless raw.is_a?(Array)
        return nil if raw.empty?

        # A) already flat
        if raw.all? { |v| numericish?(v) }
          return raw.map { |x| x.nil? ? nil : x.to_f }
        end

        # B) DI-style points: [{x,y},...]
        if raw.all? { |p| p.is_a?(Hash) && (p.key?("x") || p.key?(:x) || p.key?("X") || p.key?(:X)) }
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
        if raw.all? { |p| p.is_a?(Array) && p.length == 2 && numericish?(p[0]) && numericish?(p[1]) }
          return raw.flat_map { |p| [p[0].to_f, p[1].to_f] }
        end

        nil
      end

      def numericish?(v)
        return true if v.is_a?(Numeric)
        return false unless v.is_a?(String)
        v.strip.match?(/\A-?\d+(\.\d+)?\z/)
      end
    end
  end
end