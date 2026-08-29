# frozen_string_literal: true

module Claims
  module TestHarness
    class EvidenceSnapshot
      def self.for_domain(domain:, invoice_version:, ingest_run:)
        new(
          invoice_version: invoice_version,
          ingest_run: ingest_run
        ).for_domain(domain)
      end

      def initialize(invoice_version:, ingest_run:)
        @invoice_version = invoice_version
        @ingest_run = ingest_run
      end

      def for_domain(domain)
        case domain.to_sym
        when :document_classification
          classification
        when :supporting_document_extraction
          supporting_document_extraction
        when :upgrade_analysis
          upgrade_analysis
        else
          raise ArgumentError, "Unknown comparison domain: #{domain}"
        end
      end

      def rule(rule_key)
        @invoice_version
          .rulechecks
          .where(source_engine: "genai", rule_key: rule_key)
          .order(:invoice_upgrade_type_id)
          .map { |row| select(row, rulecheck_fields) }
      end

      private

      def classification
        documents =
          @ingest_run
            .ingest_documents
            .order(:created_at, :id)
            .map do |document|
              select(
                document,
                %w[
                  original_filename
                  content_type
                  byte_size
                  document_kind
                  document_kind_confidence
                  document_kind_reason
                  supporting_document_type_id
                  classification_confidence
                  classification_reason
                  supporting_document_routing_quality
                  supporting_document_routing_quality_reason
                  classifier_raw_json
                ]
              )
            end
        { ingest_run_id: @ingest_run.id, documents: documents }
      end

      def supporting_document_extraction
        documents =
          @invoice_version
            .supporting_documents
            .order(:created_at, :id)
            .map do |document|
              {
                document:
                  select(
                    document,
                    %w[
                      original_filename
                      supporting_document_type_id
                      classification_confidence
                      classification_reason
                      supporting_document_routing_quality
                      supporting_document_routing_quality_reason
                    ]
                  ),
                located_fields:
                  document
                    .supporting_document_located_fields
                    .order(:field_key)
                    .map do |field|
                      select(
                        field,
                        %w[
                          source_engine
                          field_key
                          value_type
                          value_text
                          value_json
                          confidence
                          page
                          evidence_text
                        ]
                      )
                    end,
                visual_findings:
                  document
                    .supporting_document_visual_findings
                    .order(:finding_seqno)
                    .map do |finding|
                      select(
                        finding,
                        finding.attributes.keys -
                          %w[id supporting_document_id created_at updated_at]
                      )
                    end
              }
            end
        { invoice_version_id: @invoice_version.id, documents: documents }
      end

      def upgrade_analysis
        {
          invoice_version_id: @invoice_version.id,
          located_fields:
            @invoice_version
              .located_fields
              .order(:field_key)
              .map do |field|
                select(
                  field,
                  field.attributes.keys -
                    %w[id invoice_version_id created_at updated_at]
                )
              end,
          rulechecks:
            @invoice_version
              .rulechecks
              .order(:source_engine, :rule_key)
              .map { |row| select(row, rulecheck_fields) }
        }
      end

      def rulecheck_fields
        %w[
          invoice_upgrade_type_id
          source_engine
          rule_key
          contractor_display_name
          rule_result
          compliance_score
          expected_text
          calculation
          evidence_text
          reason_and_likely_causes
        ]
      end

      def select(record, fields)
        record.attributes.slice(*fields)
      end
    end
  end
end
