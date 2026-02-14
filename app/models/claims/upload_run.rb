# app/models/claims/upload_run.rb
module Claims
  class UploadRun < ApplicationRecord
    self.table_name = "claims.upload_runs"

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id
  end
end
