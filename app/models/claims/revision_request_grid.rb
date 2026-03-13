module Claims
  class RevisionRequestGrid < ApplicationRecord
    self.table_name = "claims.v_revision_request_grid"
    self.primary_key = "invoice_version_id"

    def readonly?
      true
    end
  end
end
