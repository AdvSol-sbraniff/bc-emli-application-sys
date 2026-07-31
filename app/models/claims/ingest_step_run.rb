module Claims
  class IngestStepRun < ApplicationRecord
    self.table_name = "claims.ingest_step_runs"

    TERMINAL_STATUSES = %w[succeeded failed].freeze

    belongs_to :ingest_run,
               class_name: "Claims::IngestRun",
               foreign_key: :ingest_run_id

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

    before_save :synchronize_completed_at

    private

    def synchronize_completed_at
      return unless will_save_change_to_status? || completed_at.nil?

      self.completed_at =
        TERMINAL_STATUSES.include?(status) ? completed_at || Time.current : nil
    end
  end
end
