# frozen_string_literal: true

module Claims
  class TestRunRegressionCase < ApplicationRecord
    self.table_name = "claims.testrunregression_cases"

    STATUSES = %w[queued running completed failed skipped cancelled].freeze

    belongs_to :test_run,
               class_name: "Claims::TestRunRegression",
               foreign_key: :testrunregression_id,
               inverse_of: :test_cases
    belongs_to :test_suite_case,
               class_name: "Claims::TestSuiteCase",
               foreign_key: :testsuite_case_id
    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id,
               optional: true
    belongs_to :ingest_run,
               class_name: "Claims::IngestRun",
               foreign_key: :ingest_run_id,
               optional: true

    validates :status, inclusion: { in: STATUSES }
  end
end
