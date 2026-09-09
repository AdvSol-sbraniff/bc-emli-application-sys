# frozen_string_literal: true

module Claims
  class VRuleImprovementReporting < ApplicationRecord
    self.table_name = "claims.v_rule_improvement_reporting"
    self.primary_key = "rulecheck_id"

    def readonly?
      true
    end
  end
end
