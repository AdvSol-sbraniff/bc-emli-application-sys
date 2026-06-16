# Invoice Status Flow Simplification Plan

## Purpose

Simplify the claims AI invoice business workflow so `admin_review_inbox` is the admin review stage.

The new admin-facing flow is:

1. AI finishes rule advice: `genai_complete`.
2. Contractor pre-checks the advice and submits to admins: `admin_review_inbox`.
3. Admin reviews the claim from `admin_review_inbox`.
4. Admin can approve, mark ineligible, or send back to the contractor.
5. Payment completion happens outside the admin UI through a payment/batch process.

## Target Status Flow

### Processing and contractor pre-check

`upload_in_progress` -> `evidence_prep` / `ocr_in_progress` -> `validation_advice` / `genai_in_progress` -> `genai_complete`

`genai_complete` means AI rule advice is complete. The contractor can pre-check the advice, revise if needed, and submit when ready.

### Admin review

`admin_review_inbox` is the review stage.

From `admin_review_inbox`, admins can:

- Approve: move to `approved_pending`.
- Mark ineligible: move to `ineligible`.
- Send back to contractor: move to `contractor_revision_inbox`.

### Contractor revision

`contractor_revision_inbox` means admin review sent the claim back to the contractor to revise the package or provide supporting information.

After contractor correction/pre-check, contractor submits again to `admin_review_inbox`.

### Payment

`approved_pending` is admin-facing `Approved`.

`approved_paid` is not set by the admin PDF viewer. It is a downstream/payment-engine status, expected to be set by a nightly batch job or payment integration.

## Statuses To Retire From Claims AI UI

### `in_review`

Remove `in_review` from the claims AI invoice workflow.

Reason: `admin_review_inbox` is the review stage. A separate `in_review` state creates an unnecessary second admin-review stage and makes the UI sound like there are two human review phases.

### `mark_paid` UI transition

Remove the admin UI action that moves `approved_pending` to `approved_paid`.

Reason: admins approve the claim. Payment completion belongs to the payment process, not the PDF review screen.

## Places To Change

## 1. Database DDL

File:

- `claims_ai_service_ddl/2_create_schema.sql`

Changes:

- Remove `in_review` from the `claims.invoice_status` enum if we want the clean-build schema to physically prevent future use.
- Keep `approved_paid` because the payment batch still needs a final paid status.
- Update enum comments so `admin_review_inbox` is the review stage and `approved_pending` is admin-approved/payment-pending.

Decision note:

For live databases, removing a PostgreSQL enum value is not a small `ALTER TYPE` operation. Since this project often rebuilds local/gold from `2_create_schema.sql`, the clean rebuild path is easiest. If we need a non-rebuild migration later, update any existing `in_review` rows first, then recreate the enum safely.

## 2. Status Transition API

File:

- `app/controllers/api/claims/invoice_grid_controller.rb`

Current transition map includes:

- `screen_in`: `admin_review_inbox` -> `in_review`
- `approve_pending`: `in_review` -> `approved_pending`
- `mark_paid`: `approved_pending` -> `approved_paid`
- `request_revision`: `admin_review_inbox` / `in_review` -> `contractor_revision_inbox`

Changes:

- Remove `screen_in`.
- Change `approve_pending` to allow `admin_review_inbox` -> `approved_pending`.
- Add or expose an `ineligible` transition from `admin_review_inbox` -> `ineligible` if not already present.
- Change `request_revision` to allow only `admin_review_inbox` -> `contractor_revision_inbox`.
- Remove `mark_paid` from the admin API transition map.
- Update validation/error messages so they no longer mention `in_review` or payment marking from the PDF viewer.

## 3. Admin PDF Viewer

File:

- `app/frontend/components/domains/invoice-versions/index.tsx`

Changes:

- Remove `screen_in` / `Send to Supervisor`.
- Rename `Approve Pending` to business label `Approve`.
- Make `Approve` valid from `admin_review_inbox`.
- Add `Mark Ineligible` action valid from `admin_review_inbox`.
- Keep `Send to Contractor for Revision`, valid from `admin_review_inbox`.
- Remove `Mark Paid` icon/action.
- Remove `in_review` from status labels/hints.
- Display `approved_pending` as `Approved`.
- Display `approved_paid` as a payment/batch status, for example `Paid` or `Paid by Payment Process`.
- Update the PDF viewer help drawer so the described flow matches the simplified business flow.
- Update confirmation text/reminders so they explain that messages/internal notes are separate from the status move.

## 4. Invoice Admin Grid

File:

- `app/frontend/components/domains/invoices-admin/index.tsx`

Changes:

- Remove `in_review` from the status filter dropdown.
- Display `approved_pending` as `Approved`.
- Keep `approved_paid` available as `Paid` or `Paid by Payment Process` if historical/payment rows can appear.
- Update status hints:
  - `admin_review_inbox`: admin review stage.
  - `approved_pending`: admin approved; payment handled separately.
  - `approved_paid`: payment process completed.
- Update help drawer text so it does not imply a second admin-review state.

