module Claims
  class ValidationgenaiConfig < ApplicationRecord
    self.table_name = "claims.validationgenai_config"

    ADMIN_PDF_VIEWER_UX_MODES = %w[simple enterprise].freeze

    validates :admin_pdf_viewer_ux_mode,
              inclusion: {
                in: ADMIN_PDF_VIEWER_UX_MODES
              }
  end
end
