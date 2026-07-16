# frozen_string_literal: true

module Claims
  class RevisionRound < ApplicationRecord
    self.table_name = "claims.revision_rounds"

    belongs_to :invoice,
               class_name: "Claims::Invoice",
               foreign_key: :invoice_id,
               inverse_of: :revision_rounds

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id,
               inverse_of: :revision_rounds

    has_many :comments,
             -> { order(created_at: :asc, id: :asc) },
             class_name: "Claims::RevisionIssueComment",
             foreign_key: :revision_round_id,
             inverse_of: :revision_round,
             dependent: :destroy

    has_many :issues, through: :comments, source: :revision_issue

    scope :newest_first, -> { order(round_number: :desc, id: :desc) }

    validates :round_number,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 1
              },
              uniqueness: {
                scope: :invoice_id
              }
    validate :invoice_version_belongs_to_invoice
    validate :response_follows_send

    def draft?
      admin_sent_at.nil?
    end

    def waiting_for_contractor?
      admin_sent_at.present? && contractor_response_submitted_at.nil?
    end

    def responded?
      contractor_response_submitted_at.present?
    end

    def latest?
      invoice.revision_rounds.maximum(:round_number) == round_number
    end

    private

    def invoice_version_belongs_to_invoice
      return if invoice_version.blank? || invoice_id.blank?
      return if invoice_version.invoice_id == invoice_id

      errors.add(:invoice_version_id, "must belong to the invoice")
    end

    def response_follows_send
      return if contractor_response_submitted_at.blank?
      if admin_sent_at.blank?
        errors.add(:contractor_response_submitted_at, "requires a sent round")
      elsif contractor_response_submitted_at < admin_sent_at
        errors.add(
          :contractor_response_submitted_at,
          "cannot precede the send time"
        )
      end
    end
  end
end
