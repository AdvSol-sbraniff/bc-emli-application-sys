# frozen_string_literal: true

module Claims
  module SupportingDocumentGroups
    class ApplyLocatedFields
      def self.call(supporting_document_group_id:, located_fields_payload:)
        new(
          supporting_document_group_id: supporting_document_group_id,
          located_fields_payload: located_fields_payload
        ).call
      end

      def initialize(supporting_document_group_id:, located_fields_payload:)
        @supporting_document_group_id = supporting_document_group_id
        @located_fields_payload = located_fields_payload
      end

      def call
        group =
          ::Claims::SupportingDocumentGroup.find(@supporting_document_group_id)
        definitions = definitions_for(group)
        now = Time.current
        @child_documents_replaced = 0
        @child_located_fields_replaced = 0
        @child_visual_findings_replaced = 0
        rows =
          extract_located_fields
            .map do |field_payload|
              build_row(
                field_payload: field_payload,
                group: group,
                definitions: definitions,
                now: now
              )
            end
            .compact

        ::Claims::SupportingDocumentGroupLocatedField.transaction do
          apply_child_document_payloads!(group)

          ::Claims::SupportingDocumentGroupLocatedField.where(
            supporting_document_group_id: group.id,
            source_engine: "genai"
          ).delete_all

          if rows.any?
            ::Claims::SupportingDocumentGroupLocatedField.insert_all!(rows)
          end

          group.update!(
            group_status: rows.any? ? "extracted" : "needs_review",
            updated_at: now
          )
        end

        {
          ok: true,
          replaced: rows.size,
          child_documents_replaced: @child_documents_replaced,
          child_located_fields_replaced: @child_located_fields_replaced,
          child_visual_findings_replaced: @child_visual_findings_replaced
        }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def definitions_for(group)
        ::Claims::SupportingDocumentGroupTypeLocatedField
          .where(
            supporting_document_type_id: group.supporting_document_type_id,
            enabled: true
          )
          .index_by { |definition| definition.field_key.to_s }
      end

      def extract_located_fields
        return [] unless @located_fields_payload.is_a?(Hash)

        rows =
          @located_fields_payload["supporting_document_group_located_fields"] ||
            @located_fields_payload[:supporting_document_group_located_fields]
        rows.is_a?(Array) ? rows : []
      end

      def extract_child_document_payloads
        return [] unless @located_fields_payload.is_a?(Hash)

        rows =
          @located_fields_payload[
            "supporting_document_located_fields_by_document"
          ] ||
            @located_fields_payload[
              :supporting_document_located_fields_by_document
            ]
        rows.is_a?(Array) ? rows : []
      end

      def apply_child_document_payloads!(group)
        child_payloads = extract_child_document_payloads
        return if child_payloads.empty?

        payload_document_ids =
          child_payloads.filter_map do |payload|
            next unless payload.is_a?(Hash)

            (
              payload["supporting_document_id"] ||
                payload[:supporting_document_id]
            ).to_s.presence
          end

        documents_by_id =
          ::Claims::SupportingDocument
            .where(
              id: payload_document_ids,
              supporting_document_group_id: group.id
            )
            .index_by { |document| document.id.to_s }

        child_payloads.each do |payload|
          next unless payload.is_a?(Hash)

          document_id =
            (
              payload["supporting_document_id"] ||
                payload[:supporting_document_id]
            ).to_s
          next if document_id.blank?

          document = documents_by_id[document_id]
          next if document.nil?

          result =
            ::Claims::SupportingDocuments::ApplyLocatedFields.call(
              supporting_document_id: document.id,
              located_fields_payload: payload
            )
          if result[:ok] || result["ok"]
            @child_documents_replaced += 1
            @child_located_fields_replaced +=
              (result[:replaced] || result["replaced"] || 0).to_i
            @child_visual_findings_replaced +=
              (
                result[:visual_findings_replaced] ||
                  result["visual_findings_replaced"] || 0
              ).to_i
            next
          end

          raise "ApplySupportingDocumentLocatedFields failed for supporting_document_id=#{document.id}: #{result.inspect}"
        end
      end

      def build_row(field_payload:, group:, definitions:, now:)
        return nil unless field_payload.is_a?(Hash)

        field_key =
          (field_payload["field_key"] || field_payload[:field_key]).to_s.strip
        return nil if field_key.blank?

        definition = definitions[field_key]
        return nil if definition.nil?

        value =
          if field_payload.key?("value")
            field_payload["value"]
          else
            field_payload[:value]
          end
        value_type, value_text, value_json = coerce_value(value)

        {
          supporting_document_group_id: group.id,
          supporting_document_group_type_located_field_id: definition.id,
          source_engine: "genai",
          field_key: field_key,
          value_type: value_type,
          value_text: value_text,
          value_json: value_json,
          confidence:
            coerce_confidence(
              field_payload["confidence"] || field_payload[:confidence]
            ),
          evidence_text:
            field_payload["evidence_text"] || field_payload[:evidence_text],
          created_at: now,
          updated_at: now
        }
      end

      def coerce_value(value)
        return "text", nil, nil if value.nil?

        case value
        when TrueClass, FalseClass
          ["bool", value.to_s, nil]
        when Integer, Float, BigDecimal
          ["number", value.to_s, nil]
        when String
          ["text", value, nil]
        when Hash, Array
          ["json", nil, value]
        else
          ["text", value.to_s, nil]
        end
      end

      def coerce_confidence(value)
        numeric =
          begin
            Float(value || 0)
          rescue StandardError
            0
          end
        numeric *= 100 if numeric.positive? && numeric <= 1
        [[numeric.round, 0].max, 100].min
      end
    end
  end
end
