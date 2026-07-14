# frozen_string_literal: true

module Claims
  class InvoiceVersionRulecheck < ApplicationRecord
    self.table_name = "claims.invoice_version_rulechecks"

    scope :with_current_contractor_policy, -> { joins(<<~SQL.squish) }
              LEFT JOIN claims.genai_rules contractor_policy_gr
                ON claims.invoice_version_rulechecks.source_engine = 'genai'
               AND contractor_policy_gr.genai_rule_key = claims.invoice_version_rulechecks.rule_key
              LEFT JOIN claims.code_rules contractor_policy_cr
                ON claims.invoice_version_rulechecks.source_engine = 'code'
               AND contractor_policy_cr.code_rule_key = claims.invoice_version_rulechecks.rule_key
            SQL

    scope :contractor_actionable,
          -> do
            with_current_contractor_policy.where(
              "(COALESCE(contractor_policy_gr.contractor_visibility, contractor_policy_cr.contractor_visibility, 'hidden') = 'fail_only' AND claims.invoice_version_rulechecks.rule_result = 'fail') OR " \
                "(COALESCE(contractor_policy_gr.contractor_visibility, contractor_policy_cr.contractor_visibility, 'hidden') = 'warn_and_fail' AND claims.invoice_version_rulechecks.rule_result IN ('warn', 'fail'))"
            )
          end

    scope :contractor_blocking,
          -> do
            with_current_contractor_policy.where(
              "COALESCE(contractor_policy_gr.contractor_blocking_policy, contractor_policy_cr.contractor_blocking_policy, 'non_blocking') = 'block_on_fail' AND " \
                "claims.invoice_version_rulechecks.rule_result = 'fail'"
            )
          end
  end
end
