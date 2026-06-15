# frozen_string_literal: true

# ============================================================
# SECTION 00 — FILE OVERVIEW
# PURPOSE:
# - Single place to map Document Intelligence (DI) output into
#   claims.invoice_versions "first class fields"
# - Keep Sidekiq job perform() tiny + orchestration-only
# ============================================================

module Claims
  module InvoiceVersions
    class ApplyDiResult
      # ============================================================
      # SECTION 01 — PUBLIC ENTRYPOINT
      # PURPOSE:
      # - Call with: ApplyDiResult.call(invoice_version_id:, di_json:)
      # - Returns a result hash so job/controller can show debug output
      # ============================================================

      def self.call(invoice_version_id:, di_json:)
        new(invoice_version_id: invoice_version_id, di_json: di_json).call
      end

      # ============================================================
      # SECTION 02 — INIT
      # ============================================================

      def initialize(invoice_version_id:, di_json:)
        @invoice_version_id = invoice_version_id
        @di_json = di_json
      end

      # ============================================================
      # SECTION 03 — MAIN
      # ============================================================

      def call
        # 3.0.1 — Load record
        iv = Claims::InvoiceVersion.find(@invoice_version_id)
        # 3.0.1.10 — LOG: confirm service is running + which columns exist
        Rails.logger.info(
          "[ApplyDiResult] 3.0.1 invoice_version_id=#{iv.id} has_di_raw_json=#{iv.has_attribute?(:di_raw_json)} has_di_completed_at=#{iv.has_attribute?(:di_completed_at)}"
        )

        # 3.0.2 — Build attrs hash for first-class fields
        attrs = build_invoice_version_attrs(@di_json)

        # 3.0.3 — Persist in one transaction (expand later to include lineitems)
        Claims::InvoiceVersion.transaction do
          # 3.0.3.1 — Store raw DI result too (if you have a column for it)
          # NOTE: adjust column name if yours differs
          attrs[:di_raw_json] = @di_json if iv.has_attribute?(:di_raw_json)

          # 3.0.3.2 — Status / timestamps (optional)
          attrs[:di_completed_at] = Time.current if iv.has_attribute?(
            :di_completed_at
          )

          # 3.0.3.20 — LOG: what columns we are about to write
          Rails.logger.info(
            "[ApplyDiResult] 3.0.3 writing_cols=#{attrs.compact.keys.sort.inspect}"
          )

          attrs[:di_page_map] = build_di_page_map(
            @di_json
          ) if iv.has_attribute?(:di_page_map)

          # 3.0.3.3 — Update invoice_version
          iv.update!(attrs.compact)
        end

        # 3.0.4 — Return shape for debugging / run output panel
        {
          ok: true,
          invoice_version_id: iv.id,
          updated_columns: attrs.compact.keys.map(&:to_s).sort
        }
      rescue => e
        {
          ok: false,
          invoice_version_id: @invoice_version_id,
          error: e.message,
          error_class: e.class.name
        }
      end

      private

      # ============================================================
      # SECTION 04 — MAPPING: DI JSON -> FIRST CLASS FIELDS
      # PURPOSE:
      # - This is the ONLY place where “DI field -> DB column” lives
      # - Start small, then expand as needed
      # ============================================================
      # SECTION 04 — MAPPING: DI JSON -> FIRST CLASS FIELDS
      def build_invoice_version_attrs(di_json)
        fields = extract_fields(di_json)
        if fields.blank?
          raise "DI fields empty. Keys at top: #{di_json.keys.inspect}"
        end

        {
          # InvoiceId
          di_ocr_invoice_id: text_field(fields, "InvoiceId"),
          di_ocr_invoice_id_page: page_field(fields, "InvoiceId"),
          di_ocr_invoice_id_polygon: polygon_field(fields, "InvoiceId"),
          # InvoiceDate
          di_ocr_invoice_date: date_field(fields, "InvoiceDate"),
          di_ocr_invoice_date_page: page_field(fields, "InvoiceDate"),
          di_ocr_invoice_date_polygon: polygon_field(fields, "InvoiceDate"),
          # VendorName
          di_ocr_vendor_name: text_field(fields, "VendorName"),
          di_ocr_vendor_name_page: page_field(fields, "VendorName"),
          di_ocr_vendor_name_polygon: polygon_field(fields, "VendorName"),
          # VendorAddress
          di_ocr_vendor_address: text_field(fields, "VendorAddress"),
          di_ocr_vendor_address_page: page_field(fields, "VendorAddress"),
          di_ocr_vendor_address_polygon: polygon_field(fields, "VendorAddress"),
          # CustomerName
          di_ocr_customer_name: text_field(fields, "CustomerName"),
          di_ocr_customer_name_page: page_field(fields, "CustomerName"),
          di_ocr_customer_name_polygon: polygon_field(fields, "CustomerName"),
          # CustomerAddress
          di_ocr_customer_address: text_field(fields, "CustomerAddress"),
          di_ocr_customer_address_page: page_field(fields, "CustomerAddress"),
          di_ocr_customer_address_polygon:
            polygon_field(fields, "CustomerAddress"),
          # CustomerAddressRecipient
          di_ocr_customer_address_recipient:
            text_field(fields, "CustomerAddressRecipient"),
          di_ocr_customer_address_recipient_page:
            page_field(fields, "CustomerAddressRecipient"),
          di_ocr_customer_address_recipient_polygon:
            polygon_field(fields, "CustomerAddressRecipient"),
          # ServiceAddress
          di_ocr_service_address: text_field(fields, "ServiceAddress"),
          di_ocr_service_address_page: page_field(fields, "ServiceAddress"),
          di_ocr_service_address_polygon:
            polygon_field(fields, "ServiceAddress"),
          # ServiceAddressRecipient
          di_ocr_service_address_recipient:
            text_field(fields, "ServiceAddressRecipient"),
          di_ocr_service_address_recipient_page:
            page_field(fields, "ServiceAddressRecipient"),
          di_ocr_service_address_recipient_polygon:
            polygon_field(fields, "ServiceAddressRecipient"),
          # BillingAddress
          di_ocr_billing_address: text_field(fields, "BillingAddress"),
          di_ocr_billing_address_page: page_field(fields, "BillingAddress"),
          di_ocr_billing_address_polygon:
            polygon_field(fields, "BillingAddress"),
          # BillingAddressRecipient
          di_ocr_billing_address_recipient:
            text_field(fields, "BillingAddressRecipient"),
          di_ocr_billing_address_recipient_page:
            page_field(fields, "BillingAddressRecipient"),
          di_ocr_billing_address_recipient_polygon:
            polygon_field(fields, "BillingAddressRecipient"),
          # SubTotal
          di_ocr_sub_total: number_field(fields, "SubTotal"),
          di_ocr_sub_total_page: page_field(fields, "SubTotal"),
          di_ocr_sub_total_polygon: polygon_field(fields, "SubTotal"),
          # TotalTax
          di_ocr_total_tax: number_field(fields, "TotalTax"),
          di_ocr_total_tax_page: page_field(fields, "TotalTax"),
          di_ocr_total_tax_polygon: polygon_field(fields, "TotalTax"),
          # InvoiceTotal
          di_ocr_invoice_total: number_field(fields, "InvoiceTotal"),
          di_ocr_invoice_total_page: page_field(fields, "InvoiceTotal"),
          di_ocr_invoice_total_polygon: polygon_field(fields, "InvoiceTotal"),
          # AmountDue
          di_ocr_amount_due: number_field(fields, "AmountDue"),
          di_ocr_amount_due_page: page_field(fields, "AmountDue"),
          di_ocr_amount_due_polygon: polygon_field(fields, "AmountDue")
        }
      end

      # ============================================================
      # SECTION 05 — DI JSON HELPERS
      # PURPOSE:
      # - Deal with DI schema variance without polluting mapping code
      # ============================================================

      def extract_fields(di_json)
        # 5.0.1 — Typical Azure DI prebuilt-invoice schema
        docs =
          (
            if di_json.is_a?(Hash)
              (di_json["documents"] || di_json[:documents])
            else
              nil
            end
          )
        doc0 = docs.is_a?(Array) ? docs[0] : nil
        fields = doc0.is_a?(Hash) ? (doc0["fields"] || doc0[:fields]) : nil

        return fields if fields.is_a?(Hash)

        # 5.0.2 — fallback: some wrappers nest under analyzeResult -> documents
        analyze = di_json["analyzeResult"] || di_json[:analyzeResult]
        docs2 =
          (
            if analyze.is_a?(Hash)
              (analyze["documents"] || analyze[:documents])
            else
              nil
            end
          )
        doc2 = docs2.is_a?(Array) ? docs2[0] : nil
        fields2 = doc2.is_a?(Hash) ? (doc2["fields"] || doc2[:fields]) : nil

        fields2.is_a?(Hash) ? fields2 : {}
      end

      def build_di_page_map(di_json)
        # Expected shape: di_json["pages"] = [{ "pageNumber": 1, "width": 8.5, "height": 11, "unit": "inch" }, ...]
        pages = di_json["pages"] || di_json[:pages]
        return nil unless pages.is_a?(Array)

        pages
          .map do |p|
            next unless p.is_a?(Hash)
            {
              "pageNumber" => p["pageNumber"] || p[:pageNumber],
              "width" => p["width"] || p[:width],
              "height" => p["height"] || p[:height],
              "unit" => p["unit"] || p[:unit]
            }.compact
          end
          .compact
      end

      # ============================================================
      # SECTION 06 — FIELD EXTRACTORS
      # PURPOSE:
      # - Each handles common DI value shapes:
      #   - { "content": "...", "valueString": "...", "valueDate": "...", "valueCurrency": { "amount": ... } }
      # ============================================================

      def text_field(fields, key)
        f = fields[key] || fields[key.to_sym]
        return nil unless f.is_a?(Hash)

        # 6.0.1 — Prefer valueString then content
        v = f["valueString"] || f[:valueString] || f["content"] || f[:content]
        v.is_a?(String) ? v.strip : (v.nil? ? nil : v.to_s)
      end

      def date_field(fields, key)
        f = fields[key] || fields[key.to_sym]
        return nil unless f.is_a?(Hash)

        # 6.0.2 — DI often gives valueDate as ISO string
        raw = f["valueDate"] || f[:valueDate] || f["content"] || f[:content]
        return nil if raw.nil?

        # Attempt parse
        begin
          Date.parse(raw.to_s)
        rescue StandardError
          nil
        end
      end

      # ============================================================
      # SECTION 06.10 — REGION HELPERS (PAGE + POLYGON)
      # PURPOSE:
      # - Reads: fields[key]["boundingRegions"][0]["pageNumber"/"polygon"]
      # ============================================================

      def page_field(fields, key)
        f = fields[key]
        return nil unless f.is_a?(Hash)

        br0 = f["boundingRegions"].is_a?(Array) ? f["boundingRegions"][0] : nil
        return nil unless br0.is_a?(Hash)

        br0["pageNumber"]
      end

      def polygon_field(fields, key)
        f = fields[key]
        return nil unless f.is_a?(Hash)

        br0 = f["boundingRegions"].is_a?(Array) ? f["boundingRegions"][0] : nil
        return nil unless br0.is_a?(Hash)

        br0["polygon"]
      end

      def page_field(fields, key)
        f = fields[key] || fields[key.to_sym]
        return nil unless f.is_a?(Hash)

        br0 = f["boundingRegions"]&.first || f[:boundingRegions]&.first
        return nil unless br0.is_a?(Hash)

        n = br0["pageNumber"] || br0[:pageNumber]
        n.nil? ? nil : n.to_i
      end

      def polygon_field(fields, key)
        f = fields[key] || fields[key.to_sym]
        return nil unless f.is_a?(Hash)

        br0 = f["boundingRegions"]&.first || f[:boundingRegions]&.first
        return nil unless br0.is_a?(Hash)

        poly = br0["polygon"] || br0[:polygon]
        return nil unless poly.is_a?(Array)

        poly.map { |x| x.nil? ? nil : x.to_f } # ensures jsonb numbers, not strings
      end

      def number_field(fields, key)
        f = fields[key] || fields[key.to_sym]
        return nil unless f.is_a?(Hash)

        # 6.0.3 — valueNumber OR valueCurrency.amount OR content
        if f.key?("valueNumber") || f.key?(:valueNumber)
          return f["valueNumber"] || f[:valueNumber]
        end

        vc = f["valueCurrency"] || f[:valueCurrency]
        if vc.is_a?(Hash)
          amt = vc["amount"] || vc[:amount]
          return amt if !amt.nil?
        end

        raw = f["content"] || f[:content]
        return nil if raw.nil?

        # best-effort numeric parse
        cleaned = raw.to_s.gsub(/[^\d\.\-]/, "")
        return nil if cleaned.empty?

        begin
          BigDecimal(cleaned)
        rescue StandardError
          nil
        end
      end
    end
  end
end
