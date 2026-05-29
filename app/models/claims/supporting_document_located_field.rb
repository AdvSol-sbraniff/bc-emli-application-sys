module Claims
  class SupportingDocumentLocatedField < ApplicationRecord
    self.table_name = "claims.supporting_document_located_fields"

    belongs_to :supporting_document,
               class_name: "Claims::SupportingDocument",
               foreign_key: :supporting_document_id,
               inverse_of: :supporting_document_located_fields

    belongs_to :supporting_document_type_located_field,
               class_name: "Claims::SupportingDocumentTypeLocatedField",
               foreign_key: :supporting_document_type_located_field_id,
               optional: true,
               inverse_of: :supporting_document_located_fields
  end
end
