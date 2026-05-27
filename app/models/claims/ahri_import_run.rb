# frozen_string_literal: true

module Claims
  class AhriImportRun < ApplicationRecord
    self.table_name = "claims.ahri_import_runs"

    belongs_to :ahri_source,
               class_name: "Claims::AhriSource",
               foreign_key: :ahri_source_id,
               inverse_of: :ahri_import_runs

    has_many :ahri_products,
             class_name: "Claims::AhriProduct",
             foreign_key: :import_run_id,
             dependent: :restrict_with_exception
  end
end
