# AI Contractor Portal User Guides Plan

Purpose: focused documentation plan for user guides, admin guides, and business-process guides. The master map is `ai_contractor_portal_plan.md`.

Gate 0 update:

- Guides must avoid saying AI approves eligibility.
- Use language such as `pre-review`, `potential issue`, `could not verify`, and `requires admin review`.
- Contractor guides should explain that supporting documents may still be required even when invoice upload succeeds.
- Admin guides should explain which checks are deterministic code, which are GenAI evidence findings, and which remain manual/program review.

## Principle

The AI invoice flow needs user guides as part of the product, not as an afterthought.

Guides should explain:

- What the screen is for.
- Who should use it.
- What status means.
- What action to take next.
- What to do when the AI could not read something.
- What business process is happening behind the screen.

## Audiences

Contractors:

- Need simple, task-based instructions.
- Avoid technical AI/OCR terms where possible.
- Use plain language.
- Explain how to upload, review, fix, supplement, and submit.

Admins:

- Need operational process guidance.
- Can handle slightly more technical language.
- Need clear decision points: request update, screen in, approve pending, approve paid, ineligible.

System admins / Stephen:

- Need setup/config/troubleshooting guidance.
- Includes rulesets, sessions, seeds, test harness, feature flags, and Gold migration.

Mandy / BA / UX testers:

- Need walkthrough scripts and expected outcomes.
- Useful for manual UAT.

## Contractor Guides Needed

Suggested guides:

- `How to use Invoice upload assistant`
- `How to upload invoice PDFs`
- `How to review what the upload assistant found`
- `How to fix an invoice using Upload fix`
- `How to add supporting documents`
- `How to submit an invoice`
- `What invoice statuses mean`
- `What to do when required information is missing`

Contractor status guide:

- `Draft`: AI has read the invoice and it is ready for you to review.
- `Submitted`: You submitted the invoice to the program team.
- `Update needed`: The program team needs you to fix or add information.
- `In review`: The program team is reviewing the invoice.
- `Approved pending`: Approved and waiting for payment processing, if visible to contractors.
- `Approved paid`: Approved and paid, if visible to contractors.
- `Ineligible`: The invoice is not eligible, if visible to contractors.

## Admin Guides Needed

Suggested guides:

- `AI invoice admin workbench guide`
- `How to assign an AI invoice`
- `How to review AI findings`
- `How to request an update from a contractor`
- `How to screen in an invoice`
- `How to approve pending`
- `How to mark approved paid`
- `How to mark ineligible`
- `How to review supporting documents`
- `How to use reports`
- `What statuses mean for admins`

Admin process guide:

1. Open AI invoice queue.
2. Assign invoice if needed.
3. Review extracted fields, PDF highlights, confidence, rulechecks, and supporting documents.
4. If fix is needed, create/request update.
5. If ready, screen in.
6. If approved, approve pending.
7. If payment completed/recorded, mark approved paid.
8. If not eligible, mark ineligible with reason if supported.

## System Admin Guides Needed

Suggested guides:

- `AI invoice feature flag guide`
- `Ruleset setup and versioning guide`
- `Upgrade type setup guide`
- `Seed/rebuild guide for local`
- `Test harness guide`
- `Gold migration checklist`
- `Troubleshooting OCR/GenAI failures`
- `Admin menu and role guide`

## In-App Help

Screens should have concise help drawers or info blocks.

Contractor screens:

- Keep help short and plain.
- Explain the next action.
- Avoid internal terms like ruleset, DI JSON, GenAI response.

Admin screens:

- Help can mention OCR, GenAI, confidence, and rulechecks.
- Help should explain business action, not just screen mechanics.

System/dev screens:

- Help can be technical.
- Label screens clearly as setup/testing/admin-only.

## Documentation Artifacts

Possible markdown files later:

- `claims_ai_service_ddl/user_guide_contractor_ai_invoice_upload.md`
- `claims_ai_service_ddl/user_guide_admin_ai_invoice_review.md`
- `claims_ai_service_ddl/user_guide_system_admin_ai_invoice_setup.md`
- `claims_ai_service_ddl/user_guide_ai_invoice_statuses.md`
- `claims_ai_service_ddl/user_guide_ai_invoice_uat_script.md`

Keep these separate from implementation plans so they can eventually become real user-facing material.

## Test Harness Connection

The user guides should align with UAT scripts.

If the guide says a contractor can do something, the test harness should eventually cover it.

If the guide says an admin status transition exists, API/browser tests should eventually cover it.

## Open Verification Items

- Confirm whether contractors see `approved_pending`.
- Confirm whether contractors see `approved_paid`.
- Confirm whether ineligible reason text is visible to contractors.
- Confirm how legacy invoice submit notes/comments work, if at all.
- Confirm exact language Mandy prefers for contractor-facing labels.
