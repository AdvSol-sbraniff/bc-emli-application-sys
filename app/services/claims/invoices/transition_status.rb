# frozen_string_literal: true

module Claims
  module Invoices
    class TransitionStatus
      def self.call(**args)
        new(**args).call
      end

      def initialize(
        invoice:,
        to_status:,
        status_subtype: nil,
        actor_user_id: nil,
        invoice_version_id: nil,
        attributes: {},
        validate: true,
        now: Time.current
      )
        @invoice = invoice
        @to_status = to_status.to_s
        @status_subtype = status_subtype
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
          from_subtype = locked.status_subtype.presence
          to_subtype = normalized_subtype
          changed = from_status != @to_status || from_subtype != to_subtype
          version_id = resolved_invoice_version_id(locked)

          attrs =
            @attributes.except(:status, :status_subtype, :status_updated_at)
          if changed
            attrs[:status] = @to_status
            attrs[:status_subtype] = to_subtype
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
              from_status_subtype: from_subtype,
              to_status: @to_status,
              to_status_subtype: to_subtype,
              created_at: @now
            )
          end

          result = locked
        end
        result
      end

      private

      def normalized_subtype
        unless ::Claims::Invoice::FAILURE_STATUSES.include?(@to_status)
          return nil
        end

        ::Claims::Invoices::StatusSubtypes.normalize(
          @to_status,
          @status_subtype
        )
      end

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
