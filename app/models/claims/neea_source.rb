# frozen_string_literal: true

module Claims
  class NeeaSource < ApplicationRecord
    self.table_name = "claims.neea_sources"

    has_many :neea_import_runs,
             class_name: "Claims::NeeaImportRun",
             foreign_key: :neea_source_id,
             inverse_of: :neea_source
  end
end
