# frozen_string_literal: true

module Claims
  module SupportingDocuments
    class ApplyLocatedFields
      def self.call(supporting_document_id:, located_fields_payload:)
        new(
          supporting_document_id: supporting_document_id,
          located_fields_payload: located_fields_payload
        ).call
      end

      def initialize(supporting_document_id:, located_fields_payload:)
        @supporting_document_id = supporting_document_id
        @located_fields_payload = located_fields_payload
      end

      def call
        document = ::Claims::SupportingDocument.find(@supporting_document_id)
        definitions = definitions_for(document)
        located_field_rows =
          extract_located_fields
            .map do |field_payload|
              build_row(
                field_payload: field_payload,
                document: document,
                definitions: definitions,
                now: Time.current
              )
            end
            .compact
        visual_finding_rows =
          extract_visual_findings
            .each_with_index
            .map do |finding_payload, index|
              build_visual_finding_row(
                finding_payload: finding_payload,
                document: document,
                finding_seqno: index + 1,
                now: Time.current
              )
            end
            .compact

        ::Claims::SupportingDocumentLocatedField.transaction do
          ::Claims::SupportingDocumentLocatedField.where(
            supporting_document_id: document.id,
            source_engine: "genai"
          ).delete_all
          ::Claims::SupportingDocumentVisualFinding.where(
            supporting_document_id: document.id,
            source_engine: "genai"
          ).delete_all

          if located_field_rows.any?
            ::Claims::SupportingDocumentLocatedField.insert_all!(
              located_field_rows
            )
          end

          if visual_finding_rows.any?
            ::Claims::SupportingDocumentVisualFinding.insert_all!(
              visual_finding_rows
            )
          end
        end

        {
          ok: true,
          replaced: located_field_rows.size,
          visual_findings_replaced: visual_finding_rows.size
        }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def definitions_for(document)
        return {} if document.supporting_document_type_id.blank?

        ::Claims::SupportingDocumentTypeLocatedField
          .where(
            supporting_document_type_id: document.supporting_document_type_id,
            enabled: true
          )
          .index_by { |definition| definition.field_key.to_s }
      end

      def extract_located_fields
        return [] unless @located_fields_payload.is_a?(Hash)

        rows =
          @located_fields_payload["supporting_document_located_fields"] ||
            @located_fields_payload[:supporting_document_located_fields]
        rows.is_a?(Array) ? rows : []
      end

      def extract_visual_findings
        return [] unless @located_fields_payload.is_a?(Hash)

        rows =
          @located_fields_payload["visual_findings"] ||
            @located_fields_payload[:visual_findings]
        rows.is_a?(Array) ? rows : []
      end

      def build_row(field_payload:, document:, definitions:, now:)
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
          supporting_document_id: document.id,
          supporting_document_type_located_field_id: definition&.id,
          source_engine: "genai",
          field_key: field_key,
          value_type: value_type,
          value_text: value_text,
          value_json: value_json,
          confidence:
            coerce_confidence(
              field_payload["confidence"] || field_payload[:confidence]
            ),
          page:
            coerce_int_or_nil(field_payload["page"] || field_payload[:page]),
          polygon:
            polygon_to_flat_float_array(
              field_payload["polygon"] || field_payload[:polygon]
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

      def coerce_int_or_nil(value)
        return nil if value.nil?

        raw = value.is_a?(String) ? value.strip : value
        return nil if raw == ""

        Integer(raw)
      rescue StandardError
        nil
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

      def build_visual_finding_row(
        finding_payload:,
        document:,
        finding_seqno:,
        now:
      )
        return nil unless finding_payload.is_a?(Hash)

        summary =
          (finding_payload["summary"] || finding_payload[:summary]).to_s.strip
        return nil if summary.blank?

        {
          supporting_document_id: document.id,
          finding_seqno: finding_seqno,
          source_engine: "genai",
          finding_type:
            coerce_finding_type(
              finding_payload["finding_type"] || finding_payload[:finding_type]
            ),
          page:
            coerce_int_or_nil(
              finding_payload["page"] || finding_payload[:page]
            ),
          summary: summary,
          legibility:
            coerce_legibility(
              finding_payload["legibility"] || finding_payload[:legibility]
            ),
          confidence:
            coerce_confidence(
              finding_payload["confidence"] || finding_payload[:confidence]
            ),
          raw_json:
            finding_payload.except("relevant_text_seen", :relevant_text_seen),
          created_at: now,
          updated_at: now
        }
      end

      def coerce_finding_type(value)
        value = value.to_s.strip
        value.present? ? value : "other"
      end

      def coerce_legibility(value)
        value = value.to_s.strip
        if %w[legible partially_legible illegible not_applicable].include?(
             value
           )
          return value
        end

        "not_applicable"
      end

      def polygon_to_flat_float_array(raw)
        return nil if raw.nil?

        if raw.is_a?(String)
          raw =
            begin
              JSON.parse(raw.strip)
            rescue StandardError
              return nil
            end
        end

        raw =
          raw["polygon"] || raw[:polygon] || raw["points"] ||
            raw[:points] if raw.is_a?(Hash)
        return nil unless raw.is_a?(Array)
        return nil if raw.empty?

        return raw.map(&:to_f) if raw.all? { |value| numericish?(value) }

        if raw.all? { |point|
             point.is_a?(Hash) && (point.key?("x") || point.key?(:x))
           }
          flat = []
          raw.each do |point|
            x = point["x"] || point[:x]
            y = point["y"] || point[:y]
            next unless numericish?(x) && numericish?(y)

            flat << x.to_f
            flat << y.to_f
          end
          return flat.presence
        end

        if raw.all? { |point|
             point.is_a?(Array) && point.length == 2 && numericish?(point[0]) &&
               numericish?(point[1])
           }
          return raw.flat_map { |point| [point[0].to_f, point[1].to_f] }
        end

        nil
      end

      def numericish?(value)
        return true if value.is_a?(Numeric)
        return false unless value.is_a?(String)

        value.strip.match?(/\A-?\d+(\.\d+)?\z/)
      end
    end
  end
end
