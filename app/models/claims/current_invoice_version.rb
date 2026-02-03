module Claims
  class CurrentInvoiceVersion < ApplicationRecord
    self.table_name = "claims.v_current_invoice_versions"

    # This view should be read-only
    def readonly?
      true
    end

    # Optional: view has iv.id (invoice_versions.id). Use as primary key.
    self.primary_key = "id"
  end
end
