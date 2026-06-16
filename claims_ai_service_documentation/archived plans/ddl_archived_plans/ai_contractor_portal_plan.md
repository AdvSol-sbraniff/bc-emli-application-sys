# AI Contractor Portal Plan

Working note for Codex and Stephen. This is intentionally a planning artifact, not an implementation script.

Status: master planning map after Stephen's third-pass answers. Contractor portal redesign is paused behind the rules analysis prerequisite gate.

## Planning Documents

This file is the master map. Focused working plans live beside it:

- `ai_contractor_portal_ddl_plan.md`: schema/model changes.
- `ai_contractor_portal_api_plan.md`: backend endpoints, authorization, submit/retry behavior.
- `ai_contractor_portal_ui_plan.md`: contractor/admin screens, labels, menu cleanup.
- `ai_contractor_portal_test_harness_plan.md`: local test strategy and Gold readiness gate.
- `ai_contractor_portal_user_guides_plan.md`: user guides, admin guides, and business-process documentation.
- `ai_rules_analysis_prerequisite_plan.md`: standalone Gate 0 plan for analyzing Better Homes BC requirements before redesign/code work.
- `ai_rules_analysis_gate0_findings.md`: concise findings from the first public-requirements analysis pass.
- `ai_ruleset_suite_requirements_plan.md`: plan for turning Better Homes BC requirements into a traceable suite of upgrade-type rulesets.
- `ai_ruleset_requirements_matrix.md`: starter source-to-rules matrix for public ESP requirements.
- `ai_code_engine_plan.md`: deterministic validation engine plan for math/date/cap/DB-comparison rulechecks.
- `ai_windows_doors_v1_ruleset_refactor_plan.md`: maps the current `esp_default_v1` prototype into a source-traced Windows and doors hybrid ruleset.
- `ai_ruleset_editor_refactor_plan.md`: admin editor plan for validation packages, common/domain rules, code rules, and composed prompt previews.
- `ai_gate0_morning_handoff.md`: short next-step handoff after the autonomous Gate 0 analysis pass.

## Guiding Decisions

- The new AI contractor flow sits beside the legacy contractor invoice flow during transition. It does not replace the existing "Invoice submissions" tab yet.
- The contractor UI should stay close to the legacy look and feel, with modest polish where it helps. The goal is "this feels familiar, only easier", not "surprise, robots".
- Old-school screens and old-school business logic are not to be permanently changed. New work should live in AI screens, AI endpoints, and AI DDL/model areas.
- Sessions are an internal grouping/container only. Contractors should not have to understand or manage sessions.
- Invoice status is the business truth. Session status should not be a workflow concept.
- "Submit" means one thing in the AI design: the contractor has reviewed one invoice and is handing that invoice to admin. Uploading files is not submitting.
- One uploaded invoice PDF equals one AI invoice. A PDF containing multiple invoices is out of scope for v1.
- Rulesets are upgrade-type-specific, required, and immutable by UI convention after use. API-level immutability enforcement is deferred unless testing shows real risk. If the selected upgrade type has no enabled ruleset, the AI run should fail clearly instead of falling back to a generic/default ruleset.
- Gold migration waits until local is thoroughly tested by automated harness/scripts and then manually by Stephen.
- The test harness plan must be thought through before coding work starts.
- User guides and business-process guides are part of the product and should be planned alongside the screens.
- Rulesets must be grounded in the public Better Homes BC requirements, but they must distinguish invoice-checkable rules from database/supporting-document/human-review rules.
- Gate 0 comes before redesign: complete the Better Homes BC rules analysis and requirement matrix before changing contractor/admin AI screens, workflow APIs, or Gold rulesets.
- Validation is hybrid: GenAI finds fuzzy evidence; deterministic code evaluates math, dates, thresholds, caps, and DB comparisons.
- Windows and doors remains the safest v1 domain. Heat pumps are deferred because the public requirements are subtype-heavy and require product lists, heating-fuel context, removal proof, and other supporting evidence.

## Legacy Flow, First-Pass Code Findings

The legacy contractor flow currently appears to be:

