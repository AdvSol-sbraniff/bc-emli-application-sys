module Claims
  class ValidationgenaiConfig < ApplicationRecord
    self.table_name = "claims.validationgenai_config"

    SUPPORTING_DOCUMENT_EXTRACTION_MODES = %w[
      combined_with_classifier
      separate_extraction
    ].freeze

    validate :supporting_document_extraction_mode_value_is_supported

    def supporting_document_extraction_mode
      value = self[:supporting_document_extraction_mode].to_s
      return value if SUPPORTING_DOCUMENT_EXTRACTION_MODES.include?(value)

      "combined_with_classifier"
    end

    def supporting_document_extraction_separate?
      supporting_document_extraction_mode == "separate_extraction"
    end

    def classifier_system_record_for_current_mode
      if supporting_document_extraction_separate?
        classifier_without_extraction_system_record
      else
        classifier_combined_with_extraction_system_record
      end
    end

    private

    def supporting_document_extraction_mode_value_is_supported
      value = self[:supporting_document_extraction_mode].to_s
      return if SUPPORTING_DOCUMENT_EXTRACTION_MODES.include?(value)

      errors.add(
        :supporting_document_extraction_mode,
        "must be combined_with_classifier or separate_extraction"
      )
    end
  end
end
