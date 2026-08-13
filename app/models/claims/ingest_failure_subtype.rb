module Claims
  class IngestFailureSubtype < ApplicationRecord
    self.table_name = "claims.ingest_failure_subtypes"
    self.primary_key = nil

    scope :active, -> { where(active: true) }
  end
end