1. Contractor lands on `/contractor-dashboard`.
2. Contractor uses the existing "Invoice submissions" tab.
3. Contractor clicks the legacy start invoice route, `/new-invoice`.
4. The app shows a variant choice screen backed by `public.permit_classifications`.
5. The contractor selects one of the invoice `SubmissionVariant` rows.
6. Legacy flow creates a `permit_applications` record and opens the FormIO/CHEFS-style invoice form.
7. The contractor fills the generated form, uploads required documents, signs off, and submits.

Useful source anchors:

- `app/frontend/components/domains/contractor-dashboard/contractor-dashboard-screen.tsx` defines the current contractor tabs.
- `app/frontend/components/domains/energy-savings-application/new-invoice-screen.tsx` defines the current invoice variant picker.
- `app/models/concerns/application_flow/invoice_external_contractor.rb` defines the legacy contractor invoice state machine.
- `app/models/permit_application.rb` stores invoice submissions as `PermitApplication` records and has legacy invoice states.
- `config/locales/en.yml` maps legacy status labels, including `newly_submitted` to `UNREAD`, `revisions_requested` to `UPDATE NEEDED`, `resubmitted` to `RESUBMITTED`, `in_review` to `IN REVIEW`, and `ineligible` to `INELIGIBLE`.

Legacy invoice states found in code:

- `new_draft`
- `newly_submitted`
- `revisions_requested`
- `resubmitted`
- `in_review`
- `approved_pending`
- `approved_paid`
- `ineligible`

Legacy invoice transitions found in `InvoiceExternalContractor`:

- `submit`: `new_draft` -> `newly_submitted`
- `submit`: `revisions_requested` -> `resubmitted`
- `review`: `newly_submitted` or `resubmitted` -> `in_review`
- `approve`: `in_review` -> `approved_pending`
- `approve_paid`: `approved_pending` -> `approved_paid`
- `reject`: `in_review` -> `ineligible`
- `finalize_revision_requests`: can move several states to `revisions_requested`, including `newly_submitted`, `resubmitted`, and `in_review`; the exact UI behavior still needs one practical check because Stephen saw disabled pencils in one path.

Legacy permissions found in first pass:

- `PermitApplicationPolicy#approve?` allows `admin_manager` or `admin`.
- `PermitApplicationPolicy#update_revision_requests?` allows `admin_manager` or `admin`.
- `PermitApplicationPolicy#finalize_revision_requests?` allows `admin_manager` or `admin`.
- `PermitApplicationPolicy#change_status?` allows `admin_manager` or `admin`.
- `ApplicationAssignments::AssignmentManagementService` supports one assigned user per application by removing the old assignment before creating a new one.
- `PermitApplicationPolicy#destroy?` allows submitters to withdraw their own draft applications, and the controller destroys the record. This supports allowing AI contractors to delete pre-submit AI invoices.

This means the AI invoice flow should initially clone the old admin role model unless we later discover a strong reason not to.

## Feature Flag

Use a conventional feature flag so unfinished AI contractor work can stay deployed but hidden.

Planned names:

- Backend/server flag: `AI_CONTRACTOR_INVOICES_ENABLED`
- Frontend/Vite flag if needed: `VITE_AI_CONTRACTOR_INVOICES_ENABLED`

Behavior:

- If disabled, hide the AI contractor tab entirely.
- Do not show "coming soon" text.
- Keep admin/dev-only AI screens available separately as needed for Stephen/testing, but do not expose the contractor flow.

## Contractor IA And Routes

Contractor portal tab:

- Add a third tab inside `/contractor-dashboard`.
- Tab label: `Invoice upload assistant`.
- Rationale: it is less scary than "AI invoice submissions", but still explains the job. We can tune the label later with Mandy.

Routes:

- Keep the tab inside the existing contractor dashboard shell for familiarity.
- Use dedicated AI routes for the actual workflow screens:
- `/contractor-ai-invoices/new`
- `/contractor-ai-invoices/upload/:sessionId`
- `/contractor-ai-invoices/:invoiceId`

Dashboard list:

- Show one row per AI invoice, not one row per session.
- Clone the old contractor invoice list style as much as practical.
- Show status, upgrade type, created date, reference/invoice number, latest filename, and simple actions.
- Sessions remain invisible except for left/right navigation inside the PDF viewer.

## Upgrade Types

