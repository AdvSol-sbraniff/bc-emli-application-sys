# frozen_string_literal: true

module Claims
  module Ingest
    class FixUpgradeTypeScopeGuard
      FAILURE_CATEGORY = "package_needs_correction"
      FAILURE_CODE = "package_replacement_upgrade_types_changed"
      ERROR_CODE = "fix_upgrade_types_changed"

      Result = Struct.new(:changed, :payload, keyword_init: true)

      def self.call(ingest_run:, replacement_document: nil)
        new(
          ingest_run: ingest_run,
          replacement_document: replacement_document
        ).call
      end

      def self.preview(ingest_run:)
        new(ingest_run: ingest_run, replacement_document: nil).preview
      end

      def initialize(ingest_run:, replacement_document:)
        @ingest_run = ingest_run
        @replacement_document = replacement_document
      end

      def call
        result = preview
        reject_replacement! if result.changed
        result
      end

      def preview
        source = context.source_invoice_version

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

        Result.new(changed: true, payload: payload)
      end

      private

      def context
        @context ||=
          ::Claims::Ingest::FixPackageContext.new(ingest_run: @ingest_run)
      end

      def replacement_document
        @replacement_document ||= context.replacement_invoice_document
      end

      def reused_document?
        replacement_document.document_kind_reason.to_s.start_with?(
          ::Claims::Ingest::FixPackageContext::CLONED_REASON_PREFIX
        )
      end

      def replacement_upgrade_types(current_types)
        return current_types if reused_document?

        payload = replacement_document.classifier_raw_json
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
          .where(invoice_version_id: invoice_version_id)
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
        replacement_document.original_filename
      end

      def reject_replacement!
        @ingest_run.update!(resolved_invoice_version_id: nil)
        ::Claims::Ingest::RunTransition.mark_failed!(
          run: @ingest_run,
          total_files: [@ingest_run.total_files.to_i, 1].max,
          failed_files: 1,
          failure_category: FAILURE_CATEGORY,
          failure_code: FAILURE_CODE,
          pipeline_error_code: ERROR_CODE,
          pipeline_error_description:
            "Replacement invoice changed the claimed upgrade types."
        )
      end
    end
  end
end
