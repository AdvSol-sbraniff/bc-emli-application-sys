# frozen_string_literal: true

module Claims
  class InternalNote < ApplicationRecord
    self.table_name = "claims.internal_notes"

    belongs_to :invoice, class_name: "Claims::Invoice", foreign_key: :invoice_id

    belongs_to :admin_user, class_name: "User", foreign_key: :admin_user_id

    validates :invoice_id, presence: true
    validates :admin_user_id, presence: true
    validates :note_text, presence: true
  end
end
