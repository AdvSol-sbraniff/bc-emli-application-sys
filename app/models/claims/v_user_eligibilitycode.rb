# app/models/claims/v_user_eligibilitycode.rb
module Claims
  class VUserEligibilitycode < ApplicationRecord
    self.table_name = "claims.v_user_eligibilitycodes"

    # Read-only view
    def readonly?
      true
    end
  end
end
