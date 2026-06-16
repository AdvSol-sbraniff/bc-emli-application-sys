module Claims
  class IngestStepRun < ApplicationRecord
    self.table_name = "claims.ingest_step_runs"

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id,
               optional: true

    belongs_to :ingest_document,
               class_name: "Claims::IngestDocument",
               foreign_key: :ingest_document_id,
               optional: true

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               optional: true
  end
end
