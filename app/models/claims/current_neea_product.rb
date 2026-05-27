# frozen_string_literal: true

module Claims
  class CurrentNeeaProduct < ApplicationRecord
    self.table_name = "claims.v_current_neea_products"

    def readonly?
      true
    end
  end
end
