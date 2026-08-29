# frozen_string_literal: true

module Claims
  class TestSuite < ApplicationRecord
    self.table_name = "claims.testsuites"

    has_many :test_suite_cases,
             class_name: "Claims::TestSuiteCase",
             foreign_key: :testsuite_id,
             inverse_of: :test_suite,
             dependent: :destroy
    has_many :model_compares,
             class_name: "Claims::TestRunModelCompare",
             foreign_key: :testsuite_id,
             dependent: :restrict_with_error
    has_many :rule_compares,
             class_name: "Claims::TestRunRuleCompare",
             foreign_key: :testsuite_id,
             dependent: :restrict_with_error
    has_many :regressions,
             class_name: "Claims::TestRunRegression",
             foreign_key: :testsuite_id,
             dependent: :restrict_with_error

    validates :name, presence: true, uniqueness: true, length: { maximum: 200 }
  end
end
