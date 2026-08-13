# frozen_string_literal: true

module Claims
  module Invoices
    class TransitionStatus
      class ProcessingActive < StandardError
      end

      def self.call(**args)
        new(**args).call
      end

      def initialize(
        invoice:,
        to_status:,
        actor_user_id: nil,
        invoice_version_id: nil,
        attributes: {},
        validate: true,
        now: Time.current
      )
        @invoice = invoice
        @to_status = to_status.to_s
        @actor_user_id = actor_user_id.presence
        @invoice_version_id = invoice_version_id.presence
        @attributes = attributes.to_h.symbolize_keys
        @validate = validate
        @now = now
      end

      def call
        raise ArgumentError, "to_status is required" if @to_status.blank?

        result = nil
        ::Claims::Invoice.transaction do
          locked = ::Claims::Invoice.lock.find(@invoice.id)
          from_status = locked.status.to_s
          changed = from_status != @to_status
          if changed && locked.ingest_runs.active.exists?
            raise ProcessingActive,
                  "Invoice cannot change business status while processing is active"
          end
          version_id = resolved_invoice_version_id(locked)

          attrs = @attributes.except(:status, :status_updated_at)
          if changed
            attrs[:status] = @to_status
            attrs[:status_updated_at] = @now
          end
          attrs[:updated_at] ||= @now

          @validate ? locked.update!(attrs) : locked.update_columns(attrs)

          if changed
            ::Claims::InvoiceStatusTransition.create!(
              invoice_id: locked.id,
              invoice_version_id: version_id,
              actor_user_id: @actor_user_id,
              from_status: from_status.presence,
              to_status: @to_status,
              created_at: @now
            )
          end

          result = locked
        end
        result
      end

      private

      def resolved_invoice_version_id(invoice)
        if @invoice_version_id
          belongs =
            ::Claims::InvoiceVersion.exists?(
              id: @invoice_version_id,
              invoice_id: invoice.id
            )
          unless belongs
            raise ArgumentError, "invoice version does not belong to invoice"
          end

          return @invoice_version_id
        end

        ::Claims::InvoiceVersion
          .where(invoice_id: invoice.id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .limit(1)
          .pick(:id)
      end
    end
  end
end
