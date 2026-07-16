# frozen_string_literal: true

module Claims
  class GenaiRule < ApplicationRecord
    self.table_name = "claims.genai_rules"

    CONTRACTOR_VISIBILITIES = %w[hidden fail_only warn_and_fail].freeze
    CONTRACTOR_BLOCKING_POLICIES = %w[non_blocking block_on_fail].freeze
    ADMIN_WORKFLOW_POLICIES = %w[not_managed fail_only warn_and_fail].freeze

    before_update :snapshot_history!

    has_many :genai_rule_upgrade_types,
             class_name: "Claims::GenaiRuleUpgradeType",
             foreign_key: :genai_rule_id,
             inverse_of: :genai_rule,
             dependent: :destroy

    has_many :invoice_upgrade_types,
             through: :genai_rule_upgrade_types,
             class_name: "Claims::InvoiceUpgradeType"

    validates :source_quote, presence: true
    validates :contractor_display_name, presence: true
    validates :contractor_visibility, inclusion: { in: CONTRACTOR_VISIBILITIES }
    validates :contractor_blocking_policy,
              inclusion: {
                in: CONTRACTOR_BLOCKING_POLICIES
              }
    validates :admin_workflow_policy, inclusion: { in: ADMIN_WORKFLOW_POLICIES }
    validate :contractor_blocker_must_be_visible

    private

    def snapshot_history!
      ::Claims::GenaiRuleHistory.create!(
        source_id: id,
        genai_rule_key: attribute_in_database("genai_rule_key"),
        contractor_display_name:
          attribute_in_database("contractor_display_name"),
        prompt_text: attribute_in_database("prompt_text"),
        enabled: attribute_in_database("enabled"),
        source_quote: attribute_in_database("source_quote"),
        contractor_visibility: attribute_in_database("contractor_visibility"),
        contractor_blocking_policy:
          attribute_in_database("contractor_blocking_policy"),
        admin_workflow_policy: attribute_in_database("admin_workflow_policy"),
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
