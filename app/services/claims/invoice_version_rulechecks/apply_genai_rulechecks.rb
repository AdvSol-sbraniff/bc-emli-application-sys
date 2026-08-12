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

        rule_key = (r["rule_key"] || r[:rule_key]).to_s.strip
        return nil if rule_key.blank?

        rule_result = coerce_rule_result(r)
        compliance_score =
          coerce_compliance_score(r["compliance_score"] || r[:compliance_score])

        # you decided strings – we’ll accept JSON too, but stringify it safely
        expected_text =
          stringify_any(
            r["expected_text"] || r[:expected_text] || r["expected"] ||
              r[:expected]
          )
        attrs = {
          invoice_version_id: @invoice_version_id,
          invoice_upgrade_type_id: @invoice_upgrade_type_id,
          source_engine: "genai",
          rule_key: rule_key,
          rule_result: rule_result,
          compliance_score: compliance_score,
          expected_text: expected_text,
          calculation: (r["calculation"] || r[:calculation]),
          evidence_text: stringify_any(r["evidence_text"] || r[:evidence_text]),
          reason_and_likely_causes:
            (r["reason_and_likely_causes"] || r[:reason_and_likely_causes]),
          created_at: now,
          updated_at: now
        }

        attrs
      end

      def stringify_any(v)
        return nil if v.nil?
        return v if v.is_a?(String)

        # If model still returns structured expected/evidence values, stringify them for the UI.
        JSON.generate(v)
      rescue StandardError
        v.to_s
      end

      def coerce_rule_result(row)
        raw = row["rule_result"] || row[:rule_result]
        result = raw.to_s.strip.downcase
        return result if %w[pass info warn fail].include?(result)

        "fail"
      end

      def coerce_compliance_score(value)
        if value.nil? || value.to_s.strip.empty?
          raise ArgumentError,
                "compliance_score is required for every GenAI rulecheck"
        end

        score = Integer(value)
        unless score.between?(0, 100)
          raise ArgumentError, "compliance_score must be between 0 and 100"
        end

        score
      end

      def common_upgrade_type_id
        Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common").id
      end
    end
  end
end
