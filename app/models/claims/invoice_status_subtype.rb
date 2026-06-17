module Claims
  class InvoiceStatusSubtype < ApplicationRecord
    self.table_name = "claims.invoice_status_subtypes"
    self.primary_key = nil

    scope :active, -> { where(active: true) }
  end
end
