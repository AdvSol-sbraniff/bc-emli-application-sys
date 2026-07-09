# frozen_string_literal: true

module Claims
  class HervSource < ApplicationRecord
    self.table_name = "claims.herv_sources"

    has_many :herv_import_runs,
             class_name: "Claims::HervImportRun",
             foreign_key: :herv_source_id,
             inverse_of: :herv_source
  end
end
