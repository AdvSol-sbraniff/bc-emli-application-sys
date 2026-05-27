# frozen_string_literal: true

module Claims
  class CurrentAhriProduct < ApplicationRecord
    self.table_name = "claims.v_current_ahri_products"

    def readonly?
      true
    end
  end
end
