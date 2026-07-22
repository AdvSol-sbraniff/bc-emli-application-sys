# frozen_string_literal: true

module Claims
  class ConversationMessage < ApplicationRecord
    self.table_name = "claims.conversation_messages"

    belongs_to :invoice, class_name: "Claims::Invoice", foreign_key: :invoice_id

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id,
               optional: true

    before_validation :assign_invoice_id
    before_validation :assign_seqno, on: :create
    before_validation :assign_default_message_type
    before_update :reset_recipient_read_at, if: :recipient_content_changed?

    validates :invoice_id, :requester_id, :request_text, presence: true
    validates :message_type,
              inclusion: {
                in: %w[admin_message contractor_note]
              }
    validates :revreq_seqno,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 1
              }

    private

    def assign_default_message_type
      self.message_type = "admin_message" if message_type.blank?
    end

    def assign_invoice_id
      return if invoice_id.present? || invoice_version_id.blank?

      self.invoice_id =
        Claims::InvoiceVersion.where(id: invoice_version_id).pick(:invoice_id)
    end

    def assign_seqno
      return if revreq_seqno.present? || invoice_id.blank?

      self.revreq_seqno =
        self.class.where(invoice_id: invoice_id).maximum(:revreq_seqno).to_i + 1
    end

    def recipient_content_changed?
      will_save_change_to_request_text? || will_save_change_to_message_type?
    end

    def reset_recipient_read_at
      self.recipient_read_at = nil
    end
  end
end
