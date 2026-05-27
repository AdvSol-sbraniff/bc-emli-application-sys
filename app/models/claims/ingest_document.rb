module Claims
  class IngestDocument < ApplicationRecord
    self.table_name = "claims.ingest_documents"

    belongs_to :ingest_run,
               class_name: "Claims::IngestRun",
               foreign_key: :ingest_run_id

    belongs_to :session,
               class_name: "Claims::Session",
               foreign_key: :session_id

    belongs_to :contractor,
               class_name: "Contractor",
               foreign_key: :contractor_id

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               optional: true

    belongs_to :resolved_invoice,
               class_name: "Claims::Invoice",
               foreign_key: :resolved_invoice_id,
               optional: true

    belongs_to :resolved_invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :resolved_invoice_version_id,
               optional: true
  end
end
