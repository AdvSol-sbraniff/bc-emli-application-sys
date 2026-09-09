# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    module CurrentRulePeriod
      JOIN_SQL = <<~SQL.squish.freeze
        LEFT JOIN claims.genai_rules current_reporting_genai_rule
          ON current_reporting_genai_rule.genai_rule_key = v_rule_improvement_reporting.rule_key
         AND v_rule_improvement_reporting.source_engine = 'genai'
        LEFT JOIN (
          SELECT source_id, MAX(history_created_at) AS effective_at
          FROM claims.genai_rule_history
          GROUP BY source_id
        ) current_reporting_history
          ON current_reporting_history.source_id = current_reporting_genai_rule.id
        LEFT JOIN claims.code_rules current_reporting_code_rule
          ON current_reporting_code_rule.code_rule_key = v_rule_improvement_reporting.rule_key
         AND v_rule_improvement_reporting.source_engine = 'code'
      SQL

      CURRENT_PERIOD_SQL = <<~SQL.squish.freeze
        (
          (
            v_rule_improvement_reporting.source_engine = 'genai'
            AND v_rule_improvement_reporting.rulecheck_created_at >=
              COALESCE(
                current_reporting_history.effective_at,
                current_reporting_genai_rule.created_at
              )
          )
          OR
          (
            v_rule_improvement_reporting.source_engine = 'code'
            AND v_rule_improvement_reporting.rulecheck_created_at >=
              current_reporting_code_rule.created_at
          )
        )
      SQL

      module_function

      def apply(scope)
        scope.joins(Arel.sql(JOIN_SQL)).where(Arel.sql(CURRENT_PERIOD_SQL))
      end
    end
  end
end
