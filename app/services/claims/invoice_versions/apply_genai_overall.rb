# frozen_string_literal: true

module Claims
  module InvoiceVersions
    class ApplyGenaiOverall
      def self.call(invoice_version_id:, genai_payload:)
        new(
          invoice_version_id: invoice_version_id,
          genai_payload: genai_payload
        ).call
      end

      def initialize(invoice_version_id:, genai_payload:)
        @invoice_version_id = invoice_version_id
        @payload = genai_payload
      end

      def call
        iv = Claims::InvoiceVersion.find(@invoice_version_id)

        overall =
          if @payload.is_a?(Hash)
            fetch_hash_value(@payload, "overall", :overall) || {}
          else
            {}
          end

        conf =
          fetch_hash_value(overall, "overall_confidence", :overall_confidence)
        result =
          fetch_hash_value(
            overall,
            "overall_result",
            :overall_result,
            "result",
            :result
          )
        conf_i = coerce_confidence(conf)
        result_s = coerce_result(result, overall)
        advice_s = advice_from_rulechecks(@payload)

        iv.update!(
          genai_raw_json: @payload,
          genai_overall_confidence: conf_i,
          genai_result: result_s,
          genai_admin_advice: advice_s
        )

        { ok: true }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def coerce_confidence(v)
        n =
          begin
            Integer(v || 0)
          rescue StandardError
            0
          end
        [[n, 0].max, 100].min
      end

      def fetch_hash_value(hash, *keys)
        return nil unless hash.is_a?(Hash)

        keys.each { |key| return hash[key] if hash.key?(key) }

        nil
      end

      def coerce_result(value, overall)
        result = value.to_s.strip.downcase
        return result if %w[pass info warn fail].include?(result)

        nil
      end

      def advice_from_rulechecks(payload)
        return nil unless payload.is_a?(Hash)

        rows = fetch_hash_value(payload, "rulechecks", :rulechecks)
        bullets =
          Array(rows).filter_map do |row|
            next unless row.is_a?(Hash)

            result =
              fetch_hash_value(row, "rule_result", :rule_result)
                .to_s
                .strip
                .downcase
            next unless %w[info warn fail].include?(result)

            message =
              [
                fetch_hash_value(
                  row,
                  "reason_and_likely_causes",
                  :reason_and_likely_causes
                ),
                fetch_hash_value(row, "evidence_text", :evidence_text)
              ].map { |value| value.to_s.strip }.find(&:present?)
            next if message.blank?

            rule_number = fetch_hash_value(row, "rule_number", :rule_number)
            rule_key = fetch_hash_value(row, "rule_key", :rule_key).to_s.strip
            label_parts = []
            label_parts << "Rule #{rule_number}" if rule_number.present?
            label_parts << "(#{rule_key})" if rule_key.present?

            result_label =
              case result
              when "info"
                "Helpful note"
              when "warn"
                "Please verify"
              when "fail"
                "Correction needed"
              end

            "- #{[label_parts.join(" ").presence, result_label].compact.join(": ")}: #{message}"
          end

        bullets.empty? ? nil : bullets.join("\n")
      end
    end
  end
end
