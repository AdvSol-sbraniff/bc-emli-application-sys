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
          ::Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: invoice_version.id
          ).delete_all

          ::Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: invoice_version.id
          ).delete_all

          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id
          ).delete_all

          invoice_version.update!(
            genai_overall_confidence: 0,
            genai_result: nil,
            genai_admin_advice: nil
          )
        end
      end
    end
  end
end
