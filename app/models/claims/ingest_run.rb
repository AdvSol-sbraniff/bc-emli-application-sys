# app/models/claims/ingest_run.rb
module Claims
  class IngestRun < ApplicationRecord
    self.table_name = "claims.ingest_runs"

    RUN_KINDS = %w[initial_upload fix_upload rules_rerun].freeze
    ACTIVE_STATUSES = %w[queued running].freeze
    TERMINAL_STATUSES = %w[succeeded failed].freeze

    scope :active, -> { where(status: ACTIVE_STATUSES) }

    has_many :ingest_documents,
             class_name: "Claims::IngestDocument",
             foreign_key: :ingest_run_id,
             dependent: :delete_all

    has_many :ingest_step_runs,
             class_name: "Claims::IngestStepRun",
             foreign_key: :ingest_run_id,
             dependent: :delete_all

    belongs_to :contractor,
               class_name: "Contractor",
               foreign_key: :contractor_id,
               optional: true

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id,
               optional: true

    belongs_to :resolved_invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :resolved_invoice_version_id,
               optional: true
  end
end
