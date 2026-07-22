# frozen_string_literal: true

module Claims
  class GenaiLocatedField < ApplicationRecord
    self.table_name = "claims.genai_located_fields"

    before_update :snapshot_history!

    validates :contractor_display_name, presence: true
    validate :field_key_is_immutable, on: :update

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
        genai_field_key: attribute_in_database("genai_field_key"),
        contractor_display_name:
          attribute_in_database("contractor_display_name"),
        prompt_text: attribute_in_database("prompt_text"),
        enabled: attribute_in_database("enabled"),
        source_created_at: created_at,
        source_updated_at: attribute_in_database("updated_at")
      )
    end

    def field_key_is_immutable
      return unless will_save_change_to_genai_field_key?

      errors.add(:genai_field_key, "cannot be changed after creation")
    end
  end
end
