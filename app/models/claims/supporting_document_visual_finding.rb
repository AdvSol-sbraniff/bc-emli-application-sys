module Claims
  class SupportingDocumentVisualFinding < ApplicationRecord
    self.table_name = "claims.supporting_document_visual_findings"

    belongs_to :supporting_document,
               class_name: "Claims::SupportingDocument",
               foreign_key: :supporting_document_id,
               inverse_of: :supporting_document_visual_findings
  end
end
