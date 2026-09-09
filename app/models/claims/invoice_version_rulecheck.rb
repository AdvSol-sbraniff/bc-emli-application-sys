# frozen_string_literal: true

module Claims
  class InvoiceVersionRulecheck < ApplicationRecord
    self.table_name = "claims.invoice_version_rulechecks"

    REASON_COMPLAINT_CODES = %w[
      unclear_or_confusing
      too_vague
      missing_evidence_explanation
      incorrect_evidence_or_reasoning
      likely_causes_unhelpful
      required_action_unclear
      irrelevant_or_duplicative
      too_verbose_or_repetitive
      other
    ].freeze

    before_validation :normalize_reason_complaint

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id,
               inverse_of: :rulechecks

    validates :reason_complaint_code,
              inclusion: {
                in: REASON_COMPLAINT_CODES
              },
              allow_nil: true
    validate :reason_complaint_shape

    scope :with_current_rule_policies, -> { joins(<<~SQL.squish) }
              LEFT JOIN claims.genai_rules contractor_policy_gr
                ON claims.invoice_version_rulechecks.source_engine = 'genai'
               AND contractor_policy_gr.genai_rule_key = claims.invoice_version_rulechecks.rule_key
              LEFT JOIN claims.code_rules contractor_policy_cr
                ON claims.invoice_version_rulechecks.source_engine = 'code'
               AND contractor_policy_cr.code_rule_key = claims.invoice_version_rulechecks.rule_key
            SQL

    scope :contractor_actionable,
          -> do
            with_current_rule_policies.where(
              "(COALESCE(contractor_policy_gr.contractor_visibility, contractor_policy_cr.contractor_visibility, 'hidden') = 'fail_only' AND claims.invoice_version_rulechecks.rule_result = 'fail') OR " \
                "(COALESCE(contractor_policy_gr.contractor_visibility, contractor_policy_cr.contractor_visibility, 'hidden') = 'warn_and_fail' AND claims.invoice_version_rulechecks.rule_result IN ('warn', 'fail'))"
            )
          end

    scope :contractor_blocking,
          -> do
            with_current_rule_policies.where(
              "COALESCE(contractor_policy_gr.contractor_blocking_policy, contractor_policy_cr.contractor_blocking_policy, 'non_blocking') = 'block_on_fail' AND " \
                "claims.invoice_version_rulechecks.rule_result = 'fail'"
            )
          end

    scope :admin_workflow_managed,
          -> do
            with_current_rule_policies.where(
              "(COALESCE(contractor_policy_gr.admin_workflow_policy, contractor_policy_cr.admin_workflow_policy, 'fail_only') = 'fail_only' AND claims.invoice_version_rulechecks.rule_result = 'fail') OR " \
                "(COALESCE(contractor_policy_gr.admin_workflow_policy, contractor_policy_cr.admin_workflow_policy, 'fail_only') = 'warn_and_fail' AND claims.invoice_version_rulechecks.rule_result IN ('warn', 'fail')) OR " \
                "(COALESCE(contractor_policy_gr.admin_workflow_policy, contractor_policy_cr.admin_workflow_policy, 'fail_only') = 'all_results' AND claims.invoice_version_rulechecks.rule_result IN ('pass', 'info', 'warn', 'fail'))"
            )
          end

    private

    def normalize_reason_complaint
      self.reason_complaint_code = reason_complaint_code.to_s.strip.presence
      self.reason_complaint_text = reason_complaint_text.to_s.strip.presence
    end

    def reason_complaint_shape
      if reason_complaint_text.present? && reason_complaint_code.blank?
        errors.add(
          :reason_complaint_code,
          "is required when complaint detail is provided"
        )
      end

      return unless reason_complaint_code == "other"
      return if reason_complaint_text.present?

      errors.add(:reason_complaint_text, "is required for Other")
    end
  end
end
