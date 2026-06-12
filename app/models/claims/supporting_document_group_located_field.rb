module Claims
  class SupportingDocumentGroupLocatedField < ApplicationRecord
    self.table_name = "claims.supporting_document_group_located_fields"

    belongs_to :supporting_document_group,
               class_name: "Claims::SupportingDocumentGroup",
               foreign_key: :supporting_document_group_id,
               inverse_of: :supporting_document_group_located_fields

    belongs_to :supporting_document_group_type_located_field,
               class_name: "Claims::SupportingDocumentGroupTypeLocatedField",
               foreign_key: :supporting_document_group_type_located_field_id,
               optional: true,
               inverse_of: :supporting_document_group_located_fields
  end
end
