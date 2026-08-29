# frozen_string_literal: true

module Claims
  class TestRunModelCompare < ApplicationRecord
    self.table_name = "claims.testrunmodelcompares"

    STATUSES = %w[draft queued running completed failed cancelled].freeze
    DEPLOYMENT_ATTRIBUTES = %i[
      baseline_document_triage_deployment_name
      baseline_supporting_document_extraction_deployment_name
      baseline_upgrade_analysis_deployment_name
      candidate_document_triage_deployment_name
      candidate_supporting_document_extraction_deployment_name
      candidate_upgrade_analysis_deployment_name
      comparison_deployment_name
    ].freeze

    belongs_to :test_suite,
               class_name: "Claims::TestSuite",
               foreign_key: :testsuite_id
    has_many :test_cases,
             class_name: "Claims::TestRunModelCompareCase",
             foreign_key: :testrunmodelcompare_id,
             inverse_of: :test_run,
             dependent: :destroy

    validates :status, inclusion: { in: STATUSES }
    validates(*DEPLOYMENT_ATTRIBUTES, presence: true, length: { maximum: 200 })
  end
end
