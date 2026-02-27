# app/services/claims/invoice_version_rulechecks/apply_genai_rulechecks.rb
# frozen_string_literal: true

module Claims
  module InvoiceVersionRulechecks
    class ApplyGenaiRulechecks
      def self.call(invoice_version_id:, genai_payload:)
        new(invoice_version_id: invoice_version_id, genai_payload: genai_payload).call
      end

      def initialize(invoice_version_id:, genai_payload:)
        @invoice_version_id = invoice_version_id
        @genai_payload = genai_payload
      end

      def call
        rulechecks = extract_rulechecks(@genai_payload)
        return { ok: true, replaced: 0 } if rulechecks.blank?

        now = Time.current
        rows = rulechecks.map { |r| build_row(r, now: now) }.compact
        return { ok: true, replaced: 0 } if rows.empty?

        Claims::InvoiceVersionRulecheck.transaction do
          Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: @invoice_version_id,
            source_engine: "genai"
          ).delete_all

          Claims::InvoiceVersionRulecheck.insert_all!(rows)
        end

        { ok: true, replaced: rows.size }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def extract_rulechecks(payload)
        return [] unless payload.is_a?(Hash)
        rc = payload["rulechecks"] || payload[:rulechecks]
        rc.is_a?(Array) ? rc : []
      end

      def build_row(r, now:)
        return nil unless r.is_a?(Hash)

        rule_number = coerce_int_or_nil(r["rule_number"] || r[:rule_number])
        return nil if rule_number.nil?

        rule_name = (r["rule_name"] || r[:rule_name]).to_s.strip
        rule_name = "rule_#{rule_number}" if rule_name.empty?

        rule_pass_flag = coerce_bool_or_nil(r["rule_pass_flag"] || r[:rule_pass_flag])
        confidence = coerce_confidence(r["confidence"] || r[:confidence])

        # you decided strings – we’ll accept JSON too, but stringify it safely
        expected_text = stringify_any(r["expected"] || r[:expected])
        observed_text = stringify_any(r["observed"] || r[:observed])

        {
          invoice_version_id: @invoice_version_id,

          source_engine: "genai",
          rule_number: rule_number,
          rule_name: rule_name,

          rule_pass_flag: rule_pass_flag,
          confidence: confidence,

          expected_text: expected_text,
          observed_text: observed_text,

          calculation: (r["calculation"] || r[:calculation]),
          tolerance_notes: (r["tolerance_notes"] || r[:tolerance_notes]),

          evidence_text: (r["evidence_text"] || r[:evidence_text]),
          evidence_hint: (r["evidence_hint"] || r[:evidence_hint]),

          reason_and_likely_causes: (r["reason_and_likely_causes"] || r[:reason_and_likely_causes]),

          notes: (r["notes"] || r[:notes]),

          created_at: now,
          updated_at: now
        }
      end

      def stringify_any(v)
        return nil if v.nil?
        return v if v.is_a?(String)

        # if model still returns {} for expected/observed, stringify it so UI is easy
        JSON.generate(v)
      rescue
        v.to_s
      end

      def coerce_int_or_nil(v)
        return nil if v.nil?
        s = v.is_a?(String) ? v.strip : v
        return nil if s == ""
        Integer(s)
      rescue
        nil
      end

      def coerce_bool_or_nil(v)
        return nil if v.nil?
        return v if v == true || v == false
        s = v.to_s.strip.downcase
        return true if %w[true t 1 yes y].include?(s)
        return false if %w[false f 0 no n].include?(s)
        nil
      end

      def coerce_confidence(v)
        n = Integer(v || 0) rescue 0
        [[n, 0].max, 100].min
      end
    end
  end
end