Do not create a separate AI-only upgrade-type table right now.

Use the existing legacy classification rows:

- `public.permit_classifications.type = 'SubmissionVariant'`
- Parent is the `Invoice` submission type.
- Known variants:
- `15` Heat pump (space heating)
- `16` Heat pump water heater (including combined)
- `17` Insulation
- `18` Windows and doors
- `19` Ventilation
- `20` Electrical service upgrade
- `21` Health and safety remediation

AI schema direction:

- `claims.invoices.upgrade_type_id uuid NULL`
- Foreign key to `public.permit_classifications(id)`
- Expose `upgrade_type_id`, `upgrade_type_code`, and `upgrade_type_name` in AI invoice grid/reporting views.
- For v1, only Windows and doors is enabled.
- The other six types can be visible but disabled in the variant choice screen.

Important second-pass decision:

- The invoice owns `upgrade_type_id`.
- The session should not enforce one upgrade type forever.
- This keeps the future door open for one upload batch containing mixed invoice types, such as two heat pump invoices and two windows invoices.
- For v1, the UI will force an explicit Windows and doors choice because only Windows and doors is enabled.
- Future design can allow a per-file upgrade-type selector on the upload screen. The session remains the batch; each invoice row carries its own upgrade type.
- Future v2 design can replace the picker with GenAI invoice-type autodetection after OCR.

## Rulesets By Upgrade Type

The ruleset table needs to support variant-specific rules.

Current table:

- `claims.validationgenai_rulesets`
- Has `ruleset_shortname`, `system_record`, `user_record1`
- Currently not tied to an upgrade type.

Planned change:

- Add `upgrade_type_id uuid NOT NULL` or staged as nullable during local rebuild, then enforce non-null once seed data is fixed.
- FK to `public.permit_classifications(id)`.
- Add `enabled boolean NOT NULL DEFAULT true`.
- Add an index on `(upgrade_type_id, enabled, created_at DESC)`.
- Use `created_at` as the version ordering for now. No `effective_at` needed yet.
- Ruleset admin UI should filter by upgrade type.
- Rulesets should be treated as immutable after use by UI convention for v1.
- API-level rejection of edits to used rulesets is v2 hardening unless v1 testing shows real risk.
- Multiple enabled rulesets per upgrade type are allowed; choose the newest by `created_at`.

Selection rule:

- When running GenAI for an invoice, choose the newest enabled ruleset matching `invoice.upgrade_type_id`.
- If no enabled ruleset exists for the invoice's upgrade type, block/error.
- Do not fall back to `esp_default_v1` or any generic/default ruleset.
- The current `esp_default_v1` concept should be retired or renamed/re-scoped into an explicit Windows and doors ruleset in the insert scripts.

Historical explainability:

- `claims.invoice_versions` should store the `ruleset_id` used for that version.
- This is not undesirable duplication; it is a historical snapshot of which rules were used to produce that invoice version's extracted/validated output.
- If a ruleset is later disabled, renamed, or superseded, old invoice versions must still be explainable.

## Session Simplification

Session is a technical container for grouping uploads, not a business workflow.

New session model:

- A session groups invoices uploaded together.
- A session has one contractor/company context.
- A session has a `submitter_id` pointing to the actual user who started the upload, such as the contractor primary contact or an employee/secretary.
- Session is useful in the PDF viewer so the user can move left/right through invoices from the same upload batch.
- Contractor dashboard should not show sessions.
- Contractor dashboard should show one row per invoice.
- Session should not own the upgrade type long-term; invoice owns upgrade type.

Session lifecycle:

- Create the session before the first upload begins.
- For v1, create the session after the contractor chooses Windows and doors and before the upload screen accepts files.
- If the contractor forgot another invoice after completing the upload, they create a new session for that invoice.
- Do not support "add invoice #6 to an old session" in v1.

DDL direction:

- Remove/comment `claims.sessions.status` as a workflow concept.
- Remove/comment `claims.sessions.submitted_at`; `sessions.created_at` is enough to know when the batch/context was started.
- Keep `claims.sessions.submitter_id`, documented as the actual acting user.
- Update views and UI so `session_status` is not meaningful. Compatibility views may expose `NULL AS session_status` during transition if needed.

