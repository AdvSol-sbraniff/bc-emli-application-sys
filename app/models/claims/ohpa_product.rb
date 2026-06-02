# frozen_string_literal: true

module Claims
  class OhpaProduct < ApplicationRecord
    self.table_name = "claims.ohpa_products"

    belongs_to :import_run,
               class_name: "Claims::OhpaImportRun",
               foreign_key: :import_run_id
  end
end
