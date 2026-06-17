# Contractor Upload Invoice Package Processing Experience Plan

## Goal

Replace the small message/status/table area on the contractor `Upload Invoice Package` screen with a polished processing experience:

- While the server is working, show a large animated circling-arrow graphic with the text `Preparing AI Advice`.
- Remove the current success/status message area that says things like `Upload started. We are checking your invoice package now.`
- Remove the `Uploaded package` helper text and invoice/status table from the contractor upload screen.
- Keep only the `Continue to Step 2: Pre-check` button, enabled only when the upload is ready for contractor pre-check.
- If processing fails, show a contractor-safe failure sentence based on whether the failure is technical or package-correction related.
- For contractor uploads only, delete half-baked invoice/evidence records created by failed upload attempts so the contractor portal does not accumulate junk.

## Current Behaviour

The current screen is `app/frontend/components/domains/contractor-upload-invoices/index.tsx`.

Today it:

- Stores transient upload messages in `submitOk`, `submitError`, `runError`, and `rowsError`.
- Displays a message box after upload, including `Upload started. We are checking your invoice package now.`
- Polls `/api/claims/contractor/ingest/runs/:ingest_run_id` and `/api/claims/contractor/ingest/runs/:ingest_run_id/invoices`.
- Shows an `Uploaded package` section with helper copy and a two-column table: invoice + status.
- Enables `Continue to Step 2: Pre-check` only when every returned invoice row is `genai_complete`.

The current backend creates a shell invoice early in `Claims::Ingest::CreateDraftBatch`. If package staging fails, that shell invoice is marked `package_needs_correction` or `technical_failure`, but the records are left behind.

## Desired Contractor UX

### Processing State

When an upload has started and the run is queued/running/in progress:

- Hide the table and old message box.
- Show a large, premium-looking animated processing graphic.
- The graphic should use a circular arrow or orbital ring motif, not a generic spinner.
- It should animate smoothly, with a subtle glow/gradient and intentional motion.
- Beneath the graphic show:

`Preparing AI Advice`

This should feel like “the server is thinking,” not like a browser loading indicator.

### Ready State

When the invoice status is ready for contractor pre-check:

- Hide the processing graphic.
- Enable `Continue to Step 2: Pre-check`.
- Do not show the old invoice/status table.
- Do not show the old helper text:
  - `When the invoice says With Contractor for Pre-check, continue to step 2.`
  - `Upload invoice PDFs first, then wait until checks are complete.`

### Failure State

When the upload fails:

- Hide the processing graphic.
- Show one clean contractor-facing sentence.
- Do not show raw technical status codes.
- Do not show the invoice/status table.
- Keep `Continue to Step 2: Pre-check` disabled.

For `technical_failure`, use wording in this shape:

`We could not prepare your AI advice right now. Please try uploading the same files again later.`

For `package_needs_correction`, use wording in this shape:

`We could not prepare your AI advice because the upload package needs a change: {non_technical_subtype_message}`

Example:

`We could not prepare your AI advice because the upload package needs a change: More than one invoice PDF was found. Upload exactly one invoice PDF.`

## DDL / Data Model Change

Create a DB-backed status subtype lookup table so the UI can display approved non-technical text without hardcoding every message in React.

Proposed table:

```sql
CREATE TABLE IF NOT EXISTS claims.invoice_status_subtypes (
  status text NOT NULL,
  status_subtype text NOT NULL,
  admin_label text NOT NULL,
  contractor_message text NOT NULL,
  retry_guidance text NULL,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_status_subtypes_pkey PRIMARY KEY (status, status_subtype),
  CONSTRAINT invoice_status_subtypes_status_chk CHECK (
    status IN ('package_needs_correction', 'technical_failure')
  )
);
```

Seed this table from the current subtype list in `Claims::Invoices::StatusSubtypes`.

Initial contractor-message policy:

- `package_needs_correction` messages explain what to change in the batch.
- `technical_failure` messages avoid blaming the contractor and tell them to retry later.
- Technical subtypes can still have distinct `admin_label` values for troubleshooting.

This table belongs in `2_create_schema.sql` and a new or existing `3_insert_*` seed file. Do not create an alter script.

## Backend API Changes

### 1. Expose Contractor-Friendly Failure Copy

Add backend serialization for failure presentation:

```json
{
  "status": "package_needs_correction",
  "status_subtype": "package_multiple_invoice_pdfs",
  "failure_message": "We could not prepare your AI advice because the upload package needs a change: More than one invoice PDF was found. Upload exactly one invoice PDF.",
  "retry_guidance": "Upload a revised package."
}
```

Apply this to:

- `GET /api/claims/contractor/ingest/runs/:ingest_run_id`
- `GET /api/claims/contractor/ingest/runs/:ingest_run_id/invoices`
- `POST /api/claims/contractor/invoices/upload_batch`

The React screen should not need to understand every subtype. It should consume a final friendly message from the API.

### 2. Centralize Subtype Lookup

Replace or wrap the current Ruby constant copy in `app/services/claims/invoices/status_subtypes.rb` with DB-backed lookup helpers:

- `valid?(status, subtype)`
- `normalize(status, subtype)`
- `contractor_message(status, subtype)`
- `admin_label(status, subtype)`

Keep an in-code fallback only for bootstrapping/test safety, but the intended source of truth should be `claims.invoice_status_subtypes`.

### 3. Cleanup Failed Contractor Upload Artifacts

For contractor upload only, delete half-baked records after a terminal failure is detected.

Records to remove:

