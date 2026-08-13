# app/models/claims/invoice.rb
module Claims
  class Invoice < ApplicationRecord
    self.table_name = "claims.invoices"

    STATUSES = %w[
      contractor_precheck
      admin_review_inbox
      contractor_revision_inbox
      in_review
      approved_pending
      approved_paid
      ineligible
      contractor_withdrawn
    ].freeze

    has_many :invoice_versions,
             class_name: "Claims::InvoiceVersion",
             foreign_key: :invoice_id,
             dependent: :destroy

    has_many :status_transitions,
             -> { order(created_at: :desc, id: :desc) },
             class_name: "Claims::InvoiceStatusTransition",
             foreign_key: :invoice_id,
             inverse_of: :invoice,
             dependent: :delete_all

    has_many :revision_rounds,
             -> { order(round_number: :desc, id: :desc) },
             class_name: "Claims::RevisionRound",
             foreign_key: :invoice_id,
             inverse_of: :invoice,
             dependent: :destroy

    has_many :revision_issues,
             -> { order(created_at: :asc, id: :asc) },
             class_name: "Claims::RevisionIssue",
             foreign_key: :invoice_id,
             inverse_of: :invoice,
             dependent: :destroy

    has_many :conversation_messages,
             class_name: "Claims::ConversationMessage",
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

    has_many :ingest_runs,
             class_name: "Claims::IngestRun",
             foreign_key: :invoice_id,
             dependent: :nullify

    def set_workflow_status!(
      status,
      actor_user_id: nil,
      invoice_version_id: nil,
      **attrs
    )
      ::Claims::Invoices::TransitionStatus.call(
        invoice: self,
        to_status: status,
        actor_user_id: actor_user_id,
        invoice_version_id: invoice_version_id,
        attributes: attrs,
        validate: true
      )
      reload
    end

    def set_workflow_status_columns!(
      status,
      actor_user_id: nil,
      invoice_version_id: nil,
      now: Time.current
    )
      ::Claims::Invoices::TransitionStatus.call(
        invoice: self,
        to_status: status,
        actor_user_id: actor_user_id,
        invoice_version_id: invoice_version_id,
        attributes: {
        },
        validate: false,
        now: now
      )
      reload
    end
  end
end
