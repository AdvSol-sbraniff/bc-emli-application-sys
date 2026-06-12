# frozen_string_literal: true

module Claims
  module SupportingDocumentGroups
    class LocatedFieldPrompt
      def self.call(supporting_document_type:)
        new(supporting_document_type: supporting_document_type).call
      end

      def initialize(supporting_document_type:)
        @supporting_document_type = supporting_document_type
      end

      def call
        rows = located_field_rows
        return "" if rows.empty?

        body =
          rows
            .map do |field|
              "#{field.field_number} [field_key: #{field.field_key}] #{field.prompt_text.to_s.strip}"
            end
            .join("\n")

        <<~TEXT.strip
          User record: Supporting document group located-field tasks
          Use only the group-level field tasks listed below for the selected supporting_document_type_key.
          Return one supporting_document_group_located_fields[] row for each listed field task. If the group-level value cannot be determined, return value=null, confidence=0, and evidence_text=null for that field.

          Supporting document type: #{@supporting_document_type.type_key}
          #{body}
        TEXT
      end

      private

      def located_field_rows
        ::Claims::SupportingDocumentGroupTypeLocatedField.where(
          supporting_document_type_id: @supporting_document_type.id,
          enabled: true
        ).order(:field_number, :field_key)
      end
    end
  end
end
