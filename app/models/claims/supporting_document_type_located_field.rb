module Claims
  class SupportingDocumentTypeLocatedField < ApplicationRecord
    self.table_name = "claims.supporting_document_type_located_fields"

    belongs_to :supporting_document_type,
               class_name: "Claims::SupportingDocumentType",
               foreign_key: :supporting_document_type_id,
               inverse_of: :supporting_document_type_located_fields

    has_many :supporting_document_located_fields,
             class_name: "Claims::SupportingDocumentLocatedField",
             foreign_key: :supporting_document_type_located_field_id,
             dependent: :nullify

    validates :field_key, presence: true
    validates :contractor_display_name, presence: true
    validates :prompt_text, presence: true
    validates :field_number,
              numericality: {
                only_integer: true,
                greater_than_or_equal_to: 1
              }
    validates :field_key, uniqueness: { scope: :supporting_document_type_id }
    validates :field_number, uniqueness: { scope: :supporting_document_type_id }
  end
end