## Invoice Status Model

The AI invoice needs two layers of status language:

- Pipeline states before the contractor can review/submit.
- Business states after the contractor submits to admin.

Keep technical pipeline states:

- `upload_queued`
- `upload_in_progress`
- `upload_failed`
- `upload_complete`
- `ocr_queued`
- `ocr_in_progress`
- `ocr_failed`
- `ocr_complete`
- `genai_queued`
- `genai_in_progress`
- `genai_failed`
- `genai_complete`

Business/admin states:

- `admin_review_inbox`: submitted by contractor and waiting for admin attention.
- `revisions_requested`: admin has asked contractor for changes. This mirrors legacy naming.
- `in_review`: screened in / deeper admin or management review.
- `approved_pending`: approved, payment pending.
- `approved_paid`: approved and paid.
- `ineligible`: rejected/ineligible.

Remove/replace:

- Remove `closed_success`; use `approved_paid`.
- Remove `closed_reject`; use `ineligible`.
- Do not create a separate submit-blocked status unless later UX testing proves the dashboard needs it.

Important status interpretation:

- `genai_complete` is not submitted.
- `genai_complete` means AI processing is done and the invoice is ready for contractor review.
- Contractor submit transitions one invoice from `genai_complete` to `admin_review_inbox`, assuming all submit blockers pass.
- If required first-class fields are missing, keep status as `genai_complete` and block submit with a modal.
- "Resubmitted" should be derived/displayed when an invoice has multiple versions after a revision cycle, unless implementation later shows that a stored `resubmitted` state is cleaner.

Contractor labels:

- For `genai_complete`, show contractor-facing `Draft`, matching the old `new_draft` label.
- Use helper copy such as `Ready to review` inside the screen where useful.
- For `admin_review_inbox`, show contractor-facing `Submitted`.
- For admin-facing `admin_review_inbox`, show `Unread` or `New submission`, matching legacy behavior.
- For `revisions_requested`, show `Update needed`.
- For `in_review`, show `In review`.
- For `approved_pending`, `approved_paid`, and `ineligible`, match old contractor/admin visibility once verified.

## Contractor AI Upload Screen

This replaces the old-world generated form as the first screen after choosing a variant.

It should be a stripped-down contractor version of `submission-simulator-admin`.

Core behavior:

- Upload multiple invoice PDFs at once.
- PDF only for invoice upload in v1.
- Every uploaded PDF becomes one invoice.
- No debug tables.
- No admin-only controls.
- Create invoice rows and invoice version rows under the current session.
- Set each invoice `upgrade_type_id`.
- Run upload/OCR/GenAI pipeline.
- Show a clean progress/status panel.
- Upload starts processing, but it does not submit anything.

MVP copy:

- "Upload one or more invoice PDFs for Windows and doors."
- "The upload assistant will read each invoice and prepare it for your review."
- "You can leave this page and return from Invoice upload assistant."

Failure behavior:

- If upload fails, retry starts at upload.
- If OCR fails, retry starts at OCR.
- If GenAI fails, retry starts at GenAI.
- Retry reruns from the failed step forward, not from the beginning.
- Contractor failure messages should be plain-language and very simple.
- Admin failure messages can include a little more technical detail.

Delete-before-submit:

- Allow contractor delete/withdraw for pre-submit AI invoices, including failed pre-submit invoices.
- This mirrors the old system's draft withdrawal/destruction behavior closely enough for v1.
- Use hard delete for pre-submit records if no downstream admin/business action has occurred.
- Once submitted to admin, contractor delete should not be available.

## Contractor PDF Viewer

Need a contractor-facing PDF viewer similar to the admin "By Session" PDF viewer, but simplified and action-oriented.

Existing AI viewer anchors:

- `app/frontend/components/domains/invoice-versions/index.tsx`
- Title: `Invoices Admin - PDF Viewer (By Session)`
- Shows latest invoice version in session context.
- Existing admin version history/diff is separate from the by-session viewer.
- `app/frontend/components/domains/invoice-version-viewer-by-version/index.tsx` is the by-version inspection path.

Contractor viewer should:

