# frozen_string_literal: true

module Claims
  class GenaiRuleUpgradeType < ApplicationRecord
    self.table_name = "claims.genai_rule_upgrade_types"

    before_update :snapshot_history!
    before_destroy :snapshot_history!

    belongs_to :genai_rule,
               class_name: "Claims::GenaiRule",
               foreign_key: :genai_rule_id,
               inverse_of: :genai_rule_upgrade_types

    belongs_to :invoice_upgrade_type,
               class_name: "Claims::InvoiceUpgradeType",
               foreign_key: :invoice_upgrade_type_id

    private

    def snapshot_history!
      ::Claims::GenaiRuleUpgradeTypeHistory.create!(
        source_id: id,
        genai_rule_id: genai_rule_id,
        invoice_upgrade_type_id: invoice_upgrade_type_id,
        source_created_at: created_at,
        source_updated_at: updated_at
      )
    end
  end
end
