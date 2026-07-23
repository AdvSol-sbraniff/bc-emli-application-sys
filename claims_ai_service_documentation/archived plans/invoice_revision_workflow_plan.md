# Claims Revision Issues, Rounds, and Comments Plan

## Implementation Status

Implemented and verified locally on 2026-07-16. The former two-table
`revision_requests` / `revision_request_entries` workflow has been replaced end to end. This
document remains the design record and implementation handoff for the replacement.

## Goal

Replace revision-request cycles containing disposable entry copies with a durable issue-centred
workflow:

- One `revision_issue` represents one problem for the lifetime of an invoice.
- An issue remains the same database row through repeated admin/contractor exchanges.
- One `revision_round` groups a single admin-to-contractor exchange.
- `revision_issue_comments` form the ordered conversation for an issue and identify the round in
  which each comment occurred.
- The first-level admin owns all contractor back-and-forth.
- The second-level admin only performs the final four-eyes approval after all issues are closed.
- `claims.invoices.status` remains the source of truth for who currently owns the invoice.
- `revision_issues.status` records only whether and how the issue was finally closed.
- Rounds and comments do not have workflow-status columns.

## Business Workflow

### Initial submission

1. The contractor submits an analyzed package.
2. The invoice enters `admin_review_inbox`.
3. The first-level admin reviews the rule results and located fields.
4. For each workflow-managed problem, the admin creates or reuses one durable revision issue.
5. The admin creates the first round explicitly and adds an admin recommendation comment for each
   issue being sent to the contractor.
6. Sending the round sets `admin_sent_at` and moves the invoice to
   `contractor_revision_inbox`.

### Contractor response

1. The contractor sees the entire suite of issues ever exposed to them, including closed issues.
2. Open issues in the latest sent round accept contractor response comments.
3. Each contractor comment has a response-method pulldown and explanatory text.
4. An attestation response may also contain one asserted scalar value because the parent issue
   already identifies the field being asserted.
5. Formal contractor submission sets `contractor_response_submitted_at` and moves the invoice back
   to `admin_review_inbox`.

### First-level admin follow-up or closure

For every returned open issue, the first-level admin does one of two things:

- Continue the issue: explicitly create the next round, add another admin recommendation comment,
  and send that round to the contractor.
- Close the issue: add a final admin comment in the current/latest round and update the parent
  issue's terminal status in the same transaction.

There is no intermediate per-round disposition. A disposition exists only when the durable issue is
finally closed.

### Four-eyes approval

1. The first-level admin may not screen the invoice into second-level review while any issue remains
   `open` or any required workflow-managed failing rule has no issue.
2. When every issue is closed, the first-level admin uses the existing `screen_in` transition.
3. The invoice moves from `admin_review_inbox` to `in_review`.
4. The second-level admin performs final four-eyes review and may move it to `approved_pending` or
   return it to the first-level workflow according to the existing business transition rules.

## Invoice Status Ownership

Do not add another workflow-stage field.

| Invoice status              | Meaning in revision workflow                                                    |
| --------------------------- | ------------------------------------------------------------------------------- |
| `admin_review_inbox`        | First-level admin is preparing recommendations or reviewing returned responses. |
| `contractor_revision_inbox` | Contractor owns the current response.                                           |
| `in_review`                 | Second-level/four-eyes review only.                                             |

Technical upload/OCR/GenAI statuses may occur while a contractor uploads replacement evidence. The
formal contractor submission still returns the invoice to `admin_review_inbox`.

## Final Data Model

### `claims.revision_rounds`

Purpose: lightweight grouping for one admin-to-contractor exchange.

Columns:

- `id`
- `invoice_id`
- `invoice_version_id`: package current when the round was created
- `round_number`: sequential within the invoice
- `admin_sent_at`
- `contractor_response_submitted_at`
- timestamps

Deliberately excluded:

- status
- stage
- admin-completed timestamp
- cancelled timestamp
- separate contractor-response invoice-version FK
- generated or editable aggregate text

The latest round is the greatest `round_number`. An unsent draft round may be deleted. A sent round is
immutable. The contractor response version remains discoverable from append-only invoice-status
transitions.

### `claims.revision_issues`

Purpose: durable identity of one workflow-managed problem for an invoice.

Columns:

- `id`
- `invoice_id`
- `issue_type`
- exactly one original runtime source reference
- `status`
- timestamps

Issue types:

- `rule`
- `invoice_field`
- `supporting_document_field`
- `di_field`

