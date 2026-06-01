# frozen_string_literal: true

module Claims
  module Ingest
    class RedoInvoicePackage
      Result =
        Struct.new(
          :ok,
          :ingest_run_id,
          :invoice_id,
          :queued_count,
          :rows,
          :messages
        ) do
          def to_h
            {
              ok: ok,
              ingest_run_id: ingest_run_id,
              invoice_id: invoice_id,
              queued_count: queued_count,
              rows: rows,
              messages: messages
            }
          end
        end

      def self.call(invoice_id:, validationgenai_ruleset_id: nil)
        new(
          invoice_id: invoice_id,
          validationgenai_ruleset_id: validationgenai_ruleset_id
        ).call
      end

      def initialize(invoice_id:, validationgenai_ruleset_id:)
        @invoice_id = invoice_id.to_s.strip
        @validationgenai_ruleset_id = validationgenai_ruleset_id.to_s.strip
      end

      def call
        raise "Missing invoice_id." if @invoice_id.empty?

        invoice = ::Claims::Invoice.find(@invoice_id)
        raise "Invoice is missing session_id." if invoice.session_id.blank?
        if invoice.contractor_id.blank?
          raise "Invoice is missing contractor_id."
        end

        ruleset_id =
          @validationgenai_ruleset_id.presence || resolve_default_ruleset_id!
        sources = source_documents(invoice: invoice)
        if sources.empty?
          raise "No source PDFs are available for invoice_id=#{invoice.id}."
        end

        ingest_run =
          ::Claims::IngestRun.create!(
            session_id: invoice.session_id,
            status: "queued",
            total_files: sources.size,
            completed_files: 0,
            failed_files: 0,
            messages: [],
            created_at: Time.current,
            updated_at: Time.current
          )

        stage_step =
          ::Claims::IngestStepRun.create!(
            ingest_run_id: ingest_run.id,
            session_id: invoice.session_id,
            step_type: "reprocess_package_stage",
            status: "in_progress",
            error_text: nil,
            created_at: Time.current,
            updated_at: Time.current
          )

        rows =
          sources.each_with_index.map do |source, index|
            create_fresh_ingest_document!(
              invoice: invoice,
              ingest_run: ingest_run,
              source: source,
              index: index,
              ruleset_id: ruleset_id
            )
          end
        mark_superseded_source_documents!(
          sources: sources,
          ingest_run: ingest_run
        )

        stage_step.update!(
          status: "succeeded",
          error_text: nil,
          genai_results_json: {
            source_count: sources.size,
            source_storage_keys: sources.map { |row| row[:storage_key] }
          },
          updated_at: Time.current
        )

        invoice.update!(
          status: "ocr_in_progress",
          status_updated_at: Time.current,
          updated_at: Time.current
        )

        ::Claims::Ingest::AdvanceBundleRun.call(
          ingest_run_id: ingest_run.id,
          validationgenai_ruleset_id: ruleset_id
        )

        Result.new(true, ingest_run.id, invoice.id, rows.size, rows, []).to_h
      rescue => e
        begin
          if stage_step && stage_step.status != "succeeded"
            stage_step.update!(
              status: "failed",
              error_text: "#{e.class}: #{e.message}",
              updated_at: Time.current
            )
          end
        rescue StandardError
          nil
        end

        begin
          ingest_run&.update!(
            status: "failed",
            failed_files: ingest_run.total_files.to_i,
            messages: [
              {
                level: "error",
                code: "redo_invoice_package_failed",
                message: "#{e.class}: #{e.message}"
              }
            ],
            completed_at: Time.current,
            updated_at: Time.current
          )
        rescue StandardError
          nil
        end
        raise
      end

      private

      def source_documents(invoice:)
        rows = []
        seen_storage_keys = {}

        add_source =
          lambda do |source, row|
            storage_key = row[:storage_key].to_s.strip
            return if storage_key.empty? || seen_storage_keys[storage_key]

            seen_storage_keys[storage_key] = true
            rows << row.merge(source: source)
          end

        latest_invoice_version =
          ::Claims::InvoiceVersion
            .where(invoice_id: invoice.id)
            .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
            .first
        if latest_invoice_version
          add_source.call(
            "invoice_version",
            source_row_from_record(latest_invoice_version)
          )
        end

        ::Claims::SupportingDocument
          .where(invoice_id: invoice.id)
          .order(created_at: :asc, id: :asc)
          .find_each do |document|
            add_source.call(
              "supporting_document",
              source_row_from_record(document)
            )
          end

        ::Claims::IngestDocument
          .where(
            "invoice_id = :invoice_id OR resolved_invoice_id = :invoice_id",
            invoice_id: invoice.id
          )
          .where(promoted_supporting_document_id: nil)
          .where(resolved_invoice_version_id: nil)
          .where(
            "classification_status IS NULL OR classification_status <> ?",
            "superseded"
          )
          .order(created_at: :asc, id: :asc)
          .find_each do |document|
            add_source.call("ingest_document", source_row_from_record(document))
          end

        rows
      end

      def source_row_from_record(record)
        {
          storage_provider: record.storage_provider.presence || "azure_blob",
          storage_key: record.storage_key,
          original_filename:
            record.original_filename.presence || "package-document.pdf",
          content_type: record.content_type.presence || "application/pdf",
          byte_size: record.byte_size,
          sha256: record.sha256,
          source_record_id: record.id
        }
      end

      def mark_superseded_source_documents!(sources:, ingest_run:)
        source_ids =
          sources
            .select { |source| source[:source] == "ingest_document" }
            .filter_map { |source| source[:source_record_id] }
            .uniq
        return if source_ids.empty?

        ::Claims::IngestDocument
          .where(id: source_ids)
          .where(promoted_supporting_document_id: nil)
          .where(resolved_invoice_version_id: nil)
          .update_all(
            [
              "classification_status = ?, classification_reason = ?, updated_at = ?",
              "superseded",
              "Copied into redo ingest_run #{ingest_run.id}.",
              Time.current
            ]
          )
      end

      def create_fresh_ingest_document!(
        invoice:,
        ingest_run:,
        source:,
        index:,
        ruleset_id:
      )
        document =
          ::Claims::IngestDocument.create!(
            ingest_run_id: ingest_run.id,
            session_id: invoice.session_id,
            contractor_id: invoice.contractor_id,
            invoice_id: invoice.id,
            resolved_invoice_id: invoice.id,
            storage_provider: source[:storage_provider],
            storage_key: source[:storage_key],
            original_filename: source[:original_filename],
            content_type: source[:content_type],
            byte_size: source[:byte_size],
            sha256: source[:sha256],
            classification_status: "pending",
            classification_confidence: 0,
            document_kind_confidence: 0,
            created_at: Time.current,
            updated_at: Time.current
          )

        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run.id,
          session_id: invoice.session_id,
          ingest_document_id: document.id,
          step_type: "ocr_read",
          status: "queued",
          error_text: nil,
          created_at: Time.current,
          updated_at: Time.current
        )

        jid =
          ::Claims::RunIngestReadOcrJob.perform_async(
            document.id,
            ingest_run.id,
            ruleset_id
          )

        {
          index: index + 1,
          ingest_document_id: document.id,
          original_filename: document.original_filename,
          source: source[:source],
          storage_key: document.storage_key,
          status: "queued_ocr",
          job_id: jid
        }
      end

      def resolve_default_ruleset_id!
        common =
          ::Claims::InvoiceUpgradeType.find_by(upgrade_type_key: "common")
        row =
          ::Claims::ValidationgenaiRuleset
            .where(invoice_upgrade_type_id: common&.id)
            .where(enabled: true)
            .order(Arel.sql("updated_at DESC, created_at DESC, id DESC"))
            .first ||
            ::Claims::ValidationgenaiRuleset
              .where(invoice_upgrade_type_id: common&.id)
              .order(Arel.sql("updated_at DESC, created_at DESC, id DESC"))
              .first

        if row.nil?
          raise "No default/common validationgenai_ruleset found for full GenAI run."
        end

        row.id
      end
    end
  end
end
