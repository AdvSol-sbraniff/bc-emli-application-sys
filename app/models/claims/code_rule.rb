# frozen_string_literal: true

module Claims
  class CodeRule < ApplicationRecord
    self.table_name = "claims.code_rules"

    CONTRACTOR_VISIBILITIES = %w[hidden fail_only warn_and_fail].freeze
    CONTRACTOR_BLOCKING_POLICIES = %w[non_blocking block_on_fail].freeze

    before_update :snapshot_history!

    has_many :code_rule_upgrade_types,
             class_name: "Claims::CodeRuleUpgradeType",
             foreign_key: :code_rule_id,
             inverse_of: :code_rule,
             dependent: :destroy

    has_many :invoice_upgrade_types,
             through: :code_rule_upgrade_types,
             class_name: "Claims::InvoiceUpgradeType"

    validates :source_quote, presence: true
    validates :contractor_display_name, presence: true
    validates :contractor_visibility, inclusion: { in: CONTRACTOR_VISIBILITIES }
    validates :contractor_blocking_policy,
              inclusion: {
                in: CONTRACTOR_BLOCKING_POLICIES
              }
    validate :contractor_blocker_must_be_visible

    private

    def snapshot_history!
      ::Claims::CodeRuleHistory.create!(
        source_id: id,
        code_rule_key: attribute_in_database("code_rule_key"),
        contractor_display_name:
          attribute_in_database("contractor_display_name"),
        description: attribute_in_database("description"),
        enabled: attribute_in_database("enabled"),
        pass_admin_message: attribute_in_database("pass_admin_message"),
        warn_admin_message: attribute_in_database("warn_admin_message"),
        fail_admin_message: attribute_in_database("fail_admin_message"),
        info_admin_message: attribute_in_database("info_admin_message"),
        admin_notes: attribute_in_database("admin_notes"),
        source_quote: attribute_in_database("source_quote"),
        contractor_visibility: attribute_in_database("contractor_visibility"),
        contractor_blocking_policy:
          attribute_in_database("contractor_blocking_policy"),
        source_created_at: attribute_in_database("created_at"),
        source_updated_at: attribute_in_database("updated_at")
      )
    end

    def contractor_blocker_must_be_visible
      return unless contractor_visibility == "hidden"
      return unless contractor_blocking_policy == "block_on_fail"

      errors.add(
        :contractor_blocking_policy,
        "cannot block submission when the rule is hidden from contractors"
      )
    end
  end
end
