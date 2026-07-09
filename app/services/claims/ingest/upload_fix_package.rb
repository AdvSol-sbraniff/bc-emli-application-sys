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
          :error
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
              error: error
            }
          end
        end

      def self.call(
        invoice_id:,
        clone_invoice_version_id: nil,
        clone_supporting_document_ids: [],
        clone_all_current_supporting_documents: false,
        files: [],
        file_roles: []
      )
        new(
          invoice_id: invoice_id,
          clone_invoice_version_id: clone_invoice_version_id,
          clone_supporting_document_ids: clone_supporting_document_ids,
          clone_all_current_supporting_documents:
            clone_all_current_supporting_documents,
          files: files,
          file_roles: file_roles
        ).call
      end

      def initialize(
        invoice_id:,
        clone_invoice_version_id:,
        clone_supporting_document_ids:,
        clone_all_current_supporting_documents:,
        files:,
        file_roles:
      )
        @invoice_id = invoice_id.to_s.strip
        @clone_invoice_version_id = clone_invoice_version_id.to_s.strip.presence
        @clone_supporting_document_ids =
          Array(clone_supporting_document_ids).flatten.compact.map(&:to_s)
        @clone_all_current_supporting_documents =
          !!clone_all_current_supporting_documents
        @files = Array(files).flatten.compact
        @file_roles = Array(file_roles).flatten.map { |role| role.to_s.strip }
      end

      def call
        raise "Missing invoice_id in route." if @invoice_id.empty?

        invoice = ::Claims::Invoice.find(@invoice_id)
        source_invoice_version = source_invoice_version_for(invoice)
        invoice_sources = invoice_source_count
        if invoice_sources != 1
          raise(
            "The proposed fix package must contain exactly one invoice. " \
              "Detected #{invoice_sources} invoice source(s)."
          )
        end

        now = Time.current
        ingest_run = nil
        new_invoice_version = nil
        stage_step = nil
        new_file_documents = []

        ::Claims::Invoice.transaction do
          locked_invoice = ::Claims::Invoice.lock.find(invoice.id)
          next_versionno = next_invoice_versionno(locked_invoice.id)

          ingest_run =
            ::Claims::IngestRun.create!(
              session_id: locked_invoice.session_id,
              contractor_id: locked_invoice.contractor_id,
              status: "queued",
              total_files: total_file_count(source_invoice_version),
              completed_files: 0,
              failed_files: 0,
              messages: [
                "Fix package upload started.",
                "Selected current-version evidence will be cloned into the next version."
              ],
              created_at: now,
              updated_at: now
            )

          stage_step =
            ::Claims::IngestStepRun.create!(
              ingest_run_id: ingest_run.id,
              session_id: locked_invoice.session_id,
              step_type: "fix_upload_package_stage",
              status: "in_progress",
              error_text: nil,
              created_at: now,
              updated_at: now
            )

          new_invoice_version =
            if @clone_invoice_version_id.present?
              clone_invoice_version!(
                source_invoice_version: source_invoice_version,
                next_versionno: next_versionno,
                now: now
              )
            else
              create_pending_invoice_version!(
                invoice: locked_invoice,
                next_versionno: next_versionno,
                now: now
              )
            end
          ingest_run.update!(
            resolved_invoice_version_id: new_invoice_version.id,
            updated_at: now
          )

          if @clone_invoice_version_id.present?
            clone_invoice_document!(
              ingest_run: ingest_run,
              invoice: locked_invoice,
              source_invoice_version: source_invoice_version,
              new_invoice_version: new_invoice_version,
              now: now
            )
          end

          clone_supporting_documents!(
            ingest_run: ingest_run,
            invoice: locked_invoice,
            source_invoice_version: source_invoice_version,
            new_invoice_version: new_invoice_version,
            now: now
          )

          new_file_documents =
            build_new_file_documents!(
              ingest_run: ingest_run,
              invoice: locked_invoice,
              new_invoice_version: new_invoice_version,
              now: now
            )

          locked_invoice.set_workflow_status_columns!(
            "upload_in_progress",
            now: Time.current
          )
        end

        upload_new_files!(
          new_file_documents: new_file_documents,
          new_invoice_version: new_invoice_version
        )

        stage_step.update!(status: "succeeded", updated_at: Time.current)
        enqueue_new_file_ocr!(new_file_documents)

        invoice.set_workflow_status!("ocr_in_progress")
        ::Claims::Ingest::AdvanceBundleRun.call(ingest_run_id: ingest_run.id)
        ingest_run.reload

        Result.new(
          true,
          "upload_fix_package",
          invoice.id,
          new_invoice_version.id,
          new_invoice_version.invoice_versionno,
          invoice.session_id,
          ingest_run.id,
          ingest_run.status,
          "Fix package accepted. The next invoice version is being prepared.",
          nil
        )
      rescue => e
        failure_status, failure_subtype =
          upload_fix_failure_status_and_subtype(e)
        failure_payload =
          ::Claims::Invoices::FailureSubtypes.payload(
            status: failure_status,
            status_subtype: failure_subtype,
            error: e
          )
        begin
          stage_step&.update!(
            status: "failed",
            error_text: "#{e.class}: #{e.message}",
            genai_results_json: failure_payload,
            updated_at: Time.current
          )
          invoice&.set_workflow_status!(
            failure_status,
            status_subtype: failure_subtype
          )
          mark_ingest_run_failed!(
            ingest_run: ingest_run,
            status: failure_status,
            status_subtype: invoice&.status_subtype || failure_subtype,
            error: e
          )
        rescue StandardError
          nil
        end

        Result.new(
          false,
          "upload_fix_package",
          invoice&.id,
          new_invoice_version&.id,
          new_invoice_version&.invoice_versionno,
          invoice&.session_id,
          ingest_run&.id,
          safe_ingest_run_status(ingest_run),
          nil,
          "#{e.class}: #{e.message}"
        )
      end

      private

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

      def invoice_source_count
        clone_count = @clone_invoice_version_id.present? ? 1 : 0
        clone_count + new_invoice_files.size
      end

      def total_file_count(source_invoice_version)
        (@clone_invoice_version_id.present? ? 1 : 0) +
          clone_supporting_document_ids_for(source_invoice_version).size +
          @files.size
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

      def new_invoice_files
        @files.each_with_index.select do |_file, index|
          @file_roles[index].to_s == "invoice"
        end
      end

      def next_invoice_versionno(invoice_id)
        (
          ::Claims::InvoiceVersion.where(invoice_id: invoice_id).maximum(
            :invoice_versionno
          ) || 0
        ) + 1
      end

      def clone_invoice_version!(source_invoice_version:, next_versionno:, now:)
        clone = source_invoice_version.dup
        clone.invoice_versionno = next_versionno
        clone.genai_raw_json = nil
        clone.genai_overall_confidence = 0
        clone.genai_result = nil
        clone.genai_admin_advice = nil
        clone.ahri_product_id = nil
        clone.neea_product_id = nil
        clone.awhp_product_id = nil
        clone.ohpa_product_id = nil
        clone.herv_product_id = nil
        clone.vent_fan_product_id = nil
        clone.created_at = now
        clone.updated_at = now
        clone.save!

        clone_lineitems!(
          source_invoice_version_id: source_invoice_version.id,
          new_invoice_version_id: clone.id,
          now: now
        )
        clone_classifier_invoice_evidence!(
          source_invoice_version_id: source_invoice_version.id,
          new_invoice_version_id: clone.id,
          now: now
        )

        clone
      end

      def create_pending_invoice_version!(invoice:, next_versionno:, now:)
        invoice_file, index = new_invoice_files.first
        name =
          ::Claims::Ingest::EvidenceFile.original_filename(
            invoice_file,
            fallback: "invoice.pdf"
          )
        ctype =
          ::Claims::Ingest::EvidenceFile.content_type(
            invoice_file,
            fallback: "application/pdf"
          )
        size = ::Claims::Ingest::EvidenceFile.byte_size(invoice_file)

        ::Claims::InvoiceVersion.create!(
          invoice_id: invoice.id,
          invoice_versionno: next_versionno,
          storage_provider: "azure_blob",
          storage_key:
            pending_invoice_storage_key(
              invoice: invoice,
              next_versionno: next_versionno,
              filename: name,
              content_type: ctype
            ),
          original_filename: name,
          content_type: ctype,
          byte_size: size,
          created_at: now,
          updated_at: now
        )
      end

      def clone_lineitems!(
        source_invoice_version_id:,
        new_invoice_version_id:,
        now:
      )
        rows =
          ::Claims::Lineitem
            .where(invoice_version_id: source_invoice_version_id)
            .order(:lineitem_seqno, :id)
            .map do |row|
              row
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => new_invoice_version_id,
                  "created_at" => now,
                  "updated_at" => now
                )
            end
        ::Claims::Lineitem.insert_all!(rows) if rows.any?
      end

      def clone_classifier_invoice_evidence!(
        source_invoice_version_id:,
        new_invoice_version_id:,
        now:
      )
        located_rows =
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: source_invoice_version_id,
              source_engine: "classifier"
            )
            .map do |row|
              row
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => new_invoice_version_id,
                  "created_at" => now,
                  "updated_at" => now
                )
            end
        if located_rows.any?
          ::Claims::InvoiceVersionLocatedField.insert_all!(located_rows)
        end

        upgrade_rows =
          ::Claims::InvoiceVersionUpgradeType
            .where(
              invoice_version_id: source_invoice_version_id,
              source_engine: "classifier"
            )
            .map do |row|
              row
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => new_invoice_version_id,
                  "created_at" => now,
                  "updated_at" => now
                )
            end
        if upgrade_rows.any?
          ::Claims::InvoiceVersionUpgradeType.insert_all!(upgrade_rows)
        end
      end

      def clone_invoice_document!(
        ingest_run:,
        invoice:,
        source_invoice_version:,
        new_invoice_version:,
        now:
      )
        document =
          ::Claims::IngestDocument.create!(
            ingest_run_id: ingest_run.id,
            session_id: invoice.session_id,
            contractor_id: invoice.contractor_id,
            invoice_id: invoice.id,
            resolved_invoice_id: invoice.id,
            resolved_invoice_version_id: new_invoice_version.id,
            storage_provider: new_invoice_version.storage_provider,
            storage_key: new_invoice_version.storage_key,
            original_filename: new_invoice_version.original_filename,
            content_type: new_invoice_version.content_type,
            byte_size: new_invoice_version.byte_size,
            sha256: new_invoice_version.sha256,
            di_read_raw_json: source_invoice_version.di_raw_json,
            classifier_raw_json: nil,
            document_kind: "invoice",
            document_kind_confidence: 100,
            document_kind_reason: "Cloned from prior invoice version.",
            classification_status: "classified",
            classification_confidence: 100,
            classification_reason: "Cloned from prior invoice version.",
            classified_at: now,
            created_at: now,
            updated_at: now
          )
      end

      def clone_supporting_documents!(
        ingest_run:,
        invoice:,
        source_invoice_version:,
        new_invoice_version:,
        now:
      )
        clone_ids = clone_supporting_document_ids_for(source_invoice_version)

        docs =
          ::Claims::SupportingDocument
            .where(id: clone_ids, invoice_version_id: source_invoice_version.id)
            .includes(
              :supporting_document_located_fields,
              :supporting_document_visual_findings
            )
            .order(:created_at, :id)
            .to_a
        missing_ids = clone_ids - docs.map { |doc| doc.id.to_s }
        if missing_ids.any?
          raise "One or more cloned supporting documents do not belong to the current invoice version."
        end

        docs.each do |source_doc|
          new_doc =
            ::Claims::SupportingDocument.create!(
              source_doc
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => new_invoice_version.id,
                  "created_at" => now,
                  "updated_at" => now
                )
            )
          clone_supporting_document_children!(
            source_doc: source_doc,
            new_doc: new_doc,
            now: now
          )
          clone_supporting_document_ingest_row!(
            ingest_run: ingest_run,
            invoice: invoice,
            source_doc: source_doc,
            new_doc: new_doc,
            now: now
          )
        end
      end

      def clone_supporting_document_children!(source_doc:, new_doc:, now:)
        located_rows =
          source_doc.supporting_document_located_fields.map do |row|
            row
              .attributes
              .except(
                "id",
                "supporting_document_id",
                "created_at",
                "updated_at"
              )
              .merge(
                "supporting_document_id" => new_doc.id,
                "created_at" => now,
                "updated_at" => now
              )
          end
        if located_rows.any?
          ::Claims::SupportingDocumentLocatedField.insert_all!(located_rows)
        end

        finding_rows =
          source_doc.supporting_document_visual_findings.map do |row|
            row
              .attributes
              .except(
                "id",
                "supporting_document_id",
                "created_at",
                "updated_at"
              )
              .merge(
                "supporting_document_id" => new_doc.id,
                "created_at" => now,
                "updated_at" => now
              )
          end
        if finding_rows.any?
          ::Claims::SupportingDocumentVisualFinding.insert_all!(finding_rows)
        end
      end

      def clone_supporting_document_ingest_row!(
        ingest_run:,
        invoice:,
        source_doc:,
        new_doc:,
        now:
      )
        document =
          ::Claims::IngestDocument.create!(
            ingest_run_id: ingest_run.id,
            session_id: invoice.session_id,
            contractor_id: invoice.contractor_id,
            invoice_id: invoice.id,
            resolved_invoice_id: invoice.id,
            resolved_invoice_version_id: new_doc.invoice_version_id,
            promoted_supporting_document_id: new_doc.id,
            storage_provider: new_doc.storage_provider,
            storage_key: new_doc.storage_key,
            original_filename: new_doc.original_filename,
            content_type: new_doc.content_type,
            byte_size: new_doc.byte_size,
            sha256: new_doc.sha256,
            di_read_raw_json: new_doc.di_read_raw_json,
            classifier_raw_json: new_doc.classifier_raw_json,
            document_kind: "supporting_document",
            document_kind_confidence: 100,
            document_kind_reason: "Cloned from prior invoice version.",
            supporting_document_type_id: new_doc.supporting_document_type_id,
            classification_status: new_doc.classification_status,
            classification_confidence: new_doc.classification_confidence,
            classification_reason: new_doc.classification_reason,
            supporting_document_routing_quality:
              new_doc.supporting_document_routing_quality,
            supporting_document_routing_quality_reason:
              new_doc.supporting_document_routing_quality_reason,
            classified_at: now,
            created_at: now,
            updated_at: now
          )
      end

      def build_new_file_documents!(
        ingest_run:,
        invoice:,
        new_invoice_version:,
        now:
      )
        @files.each_with_index.map do |file, index|
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
              resolved_invoice_version_id: new_invoice_version.id,
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
              classification_status: "pending",
              classification_confidence: 0,
              document_kind_confidence: 0,
              created_at: now,
              updated_at: now
            )

          { file: file, role: @file_roles[index], document: document }
        end
      end

      def upload_new_files!(new_file_documents:, new_invoice_version:)
        new_file_documents.each do |row|
          file = row.fetch(:file)
          document = row.fetch(:document)
          node_resp =
            ::Claims::Ingest::UploadEvidenceFileToNode.call(
              session_id: document.session_id,
              upload_scope_id:
                (
                  if row[:role].to_s == "invoice"
                    new_invoice_version.id
                  else
                    document.id
                  end
                ),
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

          next unless row[:role].to_s == "invoice"

          new_invoice_version.update!(
            storage_key: final_storage_key,
            original_filename: document.original_filename,
            content_type: document.content_type,
            byte_size: document.byte_size,
            sha256: document.sha256,
            updated_at: Time.current
          )
        end
      end

      def enqueue_new_file_ocr!(new_file_documents)
        new_file_documents.each do |row|
          create_document_step!(
            ingest_run: row.fetch(:document).ingest_run,
            document: row.fetch(:document),
            step_type: "fix_ocr_read",
            status: "queued",
            now: Time.current
          )
          ::Claims::RunIngestReadOcrJob.perform_async(
            row.fetch(:document).id,
            row.fetch(:document).ingest_run_id,
            "fix_ocr_read"
          )
        end
      end

      def pending_invoice_storage_key(
        invoice:,
        next_versionno:,
        filename:,
        content_type:
      )
        extension =
          ::Claims::Ingest::EvidenceFile.storage_extension_for(
            filename: filename,
            content_type: content_type
          )
        "PENDING/session=#{invoice.session_id}/invoice=#{invoice.id}/v=#{next_versionno}/#{SecureRandom.uuid}#{extension}"
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

      def upload_fix_failure_status_and_subtype(error)
        message = error.message.to_s.downcase
        if message.include?(
             "the proposed fix package must contain exactly one invoice"
           )
          subtype =
            if message.include?("detected 0")
              "package_missing_required_fix_file"
            else
              "package_replacement_multiple_files"
            end
          return "package_needs_correction", subtype
        end
        if message.include?("evidence files are supported")
          return "package_needs_correction", "package_unsupported_file_type"
        end
        if message.include?(
             "cloned supporting documents do not belong to the current invoice version"
           )
          return "package_needs_correction", "package_duplicate_file_conflict"
        end

        ["technical_failure", ::Claims::Invoices::FailureSubtypes.upload(error)]
      end

      def mark_ingest_run_failed!(ingest_run:, status:, status_subtype:, error:)
        return unless ingest_run&.id

        ingest_run.update!(
          status: "failed",
          failed_files: 1,
          messages: [
            {
              level: "error",
              status: status,
              status_subtype: status_subtype,
              code: status_subtype,
              contractor_message:
                ::Claims::Invoices::StatusSubtypes.contractor_failure_message(
                  status,
                  status_subtype
                ),
              message: error.message.to_s
            }
          ],
          completed_at: Time.current,
          updated_at: Time.current
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