Issue statuses:

- `open`
- `closed_via_corrected_documentation`
- `closed_via_attestation`
- `closed_via_exception`
- `closed_as_withdrawn`

The status does not say who owns the issue; invoice status already answers that. A closed issue is
immutable. If a materially new problem later appears, create a new issue rather than rewriting the
closed issue's history.

The issue stores no copied rule key, source engine, extracted value, polygon, evidence, reason, page,
upgrade type, disposition text, or disposition timestamp. The source runtime row and ordered comments
provide those facts. For a closed issue, its last associated round is considered the closing round.

### `claims.revision_issue_comments`

Purpose: ordered admin/contractor exchange for a durable issue.

Columns:

- `id`
- `revision_issue_id`
- `revision_round_id`
- `author_type`: `admin` or `contractor`
- `admin_recommended_remedy`: admin-only pulldown
- `contractor_response_method`: contractor-only pulldown
- `comment_text`
- `contractor_asserted_value`: optional scalar value for an attestation
- timestamps

Admin recommended-remedy values:

- `correct_and_reupload_invoice`
- `upload_supporting_document`
- `provide_attestation`
- `provide_explanation`

Contractor response-method values:

- `corrected_invoice_uploaded`
- `supporting_document_uploaded`
- `attestation_provided`
- `explanation_provided`
- `unable_to_resolve`

An ordinary admin request comment has an admin remedy and no contractor method. A contractor response
has a contractor method and no admin remedy. The final admin closure comment may have both pulldowns
null because the terminal outcome is stored on `revision_issues.status`.

All human-authored workflow text, including the final admin explanation, lives in this table. There is
no disposition-comment column on the issue.

## Parent/Child Relationships

```text
claims.invoices
├── claims.revision_rounds
└── claims.revision_issues
    └── claims.revision_issue_comments

claims.revision_rounds
└── claims.revision_issue_comments
```

Comments therefore resolve the many-to-many historical relationship between rounds and issues while
also allowing multiple comments for the same issue in one round.

## Source Navigation

The issue retains the exact runtime source selected when it was opened:

- `invoice_version_rulecheck_id`
- `invoice_version_located_field_id`
- `supporting_document_located_field_id`
- or the first-class DI invoice-version/key pair

No polygon or extracted value is duplicated. Opening the source follows the runtime reference to the
original invoice version, document, page, and polygon.

For later package versions, the viewer may locate the corresponding current field/rule through the
original source's semantic key, but historical source navigation always opens the exact original
runtime occurrence.

## Draft Creation and Deterministic Text

- Creating an issue from a rule or field is insert-only and idempotent by logical source.
- Creating a round is an explicit admin action; clicking a source icon must never silently create a
  new round.
- The first admin recommendation comment is initialized deterministically from existing rule reason,
  evidence, source quote, field label, and value data.
- No GenAI call is made to draft revision text.
- Reset restores the admin comment from the deterministic source presenter.
- A continuing admin recommendation belongs to the new round it opens.
- Closed historical issues and sent historical comments are read-only.

## Admin Viewer

Remove the current revision-request cycle selector and entry editor from the admin PDF viewer.

The replacement Revision tracker shows:

- One flat issue list for the invoice, not one selected request at a time.
- Open issues first, followed by closed issues, with deterministic ordering.
- Friendly issue name and current issue status.
- An accordion or drawer per issue showing every comment chronologically.
- Round markers inside the timeline rather than a round selector at the top.
- Admin recommendation pulldown and comment box for open issues in a draft latest round.
- Add-source action from the unchanged left panel.
- Explicit Create round, Send to contractor, and Delete unsent draft controls.
- Final closure controls that create the final admin comment and update issue status atomically.
- Disabled rather than disappearing controls, with concise explanations.
- Source-navigation action opening the original document/page/polygon.

The first-level admin may create another round only after the contractor submitted the latest sent
round. The next round starts with the still-open issues selected by the admin. Closed issues are not
copied into the new round; they remain visible through the invoice-level issue list.

## Contractor Viewer

Remove the current revision-request cycle selector and entry response editor from the contractor PDF
viewer.

The replacement uses the same issue-centred tracker:

- Show every issue that has appeared in a sent round.
- Keep closed issues visible with their final status and complete comment timeline.
- Permit response comments only for open issues included in the latest sent round.
- Contractor response-method pulldown and comment box are role-specific.
- Show the asserted-value input only for an attestation on a field-level issue.
- Final submission requires a complete response for every open issue in the latest sent round.
- Internally withdrawn draft issues that were never sent are not exposed.

