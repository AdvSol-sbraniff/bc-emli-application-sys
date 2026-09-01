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
        upgrade_types =
          ::Claims::InvoiceVersionUpgradeType
            .joins(
              "LEFT JOIN claims.invoice_upgrade_types iut " \
                "ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
            )
            .where(invoice_version_id: @invoice_version.id)
            .select(
              "claims.invoice_version_upgrade_types.*",
              "iut.upgrade_type_key AS upgrade_type_key",
              "iut.description AS upgrade_type_description"
            )
            .order("iut.upgrade_type_key", :id)
            .map do |row|
              select(
                row,
                %w[
                  invoice_upgrade_type_id
                  confidence
                  evidence_text
                  classification_explanation
                  page
                  raw_json
                ]
              ).merge(
                "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
                "upgrade_type_description" =>
                  row.read_attribute("upgrade_type_description")
              )
            end
        {
          invoice_version_id: @invoice_version.id,
          supporting_documents: supporting_document_classifications,
          upgrade_types: upgrade_types
        }
      end

      def supporting_document_classifications
        @invoice_version
          .supporting_documents
          .includes(:supporting_document_type)
          .order(:created_at, :id)
          .map do |document|
            supporting_document_identity(document).merge(
              select(
                document,
                %w[
                  classification_confidence
                  classification_reason
                  supporting_document_routing_quality
                  supporting_document_routing_quality_reason
                ]
              )
            )
          end
      end

      def supporting_document_extraction
        documents =
          @invoice_version
            .supporting_documents
            .includes(:supporting_document_type)
            .order(:created_at, :id)
            .map do |document|
              {
                document: supporting_document_identity(document),
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

      def supporting_document_identity(document)
        select(
          document,
          %w[original_filename sha256 supporting_document_type_id]
        ).merge(
          "supporting_document_type_key" =>
            document.supporting_document_type&.type_key,
          "supporting_document_type_description" =>
            document.supporting_document_type&.description
        )
      end

      def upgrade_analysis
        {
          invoice_version_id: @invoice_version.id,
          located_fields: located_fields,
          rulechecks: rulechecks
        }
      end

      def located_fields
        ::Claims::InvoiceVersionLocatedField
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut " \
              "ON iut.id = claims.invoice_version_located_fields.invoice_upgrade_type_id"
          )
          .where(
            invoice_version_id: @invoice_version.id,
            source_engine: "genai"
          )
          .select(
            "claims.invoice_version_located_fields.*",
            "iut.upgrade_type_key AS upgrade_type_key",
            "iut.description AS upgrade_type_description"
          )
          .order("iut.upgrade_type_key", :source_engine, :field_key)
          .map do |field|
            select(
              field,
              field.attributes.keys -
                %w[id invoice_version_id created_at updated_at]
            ).merge(upgrade_type_labels(field))
          end
      end

      def rulechecks
        ::Claims::InvoiceVersionRulecheck
          .joins(
            "LEFT JOIN claims.invoice_upgrade_types iut " \
              "ON iut.id = claims.invoice_version_rulechecks.invoice_upgrade_type_id"
          )
          .where(
            invoice_version_id: @invoice_version.id,
            source_engine: "genai"
          )
          .select(
            "claims.invoice_version_rulechecks.*",
            "iut.upgrade_type_key AS upgrade_type_key",
            "iut.description AS upgrade_type_description"
          )
          .order("iut.upgrade_type_key", :source_engine, :rule_key)
          .map do |row|
            select(row, rulecheck_fields).merge(upgrade_type_labels(row))
          end
      end

      def upgrade_type_labels(row)
        {
          "upgrade_type_key" => row.read_attribute("upgrade_type_key"),
          "upgrade_type_description" =>
            row.read_attribute("upgrade_type_description")
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
