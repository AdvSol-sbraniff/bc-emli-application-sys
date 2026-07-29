# frozen_string_literal: true

module Claims
  module PersonalInformation
    class NormalizeClassifierResult
      ALLOWED_STATUSES = %w[
        not_flagged
        review_recommended
        high_risk
        unable_to_assess
      ].freeze
      OUTPUT_KEYS = %w[
        personal_information_review_status
        personal_information_type_key
        personal_information_review_reason
      ].freeze

      def self.call(classifier_payload:)
        new(classifier_payload: classifier_payload).call
      end

      def initialize(classifier_payload:)
        @classifier_payload = classifier_payload
      end

      def call
        unless @classifier_payload.respond_to?(:key?)
          raise ArgumentError, "Classifier payload must be an object."
        end

        provided_keys = OUTPUT_KEYS.select { |key| payload_key?(key) }
        return {} if provided_keys.empty?

        if provided_keys.length != OUTPUT_KEYS.length
          missing_keys = OUTPUT_KEYS - provided_keys
          raise ArgumentError,
                "Classifier PI result is incomplete; missing #{missing_keys.join(", ")}."
        end

        status = payload_value("personal_information_review_status").to_s.strip
        unless ALLOWED_STATUSES.include?(status)
          raise ArgumentError,
                "Unknown personal_information_review_status #{status.inspect}."
        end

        type_key =
          payload_value("personal_information_type_key").to_s.strip.presence
        raw_reason = payload_value("personal_information_review_reason")
        reason = raw_reason.is_a?(String) ? raw_reason.presence : nil

        case status
        when "not_flagged"
          if type_key.present? || reason.present?
            raise ArgumentError,
                  "not_flagged requires a null PI type and null reason."
          end
        when "review_recommended", "high_risk"
          if type_key.blank? || reason.blank?
            raise ArgumentError,
                  "#{status} requires a configured PI type and nonblank reason."
          end
        when "unable_to_assess"
          if type_key.present? || reason.blank?
            raise ArgumentError,
                  "unable_to_assess requires a null PI type and nonblank reason."
          end
        end

        type =
          if type_key.present?
            ::Claims::PersonalInformationType.enabled.find_by(
              type_key: type_key
            )
          end
        if type_key.present? && type.nil?
          raise ArgumentError,
                "Unknown or disabled personal_information_type_key #{type_key.inspect}."
        end

        {
          personal_information_review_status: status,
          personal_information_type_id: type&.id,
          personal_information_review_reason: reason
        }
      end

      private

      def payload_key?(key)
        @classifier_payload.key?(key) || @classifier_payload.key?(key.to_sym)
      end

      def payload_value(key)
        if @classifier_payload.key?(key)
          @classifier_payload[key]
        else
          @classifier_payload[key.to_sym]
        end
      end
    end
  end
end
