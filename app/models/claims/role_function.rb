module Claims
  class RoleFunction < ApplicationRecord
    self.table_name = "claims.role_functions"

    ROLE_KEYS = %w[contractor admin admin_manager system_admin].freeze

    belongs_to :function,
               class_name: "Claims::Function",
               foreign_key: :function_id,
               inverse_of: :role_functions

    validates :role_key, inclusion: { in: ROLE_KEYS }
    validates :function_id, uniqueness: { scope: :role_key }
  end
end
