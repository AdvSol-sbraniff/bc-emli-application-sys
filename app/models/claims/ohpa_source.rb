# frozen_string_literal: true

module Claims
  class OhpaSource < ApplicationRecord
    self.table_name = "claims.ohpa_sources"

    has_many :ohpa_import_runs,
             class_name: "Claims::OhpaImportRun",
             foreign_key: :ohpa_source_id,
             inverse_of: :ohpa_source
  end
end
