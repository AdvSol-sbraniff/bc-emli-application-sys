# frozen_string_literal: true

module Claims
  class CurrentAwhpProduct < ApplicationRecord
    self.table_name = "claims.v_current_awhp_products"

    def readonly?
      true
    end
  end
end
