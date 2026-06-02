# frozen_string_literal: true

module Claims
  class OhpaImportRun < ApplicationRecord
    self.table_name = "claims.ohpa_import_runs"

    belongs_to :ohpa_source,
               class_name: "Claims::OhpaSource",
               foreign_key: :ohpa_source_id,
               inverse_of: :ohpa_import_runs

    has_many :ohpa_products,
             class_name: "Claims::OhpaProduct",
             foreign_key: :import_run_id,
             dependent: :restrict_with_exception
  end
end
