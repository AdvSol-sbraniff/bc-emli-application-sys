module Claims
  class SupportingDocumentGroup < ApplicationRecord
    self.table_name = "claims.supporting_document_groups"

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id,
               inverse_of: :supporting_document_groups

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               inverse_of: :supporting_document_groups

    has_many :supporting_documents,
             class_name: "Claims::SupportingDocument",
             foreign_key: :supporting_document_group_id,
             dependent: :nullify,
             inverse_of: :supporting_document_group

    has_many :supporting_document_group_located_fields,
             class_name: "Claims::SupportingDocumentGroupLocatedField",
             foreign_key: :supporting_document_group_id,
             dependent: :destroy,
             inverse_of: :supporting_document_group
  end
end