## APIs and Services

Replace the `Claims::RevisionRequests` namespace with `Claims::RevisionIssues` services responsible
for:

- tracker serialization
- explicit round creation
- issue creation from a runtime source
- deterministic admin-comment draft construction/reset
- admin comment create/update/delete while the latest round is unsent
- sending a round
- contractor comment save
- contractor response submission
- issue closure with a final admin comment
- unsent round deletion
- review-coverage calculation
- approval gating
- source presentation/navigation

Use invoice-scoped endpoints. Do not preserve old response shapes merely to reduce frontend work; the
new API should describe issues, rounds, and comments directly.

Suggested endpoints:

```text
GET    /api/claims/admin/invoices/:invoice_id/revision_issues
POST   /api/claims/admin/invoices/:invoice_id/revision_rounds
DELETE /api/claims/admin/invoices/:invoice_id/revision_rounds/:round_id
POST   /api/claims/admin/invoices/:invoice_id/revision_issues
POST   /api/claims/admin/invoices/:invoice_id/revision_issues/:issue_id/comments
PATCH  /api/claims/admin/invoices/:invoice_id/revision_issue_comments/:id
DELETE /api/claims/admin/invoices/:invoice_id/revision_issue_comments/:id
POST   /api/claims/admin/invoices/:invoice_id/revision_rounds/:round_id/send
POST   /api/claims/admin/invoices/:invoice_id/revision_issues/:issue_id/close

GET    /api/claims/contractor/invoices/:invoice_id/revision_issues
PATCH  /api/claims/contractor/invoices/:invoice_id/revision_issues/:issue_id/comment
POST   /api/claims/contractor/invoices/:invoice_id/submit_to_admin
```

## Approval and Submission Gates

### Sending a round

- Invoice must be in `admin_review_inbox`.
- Round must be the latest round and unsent.
- At least one open issue must have an admin recommendation comment in that round.
- Every issue included for contractor action must have a nonblank recommendation and remedy.
- The round may include already-closed internal exceptions for history, but they require no contractor
  response.

### Contractor submission

- Invoice must be in `contractor_revision_inbox` or the permitted completed-pipeline state used after
  replacement uploads.
- Round must be the latest sent round and not previously submitted.
- Every open issue included in the round must have a complete contractor response.
- Closed issues require no response.
- Successful submission records the round timestamp and returns the invoice to
  `admin_review_inbox`.

### Screen-in/four-eyes gate

- No issue may remain `open`.
- No required workflow-managed failing rule may lack a revision issue.
- Warning rules are required only when their individual `admin_workflow_policy` says so.
- Historical rounds and closed issues do not block.

## Schema Replacement and Local Data Migration

### Clean-build DDL

- Remove `claims.revision_request_entries`.
- Remove `claims.revision_requests`.
- Add `claims.revision_rounds`.
- Add `claims.revision_issues`.
- Add `claims.revision_issue_comments`.
- Update conversation comments and schema documentation that refer to the old formal tables.

### Live-local migration

The migration must be idempotent and preserve local test history:

1. Create the three new tables.
2. Convert each old request into a round using its invoice, reviewed version, chronological sequence,
   sent timestamp, and response timestamp.
3. Group repeated old entries into durable issues by logical source identity.
4. Convert old admin request text into admin recommendation comments.
5. Convert old contractor response text/type/asserted value into contractor comments.
6. Convert final accepted/exception outcomes into final admin comments and terminal issue statuses.
7. Convert nonfinal/more-information entries into still-open issues carried by later rounds.
8. Validate counts and invoice/source ownership.
9. Remove old tables only after successful conversion.

No Gold deployment is performed directly; Gold receives the clean schema during the normal rebuild.

## Cleanup Scope

- Remove old models `RevisionRequest` and `RevisionRequestEntry`.
- Remove old `Claims::RevisionRequests` services.
- Remove old controller routes and response shapes.
- Remove old frontend types and selected-cycle state.
- Remove request/entry-specific copy such as “revision request entries”.
- Update invoice and invoice-version associations.
- Update invoice/package destruction to include the new tables without attempting to destroy append-only
  status history directly.
- Preserve the unrelated legacy CHEFS revision system outside the Claims namespace.
- Preserve `conversation_messages`; ordinary messages remain separate from formal issue comments.

## Test Plan

### Database

