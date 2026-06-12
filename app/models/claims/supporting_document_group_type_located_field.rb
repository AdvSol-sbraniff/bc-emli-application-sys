module Claims
  class SupportingDocumentGroupTypeLocatedField < ApplicationRecord
    self.table_name = "claims.supporting_document_group_type_located_fields"

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               inverse_of: :supporting_document_group_type_located_fields

    has_many :supporting_document_group_located_fields,
             class_name: "Claims::SupportingDocumentGroupLocatedField",
             foreign_key: :supporting_document_group_type_located_field_id,
             dependent: :nullify,
             inverse_of: :supporting_document_group_type_located_field
  end
end
