# frozen_string_literal: true

module Claims
  class VentFanImportRun < ApplicationRecord
    self.table_name = "claims.vent_fan_import_runs"

    belongs_to :vent_fan_source,
               class_name: "Claims::VentFanSource",
               foreign_key: :vent_fan_source_id,
               inverse_of: :vent_fan_import_runs

    has_many :vent_fan_products,
             class_name: "Claims::VentFanProduct",
             foreign_key: :import_run_id,
             dependent: :restrict_with_exception
  end
end
