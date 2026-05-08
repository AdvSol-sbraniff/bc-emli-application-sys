# app/services/claims/invoice_version_rulechecks/apply_genai_rulechecks.rb
# frozen_string_literal: true

module Claims
  module InvoiceVersionRulechecks
    class ApplyGenaiRulechecks
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
        rulechecks = extract_rulechecks(@genai_payload)
        now = Time.current
        rows = rulechecks.map { |r| build_row(r, now: now) }.compact

        Claims::InvoiceVersionRulecheck.transaction do
          Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: @invoice_version_id,
            invoice_upgrade_type_id: @invoice_upgrade_type_id,
            source_engine: "genai"
          ).delete_all

          Claims::InvoiceVersionRulecheck.insert_all!(rows) if rows.any?
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

        rule_pass_flag =
          coerce_bool_or_nil(r["rule_pass_flag"] || r[:rule_pass_flag])
        rule_pass_flag = false if rule_pass_flag.nil?
        confidence = coerce_confidence(r["confidence"] || r[:confidence])

        # you decided strings – we’ll accept JSON too, but stringify it safely
        expected_text =
          stringify_any(
            r["expected_text"] || r[:expected_text] || r["expected"] ||
              r[:expected]
          )
        observed_text =
          stringify_any(
            r["observed_text"] || r[:observed_text] || r["observed"] ||
              r[:observed]
          )

        attrs = {
          invoice_version_id: @invoice_version_id,
          invoice_upgrade_type_id: @invoice_upgrade_type_id,
          source_engine: "genai",
          rule_number: rule_number,
          rule_name: rule_name,
          rule_pass_flag: rule_pass_flag,
          confidence: confidence,
          expected_text: expected_text,
          observed_text: observed_text,
          calculation: (r["calculation"] || r[:calculation]),
          evidence_text: (r["evidence_text"] || r[:evidence_text]),
          reason_and_likely_causes:
            (r["reason_and_likely_causes"] || r[:reason_and_likely_causes]),
          created_at: now,
          updated_at: now
        }

        optional_metadata = {
          rule_key: r["rule_key"] || r[:rule_key],
          source_requirement_id:
            r["source_requirement_id"] || r[:source_requirement_id],
          evidence_source: r["evidence_source"] || r[:evidence_source]
        }

        optional_metadata.each do |key, value|
          attrs[
            key
          ] = value if Claims::InvoiceVersionRulecheck.column_names.include?(
            key.to_s
          )
        end

        attrs
      end

      def stringify_any(v)
        return nil if v.nil?
        return v if v.is_a?(String)

        # if model still returns {} for expected/observed, stringify it so UI is easy
        JSON.generate(v)
      rescue StandardError
        v.to_s
      end

      def coerce_int_or_nil(v)
        return nil if v.nil?
        s = v.is_a?(String) ? v.strip : v
        return nil if s == ""
        Integer(s)
      rescue StandardError
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
        n =
          begin
            Integer(v || 0)
          rescue StandardError
            0
          end
        [[n, 0].max, 100].min
      end

      def common_upgrade_type_id
        Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common").id
      end
    end
  end
end
