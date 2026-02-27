# app/models/claims/invoice_grid.rb
module Claims
  class InvoiceGrid < ApplicationRecord
    self.table_name  = "claims.v_invoice_grid"
    self.primary_key = "invoice_id"

    def readonly?
      true
    end
  end
end