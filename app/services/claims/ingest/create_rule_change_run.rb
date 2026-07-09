# frozen_string_literal: true

module Claims
  module Ingest
    class CreateRuleChangeRun
      Result =
        Struct.new(
          :ok,
          :invoice_id,
          :source_invoice_version_id,
          :invoice_version_id,
          :invoice_versionno,
          :session_id,
          :ingest_run_id,
          :job_id,
          :status,
          :message,
          :error,
          keyword_init: true
        ) do
          def to_h
            {
              ok: ok,
              invoice_id: invoice_id,
              source_invoice_version_id: source_invoice_version_id,
              invoice_version_id: invoice_version_id,
              invoice_versionno: invoice_versionno,
              session_id: session_id,
              ingest_run_id: ingest_run_id,
              job_id: job_id,
              status: status,
              message: message,
              error: error
            }
          end
        end

      def self.call(invoice_id:)
        new(invoice_id: invoice_id).call
      end

      def initialize(invoice_id:)
        @invoice_id = invoice_id.to_s.strip
      end

      def call
        raise "Missing invoice_id in route." if @invoice_id.empty?

        now = Time.current
        source_invoice_version = nil
        new_invoice_version = nil
        ingest_run = nil
        invoice = nil

        ::Claims::Invoice.transaction do
          invoice = ::Claims::Invoice.lock.find(@invoice_id)
          source_invoice_version = latest_invoice_version_for(invoice)

          if source_invoice_version.nil?
            raise "Current invoice version not found."
          end

          if source_invoice_version.di_raw_json.blank?
            raise(
              "Current invoice version has no invoice OCR/DI result to reanalyze."
            )
          end

          next_versionno = next_invoice_versionno(invoice.id)
          new_invoice_version =
            clone_invoice_version!(
              source_invoice_version: source_invoice_version,
              next_versionno: next_versionno,
              now: now
            )
          clone_supporting_documents!(
            source_invoice_version_id: source_invoice_version.id,
            new_invoice_version_id: new_invoice_version.id,
            now: now
          )

          ingest_run =
            ::Claims::IngestRun.create!(
              session_id: invoice.session_id,
              contractor_id: invoice.contractor_id,
              resolved_invoice_version_id: new_invoice_version.id,
              status: "queued",
              total_files: 0,
              completed_files: 0,
              failed_files: 0,
              messages: [
                "Advice refresh requested from admin invoice grid.",
                "Existing evidence was cloned into a new invoice version; AI advice will be regenerated."
              ],
              created_at: now,
              updated_at: now
            )

          ::Claims::IngestStepRun.create!(
            ingest_run_id: ingest_run.id,
            session_id: invoice.session_id,
            invoice_version_id: new_invoice_version.id,
            step_type: "ruleclone_clone_existing_evidence",
            status: "succeeded",
            error_text: nil,
            created_at: now,
            updated_at: now
          )

          invoice.set_workflow_status_columns!("genai_queued", now: now)
        end

        job_id =
          ::Claims::RunGenaiJob.perform_async(
            invoice.session_id,
            new_invoice_version.id,
            ingest_run.id,
            "use_existing_classifier"
          )

        Result.new(
          ok: true,
          invoice_id: invoice.id,
          source_invoice_version_id: source_invoice_version.id,
          invoice_version_id: new_invoice_version.id,
          invoice_versionno: new_invoice_version.invoice_versionno,
          session_id: invoice.session_id,
          ingest_run_id: ingest_run.id,
          job_id: job_id,
          status: invoice.reload.status,
          message:
            "Advice refresh accepted. A new invoice version is being revalidated.",
          error: nil
        )
      end

      private

      def latest_invoice_version_for(invoice)
        ::Claims::InvoiceVersion
          .where(invoice_id: invoice.id)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .first
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
        clone.users_eligibilitycode_id = nil
        clone.participant_user_id = nil
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

      def clone_supporting_documents!(
        source_invoice_version_id:,
        new_invoice_version_id:,
        now:
      )
        docs =
          ::Claims::SupportingDocument
            .where(invoice_version_id: source_invoice_version_id)
            .includes(
              :supporting_document_located_fields,
              :supporting_document_visual_findings
            )
            .order(:created_at, :id)
            .to_a

        docs.each do |source_doc|
          new_doc =
            ::Claims::SupportingDocument.create!(
              source_doc
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => new_invoice_version_id,
                  "created_at" => now,
                  "updated_at" => now
                )
            )
          clone_supporting_document_children!(
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
    end
  end
end
