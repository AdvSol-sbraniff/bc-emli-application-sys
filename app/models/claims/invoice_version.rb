# app/models/claims/invoice_version.rb
module Claims
  class InvoiceVersion < ApplicationRecord
    self.table_name = "claims.invoice_versions"

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id

    has_many :upload_runs,
             class_name: "Claims::UploadRun",
             foreign_key: :invoice_version_id,
             dependent: :destroy
  end
end

