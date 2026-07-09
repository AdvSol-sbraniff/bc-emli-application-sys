# frozen_string_literal: true

module Claims
  class HervImportRun < ApplicationRecord
    self.table_name = "claims.herv_import_runs"

    belongs_to :herv_source,
               class_name: "Claims::HervSource",
               foreign_key: :herv_source_id,
               inverse_of: :herv_import_runs

    has_many :herv_products,
             class_name: "Claims::HervProduct",
             foreign_key: :import_run_id,
             dependent: :restrict_with_exception
  end
end
