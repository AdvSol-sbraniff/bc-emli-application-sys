# AI Contractor Portal UI Plan

Purpose: focused frontend/UX plan for the AI contractor invoice flow. The master map is `ai_contractor_portal_plan.md`.

Gate 0 update:

- UI must present validation as AI-assisted pre-review, not final eligibility.
- Rule results should show whether evidence came from GenAI, code, DB, external lookup, or manual review.
- Missing evidence should display as `Could not verify` / `Requires review`, not as automatic failure.
- Contractor-facing screens should emphasize actionable fixes. Admin-facing screens should expose evidence source and evaluator.

## Principles

- Contractor UI should feel close to legacy.
- Use modest polish, but avoid a visual cliff that makes contractors think this is a different product.
- Hide AI complexity unless it helps contractors self-correct.
- Show transparency where it helps: extracted values, highlights, confidence, and rule findings.
- No old-school screens should be permanently changed.
- Screen text and help drawers should support future user guides. If a screen is hard to explain, the screen probably needs work.

## Feature Flag

- Use `AI_CONTRACTOR_INVOICES_ENABLED` and `VITE_AI_CONTRACTOR_INVOICES_ENABLED` if frontend build-time flag is needed.
- If off, hide the contractor AI tab entirely.

## Contractor Dashboard

Add a third tab:

- Label: `Invoice upload assistant`.
- Location: inside `/contractor-dashboard`.
- Existing `Invoice submissions` and `Program resources` tabs stay as-is.

Dashboard row model:

- One row per AI invoice.
- Do not show sessions.
- Show status, upgrade type, created date, reference/invoice number, latest filename, and simple action.

Status labels:

- `genai_complete`: display as `Draft`.
- Add helper text where useful: `Ready to review`.
- `admin_review_inbox`: contractor-facing `Submitted`; admin-facing `Unread` or `New submission`.
- `revisions_requested`: `Update needed`.
- `in_review`: `In review`.
- `approved_pending`, `approved_paid`, `ineligible`: match legacy visibility and labels after verification.

Rationale for `genai_complete`:

- Legacy `new_draft` displays as `Draft`.
- AI `genai_complete` is pre-submit and contractor-owned, so `Draft` is the familiar label.
- The screen itself can explain that the draft is ready for review after AI processing.

## Start Flow

V1:

- Keep explicit Windows and doors selection.
- DB remains future-ready with invoice-level upgrade type.
- Only Windows and doors is enabled.

V2:

- Replace the type picker with invoice-type autodetection after OCR/GenAI.
- AI can return detected type from the seven legacy variants.

## Upload Screen

Contractor upload screen should be a stripped-down version of `submission-simulator-admin`.

V1 behavior:

- Upload multiple PDFs.
- PDF invoice uploads only.
- Each PDF becomes one invoice.
- Upload starts OCR/GenAI pipeline.
- Upload does not submit.
- Show plain progress and failure states.

Copy direction:

- "Upload one or more invoice PDFs for Windows and doors."
- "The upload assistant will read each invoice and prepare it for your review."
- "You can leave this page and return from Invoice upload assistant."

## Contractor PDF Viewer

Viewer should show:

- Uploaded invoice PDF.
- Extracted first-class fields.
- GenAI located fields.
- Polygons/highlights.
- Confidence scores.
- Rulecheck findings.
- Requested revision items if any.

Viewer should hide:

- Admin-only quick-create revision/autorevision helper.
- Admin/dev diagnostic controls.

Actions:

- Submit invoice.
- Upload fix +1.
- Add supplement/supporting document.
- Retry failed step.
- Delete/withdraw before submit only.

Submit blocker:

- Modal if any tracked first-class field is null.
- Plain list of missing fields.
- No manual field editing.

## Supplements

Invoice upload remains PDF-only.

Supplements should allow common industry-standard document/photo uploads:

- PDF
- JPG/JPEG
- PNG
- HEIC/HEIF if upload/storage accepts it cleanly

If preview is difficult:

- Store and allow download.
- Do not block v1 just because a format is awkward to preview.

## Admin Menu Cleanup

Do as part of this work, but do not over-engineer it.

Regular admin/operator area should emphasize:

- AI invoice inbox/admin grid.
- PDF review.
- Revision workflow.
- Business reports.

System admin/dev area should emphasize:

- Rulesets admin/editor.
- Eligibility/code setup.
- Sessions admin.
- Users admin.
- Submission simulator.
- Hello AI/dev diagnostics.
- Deep version inspection tools.

Use old-system home-page cards/icons where that is cleaner than a giant nav menu.

## Admin Screen Review

The new AI admin screens need their own polish pass. They are not old-school screens, so they are in scope for improvement.

Current screens to review:

- `invoices-admin`: main operational invoice grid.
- `invoice-versions`: by-session PDF viewer.
- `invoice-version-viewer-by-version`: version inspection screen.
- `invoice-versions-admin`: version history grid.
- `revision-requests-admin`: revision request grid.
- `revision-request-editor`: revision request editor.
- `invoice-supporting-documents-admin`: supporting document management.
- `upload-invoice-admin`: admin one-off upload.
- `upload-invoice-fix-admin`: admin upload fix.
- `submission-simulator-admin`: admin/dev bulk upload simulator.
- `rulesets-admin`: ruleset grid.
- `ruleset-editor`: ruleset editor.
- `sessions-admin`, `admin-create-session`, `edit-session-admin`: session setup/debug screens.
- `eligibilitycodes-admin`, `eligibilitycode-editor`: code/admin setup.
- `reports-volume-value`: business reporting.
- `hello-ai-admin`: dev diagnostic.

Recommended grouping:

- Operational admin screens: invoice grid, PDF viewer, revision requests, supporting documents, reports.
- System/config screens: rulesets, eligibility codes, users.
- Dev/test screens: sessions admin, create/edit session, upload simulator, Hello AI, deep version inspection.

Admin UX cleanup themes:

- Replace prototype status names with business labels: `Draft`, `Submitted`, `Update needed`, `In review`, `Approved pending`, `Approved paid`, `Ineligible`.
- Remove or hide session status from operational admin screens.
- Surface assignment clearly in the invoice grid.
- Make `invoices-admin` the main workbench: search/filter, assign, open PDF review, request revision, screen in, approve pending, approve paid, mark ineligible.
- Keep deep technical screens reachable from context links, not as equal top-level destinations for regular admins.
- Move simulator/dev screens away from regular admin navigation.
- Add upgrade type filter once rulesets/invoices are upgrade-type-aware.
- Add ruleset upgrade type and enabled status to ruleset grid/editor.
- Replace obsolete `closed_success`, `closed_reject`, and `contractor_revision_inbox` labels.
- Keep help drawers, but rewrite them for admins/business users rather than for Stephen-only development notes.
- Make error/failure messages slightly technical for admins, but still readable.

Screens likely needing the most work:

- `invoices-admin`: must become the polished admin workbench.
- `invoice-versions`: should be split or parameterized so contractor viewer can reuse layout without admin-only revision helper.
- `submission-simulator-admin`: should remain a system/dev tool, not a contractor/admin operational pattern.
- `rulesets-admin` and `ruleset-editor`: need upgrade type filtering, enabled status, clone/new-version workflow, and clear immutable-after-use language.
- `reports-volume-value`: should stay business-reporting focused and not drift into AI internals.

## V2/Future

- Contractor prior-version comparison.
- Mixed upgrade-type automatic detection.
- More polished media preview for all supplement formats.
