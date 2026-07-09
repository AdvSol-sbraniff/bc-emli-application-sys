# frozen_string_literal: true

module Claims
  class CurrentHervProduct < ApplicationRecord
    self.table_name = "claims.v_current_herv_products"

    def readonly?
      true
    end
  end
end
