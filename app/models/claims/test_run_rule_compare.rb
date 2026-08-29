# frozen_string_literal: true

module Claims
  class TestRunRuleCompare < ApplicationRecord
    self.table_name = "claims.testrunrulecompares"

    STATUSES = %w[draft queued running completed failed cancelled].freeze

    belongs_to :test_suite,
               class_name: "Claims::TestSuite",
               foreign_key: :testsuite_id
    belongs_to :baseline_rule_history,
               class_name: "Claims::GenaiRuleHistory",
               foreign_key: :baseline_genai_rule_history_id
    belongs_to :candidate_rule,
               class_name: "Claims::GenaiRule",
               foreign_key: :candidate_genai_rule_id
    has_many :test_cases,
             class_name: "Claims::TestRunRuleCompareCase",
             foreign_key: :testrunrulecompare_id,
             inverse_of: :test_run,
             dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates :comparison_deployment_name,
              presence: true,
              length: {
                maximum: 200
              }
  end
end
