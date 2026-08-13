# frozen_string_literal: true

require "json"
require "securerandom"

module Claims
  module Ingest
    class UploadFixPackage
      Result =
        Struct.new(
          :ok,
          :stage,
          :invoice_id,
          :invoice_version_id,
          :invoice_versionno,
          :session_id,
          :ingest_run_id,
          :status,
          :message,
          :error,
          :failure_category,
          :failure_code,
          :error_code,
          :retryable,
          :diagnostic_id
        ) do
          def to_h
            {
              ok: ok,
              stage: stage,
              invoice_id: invoice_id,
              invoice_version_id: invoice_version_id,
              invoice_versionno: invoice_versionno,
              session_id: session_id,
              ingest_run_id: ingest_run_id,
              status: status,
              message: message,
              error: error,
              failure_category: failure_category,
              failure_code: failure_code,
              error_code: error_code,
              retryable: retryable,
              diagnostic_id: diagnostic_id
            }.compact
          end
        end

      def self.call(
        invoice_id:,
        clone_invoice_version_id: nil,
        clone_supporting_document_ids: [],
        clone_all_current_supporting_documents: false,
        files: []
      )
        new(
          invoice_id: invoice_id,
          clone_invoice_version_id: clone_invoice_version_id,
          clone_supporting_document_ids: clone_supporting_document_ids,
          clone_all_current_supporting_documents:
            clone_all_current_supporting_documents,
          files: files
        ).call
      end

      def initialize(
        invoice_id:,
        clone_invoice_version_id:,
        clone_supporting_document_ids:,
        clone_all_current_supporting_documents:,
        files:
      )
        @invoice_id = invoice_id.to_s.strip
        @clone_invoice_version_id = clone_invoice_version_id.to_s.strip.presence
        @clone_supporting_document_ids =
          Array(clone_supporting_document_ids).flatten.compact.map(&:to_s)
        @clone_all_current_supporting_documents =
          ActiveModel::Type::Boolean.new.cast(
            clone_all_current_supporting_documents
          )
        @files = Array(files).flatten.compact
      end

      def call
        raise "Missing invoice_id in route." if @invoice_id.empty?

        invoice = ::Claims::Invoice.find(@invoice_id)
        source_invoice_version = source_invoice_version_for(invoice)
        retained_supporting_document_ids =
          clone_supporting_document_ids_for(source_invoice_version)

        now = Time.current
        ingest_run = nil
        stage_step = nil
        ::Claims::IngestRun.transaction do
          ingest_run =
            ::Claims::IngestRun.create!(
              session_id: invoice.session_id,
              contractor_id: invoice.contractor_id,
              invoice_id: invoice.id,
              run_kind: "fix_upload",
              status: "queued",
              total_files: total_file_count(retained_supporting_document_ids),
              completed_files: 0,
              failed_files: 0,
              created_at: now,
              updated_at: now
            )
          stage_step =
            ::Claims::IngestStepRun.create!(
              ingest_run_id: ingest_run.id,
              session_id: invoice.session_id,
              step_type: "stage_package",
              status: "in_progress",
              error_text: nil,
              created_at: now,
              updated_at: now
            )
        end
        new_file_documents = []

        ::Claims::IngestDocument.transaction do
          if @clone_invoice_version_id.present?
            stage_cloned_invoice_document!(
              ingest_run: ingest_run,
              invoice: invoice,
              source_invoice_version: source_invoice_version,
              now: now
            )
          end

          stage_cloned_supporting_documents!(
            ingest_run: ingest_run,
            invoice: invoice,
            source_invoice_version: source_invoice_version,
            retained_supporting_document_ids: retained_supporting_document_ids,
            now: now
          )

          new_file_documents =
            build_new_file_documents!(
              ingest_run: ingest_run,
              invoice: invoice,
              now: now
            )
        end

        upload_new_files!(new_file_documents: new_file_documents)

        stage_step.update!(status: "succeeded", updated_at: Time.current)
        enqueue_new_file_ocr!(new_file_documents)

        ::Claims::Ingest::AdvanceRun.call(ingest_run_id: ingest_run.id)
        ingest_run.reload
        if ingest_run.status == "failed"
          return failed_run_result(invoice: invoice, ingest_run: ingest_run)
        end

        Result.new(
          true,
          "upload_fix_package",
          invoice.id,
          ingest_run.resolved_invoice_version_id,
          nil,
          invoice.session_id,
          ingest_run.id,
          ingest_run.status,
          "Fix package accepted. The next invoice version is being prepared.",
          nil,
          nil,
          nil,
          nil,
          nil,
          nil
        )
      rescue StandardError => e
        failure_category, failure_subtype =
          upload_fix_failure_category_and_subtype(e)
        retryable = ::Claims::Ingest::FailureClassifier.retryable?(e)
        diagnostic_id = SecureRandom.uuid if failure_category ==
          "technical_failure"
        finalize_upload_fix_failure!(
          stage_step: stage_step,
          invoice: invoice,
          ingest_run: ingest_run,
          failure_category: failure_category,
          failure_subtype: failure_subtype,
          retryable: retryable,
          diagnostic_id: diagnostic_id,
          error: e
        )

        if diagnostic_id.present?
          Rails.logger.error(
            "[claims][ingest][upload_fix_package] diagnostic_id=#{diagnostic_id} " \
              "ingest_run_id=#{ingest_run&.id || "-"} " \
              "ERROR: #{e.class}: #{e.message}"
          )
          Rails.logger.error(Array(e.backtrace).join("\n"))
        end

        safe_error =
          ::Claims::Ingest::FailureCatalog.contractor_failure_message(
            failure_category,
            failure_subtype
          ).presence || ::Claims::Ingest::UploadErrors::SAFE_TECHNICAL_MESSAGE

        Result.new(
          false,
          "upload_fix_package",
          invoice&.id,
          ingest_run&.resolved_invoice_version_id,
          nil,
          invoice&.session_id,
          ingest_run&.id,
          safe_ingest_run_status(ingest_run),
          nil,
          safe_error,
          failure_category,
          failure_subtype,
          failure_subtype,
          retryable,
          diagnostic_id
        )
      end

      private

      def failed_run_result(invoice:, ingest_run:)
        failure_category =
          ingest_run.failure_category.presence || "technical_failure"
        failure_subtype =
          ingest_run.failure_code.presence || "unknown_runtime_failure"
        safe_error =
          ::Claims::Ingest::FailureCatalog.contractor_failure_message(
            failure_category,
            failure_subtype
          ).presence || ::Claims::Ingest::UploadErrors::SAFE_TECHNICAL_MESSAGE

        Result.new(
          false,
          "upload_fix_package",
          invoice.id,
          ingest_run.resolved_invoice_version_id,
          nil,
          invoice.session_id,
          ingest_run.id,
          ingest_run.status,
          nil,
          safe_error,
          failure_category,
          failure_subtype,
          ingest_run.pipeline_error_code.presence || failure_subtype,
          false,
          nil
        )
      end

      def finalize_upload_fix_failure!(
        stage_step:,
        invoice:,
        ingest_run:,
        failure_category:,
        failure_subtype:,
        retryable:,
        diagnostic_id:,
        error:
      )
        now = Time.current
        diagnostic_attributes =
          ::Claims::Ingest::FailureClassifier.step_attributes(
            failure_category: failure_category,
            failure_code: failure_subtype,
            error: error
          )
        diagnostic_attributes[
          :diagnostic_id
        ] ||= diagnostic_id if diagnostic_id.present?
        diagnostic_attributes[:retryable] = retryable

        safely_finalize_upload_fix!(
          label: "stage step",
          diagnostic_id: diagnostic_id
        ) do
          stage_step&.update_columns(
            status: "failed",
            error_text: "Fix upload failed: #{failure_subtype}.",
            genai_results_json: nil,
            completed_at: now,
            **diagnostic_attributes,
            updated_at: now
          )
        end

        normalized_subtype =
          ::Claims::Ingest::FailureCatalog.normalize(
            failure_category,
            failure_subtype
          ).presence || failure_subtype
        safely_finalize_upload_fix!(
          label: "ingest run",
          diagnostic_id: diagnostic_id
        ) do
          mark_ingest_run_failed!(
            ingest_run: ingest_run,
            failure_category: failure_category,
            failure_code: normalized_subtype
          )
        end
      end

      def safely_finalize_upload_fix!(label:, diagnostic_id:)
        yield
      rescue StandardError => finalization_error
        Rails.logger.error(
          "[claims][ingest][upload_fix_package] diagnostic_id=#{diagnostic_id || "-"} " \
            "failed to finalize #{label}: " \
            "#{finalization_error.class}: #{finalization_error.message}"
        )
      end

      def source_invoice_version_for(invoice)
        if @clone_invoice_version_id.present?
          return(
            ::Claims::InvoiceVersion.find_by!(
              id: @clone_invoice_version_id,
              invoice_id: invoice.id
            )
          )
        end

        ::Claims::InvoiceVersion
          .where(invoice_id: invoice.id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .first
      end

      def total_file_count(retained_supporting_document_ids)
        (@clone_invoice_version_id.present? ? 1 : 0) +
          retained_supporting_document_ids.size + @files.size
      end

      def clone_supporting_document_ids_for(source_invoice_version)
        explicit_ids = @clone_supporting_document_ids.uniq
        return explicit_ids unless @clone_all_current_supporting_documents
        return explicit_ids if explicit_ids.any?
        return [] if source_invoice_version.blank?

        ::Claims::SupportingDocument
          .where(invoice_version_id: source_invoice_version.id)
          .order(:created_at, :id)
          .pluck(:id)
          .map(&:to_s)
      end

      def stage_cloned_invoice_document!(
        ingest_run:,
        invoice:,
        source_invoice_version:,
        now:
      )
        ::Claims::IngestDocument.create!(
          ingest_run_id: ingest_run.id,
          session_id: invoice.session_id,
          contractor_id: invoice.contractor_id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: nil,
          storage_provider: source_invoice_version.storage_provider,
          storage_key: source_invoice_version.storage_key,
          original_filename: source_invoice_version.original_filename,
          content_type: source_invoice_version.content_type,
          byte_size: source_invoice_version.byte_size,
          sha256: source_invoice_version.sha256,
          di_read_raw_json: source_invoice_version.di_raw_json,
          classifier_raw_json: nil,
          document_kind: "invoice",
          document_kind_confidence: 100,
          document_kind_reason: "Cloned from prior invoice version.",
          classification_confidence: 100,
          classification_reason: "Cloned from prior invoice version.",
          classified_at: now,
          created_at: now,
          updated_at: now
        )
      end

      def stage_cloned_supporting_documents!(
        ingest_run:,
        invoice:,
        source_invoice_version:,
        retained_supporting_document_ids:,
        now:
      )
        docs =
          ::Claims::SupportingDocument
            .where(
              id: retained_supporting_document_ids,
              invoice_version_id: source_invoice_version.id
            )
            .order(:created_at, :id)
            .to_a
        missing_ids =
          retained_supporting_document_ids - docs.map { |doc| doc.id.to_s }
        if missing_ids.any?
          raise "One or more cloned supporting documents do not belong to the current invoice version."
        end

        docs.each do |source_doc|
          stage_cloned_supporting_document!(
            ingest_run: ingest_run,
            invoice: invoice,
            source_doc: source_doc,
            now: now
          )
        end
      end

      def stage_cloned_supporting_document!(
        ingest_run:,
        invoice:,
        source_doc:,
        now:
      )
        ::Claims::IngestDocument.create!(
          ingest_run_id: ingest_run.id,
          session_id: invoice.session_id,
          contractor_id: invoice.contractor_id,
          invoice_id: invoice.id,
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: nil,
          promoted_supporting_document_id: nil,
          storage_provider: source_doc.storage_provider,
          storage_key: source_doc.storage_key,
          original_filename: source_doc.original_filename,
          content_type: source_doc.content_type,
          byte_size: source_doc.byte_size,
          sha256: source_doc.sha256,
          di_read_raw_json: source_doc.di_read_raw_json,
          classifier_raw_json: source_doc.classifier_raw_json,
          document_kind: "supporting_document",
          document_kind_confidence: 100,
          document_kind_reason: "Cloned from prior invoice version.",
          supporting_document_type_id: source_doc.supporting_document_type_id,
          classification_confidence: source_doc.classification_confidence,
          classification_reason: source_doc.classification_reason,
          supporting_document_routing_quality:
            source_doc.supporting_document_routing_quality,
          supporting_document_routing_quality_reason:
            source_doc.supporting_document_routing_quality_reason,
          classified_at: now,
          created_at: now,
          updated_at: now
        )
      end

      def build_new_file_documents!(ingest_run:, invoice:, now:)
        @files.map do |file|
          name =
            ::Claims::Ingest::EvidenceFile.original_filename(
              file,
              fallback: "uploaded-file"
            )
          ctype = ::Claims::Ingest::EvidenceFile.content_type(file)
          size = ::Claims::Ingest::EvidenceFile.byte_size(file)
          unless ::Claims::Ingest::EvidenceFile.supported?(
                   filename: name,
                   content_type: ctype
                 )
            raise "Only PDF, JPG, JPEG, and PNG evidence files are supported."
          end

          document =
            ::Claims::IngestDocument.create!(
              ingest_run_id: ingest_run.id,
              session_id: invoice.session_id,
              contractor_id: invoice.contractor_id,
              invoice_id: invoice.id,
              resolved_invoice_id: invoice.id,
              resolved_invoice_version_id: nil,
              storage_provider: "azure_blob",
              storage_key:
                pending_ingest_storage_key(
                  session_id: invoice.session_id,
                  filename: name,
                  content_type: ctype
                ),
              original_filename: name,
              content_type: ctype,
              byte_size: size,
              classification_confidence: 0,
              document_kind_confidence: 0,
              created_at: now,
              updated_at: now
            )

          { file: file, document: document }
        end
      end

      def upload_new_files!(new_file_documents:)
        new_file_documents.each do |row|
          file = row.fetch(:file)
          document = row.fetch(:document)
          node_resp =
            ::Claims::Ingest::UploadEvidenceFileToNode.call(
              session_id: document.session_id,
              upload_scope_id: document.id,
              ingest_document_id: document.id,
              file: file
            )
          final_storage_key = node_resp.fetch("storage_key").to_s.strip
          if final_storage_key.empty?
            raise "Node upload returned no storage_key"
          end

          document.update!(
            storage_key: final_storage_key,
            byte_size:
              (
                if node_resp.key?("byte_size")
                  node_resp["byte_size"]
                else
                  document.byte_size
                end
              ),
            sha256: node_resp["sha256"],
            updated_at: Time.current
          )
        end
      end

      def enqueue_new_file_ocr!(new_file_documents)
        new_file_documents.each do |row|
          create_document_step!(
            ingest_run: row.fetch(:document).ingest_run,
            document: row.fetch(:document),
            step_type: "read_document",
            status: "queued",
            now: Time.current
          )
          ::Claims::RunIngestReadOcrJob.perform_async(
            row.fetch(:document).id,
            row.fetch(:document).ingest_run_id
          )
        end
      end

      def pending_ingest_storage_key(session_id:, filename:, content_type:)
        extension =
          ::Claims::Ingest::EvidenceFile.storage_extension_for(
            filename: filename,
            content_type: content_type
          )
        "PENDING/session=#{session_id}/ingest_document=#{SecureRandom.uuid}/#{SecureRandom.uuid}#{extension}"
      end

      def create_document_step!(
        ingest_run:,
        document:,
        step_type:,
        status:,
        now:,
        di_results_json: nil,
        genai_results_json: nil
      )
        ::Claims::IngestStepRun.create!(
          ingest_run_id: ingest_run.id,
          session_id: document.session_id,
          ingest_document_id: document.id,
          step_type: step_type,
          status: status,
          error_text: nil,
          di_results_json: di_results_json,
          genai_results_json: genai_results_json,
          created_at: now,
          updated_at: now
        )
      end

      def upload_fix_failure_category_and_subtype(error)
        message = error.message.to_s.downcase
        if message.include?("evidence files are supported")
          return "package_needs_correction", "package_unsupported_file_type"
        end
        if message.include?(
             "cloned supporting documents do not belong to the current invoice version"
           )
          return "package_needs_correction", "package_duplicate_file_conflict"
        end

        ["technical_failure", ::Claims::Ingest::FailureClassifier.upload(error)]
      end

      def mark_ingest_run_failed!(ingest_run:, failure_category:, failure_code:)
        return unless ingest_run&.id

        ::Claims::Ingest::RunTransition.mark_failed!(
          run: ingest_run,
          total_files: [ingest_run.total_files.to_i, 1].max,
          failed_files: 1,
          failure_category: failure_category,
          failure_code: failure_code,
          pipeline_error_code: failure_code,
          pipeline_error_description: "Fix upload failed: #{failure_code}."
        )
      end

      def safe_ingest_run_status(ingest_run)
        return nil if ingest_run.nil? || ingest_run.id.blank?

        ingest_run.reload.status
      rescue StandardError
        nil
      end
    end
  end
end
