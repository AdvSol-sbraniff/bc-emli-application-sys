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
        pass =
          fetch_hash_value(
            overall,
            "all_rulechecks_pass_flag",
            :all_rulechecks_pass_flag
          )
        advice = fetch_hash_value(overall, "admin_advice", :admin_advice)

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
