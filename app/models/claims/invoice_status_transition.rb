# frozen_string_literal: true

module Claims
  class InvoiceStatusTransition < ApplicationRecord
    self.table_name = "claims.invoice_status_transitions"

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id,
               inverse_of: :status_transitions

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id,
               optional: true

    belongs_to :actor_user,
               class_name: "::User",
               foreign_key: :actor_user_id,
               optional: true

    validates :to_status, presence: true

    def readonly?
      persisted?
    end
  end
end
