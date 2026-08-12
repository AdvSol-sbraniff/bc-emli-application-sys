# frozen_string_literal: true

module Claims
  module Ingest
    class PromoteFixPackage
      def self.call(ingest_run:, resolved_document:)
        new(ingest_run: ingest_run, resolved_document: resolved_document).call
      end

      def initialize(ingest_run:, resolved_document:)
        @ingest_run = ingest_run
        @resolved_document = resolved_document
      end

      def call
        existing_id = @ingest_run.reload.resolved_invoice_version_id
        return existing_id if existing_id.present?

        ActiveRecord::Base.transaction do
          invoice = ::Claims::Invoice.lock.find(invoice_id)
          @ingest_run.lock!

          existing_id = @ingest_run.resolved_invoice_version_id
          return existing_id if existing_id.present?

          source = source_invoice_version!(invoice)
          replacement =
            if reused_document?(@resolved_document)
              clone_invoice_version!(
                source: source,
                next_versionno: next_invoice_versionno(invoice.id)
              )
            else
              create_replacement_invoice_version!(
                invoice: invoice,
                next_versionno: next_invoice_versionno(invoice.id)
              )
            end

          clone_retained_supporting_documents!(
            source: source,
            replacement: replacement
          )
          bind_staged_documents!(invoice: invoice, replacement: replacement)
          @ingest_run.update!(
            resolved_invoice_version_id: replacement.id,
            updated_at: Time.current
          )

          replacement.id
        end
      end

      private

      def run_messages
        Array(@ingest_run.messages).map do |message|
          message.respond_to?(:to_h) ? message.to_h.stringify_keys : {}
        end
      end

      def upload_context
        run_messages.reverse.find do |message|
          message["code"] == "fix_upload_context"
        end || {}
      end

      def invoice_id
        @resolved_document.resolved_invoice_id.presence ||
          @resolved_document.invoice_id.presence ||
          upload_context["invoice_id"].presence ||
          raise("Fix upload is missing its invoice context.")
      end

      def source_invoice_version!(invoice)
        source_id = upload_context["source_invoice_version_id"].presence
        source =
          ::Claims::InvoiceVersion.find_by(
            id: source_id,
            invoice_id: invoice.id
          )
        return source if source.present?

        raise "The source invoice version for this fix is no longer available."
      end

      def reused_document?(document)
        document.document_kind_reason.to_s.start_with?("Cloned from prior")
      end

      def clone_invoice_version!(source:, next_versionno:)
        now = Time.current
        clone = source.dup
        clone.invoice_versionno = next_versionno
        clone.genai_raw_json = nil
        clone.genai_result = nil
        clone.ahri_product_id = nil
        clone.neea_product_id = nil
        clone.awhp_product_id = nil
        clone.ohpa_product_id = nil
        clone.herv_product_id = nil
        clone.vent_fan_product_id = nil
        clone.created_at = now
        clone.updated_at = now
        clone.save!

        clone_invoice_children!(source: source, replacement: clone, now: now)
        clone
      end

      def create_replacement_invoice_version!(invoice:, next_versionno:)
        now = Time.current
        replacement =
          ::Claims::InvoiceVersion.create!(
            invoice_id: invoice.id,
            invoice_versionno: next_versionno,
            storage_provider: @resolved_document.storage_provider,
            storage_key: @resolved_document.storage_key,
            original_filename: @resolved_document.original_filename,
            content_type: @resolved_document.content_type,
            byte_size: @resolved_document.byte_size,
            sha256: @resolved_document.sha256,
            created_at: now,
            updated_at: now
          )
        apply_classifier_evidence!(replacement)
        replacement
      end

      def apply_classifier_evidence!(replacement)
        result =
          ::Claims::InvoiceVersionUpgradeTypes::ApplyClassifierResult.call(
            invoice_version_id: replacement.id,
            classifier_payload: @resolved_document.classifier_raw_json
          )
        unless result[:ok] || result["ok"]
          raise "ApplyClassifierResult failed: #{result.inspect}"
        end

        attributes =
          ::Claims::PersonalInformation::NormalizeClassifierResult.call(
            classifier_payload: @resolved_document.classifier_raw_json || {}
          )
        if attributes.any?
          replacement.update!(attributes.merge(updated_at: Time.current))
        end
      end

      def clone_invoice_children!(source:, replacement:, now:)
        lineitems =
          ::Claims::Lineitem
            .where(invoice_version_id: source.id)
            .map do |row|
              row
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => replacement.id,
                  "created_at" => now,
                  "updated_at" => now
                )
            end
        ::Claims::Lineitem.insert_all!(lineitems) if lineitems.any?

        located_fields =
          ::Claims::InvoiceVersionLocatedField
            .where(invoice_version_id: source.id, source_engine: "classifier")
            .map do |row|
              row
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => replacement.id,
                  "created_at" => now,
                  "updated_at" => now
                )
            end
        if located_fields.any?
          ::Claims::InvoiceVersionLocatedField.insert_all!(located_fields)
        end

        upgrade_types =
          ::Claims::InvoiceVersionUpgradeType
            .where(invoice_version_id: source.id, source_engine: "classifier")
            .map do |row|
              row
                .attributes
                .except("id", "invoice_version_id", "created_at", "updated_at")
                .merge(
                  "invoice_version_id" => replacement.id,
                  "created_at" => now,
                  "updated_at" => now
                )
            end
        if upgrade_types.any?
          ::Claims::InvoiceVersionUpgradeType.insert_all!(upgrade_types)
        end
      end

      def clone_retained_supporting_documents!(source:, replacement:)
        ids =
          Array(upload_context["clone_supporting_document_ids"]).map(
            &:to_s
          ).uniq
        return if ids.empty?

        source_documents =
          ::Claims::SupportingDocument
            .where(id: ids, invoice_version_id: source.id)
            .includes(
              :supporting_document_located_fields,
              :supporting_document_visual_findings
            )
            .order(:created_at, :id)
            .to_a
        missing_ids = ids - source_documents.map { |document| document.id.to_s }
        if missing_ids.any?
          raise "One or more retained supporting documents no longer belong to the source invoice version."
        end

        source_documents.each do |source_document|
          clone_supporting_document!(
            source_document: source_document,
            replacement: replacement
          )
        end
      end

      def clone_supporting_document!(source_document:, replacement:)
        now = Time.current
        clone =
          ::Claims::SupportingDocument.create!(
            source_document
              .attributes
              .except("id", "invoice_version_id", "created_at", "updated_at")
              .merge(
                "invoice_version_id" => replacement.id,
                "created_at" => now,
                "updated_at" => now
              )
          )

        located_fields =
          source_document.supporting_document_located_fields.map do |row|
            row
              .attributes
              .except(
                "id",
                "supporting_document_id",
                "created_at",
                "updated_at"
              )
              .merge(
                "supporting_document_id" => clone.id,
                "created_at" => now,
                "updated_at" => now
              )
          end
        if located_fields.any?
          ::Claims::SupportingDocumentLocatedField.insert_all!(located_fields)
        end

        findings =
          source_document.supporting_document_visual_findings.map do |row|
            row
              .attributes
              .except(
                "id",
                "supporting_document_id",
                "created_at",
                "updated_at"
              )
              .merge(
                "supporting_document_id" => clone.id,
                "created_at" => now,
                "updated_at" => now
              )
          end
        if findings.any?
          ::Claims::SupportingDocumentVisualFinding.insert_all!(findings)
        end

        staged_document =
          ::Claims::IngestDocument.find_by(
            ingest_run_id: @ingest_run.id,
            storage_key: source_document.storage_key,
            document_kind: "supporting_document"
          )
        staged_document&.update!(
          resolved_invoice_id: replacement.invoice_id,
          resolved_invoice_version_id: replacement.id,
          promoted_supporting_document_id: clone.id,
          updated_at: now
        )
      end

      def bind_staged_documents!(invoice:, replacement:)
        now = Time.current
        ::Claims::IngestDocument.where(
          ingest_run_id: @ingest_run.id
        ).update_all(
          resolved_invoice_id: invoice.id,
          resolved_invoice_version_id: replacement.id,
          updated_at: now
        )
        @resolved_document.reload
      end

      def next_invoice_versionno(invoice_id)
        (
          ::Claims::InvoiceVersion.where(invoice_id: invoice_id).maximum(
            :invoice_versionno
          ) || 0
        ) + 1
      end
    end
  end
end
