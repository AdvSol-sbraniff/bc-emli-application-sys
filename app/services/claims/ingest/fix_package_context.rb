# frozen_string_literal: true

module Claims
  module Ingest
    class FixPackageContext
      CLONED_REASON_PREFIX = "Cloned from prior"

      def initialize(ingest_run:)
        @ingest_run = ingest_run
      end

      def invoice
        @invoice ||=
          ::Claims::Invoice.find(
            @ingest_run.invoice_id.presence ||
              raise("Fix upload is missing its invoice context.")
          )
      end

      def source_invoice_version
        @source_invoice_version ||=
          begin
            scope =
              ::Claims::InvoiceVersion.where(invoice_id: invoice.id).where(
                "created_at <= ?",
                @ingest_run.created_at
              )
            cloned_invoice = cloned_documents.find_by(document_kind: "invoice")
            if cloned_invoice.present?
              scope =
                scope.where(
                  storage_provider: cloned_invoice.storage_provider,
                  storage_key: cloned_invoice.storage_key
                )
              scope =
                scope.where(
                  sha256: cloned_invoice.sha256
                ) if cloned_invoice.sha256.present?
            end

            scope.order(
              invoice_versionno: :desc,
              created_at: :desc,
              id: :desc
            ).first ||
              raise(
                "The source invoice version for this fix is no longer available."
              )
          end
      end

      def replacement_invoice_document
        invoice_documents =
          documents.where(document_kind: "invoice").limit(2).to_a
        unless invoice_documents.one?
          raise "Fix upload must contain exactly one replacement invoice."
        end

        invoice_documents.first
      end

      def retained_supporting_documents
        cloned_documents
          .where(document_kind: "supporting_document")
          .order(:created_at, :id)
          .map do |staged_document|
            matches =
              ::Claims::SupportingDocument.where(
                invoice_version_id: source_invoice_version.id,
                storage_provider: staged_document.storage_provider,
                storage_key: staged_document.storage_key
              )
            if staged_document.sha256.present?
              matches = matches.where(sha256: staged_document.sha256)
            end
            source_documents = matches.limit(2).to_a
            unless source_documents.one?
              raise "A retained supporting document could not be matched uniquely to the source invoice version."
            end

            [staged_document, source_documents.first]
          end
      end

      private

      def documents
        ::Claims::IngestDocument.where(ingest_run_id: @ingest_run.id)
      end

      def cloned_documents
        documents.where(
          "document_kind_reason LIKE ?",
          "#{CLONED_REASON_PREFIX}%"
        )
      end
    end
  end
end
