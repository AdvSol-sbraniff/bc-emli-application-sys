# frozen_string_literal: true

module Claims
  class VentFanSource < ApplicationRecord
    self.table_name = "claims.vent_fan_sources"

    has_many :vent_fan_import_runs,
             class_name: "Claims::VentFanImportRun",
             foreign_key: :vent_fan_source_id,
             inverse_of: :vent_fan_source
  end
end
