# frozen_string_literal: true

module Claims
  class VIngestRun < ApplicationRecord
    self.table_name = "claims.v_ingest_runs"
    self.primary_key = "id"

    def readonly?
      true
    end
  end
end
