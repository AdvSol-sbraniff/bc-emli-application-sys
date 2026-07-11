# frozen_string_literal: true

module Claims
  class CodeRule < ApplicationRecord
    self.table_name = "claims.code_rules"

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
    validates :contractor_visible_flag, inclusion: { in: [true, false] }

    private

    def snapshot_history!
      ::Claims::CodeRuleHistory.create!(
        source_id: id,
        code_rule_key: code_rule_key,
        description: description,
        enabled: enabled,
        pass_admin_message: pass_admin_message,
        warn_admin_message: warn_admin_message,
        fail_admin_message: fail_admin_message,
        info_admin_message: info_admin_message,
        admin_notes: admin_notes,
        source_quote: source_quote,
        contractor_visible_flag: contractor_visible_flag,
        source_created_at: created_at,
        source_updated_at: updated_at
      )
    end
  end
end
