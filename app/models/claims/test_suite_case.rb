# frozen_string_literal: true

module Claims
  class TestSuiteCase < ApplicationRecord
    self.table_name = "claims.testsuite_cases"

    belongs_to :test_suite,
               class_name: "Claims::TestSuite",
               foreign_key: :testsuite_id,
               inverse_of: :test_suite_cases
    belongs_to :baseline_invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :baseline_invoice_version_id
    belongs_to :baseline_ingest_run,
               class_name: "Claims::IngestRun",
               foreign_key: :baseline_ingest_run_id

    validates :name,
              presence: true,
              length: {
                maximum: 200
              },
              uniqueness: {
                scope: :testsuite_id
              }
    validates :baseline_invoice_version_id, uniqueness: { scope: :testsuite_id }
  end
end
