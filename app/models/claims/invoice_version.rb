# app/models/claims/invoice_version.rb
module Claims
  class InvoiceVersion < ApplicationRecord
    self.table_name = "claims.invoice_versions"

    VALIDATION_RESULTS_BY_SEVERITY = %w[fail warn info pass].freeze

    belongs_to :invoice, class_name: "Claims::Invoice", foreign_key: :invoice_id

    belongs_to :ahri_product,
               class_name: "Claims::AhriProduct",
               foreign_key: :ahri_product_id,
               optional: true

    belongs_to :neea_product,
               class_name: "Claims::NeeaProduct",
               foreign_key: :neea_product_id,
               optional: true

    belongs_to :awhp_product,
               class_name: "Claims::AwhpProduct",
               foreign_key: :awhp_product_id,
               optional: true

    belongs_to :ohpa_product,
               class_name: "Claims::OhpaProduct",
               foreign_key: :ohpa_product_id,
               optional: true

    belongs_to :herv_product,
               class_name: "Claims::HervProduct",
               foreign_key: :herv_product_id,
               optional: true

    belongs_to :vent_fan_product,
               class_name: "Claims::VentFanProduct",
               foreign_key: :vent_fan_product_id,
               optional: true

    belongs_to :users_eligibilitycode,
               class_name: "Claims::UsersEligibilitycode",
               foreign_key: :users_eligibilitycode_id,
               optional: true

    belongs_to :participant_user,
               class_name: "::User",
               foreign_key: :participant_user_id,
               optional: true

    belongs_to :personal_information_type,
               class_name: "Claims::PersonalInformationType",
               foreign_key: :personal_information_type_id,
               optional: true

    has_many :located_fields,
             class_name: "Claims::InvoiceVersionLocatedField",
             foreign_key: :invoice_version_id,
             inverse_of: :invoice_version,
             dependent: :destroy

    has_many :rulechecks,
             class_name: "Claims::InvoiceVersionRulecheck",
             foreign_key: :invoice_version_id,
             inverse_of: :invoice_version,
             dependent: :destroy

    has_many :supporting_documents,
             class_name: "Claims::SupportingDocument",
             foreign_key: :invoice_version_id,
             inverse_of: :invoice_version,
             dependent: :destroy

    has_many :revision_rounds,
             class_name: "Claims::RevisionRound",
             foreign_key: :invoice_version_id,
             inverse_of: :invoice_version,
             dependent: :restrict_with_exception

    has_many :upload_runs,
             class_name: "Claims::UploadRun",
             foreign_key: :invoice_version_id,
             dependent: :destroy

    def validation_result
      results = rulechecks.distinct.pluck(:rule_result)
      VALIDATION_RESULTS_BY_SEVERITY.find { |result| results.include?(result) }
    end
  end
end
