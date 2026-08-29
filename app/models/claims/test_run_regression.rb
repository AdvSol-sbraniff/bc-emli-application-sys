# frozen_string_literal: true

module Claims
  class TestRunRegression < ApplicationRecord
    self.table_name = "claims.testrunregressions"

    STATUSES = %w[draft queued running completed failed cancelled].freeze
    DEPLOYMENT_ATTRIBUTES = %i[
      document_triage_deployment_name
      supporting_document_extraction_deployment_name
      upgrade_analysis_deployment_name
    ].freeze

    belongs_to :test_suite,
               class_name: "Claims::TestSuite",
               foreign_key: :testsuite_id
    has_many :test_cases,
             class_name: "Claims::TestRunRegressionCase",
             foreign_key: :testrunregression_id,
             inverse_of: :test_run,
             dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates(*DEPLOYMENT_ATTRIBUTES, presence: true, length: { maximum: 200 })
  end
end
