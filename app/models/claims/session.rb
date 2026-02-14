module Claims
  class Session < ApplicationRecord
    self.table_name = "claims.sessions"
  end
end
