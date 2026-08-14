module Claims
  class Function < ApplicationRecord
    self.table_name = "claims.functions"

    has_many :role_functions,
             class_name: "Claims::RoleFunction",
             foreign_key: :function_id,
             inverse_of: :function,
             dependent: :delete_all

    validates :function_key, presence: true, uniqueness: true
  end
end
