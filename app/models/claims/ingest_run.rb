# app/models/claims/ingest_run.rb
module Claims
  class IngestRun < ApplicationRecord
    self.table_name = "claims.ingest_runs"

    has_many :ingest_documents,
             class_name: "Claims::IngestDocument",
             foreign_key: :ingest_run_id,
             dependent: :delete_all

    belongs_to :contractor,
               class_name: "Contractor",
               foreign_key: :contractor_id,
               optional: true
  end
end
