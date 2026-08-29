module Claims
  class ValidationgenaiConfig < ApplicationRecord
    self.table_name = "claims.validationgenai_config"

    ADMIN_PDF_VIEWER_UX_MODES = %w[simple enterprise].freeze

    validates :admin_pdf_viewer_ux_mode,
              inclusion: {
                in: ADMIN_PDF_VIEWER_UX_MODES
              }

    validates :document_triage_deployment_name,
              :supporting_document_extraction_deployment_name,
              :upgrade_analysis_deployment_name,
              :comparison_deployment_name,
              length: {
                maximum: 200
              },
              allow_blank: true
  end
end
