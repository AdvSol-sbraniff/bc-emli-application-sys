# frozen_string_literal: true

module Claims
  module SupportingDocuments
    class ApplyTypeLocatedFields
      def self.call(
        invoice_version_id:,
        supporting_document_type_id:,
        located_fields_payload:
      )
        new(
          invoice_version_id: invoice_version_id,
          supporting_document_type_id: supporting_document_type_id,
          located_fields_payload: located_fields_payload
        ).call
      end

      def initialize(
        invoice_version_id:,
        supporting_document_type_id:,
        located_fields_payload:
      )
        @invoice_version_id = invoice_version_id
        @supporting_document_type_id = supporting_document_type_id
        @located_fields_payload = located_fields_payload
      end

      def call
        documents_by_id =
          ::Claims::SupportingDocument
            .where(
              invoice_version_id: @invoice_version_id,
              supporting_document_type_id: @supporting_document_type_id
            )
            .index_by { |document| document.id.to_s }
        if documents_by_id.empty?
          return { ok: false, error: "No supporting documents found for type." }
        end

        payloads = extract_document_payloads
        payloads =
          single_document_payload(documents_by_id) if payloads.empty? &&
          documents_by_id.size == 1
        if payloads.empty?
          return(
            {
              ok: false,
              error: "No per-document extraction payloads returned."
            }
          )
        end

        replaced_documents = 0
        replaced_fields = 0
        replaced_visual_findings = 0
        skipped_payloads = 0

        payloads.each do |payload|
          next skipped_payloads += 1 unless payload.is_a?(Hash)

          document_id =
            (
              payload["supporting_document_id"] ||
                payload[:supporting_document_id]
            ).to_s.strip
          document = documents_by_id[document_id]
          if document.nil?
            skipped_payloads += 1
            next
          end

          result =
            ::Claims::SupportingDocuments::ApplyLocatedFields.call(
              supporting_document_id: document.id,
              located_fields_payload: payload
            )
          unless result[:ok] || result["ok"]
            return(
              {
                ok: false,
                error:
                  "ApplyLocatedFields failed for supporting_document_id=#{document.id}: #{result.inspect}"
              }
            )
          end

          replaced_documents += 1
          replaced_fields += (result[:replaced] || result["replaced"] || 0).to_i
          replaced_visual_findings +=
            (
              result[:visual_findings_replaced] ||
                result["visual_findings_replaced"] || 0
            ).to_i
        end

        {
          ok: true,
          documents_replaced: replaced_documents,
          located_fields_replaced: replaced_fields,
          visual_findings_replaced: replaced_visual_findings,
          skipped_payloads: skipped_payloads
        }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def extract_document_payloads
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

      def single_document_payload(documents_by_id)
        return [] unless @located_fields_payload.is_a?(Hash)

        has_single_shape =
          @located_fields_payload.key?("supporting_document_located_fields") ||
            @located_fields_payload.key?(:supporting_document_located_fields) ||
            @located_fields_payload.key?("visual_findings") ||
            @located_fields_payload.key?(:visual_findings)
        return [] unless has_single_shape

        document = documents_by_id.values.first
        [@located_fields_payload.merge("supporting_document_id" => document.id)]
      end
    end
  end
end
