# frozen_string_literal: true

module Claims
  module InvoiceVersionUpgradeTypes
    class ApplyClassifierResult
      def self.call(invoice_version_id:, classifier_payload:)
        new(
          invoice_version_id: invoice_version_id,
          classifier_payload: classifier_payload
        ).call
      end

      def initialize(invoice_version_id:, classifier_payload:)
        @invoice_version_id = invoice_version_id
        @classifier_payload = classifier_payload
      end

      def call
        detected = extract_detected_upgrade_types
        lineitem_mappings = extract_lineitem_mappings
        now = Time.current

        rows =
          detected.filter_map do |row|
            upgrade_type = upgrade_type_for(row)
            next unless upgrade_type

            {
              invoice_version_id: @invoice_version_id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "classifier",
              call_status: "classified",
              confidence:
                coerce_confidence(row["confidence"] || row[:confidence]),
              raw_json: row,
              created_at: now,
              updated_at: now
            }
          end

        Claims::InvoiceVersionUpgradeType.transaction do
          Claims::InvoiceVersionUpgradeType.where(
            invoice_version_id: @invoice_version_id,
            source_engine: "classifier"
          ).delete_all

          Claims::InvoiceVersionUpgradeType.insert_all!(rows) if rows.any?
          stamp_lineitems!(
            detected: detected,
            lineitem_mappings: lineitem_mappings,
            now: now
          )
        end

        { ok: true, replaced: rows.size }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def extract_detected_upgrade_types
        return [] unless @classifier_payload.is_a?(Hash)

        rows =
          @classifier_payload["detected_upgrade_types"] ||
            @classifier_payload[:detected_upgrade_types]
        rows.is_a?(Array) ? rows : []
      end

      def extract_lineitem_mappings
        return [] unless @classifier_payload.is_a?(Hash)

        rows =
          @classifier_payload["lineitem_mappings"] ||
            @classifier_payload[:lineitem_mappings]
        rows.is_a?(Array) ? rows : []
      end

      def upgrade_type_for(row)
        key = (row["upgrade_type_key"] || row[:upgrade_type_key]).to_s.strip
        return nil if key.empty? || key == "common"

        Claims::InvoiceUpgradeType.find_by(upgrade_type_key: key)
      end

      def coerce_confidence(value)
        n =
          begin
            Integer(value || 0)
          rescue StandardError
            0
          end
        [[n, 0].max, 100].min
      end

      def stamp_lineitems!(detected:, lineitem_mappings:, now:)
        lineitems =
          Claims::Lineitem.where(invoice_version_id: @invoice_version_id).to_a
        return if lineitems.empty?

        common_type =
          Claims::InvoiceUpgradeType.find_by!(upgrade_type_key: "common")

        Claims::Lineitem.where(
          invoice_version_id: @invoice_version_id
        ).update_all(invoice_upgrade_type_id: common_type.id, updated_at: now)

        assignments = {}

        lineitem_mappings.each do |row|
          upgrade_type = upgrade_type_for(row)
          next unless upgrade_type

          matching_lineitems(lineitems: lineitems, row: row).each do |lineitem|
            assignments[lineitem.id] = upgrade_type.id
          end
        end

        detected.each do |row|
          upgrade_type = upgrade_type_for(row)
          next unless upgrade_type

          matching_lineitems(lineitems: lineitems, row: row).each do |lineitem|
            assignments[lineitem.id] ||= upgrade_type.id
          end
        end

        assignments
          .group_by { |_lineitem_id, upgrade_type_id| upgrade_type_id }
          .each do |upgrade_type_id, pairs|
            ids = pairs.map(&:first)
            Claims::Lineitem.where(id: ids).update_all(
              invoice_upgrade_type_id: upgrade_type_id,
              updated_at: now
            )
          end
      end

      def matching_lineitems(lineitems:, row:)
        seqno = row["lineitem_seqno"] || row[:lineitem_seqno]
        if seqno.present?
          seqno_i =
            begin
              Integer(seqno)
            rescue StandardError
              nil
            end
          if seqno_i
            return lineitems.select { |li| li.lineitem_seqno.to_i == seqno_i }
          end
        end

        evidence = (row["evidence_text"] || row[:evidence_text]).to_s
        return [] if evidence.strip.empty?

        evidence_norm = normalize_text(evidence)
        lineitems.select do |lineitem|
          description_norm = normalize_text(lineitem.ocr_description)
          next false if description_norm.empty?

          description_norm == evidence_norm ||
            description_norm.include?(evidence_norm) ||
            evidence_norm.include?(description_norm)
        end
      end

      def normalize_text(value)
        value.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
      end
    end
  end
end
