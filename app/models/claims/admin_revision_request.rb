module Claims
  class AdminRevisionRequest < ApplicationRecord
    self.table_name = "claims.admin_revision_requests"

    belongs_to :invoice_version,
               class_name: "Claims::InvoiceVersion",
               foreign_key: :invoice_version_id

    before_validation :assign_revreq_seqno, on: :create
    before_validation :assign_default_message_type

    validates :invoice_version_id, presence: true
    validates :requester_id, presence: true
    validates :message_type,
              presence: true,
              inclusion: {
                in: %w[admin_revision_request contractor_note]
              }
    validates :request_text, presence: true
    validates :revreq_seqno,
              presence: true,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 1
              }

    private

    def assign_default_message_type
      self.message_type = "admin_revision_request" if message_type.blank?
    end

    def assign_revreq_seqno
      return if revreq_seqno.present?
      return if invoice_version_id.blank?

      self.revreq_seqno =
        self
          .class
          .where(invoice_version_id: invoice_version_id)
          .maximum(:revreq_seqno)
          .to_i + 1
    end
  end
end
