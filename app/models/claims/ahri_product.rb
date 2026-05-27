# frozen_string_literal: true

module Claims
  class AhriProduct < ApplicationRecord
    self.table_name = "claims.ahri_products"

    belongs_to :import_run,
               class_name: "Claims::AhriImportRun",
               foreign_key: :import_run_id
  end
end
