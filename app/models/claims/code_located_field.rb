# frozen_string_literal: true

module Claims
  class CodeLocatedField < ApplicationRecord
    self.table_name = "claims.code_located_fields"

    before_update :snapshot_history!

    private

    def snapshot_history!
      ::Claims::CodeLocatedFieldHistory.create!(
        source_id: id,
        code_field_key: code_field_key,
        description: description,
        enabled: enabled,
        source_created_at: created_at,
        source_updated_at: updated_at
      )
    end
  end
end
