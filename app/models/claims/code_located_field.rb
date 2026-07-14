# frozen_string_literal: true

module Claims
  class CodeLocatedField < ApplicationRecord
    self.table_name = "claims.code_located_fields"

    before_update :snapshot_history!

    validates :contractor_display_name, presence: true

    private

    def snapshot_history!
      ::Claims::CodeLocatedFieldHistory.create!(
        source_id: id,
        code_field_key: attribute_in_database("code_field_key"),
        contractor_display_name:
          attribute_in_database("contractor_display_name"),
        description: attribute_in_database("description"),
        enabled: attribute_in_database("enabled"),
        source_created_at: created_at,
        source_updated_at: attribute_in_database("updated_at")
      )
    end
  end
end
