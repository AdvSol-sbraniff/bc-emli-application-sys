# frozen_string_literal: true

module Claims
  class NeeaProduct < ApplicationRecord
    self.table_name = "claims.neea_products"

    belongs_to :import_run,
               class_name: "Claims::NeeaImportRun",
               foreign_key: :import_run_id
  end
end