- Clean schema builds from scratch.
- Live-local migration is idempotent.
- Three-table FK and enum checks behave correctly.
- Multiple comments per issue/round are allowed and ordered.
- Duplicate round numbers per invoice are rejected.
- Exactly one original source route is required for each issue type.
- Invoice deletion cleans up rounds, issues, and comments safely.

### Service/model

- Explicit round creation; source clicks do not create rounds.
- Issue creation and logical duplicate prevention.
- Deterministic admin draft/reset.
- Send validation and invoice transition.
- Contractor response save and asserted-value rules.
- Contractor submission ignores closed issues and requires all open current-round issues.
- Admin continuation creates comments in the next explicit round.
- Admin closure inserts final comment and changes issue status atomically.
- Closed issue immutability.
- Review-coverage and approval gate use issues rather than old entries.
- Exact source navigation remains correct.

### Request/API

- Admin and contractor authorization and visibility.
- Admin sees all draft/sent/historical issue information.
- Contractor sees only issues exposed by a sent round.
- Historical comments are read-only.
- Invalid cross-invoice issue/round/comment access is rejected.
- Status-transition endpoints enforce first-level and four-eyes ownership.

### Frontend

- Production TypeScript build.
- Focused lint/type checks for changed files.
- Admin viewer creates a round, adds issues/comments, sends, reviews, and closes.
- Contractor viewer sees all issues, responds only to current open issues, and submits.
- Closed issues remain visible in chronological history.
- No round selector or old request-entry editor remains.
- Document/revision/fullscreen panel modes continue to work.
- Tooltips dismiss correctly and disabled controls explain their gate.

### End-to-end scenario

1. Create an invoice with several managed failing rules.
2. First-level admin creates round 1 and durable issues.
3. Admin closes several by exception and sends the remaining issues.
4. Contractor responds using corrected documentation and attestation paths.
5. First-level admin closes one issue and continues another into explicit round 2.
6. Contractor sees the complete issue suite, including closed history, and responds to round 2.
7. First-level admin closes the final issue.
8. Approval gate allows `screen_in` only now.
9. Second-level admin completes four-eyes approval.
10. Reload both viewers after every transition to verify persisted state and role visibility.

## Definition of Done

- The clean-build schema contains only the three new formal revision tables.
- The local database is migrated without losing existing workflow history.
- No Claims runtime code references `claims.revision_requests` or
  `claims.revision_request_entries`.
- Both viewers use the issue-centred chronological tracker.
- First-level admin owns all revision exchanges; second-level admin remains four-eyes only.
- Required failing rules are gated by durable issue coverage.
- Closed issues remain visible to both roles after exposure.
- Database, Rails, request, frontend, and end-to-end tests pass.
- This plan records the final files changed, migration result, commands run, and test outcomes.

## Implementation Record

Completed on 2026-07-16:

- Replaced the old clean-build DDL with the three-table schema and verified it in a fresh temporary
  database containing the application's public schema.
- Added and ran the idempotent local conversion script twice. The old Claims tables no longer exist
  locally; only `revision_rounds`, `revision_issues`, and `revision_issue_comments` remain.
- Replaced the old models, controller, routes, service namespace, serializers, submission gates,
  approval gates, and package-cleanup references.
- Rebuilt both PDF-viewer revision panels around one flat durable issue list with chronological
  comments and inline round markers. Removed selected-cycle state and old request-entry APIs.
- Kept Create round explicit. Source buttons add issues only to an existing unsent round.
- Preserved the three right-panel modes in both viewers: fullscreen, revision issues, and document.
- Added service and request coverage for multi-round issue continuity, contractor response,
  exception-before-send behavior, incomplete response IDs, corrected-document version enforcement,
  closed-issue immutability, deletion of unsent rounds, rule-level workflow policy, and four-eyes
  approval gating.

Verification completed:

- Fresh-schema build: passed; exactly the three new `revision_*` tables were created.
- Local conversion script, first and second run: passed.
- Focused Claims regression suite: 22 examples, 0 failures.
- Rails autoload/eager-load check: passed.
- Focused ESLint: 0 errors in the two viewers and shared tracker; pre-existing unused-variable
  warnings remain in the large viewer files.
- Vite production build: passed.
- A broader Claims test sweep reaches one unrelated pre-existing failure in
  `reanalyze_advice_spec.rb`: that spec still supplies the absent
  `invoice_versions.genai_admin_advice` attribute. The revision workflow tests are not implicated.
