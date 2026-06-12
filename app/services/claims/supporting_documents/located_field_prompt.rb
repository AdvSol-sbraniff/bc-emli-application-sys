# frozen_string_literal: true

module Claims
  module SupportingDocuments
    class LocatedFieldPrompt
      def self.call(supporting_document_type: nil)
        new(supporting_document_type: supporting_document_type).call
      end

      def initialize(supporting_document_type: nil)
        @supporting_document_type = supporting_document_type
      end

      def call
        rows = located_field_rows
        return "" if rows.empty?

        sections =
          rows
            .group_by(&:supporting_document_type_id)
            .map do |_type_id, fields|
              type = fields.first.supporting_document_type
              next if type.nil?

              body =
                fields
                  .map do |field|
                    "#{field.field_number} [field_key: #{field.field_key}] #{field.prompt_text.to_s.strip}"
                  end
                  .join("\n")

              ["Supporting document type: #{type.type_key}", body].join("\n")
            end
            .compact

        instruction =
          if @supporting_document_type.present?
            "Use only the field tasks listed below for the selected supporting_document_type_key."
          else
            "If document_kind=\"supporting_document\", first choose supporting_document_type_key. Then use only the field tasks listed under that selected supporting_document_type_key."
          end

        <<~TEXT.strip
          User record: Supporting document located-field tasks
          #{instruction}
          Return one supporting_document_located_fields[] row for each listed field task for the selected supporting-document type. If the value is not visible, return value=null, confidence=0, page=null, polygon=null, and evidence_text=null for that field.

          #{sections.join("\n\n")}
        TEXT
      end

      private

      def located_field_rows
        scope =
          ::Claims::SupportingDocumentTypeLocatedField
            .joins(:supporting_document_type)
            .includes(:supporting_document_type)
            .where(enabled: true)
            .merge(::Claims::SupportingDocumentType.where(enabled: true))

        if @supporting_document_type.present?
          type_id =
            if @supporting_document_type.respond_to?(:id)
              @supporting_document_type.id
            else
              @supporting_document_type
            end

          scope = scope.where(supporting_document_type_id: type_id)
        end

        scope.order(
          "claims.supporting_document_types.type_key ASC",
          "claims.supporting_document_type_located_fields.field_number ASC",
          "claims.supporting_document_type_located_fields.field_key ASC"
        )
      end
    end
  end
end
