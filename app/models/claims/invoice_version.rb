# app/models/claims/invoice_version.rb
module Claims
  class InvoiceVersion < ApplicationRecord
    self.table_name = "claims.invoice_versions"

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

    has_many :located_fields,
             class_name: "Claims::InvoiceVersionLocatedField",
             foreign_key: :invoice_version_id,
             inverse_of: :invoice_version,
             dependent: :destroy

    has_many :rulechecks,
             class_name: "Claims::InvoiceVersionRulecheck",
             foreign_key: :invoice_version_id,
             dependent: :destroy

    has_many :upload_runs,
             class_name: "Claims::UploadRun",
             foreign_key: :invoice_version_id,
             dependent: :destroy
  end
end
