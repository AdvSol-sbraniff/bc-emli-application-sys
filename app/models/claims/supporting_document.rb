module Claims
  class SupportingDocument < ApplicationRecord
    self.table_name = "claims.supporting_documents"

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               optional: true
  end
end
