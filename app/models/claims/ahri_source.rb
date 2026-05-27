# frozen_string_literal: true

module Claims
  class AhriSource < ApplicationRecord
    self.table_name = "claims.ahri_sources"

    has_many :ahri_import_runs,
             class_name: "Claims::AhriImportRun",
             foreign_key: :ahri_source_id,
             inverse_of: :ahri_source
  end
end