- Show the uploaded invoice PDF.
- Show OCR/GenAI extracted fields.
- Show polygons/highlights.
- Show AI findings/rulecheck details.
- Show confidence scores and AI transparency details because the goal is to help contractors self-correct.
- Hide admin-only quick-create revision helper/autorevision tooling.
- Show requested revision items if any.
- Provide invoice-level actions:
- Submit.
- Upload fix +1 invoice version.
- Add supplement/supporting document.
- Retry failed AI step when status is failed.
- Delete/withdraw before submit only.

Version behavior:

- v1 shows latest version only, matching the current by-session admin viewer.
- Prior version comparison is v2 unless we later decide contractors absolutely need it.
- In the old generated form flow, the submitter effectively edits/overtype fields during revision; prior visible field comparison is not central to the contractor experience.

Submit behavior:

- Submit is invoice-level only.
- Submit should block if any tracked first-class OCR field is null/missing.
- The block should be a simple "we cannot submit this yet" modal with a plain list of missing items.
- No manual editing of extracted first-class fields is allowed. Correction path is upload fix +1 only.
- Do not add a new generic contractor note on submit unless a true legacy equivalent is found. The old system has revision comments and support-file request notes, but no obvious generic submit note in the first scan.

Supplement behavior:

- "Supplement" means supporting document tied to the invoice.
- It is not another invoice PDF.
- Examples may include photos of windows, street/front-of-home photos, warranty info, NRCan declaration material, or whatever supporting evidence the contractor needs to provide.
- Supplements do not trigger OCR/GenAI in v1.
- Supplements should allow common industry-standard document/photo uploads: PDF, JPG/JPEG, PNG, and HEIC/HEIF if upload/storage accepts it cleanly.
- If a format is awkward to preview in-browser, store it and offer download rather than blocking upload.
- Legacy FormIO simple file upload appears to allow several file types, including `.jpg`, `.jpeg`, `.png`, `.img`, `.pdf`, `.xlsx`, `.xls`, and `.txt`; AI supplement support can start narrower if that is safer.
- No clear old-system count/size limit was found in the quick scan; use existing storage/global limits if present.

Fix +1 behavior:

- Contractor upload fix creates a new invoice version.
- Contractor upload fix automatically reruns OCR and GenAI.
- The AI should use the same invoice/upgrade type and the newest enabled matching ruleset.
- The new invoice version stores the ruleset used.

## Admin UI Impact

Admin AI screens need status language and actions aligned to legacy flow.

Existing AI/admin screens likely affected:

- `invoices-admin`
- `invoice-versions-admin`
- `invoice-versions` by-session viewer
- `invoice-version-viewer-by-version`
- `submission-simulator-admin`
- reports

Focused admin-screen review lives in `ai_contractor_portal_ui_plan.md`.

Admin actions to support:

- Move `admin_review_inbox` -> `revisions_requested` by creating/finalizing revision requests.
- Move `admin_review_inbox` or resubmitted equivalent -> `in_review`.
- Move `in_review` -> `approved_pending`.
- Move `approved_pending` -> `approved_paid`.
- Move `in_review` -> `ineligible`.
- Keep assignment/ownership for AI invoices, because legacy submission inbox has assignment.

Legacy parity findings from first pass:

- Legacy "screen-in" is the `review` event, moving `newly_submitted`/`resubmitted` to `in_review`.
- Legacy invoice approval is two-step: `in_review` -> `approved_pending` -> `approved_paid`.
- Legacy ineligible/reject appears to be from `in_review` to `ineligible`.
- Legacy admin permissions for approve/revision/finalize are broad: `admin` or `admin_manager`.
- Legacy assignment stores one assigned user for an application and replaces the prior assignment.

Admin menu/role cleanup:

- Current AI admin screens were added quickly into one menu; clean this up as part of the contractor MVP.
- Regular admin/operator menu should include operational work:
- AI invoice inbox/admin grid.
- AI invoice PDF viewer via links.
- Revision request workflow via links.
- Reports that admins/business users need.
- System admin/dev menu should include configuration and testing work:
- Rulesets admin/editor.
- Eligibility/admin code tables.
- Sessions admin.
- Users admin.
- Submission simulator.
- Hello AI/dev diagnostics.
- Deep inspection/version tools if they are too technical for regular admins.
- Prefer old-system home-page icons/cards for important workflows where that fits better than stuffing everything into nav.
- The new AI admin screens are in scope for polish/refactor because they are Stephen-created AI screens, not protected old-school screens.

