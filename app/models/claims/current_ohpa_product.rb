# frozen_string_literal: true

module Claims
  class CurrentOhpaProduct < ApplicationRecord
    self.table_name = "claims.v_current_ohpa_products"

    def readonly?
      true
    end
  end
end
