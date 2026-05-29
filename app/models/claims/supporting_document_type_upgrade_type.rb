module Claims
  class SupportingDocumentTypeUpgradeType < ApplicationRecord
    self.table_name = "claims.supporting_document_type_upgrade_types"

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id

    belongs_to :invoice_upgrade_type,
               class_name: "Claims::InvoiceUpgradeType",
               foreign_key: :invoice_upgrade_type_id
  end
end
