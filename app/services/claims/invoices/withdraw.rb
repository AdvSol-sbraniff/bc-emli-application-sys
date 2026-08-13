# frozen_string_literal: true

module Claims
  module Invoices
    class Withdraw
      class NotAllowed < StandardError
        attr_reader :invoice_status

        def initialize(invoice_status)
          @invoice_status = invoice_status
          super("Invoice cannot be withdrawn from its current status")
        end
      end

      WITHDRAWN_STATUS = "contractor_withdrawn"
      WITHDRAWABLE_STATUSES = %w[
        contractor_precheck
        admin_review_inbox
        contractor_revision_inbox
        in_review
      ].freeze
      ISSUE_DISPOSITION = "Invoice withdrawn by contractor."

      def self.call(**args)
        new(**args).call
      end

      def initialize(invoice:, actor_user_id:)
        @invoice = invoice
        @actor_user_id = actor_user_id
      end

      def call
        result = nil
        ::Claims::Invoice.transaction do
          invoice = ::Claims::Invoice.lock.find(@invoice.id)
          if invoice.status == WITHDRAWN_STATUS
            result = invoice
            next
          end

          unless WITHDRAWABLE_STATUSES.include?(invoice.status)
            raise NotAllowed, invoice.status
          end

          invoice.revision_issues.unresolved_issues.find_each do |issue|
            issue.update!(
              status: "closed_as_withdrawn",
              disposition_comment: ISSUE_DISPOSITION
            )
          end

          result =
            ::Claims::Invoices::TransitionStatus.call(
              invoice: invoice,
              to_status: WITHDRAWN_STATUS,
              actor_user_id: @actor_user_id,
              validate: true
            )
        end
        result
      end
    end
  end
end
