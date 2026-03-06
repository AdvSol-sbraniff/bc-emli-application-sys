# app/models/claims/v_session_with_contractor.rb
module Claims
  class VSessionWithContractor < ApplicationRecord
    self.table_name = "claims.v_sessions_with_contractors"
    self.primary_key = "id"  # session id

    # read-only view
    def readonly?
      true
    end
  end
end