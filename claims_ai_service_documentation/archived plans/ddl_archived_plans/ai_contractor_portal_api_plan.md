# AI Contractor Portal API Plan

Purpose: focused backend/API plan for the AI contractor invoice flow. The master map is `ai_contractor_portal_plan.md`.

Gate 0 update:

- Backend design must support a hybrid validator.
- GenAI is not the only rules executor.
- Add/plan a deterministic code-engine service that writes `claims.invoice_version_rulechecks` rows with `source_engine = 'code'`.
- Use GenAI for evidence location and fuzzy interpretation; use code for date/math/cap/threshold/DB-comparison checks.
- Do not redesign contractor APIs around a single all-powerful GenAI result.

## Principles

- Existing Node/GenAI calls are internal/trusted between Ruby and Node in the same OpenShift app.
- New contractor-facing Ruby endpoints need real authorization.
- Contractor endpoints must scope all data to the current user's contractor relationship.
- Contractor primary contacts and contractor employees/secretaries should follow legacy access behavior.
- Upload is not submit.
- Submit is invoice-level only.

## Contractor Endpoints

Likely endpoints:

- List AI invoices for current contractor.
- Create AI session.
- Upload one or more invoice PDFs.
- Read one invoice/latest version for contractor viewer.
- Get invoice PDF URL.
- Retry failed pipeline step.
- Submit invoice to admin.
- Upload fix +1 invoice version.
- Add supplement/supporting document.
- Delete/withdraw pre-submit invoice.

## Admin Endpoints

Likely endpoints:

- List/search AI invoices for admin grid.
- Assign invoice to admin.
- Move invoice to `in_review`.
- Move invoice to `approved_pending`.
- Move invoice to `approved_paid`.
- Move invoice to `ineligible`.
- Create/finalize revision requests.
- Read ruleset/admin metadata.

## Authorization

Contractor:

- Must be authenticated.
- Must be associated with the contractor/company that owns the invoice/session.
- Must not be suspended/deactivated if legacy flow blocks that user.
- Can delete only pre-submit AI invoices owned by their contractor.
- Can upload fix only when status permits contractor action.
- Can add supplements only when status permits contractor visibility/action.

Admin:

- Clone old role behavior for v1.
- `admin` and `admin_manager` can perform approve/revision/finalize style actions unless deeper code review says otherwise.
- System/admin menu visibility can differ from endpoint permission, but endpoint permission must still be enforced.

## Submit Blocker

Contractor submit should block if any tracked first-class OCR field is null on the latest invoice version.

Response shape should be plain and UI-friendly:

```json
{
  "ok": false,
  "error_code": "missing_required_invoice_fields",
  "message": "We cannot submit this invoice yet because some required information could not be found.",
  "missing_fields": [{ "field": "di_ocr_invoice_id", "label": "Invoice number" }]
}
```

Status remains `genai_complete`; no submit-blocked status for v1.

## Retry Rules

- Upload failure retries upload.
- OCR failure retries OCR and then GenAI if OCR succeeds.
- GenAI failure retries GenAI only.
- Retry should not redo successful prior steps pointlessly.

## Upload/Fix Rules

Initial invoice upload:

- PDF only.
- Every PDF creates one invoice and one invoice version.
- Version number starts at 1.

Fix +1:

- Creates a new invoice version.
- Automatically reruns OCR and GenAI.
- Uses same invoice and upgrade type.
- Stores the ruleset used on the invoice version.

## Supplement Rules

- Supplement means supporting document, not another invoice.
- Supplements do not trigger OCR/GenAI in v1.
- Allow common document/photo uploads.
- Preview what is easy to preview; otherwise allow download.

## V2/Future

- Invoice type autodetection can happen after OCR inside the GenAI response.
- V1 should not do this beyond documenting the path.
- Future API may classify first, then select a type-specific ruleset.
