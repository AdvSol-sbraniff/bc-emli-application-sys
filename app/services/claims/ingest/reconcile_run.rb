# frozen_string_literal: true

module Claims
  module Ingest
    class ReconcileRun
      TERMINAL_STATUSES = %w[succeeded failed partial].freeze
      VALIDATION_STEP_TYPES = %w[
        genai
        classifier
        case_facts
        genai_common
        genai_upgrade
        product_lookup_enrichment
        code_common
        code_upgrade
        aggregate_advice
      ].freeze
      INVOICE_CANDIDATE_ERROR_CODE = "invoice_bundle_count_invalid"

      def self.call(ingest_run_id:)
        new(ingest_run_id: ingest_run_id).call
      end

      def initialize(ingest_run_id:)
        @ingest_run_id = ingest_run_id
      end

      def call
        return if @ingest_run_id.blank?

        run = ::Claims::IngestRun.find_by(id: @ingest_run_id)
        return unless run

        invoice_version_ids =
          ::Claims::IngestStepRun
            .where(ingest_run_id: run.id)
            .distinct
            .pluck(:invoice_version_id)

        total_files = run.total_files.to_i
        total_files = invoice_version_ids.size if total_files <= 0

        succeeded = 0
        failed = 0
        running = 0

        invoice_version_ids.each do |invoice_version_id|
          plus1fix_read =
            latest_step(run.id, invoice_version_id, "plus1fix_ocr_read")

          if plus1fix_read&.status == "failed"
            failed += 1
            next
          end

          if plus1fix_read.present? && plus1fix_read.status != "succeeded"
            running += 1
            next
          end

          classifier =
            latest_step(
              run.id,
              invoice_version_id,
              %w[plus1fix_classifier classifier_pdfs]
            )

          if classifier&.status == "failed"
            failed += 1
            next
          end

          if classifier.present? && classifier.status != "succeeded"
            running += 1
            next
          end

          ocr = latest_step(run.id, invoice_version_id, %w[ocr ocr_invoice])

          if ocr.nil?
            running += 1
            next
          end

          if ocr.status == "failed"
            failed += 1
            next
          end

          if ocr.status != "succeeded"
            running += 1
            next
          end

          # OCR succeeded
          validation_steps = latest_validation_steps(run.id, invoice_version_id)
          invoice_status = invoice_status_for(invoice_version_id)

          if validation_steps.empty?
            if %w[genai_queued genai_in_progress].include?(invoice_status)
              running += 1
            else
              succeeded += 1
            end
          elsif validation_steps.any? { |step| step.status == "failed" } ||
                %w[
                  genai_failed
                  package_needs_correction
                  technical_failure
                ].include?(invoice_status)
            failed += 1
          elsif invoice_status == "genai_complete" &&
                validation_steps.all? { |step| step.status == "succeeded" }
            succeeded += 1
          else
            running += 1
          end
        end

        processed = succeeded + failed

        status =
          if total_files.positive? && processed >= total_files
            if failed.zero?
              "succeeded"
            elsif succeeded.zero?
              "failed"
            else
              "partial"
            end
          elsif processed.positive? || running.positive?
            "running"
          else
            "queued"
          end

        messages = parse_messages(run.messages)

        if TERMINAL_STATUSES.include?(status)
          bundle_validation =
            invoice_bundle_validation(
              run_id: run.id,
              invoice_version_ids: invoice_version_ids
            )

          if bundle_validation
            status = "failed"
            succeeded = 0
            failed =
              total_files.positive? ? total_files : invoice_version_ids.size
            messages = upsert_invoice_bundle_error(messages, bundle_validation)
          else
            messages = remove_invoice_bundle_error(messages)
          end
        end

        completed_at = TERMINAL_STATUSES.include?(status) ? Time.current : nil

        run.update!(
          status: status,
          total_files: total_files,
          completed_files: succeeded,
          failed_files: failed,
          messages: messages,
          completed_at: completed_at,
          updated_at: Time.current
        )
      end

      private

      def latest_step(ingest_run_id, invoice_version_id, step_type)
        ::Claims::IngestStepRun
          .where(
            ingest_run_id: ingest_run_id,
            invoice_version_id: invoice_version_id,
            step_type: Array(step_type)
          )
          .order(created_at: :desc)
          .first
      end

      def latest_validation_steps(ingest_run_id, invoice_version_id)
        ::Claims::IngestStepRun.where(
          ingest_run_id: ingest_run_id,
          invoice_version_id: invoice_version_id,
          step_type: VALIDATION_STEP_TYPES
        ).order(created_at: :desc)
      end

      def invoice_status_for(invoice_version_id)
        ::Claims::InvoiceVersion
          .joins(
            "JOIN claims.invoices i ON i.id = claims.invoice_versions.invoice_id"
          )
          .where(id: invoice_version_id)
          .pick("i.status")
          .to_s
      end

      def invoice_bundle_validation(run_id:, invoice_version_ids:)
        candidate_rows =
          ::Claims::InvoiceVersionUpgradeType
            .joins(
              "JOIN claims.invoice_versions iv ON iv.id = claims.invoice_version_upgrade_types.invoice_version_id"
            )
            .joins(
              "JOIN claims.invoice_upgrade_types iut ON iut.id = claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
            )
            .where(
              invoice_version_id: invoice_version_ids,
              source_engine: "classifier"
            )
            .where.not("iut.upgrade_type_key = ?", "common")
            .distinct
            .pluck(
              "claims.invoice_version_upgrade_types.invoice_version_id",
              "iv.original_filename"
            )

        candidate_count = candidate_rows.size
        return nil if candidate_count == 1

        {
          code: INVOICE_CANDIDATE_ERROR_CODE,
          level: "error",
          invoice_candidate_count: candidate_count,
          invoice_candidate_filenames:
            candidate_rows.map { |_id, filename| filename.to_s }.uniq.sort,
          message:
            "Exactly one invoice is required in the upload bundle; detected #{candidate_count} invoice candidates."
        }
      end

      def parse_messages(messages)
        return messages if messages.is_a?(Array)

        JSON.parse(messages.to_s)
      rescue JSON::ParserError, TypeError
        []
      end

      def upsert_invoice_bundle_error(messages, payload)
        cleaned = remove_invoice_bundle_error(messages)
        cleaned << payload
        cleaned
      end

      def remove_invoice_bundle_error(messages)
        Array(messages).reject do |row|
          row.is_a?(Hash) &&
            (
              row["code"].to_s == INVOICE_CANDIDATE_ERROR_CODE ||
                row[:code].to_s == INVOICE_CANDIDATE_ERROR_CODE
            )
        end
      end
    end
  end
end
