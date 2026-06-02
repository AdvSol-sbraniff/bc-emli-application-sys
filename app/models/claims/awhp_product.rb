# frozen_string_literal: true

module Claims
  class AwhpProduct < ApplicationRecord
    self.table_name = "claims.awhp_products"

    belongs_to :import_run,
               class_name: "Claims::AwhpImportRun",
               foreign_key: :import_run_id
  end
end
