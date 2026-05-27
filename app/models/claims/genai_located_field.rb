# frozen_string_literal: true

module Claims
  class GenaiLocatedField < ApplicationRecord
    self.table_name = "claims.genai_located_fields"

    before_update :snapshot_history!

    has_many :genai_located_field_upgrade_types,
             class_name: "Claims::GenaiLocatedFieldUpgradeType",
             foreign_key: :genai_field_id,
             inverse_of: :genai_located_field,
             dependent: :destroy

    has_many :invoice_upgrade_types,
             through: :genai_located_field_upgrade_types,
             class_name: "Claims::InvoiceUpgradeType"

    private

    def snapshot_history!
      ::Claims::GenaiLocatedFieldHistory.create!(
        source_id: id,
        genai_field_key: genai_field_key,
        prompt_text: prompt_text,
        enabled: enabled,
        source_created_at: created_at,
        source_updated_at: updated_at
      )
    end
  end
end
