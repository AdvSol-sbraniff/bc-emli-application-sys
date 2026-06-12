# frozen_string_literal: true

module Claims
  module InvoiceVersions
    class CopyClassifierEvidence
      def self.call(source_invoice_version_id:, target_invoice_version_id:)
        new(
          source_invoice_version_id: source_invoice_version_id,
          target_invoice_version_id: target_invoice_version_id
        ).call
      end

      def initialize(source_invoice_version_id:, target_invoice_version_id:)
        @source_invoice_version_id = source_invoice_version_id
        @target_invoice_version_id = target_invoice_version_id
      end

      def call
        now = Time.current
        source_version =
          ::Claims::InvoiceVersion.find(@source_invoice_version_id)
        target_version =
          ::Claims::InvoiceVersion.find(@target_invoice_version_id)

        unless source_version.invoice_id == target_version.invoice_id
          raise "Cannot copy classifier evidence across different invoices."
        end

        upgrade_rows =
          ::Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: source_version.id,
            source_engine: "classifier"
          ).to_a
        located_rows =
          ::Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: source_version.id,
            source_engine: "classifier"
          ).to_a

        if upgrade_rows.empty?
          raise "Source invoice version has no classifier upgrade evidence."
        end

        ::Claims::InvoiceVersion.transaction do
          ::Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: target_version.id,
            source_engine: "classifier"
          ).delete_all
          ::Claims::InvoiceVersionLocatedField.where(
            invoice_version_id: target_version.id,
            source_engine: "classifier"
          ).delete_all

          ::Claims::InvoiceVersionUpgradeType.insert_all!(
            upgrade_rows.map do |row|
              {
                invoice_version_id: target_version.id,
                invoice_upgrade_type_id: row.invoice_upgrade_type_id,
                source_engine: row.source_engine,
                call_status: row.call_status,
                confidence: row.confidence,
                result: row.result,
                admin_advice: row.admin_advice,
                raw_json: row.raw_json,
                created_at: now,
                updated_at: now
              }
            end
          )

          if located_rows.any?
            ::Claims::InvoiceVersionLocatedField.insert_all!(
              located_rows.map do |row|
                {
                  invoice_version_id: target_version.id,
                  invoice_upgrade_type_id: row.invoice_upgrade_type_id,
                  source_engine: row.source_engine,
                  field_key: row.field_key,
                  value_type: row.value_type,
                  value_text: row.value_text,
                  value_json: row.value_json,
                  confidence: row.confidence,
                  page: row.page,
                  polygon: row.polygon,
                  evidence_text: row.evidence_text,
                  created_at: now,
                  updated_at: now
                }
              end
            )
          end
        end

        {
          ok: true,
          copied_upgrade_rows: upgrade_rows.size,
          copied_located_field_rows: located_rows.size
        }
      end
    end
  end
end
