# frozen_string_literal: true

module Claims
  module SupportingDocumentGroups
    class EnsureForInvoice
      GROUP_CAPABLE_TYPE_KEYS = %w[before_after_photo_set].freeze

      def self.call(invoice_id:)
        new(invoice_id: invoice_id).call
      end

      def initialize(invoice_id:)
        @invoice_id = invoice_id
      end

      def call
        invoice = ::Claims::Invoice.find(@invoice_id)
        groups = []

        group_capable_types.each do |type|
          documents =
            invoice
              .supporting_documents
              .where(supporting_document_type_id: type.id)
              .order(:created_at, :id)
              .to_a
          next if documents.empty?

          group =
            ::Claims::SupportingDocumentGroup.find_or_initialize_by(
              invoice_id: invoice.id,
              supporting_document_type_id: type.id
            )
          group.group_label ||= default_group_label(type)
          group.group_status =
            (
              if group.supporting_document_group_located_fields.exists?
                "extracted"
              else
                "ready"
              end
            )
          group.updated_at = Time.current
          group.created_at ||= Time.current
          group.save!

          ::Claims::SupportingDocument.where(
            id: documents.map(&:id)
          ).update_all(
            supporting_document_group_id: group.id,
            updated_at: Time.current
          )

          groups << group
        end

        groups
      end

      private

      def group_capable_types
        ::Claims::SupportingDocumentType.where(
          type_key: GROUP_CAPABLE_TYPE_KEYS,
          enabled: true
        )
      end

      def default_group_label(type)
        type.description.presence || type.type_key.to_s.humanize
      end
    end
  end
end
