# frozen_string_literal: true

module Claims
  module InvoiceVersions
    class ApplyGenaiOverall
      def self.call(invoice_version_id:, genai_payload:)
        new(invoice_version_id: invoice_version_id, genai_payload: genai_payload).call
      end

      def initialize(invoice_version_id:, genai_payload:)
        @invoice_version_id = invoice_version_id
        @payload = genai_payload
      end

      def call
        iv = Claims::InvoiceVersion.find(@invoice_version_id)

        overall = @payload.is_a?(Hash) ? (@payload["overall"] || @payload[:overall] || {}) : {}
        conf = overall["overall_confidence"] || overall[:overall_confidence]
        pass = overall["all_rulechecks_pass_flag"] || overall[:all_rulechecks_pass_flag]
        advice = overall["admin_advice"] || overall[:admin_advice]

        conf_i = coerce_confidence(conf)
        pass_b = coerce_bool_or_nil(pass)
        advice_s = advice.nil? ? nil : advice.to_s

        iv.update!(
          genai_raw_json: @payload,
          genai_overall_confidence: conf_i,
          genai_all_rulechecks_pass_flag: pass_b,
          genai_admin_advice: advice_s
        )

        { ok: true }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def coerce_confidence(v)
        n = Integer(v || 0) rescue 0
        [[n, 0].max, 100].min
      end

      def coerce_bool_or_nil(v)
        return nil if v.nil?
        return v if v == true || v == false
        s = v.to_s.strip.downcase
        return true if %w[true t 1 yes y].include?(s)
        return false if %w[false f 0 no n].include?(s)
        nil
      end
    end
  end
end