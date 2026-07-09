# frozen_string_literal: true

module Claims
  class CurrentVentFanProduct < ApplicationRecord
    self.table_name = "claims.v_current_vent_fan_products"

    def readonly?
      true
    end
  end
end
