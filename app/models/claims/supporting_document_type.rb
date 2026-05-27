module Claims
  class SupportingDocumentType < ApplicationRecord
    self.table_name = "claims.supporting_document_types"

    has_many :supporting_documents,
             class_name: "Claims::SupportingDocument",
             foreign_key: :supporting_document_type_id,
             dependent: :restrict_with_exception
  end
end
