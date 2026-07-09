# frozen_string_literal: true

module Claims
  class VentFanProduct < ApplicationRecord
    self.table_name = "claims.vent_fan_products"

    belongs_to :import_run,
               class_name: "Claims::VentFanImportRun",
               foreign_key: :import_run_id
  end
end
