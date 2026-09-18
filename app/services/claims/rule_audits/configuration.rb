# frozen_string_literal: true

module Claims
  module RuleAudits
    class Configuration
      class Unavailable < StandardError
      end

      def self.default_system_record
        Rails
          .root
          .join("config/prompts/rule_package_audit_system.txt")
          .read
          .strip
      end

      def self.system_record
        config = ::Claims::ValidationgenaiConfig.order(:created_at).first
        unless config&.has_attribute?(:rule_audit_system_record)
          raise Unavailable,
                "Rule audit configuration is not installed. Apply the additive rule audit schema update."
        end
        config.rule_audit_system_record.to_s.strip.presence ||
          default_system_record
      end
    end
  end
end
