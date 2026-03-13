module Claims
  class VReportingInvoiceBusiness < ApplicationRecord
    self.table_name = "claims.v_reporting_invoice_business"
    self.primary_key = "invoice_id"

    def readonly?
      true
    end
  end
end
