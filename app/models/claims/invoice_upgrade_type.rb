module Claims
  class InvoiceUpgradeType < ApplicationRecord
    self.table_name = "claims.invoice_upgrade_types"

    has_many :code_rule_upgrade_types,
             class_name: "Claims::CodeRuleUpgradeType",
             foreign_key: :invoice_upgrade_type_id

    has_many :code_rules,
             through: :code_rule_upgrade_types,
             class_name: "Claims::CodeRule"

    has_many :genai_rule_upgrade_types,
             class_name: "Claims::GenaiRuleUpgradeType",
             foreign_key: :invoice_upgrade_type_id

    has_many :genai_rules,
             through: :genai_rule_upgrade_types,
             class_name: "Claims::GenaiRule"

    has_many :genai_located_field_upgrade_types,
             class_name: "Claims::GenaiLocatedFieldUpgradeType",
             foreign_key: :invoice_upgrade_type_id

    has_many :genai_located_fields,
             through: :genai_located_field_upgrade_types,
             class_name: "Claims::GenaiLocatedField"
  end
end
