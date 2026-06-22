# app/models/claims/invoice.rb
module Claims
  class Invoice < ApplicationRecord
    self.table_name = "claims.invoices"

    FAILURE_STATUSES = %w[package_needs_correction technical_failure].freeze

    has_many :invoice_versions,
             class_name: "Claims::InvoiceVersion",
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

    def set_workflow_status!(status, status_subtype: nil, **attrs)
      status = status.to_s
      attrs = attrs.symbolize_keys
      attrs[:status] = status
      attrs[:status_subtype] = if FAILURE_STATUSES.include?(status)
        ::Claims::Invoices::StatusSubtypes.normalize(status, status_subtype)
      end
      attrs[:status_updated_at] ||= Time.current
      attrs[:updated_at] ||= Time.current
      update!(attrs)
    end

    def set_workflow_status_columns!(
      status,
      status_subtype: nil,
      now: Time.current
    )
      status = status.to_s
      update_columns(
        status: status,
        status_subtype:
          (
            if FAILURE_STATUSES.include?(status)
              ::Claims::Invoices::StatusSubtypes.normalize(
                status,
                status_subtype
              )
            end
          ),
        status_updated_at: now,
        updated_at: now
      )
    end
  end
end
