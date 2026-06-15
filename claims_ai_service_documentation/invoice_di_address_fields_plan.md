# Invoice DI Address Fields Plan

## Goal

Persist the address fields that Azure Document Intelligence can already detect on invoice PDFs, instead of treating `BillingAddress` as the only customer-side invoice address. Then show those fields in the admin PDF viewer with the same clickable polygon behaviour as the existing first-class invoice fields.

## Current State

- `claims.invoice_versions` stores `di_ocr_vendor_address` and `di_ocr_billing_address`.
- `claims.invoice_versions` stores `di_ocr_customer_name`, but not `di_ocr_customer_address`.
- `Claims::InvoiceVersions::ApplyDiResult` maps Azure DI `BillingAddress` into `di_ocr_billing_address`.
- Azure DI may also return invoice address concepts such as `CustomerAddress`, `ServiceAddress`, `ShippingAddress`, and address-recipient fields.
- The admin PDF viewer currently displays the existing first-class invoice fields inside the Invoice accordion.
- The `first_class_invoice_fields_present` code rule currently treats address as part of baseline invoice completeness.

## Proposed Data Model Changes

Add first-class invoice-version columns for customer/site address evidence, each with the same value/page/polygon pattern already used by the current invoice fields.

Recommended columns:

- `di_ocr_customer_address`
- `di_ocr_customer_address_page`
- `di_ocr_customer_address_polygon`
- `di_ocr_customer_address_recipient`
- `di_ocr_customer_address_recipient_page`
- `di_ocr_customer_address_recipient_polygon`
- `di_ocr_service_address`
- `di_ocr_service_address_page`
- `di_ocr_service_address_polygon`
- `di_ocr_service_address_recipient`
- `di_ocr_service_address_recipient_page`
- `di_ocr_service_address_recipient_polygon`
- `di_ocr_billing_address_recipient`
- `di_ocr_billing_address_recipient_page`
- `di_ocr_billing_address_recipient_polygon`

Optional later columns:

- `di_ocr_shipping_address`
- `di_ocr_shipping_address_page`
- `di_ocr_shipping_address_polygon`
- `di_ocr_shipping_address_recipient`
- `di_ocr_shipping_address_recipient_page`
- `di_ocr_shipping_address_recipient_polygon`
- `di_ocr_remittance_address`
- `di_ocr_remittance_address_page`
- `di_ocr_remittance_address_polygon`
- `di_ocr_remittance_address_recipient`
- `di_ocr_remittance_address_recipient_page`
- `di_ocr_remittance_address_recipient_polygon`
- `di_ocr_vendor_address_recipient`
- `di_ocr_vendor_address_recipient_page`
- `di_ocr_vendor_address_recipient_polygon`

The first implementation should focus on customer, service, and billing recipient fields. Shipping/remittance/vendor-recipient can wait unless the UI or rules need them.

## Pipeline Changes

1. Update the DDL and any schema-rebuild scripts to create the new columns.
2. Update `Claims::InvoiceVersions::ApplyDiResult` to map:
   - `CustomerAddress`
   - `CustomerAddressRecipient`
   - `ServiceAddress`
   - `ServiceAddressRecipient`
   - `BillingAddressRecipient`
3. Preserve raw DI JSON as-is, but do not rely on raw JSON for fields that admins need to see.
4. Update API blueprints/views so the admin PDF viewer receives the new fields.
5. Update any test seed data only where it helps local visual testing.

## Admin PDF Viewer Changes

Display the new address fields in the existing Invoice accordion.

Recommended display order:

1. Invoice number
2. Invoice date
3. Vendor name
4. Vendor address
5. Customer name
6. Customer address
7. Service address
8. Billing address
9. Billing address recipient
10. Subtotal
11. Total tax
12. Invoice total
13. Amount due

Only render address fields that have a value. This avoids clutter on invoices where DI only returns one address concept.

Each displayed address field should use the same click-to-highlight behaviour as the existing invoice fields:

- value text is shown in the accordion
- click switches the document viewer to the invoice PDF
- click navigates to the stored page
- click draws the stored polygon

## Rule Changes

Remove address checks from `first_class_invoice_fields_present`.

That rule should only verify fields that are universally needed for baseline invoice processing and are not semantically ambiguous:

- invoice number
- invoice date
- vendor name
- customer name
- subtotal
- total tax
- invoice total
- amount due

Vendor address and billing/customer/service address should not be part of this rule. Address extraction is valuable evidence, but Azure DI can validly classify the same visible address differently depending on invoice layout.

## Address Rule Recommendation

There does not appear to be a dedicated code rule for invoice customer/site/billing address completeness.

Recommended backlog rule:

- `invoice_address_evidence_present`

Suggested behaviour:

- Pass when at least one useful customer-side/site-side invoice address is present.
- Use `CustomerAddress`, `ServiceAddress`, or `BillingAddress` as acceptable evidence.
- Warn when none of those are present, because admins may need to inspect the invoice or supporting documents.
- Do not fail by default unless a specific program requirement makes invoice address mandatory.

This should be separate from `first_class_invoice_fields_present` so the baseline invoice completeness rule stays deterministic and the address rule can explain the address ambiguity clearly.

## Testing Plan

1. Rebuild local schema or apply a local migration for the new columns.
2. Re-run `test014` with an invoice where DI finds customer/service/billing address fields.
3. Confirm `claims.invoice_versions` has values, pages, and polygons populated for any returned address fields.
4. Confirm the admin PDF viewer shows the new fields in the Invoice accordion.
5. Confirm clicking each new field highlights the correct invoice PDF region.
6. Confirm `first_class_invoice_fields_present` no longer warns solely because an address field is missing.
7. If `invoice_address_evidence_present` is added, confirm it warns only when all customer/service/billing address evidence is absent.
