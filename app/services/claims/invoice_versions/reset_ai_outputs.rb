# frozen_string_literal: true

module Claims
  module InvoiceVersions
    class ResetAiOutputs
      def self.call(invoice_version_id:)
        new(invoice_version_id: invoice_version_id).call
      end

      def initialize(invoice_version_id:)
        @invoice_version_id = invoice_version_id
      end

      def call
        invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)

        ::Claims::InvoiceVersion.transaction do
          located_field_scope =
            ::Claims::InvoiceVersionLocatedField.where(
              invoice_version_id: invoice_version.id
            )
          located_field_scope =
            located_field_scope.where.not(source_engine: "classifier")
          located_field_scope.delete_all

          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id
          ).delete_all

          invoice_version.update!(
            ahri_product_id: nil,
            neea_product_id: nil,
            awhp_product_id: nil,
            ohpa_product_id: nil,
            herv_product_id: nil,
            vent_fan_product_id: nil
          )
        end
      end
    end
  end
end
