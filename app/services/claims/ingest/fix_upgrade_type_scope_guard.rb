# frozen_string_literal: true

module Claims
  module Ingest
    class FixUpgradeTypeScopeGuard
      FAILURE_STATUS = "package_needs_correction"
      FAILURE_SUBTYPE = "package_replacement_upgrade_types_changed"
      ERROR_CODE = "fix_upgrade_types_changed"

      Result = Struct.new(:changed, :payload, keyword_init: true)

      def self.call(
        ingest_run:,
        replacement_document: nil,
        replacement_invoice_version_id: nil
      )
        new(
          ingest_run: ingest_run,
          replacement_document: replacement_document,
          replacement_invoice_version_id: replacement_invoice_version_id
        ).call
      end

      def initialize(
        ingest_run:,
        replacement_document:,
        replacement_invoice_version_id:
      )
        @ingest_run = ingest_run
        @replacement_document = replacement_document
        @replacement_invoice_version_id = replacement_invoice_version_id
      end

      def call
        source = source_invoice_version
        return Result.new(changed: false, payload: nil) if source.blank?

        current_types = persisted_upgrade_types(source.id)
        return Result.new(changed: false, payload: nil) if current_types.empty?

        replacement_types = replacement_upgrade_types(current_types)
        added_keys = replacement_types.keys - current_types.keys
        removed_keys = current_types.keys - replacement_types.keys
        if added_keys.empty? && removed_keys.empty?
          return Result.new(changed: false, payload: nil)
        end

        payload = {
          code: ERROR_CODE,
          level: "error",
          message: "Replacement invoice changed the claimed upgrade types.",
          source_invoice_version_id: source.id,
          source_invoice_versionno: source.invoice_versionno,
          replacement_filename: replacement_filename,
          current_upgrade_types: current_types.values,
          replacement_upgrade_types: replacement_types.values,
          added_upgrade_types: added_keys.map { |key| replacement_types[key] },
          removed_upgrade_types: removed_keys.map { |key| current_types[key] }
        }

        reject_candidate!(source: source, payload: payload)
        Result.new(changed: true, payload: payload)
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

      def source_invoice_version
        source_id = upload_context["source_invoice_version_id"].presence
        source = ::Claims::InvoiceVersion.find_by(id: source_id)
        return source if source.present?
        return nil if @replacement_invoice_version_id.blank?

        replacement =
          ::Claims::InvoiceVersion.find(@replacement_invoice_version_id)
        ::Claims::InvoiceVersion
          .where(invoice_id: replacement.invoice_id)
          .where.not(id: replacement.id)
          .where("invoice_versionno < ?", replacement.invoice_versionno)
          .order(invoice_versionno: :desc, updated_at: :desc, id: :desc)
          .first
      end

      def reused_document?
        return false if @replacement_document.blank?

        @replacement_document.document_kind_reason.to_s.start_with?(
          "Cloned from prior"
        )
      end

      def replacement_upgrade_types(current_types)
        if @replacement_invoice_version_id.present?
          return persisted_upgrade_types(@replacement_invoice_version_id)
        end
        return current_types if reused_document?

        payload = @replacement_document.classifier_raw_json
        rows =
          if payload.is_a?(Hash)
            payload["detected_upgrade_types"] ||
              payload[:detected_upgrade_types]
          end
        keys =
          Array(rows)
            .filter_map do |row|
              next unless row.respond_to?(:[])

              key =
                (row["upgrade_type_key"] || row[:upgrade_type_key]).to_s.strip
              key.presence unless key == "common"
            end
            .uniq
        configured_types(keys)
      end

      def persisted_upgrade_types(invoice_version_id)
        ::Claims::InvoiceVersionUpgradeType
          .joins(
            "INNER JOIN claims.invoice_upgrade_types iut " \
              "ON iut.id = " \
              "claims.invoice_version_upgrade_types.invoice_upgrade_type_id"
          )
          .where(
            invoice_version_id: invoice_version_id,
            source_engine: "classifier"
          )
          .where("iut.upgrade_type_key <> ?", "common")
          .pluck("iut.upgrade_type_key", "iut.description")
          .to_h { |key, description| [key, type_payload(key, description)] }
      end

      def configured_types(keys)
        ::Claims::InvoiceUpgradeType
          .where(upgrade_type_key: keys)
          .pluck(:upgrade_type_key, :description)
          .to_h { |key, description| [key, type_payload(key, description)] }
      end

      def type_payload(key, description)
        {
          upgrade_type_key: key,
          description: description.presence || key.to_s.humanize
        }
      end

      def replacement_filename
        return @replacement_document.original_filename if @replacement_document

        ::Claims::InvoiceVersion.where(
          id: @replacement_invoice_version_id
        ).pick(:original_filename)
      end

      def reject_candidate!(source:, payload:)
        now = Time.current
        ActiveRecord::Base.transaction do
          @ingest_run.update!(
            resolved_invoice_version_id: nil,
            status: "failed",
            completed_files: 0,
            failed_files: 1,
            failure_status: FAILURE_STATUS,
            failure_status_subtype: FAILURE_SUBTYPE,
            pipeline_error_code: ERROR_CODE,
            pipeline_error_description:
              "Replacement invoice changed the claimed upgrade types.",
            messages: run_messages + [payload.deep_stringify_keys],
            completed_at: now,
            updated_at: now
          )

          if @replacement_invoice_version_id.present?
            replacement =
              ::Claims::InvoiceVersion.find(@replacement_invoice_version_id)
            ::Claims::Lineitem.where(
              invoice_version_id: replacement.id
            ).delete_all
            replacement.delete
            restore_prior_invoice_status!(source: source, now: now)
          end
        end
      end

      def restore_prior_invoice_status!(source:, now:)
        context = upload_context
        source.invoice.set_workflow_status_columns!(
          context["prior_invoice_status"].presence || "genai_complete",
          status_subtype: context["prior_invoice_status_subtype"].presence,
          invoice_version_id: source.id,
          now: now
        )
      end
    end
  end
end
