# app/models/claims/invoice.rb
module Claims
  class Invoice < ApplicationRecord
    self.table_name = "claims.invoices"

    has_many :invoice_versions,
             class_name: "Claims::InvoiceVersion",
             foreign_key: :invoice_id,
             dependent: :destroy

    has_many :supporting_documents,
             class_name: "Claims::SupportingDocument",
             foreign_key: :invoice_id,
             dependent: :destroy

    has_many :internal_notes,
             class_name: "Claims::InternalNote",
             foreign_key: :invoice_id,
             dependent: :destroy

    has_many :ingest_documents,
             class_name: "Claims::IngestDocument",
             foreign_key: :invoice_id,
             dependent: :nullify

    has_many :supporting_document_types,
             through: :supporting_documents,
             source: :supporting_document_type
  end
end
