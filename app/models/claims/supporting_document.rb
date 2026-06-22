module Claims
  class SupportingDocument < ApplicationRecord
    self.table_name = "claims.supporting_documents"

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               optional: true

    has_many :supporting_document_located_fields,
             class_name: "Claims::SupportingDocumentLocatedField",
             foreign_key: :supporting_document_id,
             dependent: :destroy,
             inverse_of: :supporting_document

    has_many :supporting_document_visual_findings,
             class_name: "Claims::SupportingDocumentVisualFinding",
             foreign_key: :supporting_document_id,
             dependent: :destroy,
             inverse_of: :supporting_document
  end
end
