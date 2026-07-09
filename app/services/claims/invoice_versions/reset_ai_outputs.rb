# frozen_string_literal: true

module Claims
  module InvoiceVersions
    class ResetAiOutputs
      def self.call(invoice_version_id:, preserve_classifier: false)
        new(
          invoice_version_id: invoice_version_id,
          preserve_classifier: preserve_classifier
        ).call
      end

      def initialize(invoice_version_id:, preserve_classifier:)
        @invoice_version_id = invoice_version_id
        @preserve_classifier = preserve_classifier
      end

      def call
        invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)

        ::Claims::InvoiceVersion.transaction do
          scope =
            ::Claims::InvoiceVersionUpgradeType.where(
              invoice_version_id: invoice_version.id
            )
          scope =
            scope.where.not(source_engine: "classifier") if @preserve_classifier
          scope.delete_all

          located_field_scope =
            ::Claims::InvoiceVersionLocatedField.where(
              invoice_version_id: invoice_version.id
            )
          located_field_scope =
            located_field_scope.where.not(
              source_engine: "classifier"
            ) if @preserve_classifier
          located_field_scope.delete_all

          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id
          ).delete_all

          invoice_version.update!(
            genai_overall_confidence: 0,
            genai_result: nil,
            genai_admin_advice: nil,
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
