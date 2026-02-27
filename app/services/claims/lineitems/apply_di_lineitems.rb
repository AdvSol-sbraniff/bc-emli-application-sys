# app/services/claims/lineitems/apply_di_lineitems.rb
# frozen_string_literal: true

module Claims
  module Lineitems
    class ApplyDiLineitems
      def self.call(invoice_version_id:, di_json:)
        new(invoice_version_id: invoice_version_id, di_json: di_json).call
      end

      def initialize(invoice_version_id:, di_json:)
        @invoice_version_id = invoice_version_id
        @di_json = di_json
      end

      def call
        items = @di_json.dig("documents", 0, "fields", "Items", "valueArray") || []
        return { ok: true, replaced: 0 } if !items.is_a?(Array) || items.empty?

        now = Time.current
        rows = items.each_with_index.map do |it, idx|
          build_row(it, seqno: idx + 1, now: now)
        end.compact

        return { ok: true, replaced: 0 } if rows.empty?

        Claims::Lineitem.transaction do
          Claims::Lineitem.where(invoice_version_id: @invoice_version_id).delete_all
          Claims::Lineitem.insert_all!(rows)
        end

        { ok: true, replaced: rows.size }
      rescue => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      def build_row(item, seqno:, now:)
        return nil unless item.is_a?(Hash)

        vo = item["valueObject"] || item[:valueObject]
        return nil unless vo.is_a?(Hash)

        desc = vo.dig("Description", "valueString")
        qty  = vo.dig("Quantity", "valueNumber")
        unit = vo.dig("UnitPrice", "valueCurrency", "amount")
        amt  = vo.dig("Amount", "valueCurrency", "amount")

        # polygons/pages: prefer each field’s own boundingRegions if present
        desc_br = first_br(vo["Description"])
        qty_br  = first_br(vo["Quantity"])
        unit_br = first_br(vo["UnitPrice"])
        amt_br  = first_br(vo["Amount"])

        {
          invoice_version_id: @invoice_version_id,
          lineitem_seqno: seqno,

          ocr_description: desc,
          ocr_description_page: desc_br&.dig("pageNumber"),
          ocr_description_polygon: desc_br&.dig("polygon"),

          ocr_quantity: qty.nil? ? nil : BigDecimal(qty.to_s),
          ocr_quantity_page: qty_br&.dig("pageNumber"),
          ocr_quantity_polygon: qty_br&.dig("polygon"),

          ocr_unit_price: unit.nil? ? nil : BigDecimal(unit.to_s),
          ocr_unit_price_page: unit_br&.dig("pageNumber"),
          ocr_unit_price_polygon: unit_br&.dig("polygon"),

          ocr_amount: amt.nil? ? nil : BigDecimal(amt.to_s),
          ocr_amount_page: amt_br&.dig("pageNumber"),
          ocr_amount_polygon: amt_br&.dig("polygon"),

          created_at: now,
          updated_at: now
        }
      end

      def first_br(field_hash)
        return nil unless field_hash.is_a?(Hash)
        br = field_hash["boundingRegions"]
        return nil unless br.is_a?(Array) && br.any?
        br.first
      end
    end
  end
end