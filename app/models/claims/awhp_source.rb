# frozen_string_literal: true

module Claims
  class AwhpSource < ApplicationRecord
    self.table_name = "claims.awhp_sources"

    has_many :awhp_import_runs,
             class_name: "Claims::AwhpImportRun",
             foreign_key: :awhp_source_id,
             inverse_of: :awhp_source
  end
end
