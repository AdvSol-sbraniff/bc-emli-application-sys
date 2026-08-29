# frozen_string_literal: true

module Claims
  class TestRunModelCompareCase < ApplicationRecord
    self.table_name = "claims.testrunmodelcompare_cases"

    STATUSES = %w[queued running completed failed skipped cancelled].freeze

    belongs_to :test_run,
               class_name: "Claims::TestRunModelCompare",
               foreign_key: :testrunmodelcompare_id,
               inverse_of: :test_cases
    belongs_to :test_suite_case,
               class_name: "Claims::TestSuiteCase",
               foreign_key: :testsuite_case_id
    belongs_to :baseline_invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :baseline_invoice_version_id
    belongs_to :baseline_ingest_run,
               class_name: "Claims::IngestRun",
               foreign_key: :baseline_ingest_run_id
    belongs_to :candidate_invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :candidate_invoice_version_id,
               optional: true
    belongs_to :candidate_ingest_run,
               class_name: "Claims::IngestRun",
               foreign_key: :candidate_ingest_run_id,
               optional: true

    validates :status, inclusion: { in: STATUSES }
  end
end
