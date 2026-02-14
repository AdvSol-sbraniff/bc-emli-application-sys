# app/models/claims/invoice_version_located_field.rb
module Claims
  class InvoiceVersionLocatedField < ApplicationRecord
    self.table_name = "claims.invoice_version_located_fields"

    belongs_to :invoice_version,
      class_name: "Claims::InvoiceVersion",
      foreign_key: :invoice_version_id,
      inverse_of: :located_fields,
      optional: false
  end
end
