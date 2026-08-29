# frozen_string_literal: true

module Claims
  module TestHarness
    class RunLookup
      def self.harness_run?(ingest_run_id)
        ::Claims::TestRunModelCompareCase.where(
          candidate_ingest_run_id: ingest_run_id
        ).exists? ||
          ::Claims::TestRunRuleCompareCase.where(
            candidate_ingest_run_id: ingest_run_id
          ).exists? ||
          ::Claims::TestRunRegressionCase.where(
            ingest_run_id: ingest_run_id
          ).exists?
      end
    end
  end
end
