# frozen_string_literal: true

module Claims
  class AwhpImportRun < ApplicationRecord
    self.table_name = "claims.awhp_import_runs"

    belongs_to :awhp_source,
               class_name: "Claims::AwhpSource",
               foreign_key: :awhp_source_id,
               inverse_of: :awhp_import_runs

    has_many :awhp_products,
             class_name: "Claims::AwhpProduct",
             foreign_key: :import_run_id,
             dependent: :restrict_with_exception
  end
end
