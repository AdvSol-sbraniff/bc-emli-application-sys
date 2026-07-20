# frozen_string_literal: true

module Claims
  module RevisionIssues
    class BuildAdminCommentDraft
      def self.call(issue:)
        source = SourcePresenter.call(issue)
        label = source[:friendly_label].to_s.strip.presence || "This item"

        if issue.issue_type == "rule"
          parts = ["#{label} needs attention."]
          parts << source[:reason].to_s.strip if source[:reason].present?
          if source[:evidence_text].present?
            parts << "Evidence: #{source[:evidence_text].to_s.strip}"
          end
          parts << "Please provide corrected documentation or explain why it cannot be supplied."
          return parts.join("\n\n")
        end

        parts = ["Please review #{label}."]
        value = source[:value]
        unless value.nil?
          parts << "The submitted document was read as: #{display_value(value)}."
        end
        if source[:evidence_text].present?
          parts << source[:evidence_text].to_s.strip
        end
        parts << "Please correct the documentation or provide the requested supporting information."
        parts.join("\n\n")
      end

      def self.display_value(value)
        value.is_a?(Hash) || value.is_a?(Array) ? value.to_json : value.to_s
      end
      private_class_method :display_value
    end
  end
end
