module Claims
  class SupportingDocument < ApplicationRecord
    self.table_name = "claims.supporting_documents"

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id
  end
end
