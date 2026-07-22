module Claims
  class SupportingDocumentType < ApplicationRecord
    self.table_name = "claims.supporting_document_types"

    validate :type_key_is_immutable, on: :update

    has_many :supporting_document_type_upgrade_types,
             class_name: "Claims::SupportingDocumentTypeUpgradeType",
             foreign_key: :supporting_document_type_id,
             dependent: :destroy

    has_many :invoice_upgrade_types,
             through: :supporting_document_type_upgrade_types,
             source: :invoice_upgrade_type

    has_many :supporting_documents,
             class_name: "Claims::SupportingDocument",
             foreign_key: :supporting_document_type_id,
             dependent: :restrict_with_exception

    has_many :supporting_document_type_located_fields,
             class_name: "Claims::SupportingDocumentTypeLocatedField",
             foreign_key: :supporting_document_type_id,
             dependent: :destroy,
             inverse_of: :supporting_document_type

    private

    def type_key_is_immutable
      return unless will_save_change_to_type_key?

      errors.add(:type_key, "cannot be changed after creation")
    end
  end
end
