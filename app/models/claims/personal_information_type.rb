# frozen_string_literal: true

module Claims
  class PersonalInformationType < ApplicationRecord
    self.table_name = "claims.personal_information_types"

    scope :enabled, -> { where(enabled: true) }
    scope :classifier_order, -> { order(:sort_order, :type_key) }

    validate :type_key_is_immutable, on: :update

    has_many :invoice_versions,
             class_name: "Claims::InvoiceVersion",
             foreign_key: :personal_information_type_id,
             dependent: :restrict_with_exception

    has_many :supporting_documents,
             class_name: "Claims::SupportingDocument",
             foreign_key: :personal_information_type_id,
             dependent: :restrict_with_exception

    private

    def type_key_is_immutable
      return unless will_save_change_to_type_key?

      errors.add(:type_key, "cannot be changed after creation")
    end
  end
end