Still needs practical verification:

- Whether legacy UI lets an admin request revisions from `in_review`, even though the backend flow appears to allow `finalize_revision_requests` from `in_review`.
- Whether contractors can see `approved_pending` and/or `approved_paid`.
- Whether `ineligible` includes visible reason text for contractors.
- Whether payment is actually performed in this app or merely recorded.

## Assignment Model

Business decision:

- AI invoices should have assignment/ownership like the legacy submission inbox.
- Reuse the legacy assignment concept: one assigned admin at a time, replace prior assignee when changed.

Implementation caution:

- The existing legacy assignment table is `application_assignments` and points to `permit_applications`.
- AI invoices live in `claims.invoices`, not `permit_applications`.
- Reuse the semantics and UI pattern, but implement an AI-specific physical table such as `claims.invoice_assignments`.

## Backend/API Work

Likely endpoints needed:

- Contractor AI invoice list endpoint.
- Contractor AI create-session endpoint.
- Contractor AI multi-PDF upload endpoint.
- Contractor AI retry endpoint.
- Contractor AI PDF/view endpoint.
- Contractor AI submit endpoint.
- Contractor AI upload fix +1 endpoint.
- Contractor AI supplement endpoint.
- Contractor AI pre-submit delete endpoint.
- Admin AI status transition endpoint(s).
- Admin AI assignment endpoint.

Security model:

- Existing Node/GenAI API calls are internal/trusted between Ruby and Node in the same OpenShift app.
- New contractor-facing Ruby endpoints need real authorization and thorough tests.
- Contractor endpoints must filter by the contractor associated to the current user, including primary contacts and contractor employees/secretaries.
- The exact contractor employee access model should clone legacy behavior.

Potential contractor ownership model:

- `sessions.submitter_id` stores the user who started the upload.
- Session/invoice also needs contractor/company ownership, either directly or through existing relationships.
- Contractor primary contact and employees should see the same invoices if the legacy system does that.
- Need to verify old search/filter behavior for contractor employees before implementation.

## Data/DDL Checklist

Already discussed or started locally:

- `claims.invoices.upgrade_type_id` -> `public.permit_classifications(id)`.
- Expose upgrade type in AI views/reporting.

Needed next:

- Update session table DDL to remove/comment session status concept.
- Update local DB to drop session status constraints/columns or leave compatibility columns nullable during transition.
- Update invoice status check constraint.
- Add `upgrade_type_id` to `claims.validationgenai_rulesets`.
- Add `enabled` to `claims.validationgenai_rulesets`.
- Add `ruleset_id` to `claims.invoice_versions`.
- Rename/re-seed `esp_default_v1` as a Windows and doors ruleset in insert scripts.
- Add indexes for status and upgrade-type query patterns.
- Add `claims.invoice_assignments`.

Stephen preference on DB shape:

- Avoid duplicate sources of truth unless it clearly helps.
- Check before adding DB fields that duplicate existing data.
- Local can be destroyed/rebuilt freely.
- Gold should be migrated only after local test harness plus manual testing.
- There is no existing AI production data to migrate.

## Test Harness Plan

This must be planned before coding work starts.

Principle:

- Manual testing is not enough. The AI contractor flow has too many states, retries, permissions, and file paths to trust by clicking around only.

Suggested layers:

- SQL smoke checks for seed/reference data.
- Rails request specs or script-based endpoint tests for contractor permissions and status transitions.
- Node service tests for OCR/GenAI retry-from-failed-step behavior where practical.
- End-to-end browser test for the happy path: MiniMe-style contractor uploads PDF, reviews, submits; admin sees row, screens in, approves pending, approves paid.
- End-to-end failure tests: upload failed, OCR failed, GenAI failed, missing first-class fields block submit, contractor upload fix reruns OCR/GenAI.
- Security tests: contractor cannot see another contractor's invoices; regular admin/system admin route visibility is correct; feature flag hides contractor AI tab.
- DDL/seed repeatability tests: local rebuild produces all required upgrade types, rulesets, test users, and views.

