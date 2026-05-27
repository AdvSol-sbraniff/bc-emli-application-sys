# frozen_string_literal: true

module Claims
  class GenaiLocatedFieldUpgradeType < ApplicationRecord
    self.table_name = "claims.genai_located_field_upgrade_types"

    before_update :snapshot_history!
    before_destroy :snapshot_history!

    belongs_to :genai_located_field,
               class_name: "Claims::GenaiLocatedField",
               foreign_key: :genai_field_id,
               inverse_of: :genai_located_field_upgrade_types

    belongs_to :invoice_upgrade_type,
               class_name: "Claims::InvoiceUpgradeType",
               foreign_key: :invoice_upgrade_type_id

    private

    def snapshot_history!
      ::Claims::GenaiLocatedFieldUpgradeTypeHistory.create!(
        source_id: id,
        genai_field_id: genai_field_id,
        invoice_upgrade_type_id: invoice_upgrade_type_id,
        field_number: field_number,
        source_created_at: created_at,
        source_updated_at: updated_at
      )
    end
  end
end
