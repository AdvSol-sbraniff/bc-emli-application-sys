# frozen_string_literal: true

module Claims
  class NeeaImportRun < ApplicationRecord
    self.table_name = "claims.neea_import_runs"

    belongs_to :neea_source,
               class_name: "Claims::NeeaSource",
               foreign_key: :neea_source_id,
               inverse_of: :neea_import_runs

    has_many :neea_products,
             class_name: "Claims::NeeaProduct",
             foreign_key: :import_run_id,
             dependent: :restrict_with_exception
  end
end
