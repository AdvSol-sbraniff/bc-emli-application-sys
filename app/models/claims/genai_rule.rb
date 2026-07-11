# frozen_string_literal: true

module Claims
  class GenaiRule < ApplicationRecord
    self.table_name = "claims.genai_rules"

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
    validates :contractor_visible_flag, inclusion: { in: [true, false] }

    private

    def snapshot_history!
      ::Claims::GenaiRuleHistory.create!(
        source_id: id,
        genai_rule_key: genai_rule_key,
        prompt_text: prompt_text,
        enabled: enabled,
        source_quote: source_quote,
        contractor_visible_flag: contractor_visible_flag,
        source_created_at: created_at,
        source_updated_at: updated_at
      )
    end
  end
end
