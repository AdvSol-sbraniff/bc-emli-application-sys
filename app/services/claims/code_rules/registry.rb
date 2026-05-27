# frozen_string_literal: true

module Claims
  module CodeRules
    class Registry
      ADMIN_MESSAGE_BY_RESULT = {
        "pass" => :pass_admin_message,
        "warn" => :warn_admin_message,
        "fail" => :fail_admin_message,
        "info" => :info_admin_message
      }.freeze

      def self.enabled_for?(code_rule_key:, invoice_upgrade_type_id:, fallback: true)
        new(code_rule_key: code_rule_key, invoice_upgrade_type_id: invoice_upgrade_type_id)
          .enabled_for?(fallback: fallback)
      end

      def self.admin_message(code_rule_key:, rule_result:)
        new(code_rule_key: code_rule_key, invoice_upgrade_type_id: nil)
          .admin_message(rule_result: rule_result)
      end

      def initialize(code_rule_key:, invoice_upgrade_type_id:)
        @code_rule_key = code_rule_key.to_s
        @invoice_upgrade_type_id = invoice_upgrade_type_id
      end

      def enabled_for?(fallback: true)
        return fallback if code_rule_key.blank? || invoice_upgrade_type_id.blank?

        rule = code_rule
        return fallback unless rule
        return false unless rule.enabled?

        ::Claims::CodeRuleUpgradeType.exists?(
          code_rule_id: rule.id,
          invoice_upgrade_type_id: invoice_upgrade_type_id
        )
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        fallback
      end

      def admin_message(rule_result:)
        column = ADMIN_MESSAGE_BY_RESULT[rule_result.to_s]
        return nil unless column

        code_rule&.public_send(column).presence
      rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
        nil
      end

      private

      attr_reader :code_rule_key, :invoice_upgrade_type_id

      def code_rule
        @code_rule ||= ::Claims::CodeRule.find_by(code_rule_key: code_rule_key)
      end
    end
  end
end
