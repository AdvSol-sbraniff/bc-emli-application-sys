# frozen_string_literal: true

module Claims
  class HervProduct < ApplicationRecord
    self.table_name = "claims.herv_products"

    belongs_to :import_run,
               class_name: "Claims::HervImportRun",
               foreign_key: :import_run_id
  end
end
