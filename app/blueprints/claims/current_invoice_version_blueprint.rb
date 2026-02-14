# app/blueprints/claims/current_invoice_version_blueprint.rb
class Claims::CurrentInvoiceVersionBlueprint < Blueprinter::Base
  identifier :id

  view :read_screen do
    # ---- identifiers / linkage ----
    fields :session_id, :invoice_id, :invoice_status,
           :id, :invoice_versionno

    # ---- storage pointer ----
    fields :storage_provider, :storage_key, :original_filename,
           :content_type, :byte_size, :sha256

    # ---- DI header fields (first-class) ----
    fields :di_page_map, :di_ocr_invoice_id, :di_ocr_invoice_id_page, :di_ocr_invoice_id_polygon,
           :di_ocr_invoice_date, :di_ocr_invoice_date_page, :di_ocr_invoice_date_polygon,
           :di_ocr_vendor_name, :di_ocr_vendor_name_page, :di_ocr_vendor_name_polygon,
           :di_ocr_vendor_address, :di_ocr_vendor_address_page, :di_ocr_vendor_address_polygon,
           :di_ocr_customer_name, :di_ocr_customer_name_page, :di_ocr_customer_name_polygon,
           :di_ocr_billing_address, :di_ocr_billing_address_page, :di_ocr_billing_address_polygon,
           :di_ocr_sub_total, :di_ocr_sub_total_page, :di_ocr_sub_total_polygon,
           :di_ocr_total_tax, :di_ocr_total_tax_page, :di_ocr_total_tax_polygon,
           :di_ocr_invoice_total, :di_ocr_invoice_total_page, :di_ocr_invoice_total_polygon,
           :di_ocr_amount_due, :di_ocr_amount_due_page, :di_ocr_amount_due_polygon

    # ---- timestamps ----
    fields :created_at, :updated_at
  end
end