Practical local test identities:

- Contractor user like MiniMe1.
- Admin user like sbraniff.
- UX/BA tester Mandy, who may test as herself and also as a MiniMe-style contractor persona.

Potential test artifacts:

- `claims_ai_service_ddl/ai_contractor_portal_test_harness_plan.md`
- A script to validate DB seed/reference data.
- A script or spec suite to exercise Rails claims endpoints.
- A Playwright/Cypress-style browser smoke test if the project already has a preferred E2E tool.

## Suggested Implementation Order

1. Finalize this master plan and focused sub-plans.
2. Update DDL locally:

- session simplification
- invoice status check constraint
- ruleset upgrade type/enabled fields
- invoice version ruleset tracking
- assignment model

3. Update local seed/ruleset data:

- explicit Windows and doors ruleset
- no generic fallback/default behavior

4. Build the ruleset requirements matrix and Windows and doors ruleset plan from Better Homes BC requirements.
5. Build the first test harness layer for DDL/seed/API/ruleset smoke checks.
6. Update backend models/services:

- remove session status writes from AI code
- choose ruleset by invoice upgrade type
- store ruleset on invoice version
- add/clean status transitions
- add contractor authorization

7. Add contractor AI tab behind feature flag.
8. Add AI variant choice screen with only Windows enabled.
9. Add contractor multi-PDF upload screen.
10. Add contractor AI invoice list/grid.
11. Add contractor PDF viewer/actions.
12. Add contractor submit blocker for required first-class fields.
13. Update admin AI status labels/actions to mirror legacy.
14. Expand automated harness/tests for happy path and failure paths.
15. Draft first-pass contractor/admin guide material for the implemented screens.
16. Test locally end-to-end with MiniMe1, sbraniff, and Mandy.
17. Migrate to Gold after local harness and manual testing pass.

## Rollback/Decommission Plan

Feature flag rollback:

- Turn off `AI_CONTRACTOR_INVOICES_ENABLED`.
- Contractor AI tab disappears.
- Existing AI admin/dev screens can remain accessible to Stephen/system admins if needed for cleanup.

Data rollback:

- Since there is no existing AI production data yet, early local iteration can be destructive.
- Once Gold has data, prefer additive migrations and disabled UI over destructive rollback.
- If the pilot pauses after Gold data exists, keep AI tables/data but hide contractor entry points.

Decommission after transition:

- If AI replaces old-school invoice submission later, route and tab consolidation should be a separate project.
- Do not attempt to blend old and AI invoice records through a single database view during v1 unless business reporting absolutely requires it.

## Not Doing In V1

- Mixed image/PDF invoice upload for invoice files. Invoice upload is PDF only in v1.
- One PDF containing multiple invoices.
- Contractor batch submit.
- Contractor-visible session management.
- Contractor prior-version comparison.
- OCR/GenAI on supplements.
- Manual editing of extracted AI fields by contractor.
- Custom supervisor send-back workflow beyond what old system already supports.
- Audit history for every AI status transition.
- Any permanent changes to old-school screens/logic.

## Implementation Verification Items

These are not business-design blockers, but they must be verified while implementing.

1. Verify legacy contractor employee access rules and clone them for AI invoice endpoints.
2. Verify whether legacy UI allows revision requests from `in_review`, because backend flow appears to allow it but one manual path showed disabled pencils.
3. Verify contractor/admin visibility for `approved_pending`, `approved_paid`, and `ineligible` reason text.
4. Verify whether payment is actually performed in the app or only recorded by status.
5. Sequence admin menu cleanup around the contractor happy path without over-engineering it.

## Working Glossary

- AI invoice: A record in the new `claims` schema representing one uploaded contractor invoice PDF.
- Session: A technical upload grouping/container, not a business workflow.
- Upgrade type: The invoice variant/domain, backed by legacy `SubmissionVariant` classifications.
- Ruleset: The GenAI instructions and validation rules for one upgrade type.
- Submit: Contractor hands one reviewed AI invoice to admin.
- Fix +1: Contractor uploads a replacement/corrected invoice PDF, creating a new invoice version and rerunning OCR/GenAI.
- Supplement: Supporting document tied to an invoice; not OCR/GenAI processed in v1.