- `claims.invoices` shell invoice and children.
- `claims.invoice_versions`.
- `claims.supporting_documents`.
- `claims.supporting_document_located_fields`.
- `claims.supporting_document_visual_findings`.
- `claims.invoice_version_located_fields`.
- `claims.invoice_version_rulechecks`.
- `claims.lineitems`.
- Any other invoice/version child records reachable from the invoice.

Important distinction:

- Contractor upload screen should clean failed invoice artifacts.
- Contractor simulator/admin troubleshooting should not clean failed artifacts, because support staff use those records to diagnose failures.

Implementation option:

- Add a cleanup mode to `Claims::Ingest::CreateDraftBatch`, for example `cleanup_failed_invoice_artifacts: true`.
- `ContractorPortalController#upload_batch` passes `true`.
- Admin simulator paths pass `false`.

### 4. Minimal Failure Record Boundary

The contractor browser needs something to poll if an async worker fails after the initial upload response. Therefore:

- Delete the half-baked invoice/evidence artifacts.
- Keep a minimal failed `claims.ingest_runs` row with `messages` containing the contractor-safe failure message.
- Keep only enough `claims.ingest_step_runs` detail for current-screen display and immediate support correlation if needed.

If the desired policy is stricter later, add a TTL cleanup job that removes failed contractor ingest runs after a short period, for example 24 hours.

This avoids leaving bad invoice records in the contractor portal while still allowing the current browser session to show a meaningful error.

## Frontend Changes

Update `app/frontend/components/domains/contractor-upload-invoices/index.tsx`.

Remove:

- `submitOk`.
- The current message box containing `submitError`, `submitOk`, `runError`, and `rowsError` as separate raw lines.
- The `Uploaded package` heading.
- The helper text under `Uploaded package`.
- The invoice/status table.

Add:

- A derived state for:
  - `isProcessing`
  - `isReadyForPrecheck`
  - `failureMessage`
- A new visual component, for example `ContractorUploadProcessingGraphic`.

Processing display:

```tsx
<ContractorUploadProcessingGraphic label="Preparing AI Advice" />
```

Failure display:

```tsx
<ContractorUploadFailureNotice message={failureMessage} />
```

Continue button:

- Keep the existing text: `Continue to Step 2: Pre-check`.
- Enable only when the backend indicates the invoice is ready for contractor pre-check.
- Prefer status check against business state, not table rows:
  - `genai_complete`, or
  - business label/status `With Contractor for Pre-check`, depending on the final backend status convention.

## Visual Direction

The processing graphic should be custom CSS/SVG, not a generic Chakra spinner.

Suggested design:

- Large circular arrow, approximately 120-160px.
- Soft blue/cyan gradient stroke.
- Slight 3D/glass glow.
- Smooth continuous rotation.
- Secondary inner shimmer or orbiting dot for “server thinking” feel.
- Respect `prefers-reduced-motion` by slowing or disabling rotation.

Keep it tasteful. It should feel premium, not arcade-ish.

## Failure Copy Policy

### Technical Failure

Technical failures mean the contractor likely did nothing wrong.

Contractor wording:

`We could not prepare your AI advice right now. Please try uploading the same files again later.`

Optional subtype-specific second sentence:

- `The upload service did not respond.`
- `The OCR service did not respond.`
- `The AI advice service did not respond.`

Do not expose raw service names unless business wants that.

### Package Needs Correction

Package correction failures mean the upload package itself needs a different batch.

Contractor wording:

`We could not prepare your AI advice because the upload package needs a change: {contractor_message}`

Examples:

- `No invoice PDF was found. Upload exactly one invoice PDF.`
- `More than one invoice PDF was found. Upload exactly one invoice PDF.`
- `One or more files use an unsupported file type. Upload PDFs, JPGs, or PNGs only.`
- `The replacement file was not recognized as an invoice. Upload one corrected invoice PDF.`

## Testing Plan

### Frontend

1. Upload valid package.

   - Processing graphic appears.
   - Old `Upload started...` message does not appear.
   - Old invoice/status table does not appear.
   - `Continue to Step 2: Pre-check` is disabled while processing.
   - Button enables when ready.

2. Package correction failure.

   - Use a batch with zero invoice PDFs.
   - Use a batch with multiple invoice PDFs.
   - Use unsupported file type.
   - Confirm friendly correction message appears.
   - Confirm old table/message section does not appear.
   - Confirm button remains disabled.

3. Technical failure.
   - Simulate upload service failure.
   - Simulate OCR/GenAI failure if practical.
   - Confirm technical retry-later message appears.
   - Confirm raw subtype/code is not visible to contractor.

### Backend

1. Verify subtype table seed:

   - All package subtypes are present.
   - All technical subtypes are present.
   - Each active subtype has `contractor_message`.

2. Verify contractor upload cleanup:

   - Failed contractor upload does not leave a contractor-visible invoice.
   - Failed contractor upload does not leave invoice versions/support docs/located fields.
   - Minimal ingest run failure message remains available for current screen polling.

3. Verify simulator/admin path:

   - Same malformed package in contractor simulator does leave diagnostic records.
   - Admin can inspect failure details.

4. Verify valid upload:
   - Valid package still creates invoice/version/supporting document records.
   - Continue button routes to contractor invoice review.

## Open Decision

The only policy choice still worth confirming before implementation:

- Do we keep failed contractor `ingest_runs` for a short period so the browser can show the failure after async processing fails?
- Or do we delete absolutely everything immediately and rely only on the current HTTP response?

Recommendation: keep minimal failed `ingest_runs` temporarily, delete invoice/evidence artifacts immediately.