## 5. Contractor-Facing Invoice Screens

Files:

- `app/frontend/components/domains/contractor-invoice-review/index.tsx`
- `app/frontend/components/domains/contractor-upload-invoices/index.tsx`
- `app/frontend/components/domains/ai-contractor-dashboard/ai-contractor-dashboard-screen.tsx`

Changes:

- Remove or neutralize contractor-facing `in_review` labels.
- Use contractor-friendly wording:
  - `admin_review_inbox`: `Submitted to admin`
  - `contractor_revision_inbox`: `Update requested`
  - `approved_pending`: `Approved`
  - `approved_paid`: `Paid` or still `Approved`, depending on what contractors should see.
- Update any help text that says AI “review” is complete to say AI rule advice is complete.

## 6. Admin Upload / Fix Screens

Files:

- `app/frontend/components/domains/submission-simulator-admin/index.tsx`
- `app/frontend/components/domains/upload-invoice-fix-admin/index.tsx`

Changes:

- Remove `in_review` from local status colour/label helpers.
- Treat `approved_pending` as `Approved`.
- Ensure +1 fix paths still start the correct processing phase and do not depend on `in_review`.

## 7. Reports

File:

- `app/frontend/components/domains/reports-volume-value/index.tsx`

Changes:

- Remove `in_review` from report status filters for claims AI reports.
- Relabel `approved_pending` as `Approved` in the UI.
- Keep `approved_paid` only if reports need payment completion visibility.

## 8. Models / Type Definitions

Files:

- `app/models/claims/invoice.rb`
- `app/frontend/types/enums.ts`
- Any claims-specific status helper models or serializers found during implementation.

Changes:

- Remove claims-AI references to `in_review` if present.
- Keep legacy public `PermitApplication` statuses separate unless they are explicitly claims-AI paths.
- Do not refactor old `PermitApplication` flow as part of this change.

## 9. Revision Requests / Internal Notes

Files:

- `app/frontend/components/domains/revision-requests-admin/index.tsx`
- `app/models/claims/admin_revision_request.rb`
- Any API controller that gates admin messages by invoice status.

Changes:

- Confirm conversations remain open regardless of invoice state, as already intended.
- Remove any special allowance or wording for `in_review`.
- Ensure admin can message/internal-note while in `admin_review_inbox`, `contractor_revision_inbox`, `approved_pending`, `ineligible`, etc., if that is still the desired always-open rule.

## 10. Documentation

Files:

- `claims_ai_service_documentation/claims_data_model.md`
- Any current non-archived operational docs that describe invoice status flow.

Changes:

- Rewrite invoice status lifecycle sections:
  - Remove `in_review` from the claims AI business flow.
  - Explain `admin_review_inbox` as the admin review stage.
  - Explain `approved_pending` as admin-approved/payment pending.
  - Explain `approved_paid` as payment-engine/batch-completed.
- Leave archived plans alone unless they are actively referenced.

## 11. Existing Data Cleanup

Before enforcing the new flow:

```sql
update claims.invoices
set status = 'admin_review_inbox',
    updated_at = now()
where status = 'in_review';
```

Rationale: any existing `in_review` claim should return to the single admin review stage unless there is a known reason it should already be approved.

If the enum is physically rebuilt, run this cleanup before the enum change or do a full schema rebuild.

## 12. Tests

Local test sequence:

1. Rebuild or update local DB so no claim invoices are stuck in `in_review`.
2. Run a normal test invoice package through AI rule advice to `genai_complete`.
3. Contractor submit: verify status becomes `admin_review_inbox`.
4. Admin PDF viewer:
   - Verify no `Send to Supervisor` button.
   - Verify `Approve`, `Send to Contractor for Revision`, and `Mark Ineligible` are available from `admin_review_inbox`.
   - Verify no `Mark Paid` action.
5. Approve from admin PDF viewer:
   - Verify status becomes `approved_pending`.
   - Verify UI displays business label `Approved`.
6. Send back to contractor:
   - Verify status becomes `contractor_revision_inbox`.
   - Verify messages/internal notes still open.
7. Mark ineligible:
   - Verify status becomes `ineligible`.
8. Contractor dashboard:
   - Verify submitted/approved/update-needed labels make sense and no `in_review` label appears.
9. Reports:
   - Verify filters and output do not expose `in_review`.

Regression packages:

- `claims_ai_service_documentation/Test Data/Heat Pump/test014`
- `claims_ai_service_documentation/Test Data/windows doors/test002`
- One simple single-upgrade package from Heat Pump or Insulation.

## Open Questions

1. Should `approved_paid` be visible to contractors as `Paid`, or should contractors simply see `Approved` for both `approved_pending` and `approved_paid`?
2. Should `approved_pending` be displayed as exactly `Approved`, or `Approved - Payment Pending` in reports/back-office screens?
3. What should the admin button label be for `ineligible`: `Mark Ineligible`, `Reject`, or `Deny`?
4. Should `in_review` be physically removed from the enum now, or left as a deprecated value until the next clean DB rebuild?
