# Admin PDF Viewer Inline Revision Workspace Plan

## Plan Status

Planned and implemented on 2026-07-22. Automated service/request coverage, targeted lint, and the
frontend build pass. The browser acceptance walkthrough remains a final local UX check.

This work builds on the implemented durable `revision_issues`, `revision_rounds`, and
`revision_issue_comments` workflow. It must preserve the current contractor PDF viewer behavior.

## Goal

Make the admin PDF viewer a single, cohesive revision workspace:

- Perform all revision editing beside the relevant rule or field in the main review panel.
- Convert the secondary Revision panel into a read-only snapshot and navigator.
- Automatically create pending admin work items for rule results selected by their registry
  workflow-management policy.
- Keep manual plus controls for every rule and field.
- Never show a closed issue in the admin Revision snapshot if that issue was never sent to the
  contractor.
- Continue showing closed issues that were previously sent to the contractor.
- Preserve contractor visibility, response, and history behavior end to end.

## Settled Product Decisions

### Main admin review panel

- The existing rule and field accordions become the only editing surface.
- A matching revision issue is rendered inline below its current rule or field evidence.
- Inline controls retain the existing capabilities:
  - select the contractor-facing recommendation;
  - edit and save the admin comment;
  - reset an editable draft;
  - close with an allowed disposition and required disposition explanation;
  - delete an eligible unsent issue;
  - review prior admin/contractor exchanges.
- The global `Send to contractor` action moves into the main workspace.
- Sending remains disabled until every unresolved issue has a complete saved admin recommendation.

### Rule plus controls

- Keep the plus control on every rule, including workflow-managed rules that were automatically
  given an issue.
- A normal blue plus means no issue currently exists and creates an optional issue.
- An existing-issue plus remains a plus, but uses a visibly different treatment and an adjacent
  status indication.
- Clicking an existing-issue plus must not create a duplicate. It expands, focuses, and scrolls to
  the existing inline editor.
- Administrators can therefore create an issue for a rule even when its evaluated result is not
  mandatory under the rule's policy.

### Field plus controls

- DI fields, invoice located fields, and supporting-document located fields remain manually
  initiated.
- There is no automatic workflow-policy creation for fields.
- A field plus creates the issue and then opens its inline editor.
- Clicking the distinct existing-issue plus focuses the existing editor rather than creating a
  duplicate.

### Read-only Revision snapshot

- The current secondary Revision panel becomes read-only.
- It shows unresolved issues first and previously contractor-visible resolved issues second.
- It contains no comment, remedy, close, delete, or send controls.
- It may retain read-only chronological history and source-navigation/focus controls.
- Clicking a currently matched item focuses the corresponding inline editor in the main panel.
- A sent, resolved issue whose source is no longer rendered remains in the snapshot as history.

The snapshot visibility predicate is:

```text
show = issue is unresolved OR issue was sent to the contractor at least once
hide = issue is closed AND issue was never sent to the contractor
```

`pending_admin_review` and `open` are unresolved. A closed issue was sent when at least one of its
comments belongs to a revision round whose `admin_sent_at` is populated.

Do not implement this as only `status != closed_no_contractor_action_required`. That status is the
normal internal-only closure, but an issue can also become `closed_as_withdrawn` before or after it
was sent. Actual sent history is the authoritative distinction.

### Unmatched open revisions

- Add an `Unmatched open revisions` area at the bottom of the main review workspace.
- It contains unresolved issues whose stable identity cannot be matched to a currently rendered
  rule or field.
- These issues remain fully editable so a package-version change cannot strand required work.
- Previously sent, resolved unmatched issues remain available in the read-only snapshot but do not
  need an inline editor.

## Workflow-Managed Rule Creation

### Eligibility

Use the existing effective registry policy and runtime result selection represented by
`Claims::InvoiceVersionRulecheck.admin_workflow_managed`:

| Registry policy | Automatically managed results |
| --------------- | ----------------------------- |
| `not_managed`   | none                          |
| `fail_only`     | fail                          |
| `warn_and_fail` | warn and fail                 |
| `all_results`   | pass, info, warn, and fail    |

The current code-rule or GenAI-rule registry configuration remains authoritative. This plan does
not add a policy snapshot column.

### Creation behavior

- Add an idempotent `EnsureManagedIssues` service for the current invoice version.
- For each eligible rulecheck without a durable logical issue, create one issue through the
  existing issue-creation path.
- New issues begin as `pending_admin_review`, displayed to admins as `Awaiting admin decision`.
- Reuse the existing stable rule identity:
  - rule key;
  - originating invoice upgrade type ID.
- Preserve the exact originating runtime rulecheck UUID for audit and source navigation.
- Create the deterministic initial admin draft through the existing draft builder.
- Never create issues for fields through this service.
- Never reopen or duplicate a closed logical issue automatically.
- Make retries and concurrent requests safe through service-level checks plus existing database
  uniqueness constraints.

### Handoff trigger

- Add an explicit admin-only reconciliation endpoint, for example:

```text
POST /api/claims/admin/invoices/:invoice_id/revision_issues/ensure_managed
```

- Run the ensure service as part of each explicit contractor-to-admin handoff:
  - initial contractor submission of the current analyzed package;
  - contractor submission of a completed revision response for the current package.
- Do not create managed issues merely because formal rule analysis completed. The contractor may
  autonomously upload and analyze one or more package fixes before ever handing the package to an
  admin.
- At handoff, use only the current/latest package version. This prevents obsolete issues from being
  created for an earlier package version that the contractor corrected during precheck.
- Invoke the explicit endpoint from the admin viewer only as an idempotent repair for legacy or
  interrupted handoffs that are already in `admin_review_inbox`.
- Keep the existing GET tracker endpoint read-only.
- Return the complete updated tracker payload so the frontend adopts one authoritative state.
- Treat repeated calls as successful no-ops after coverage is complete.
- Continue enforcing coverage in `SendRound`; reconciliation improves the workspace but does not
  replace the backend send gate.

## Stable Source Matching

The inline workspace must match issues to current sources by `source_identity`, not only by the
original runtime UUID.

Use these identities:

| Issue type                | Stable current-source identity           |
| ------------------------- | ---------------------------------------- |
| Rule                      | rule key + invoice upgrade type ID       |
| Invoice field             | field key + invoice upgrade type ID      |
| Supporting-document field | supporting-document type key + field key |
| DI field                  | DI field key                             |

The original runtime UUID remains the historical source reference. Stable identity is only for
matching the durable issue into the current package-version workspace.

If a supporting-document field identity is ambiguous because more than one current document has
the same type and field key, do not guess. Place the unresolved issue in `Unmatched open revisions`.

## Backend Changes

### Tracker serialization

Extend `Claims::RevisionIssues::SerializeTracker` with a computed boolean on every issue:

```text
was_sent_to_contractor
```

Compute it from associated issue comments and their revision rounds:

```text
any revision_issue_comment.revision_round.admin_sent_at is present
```

Use eager-loaded comments/rounds already available to the serializer and avoid per-issue queries.
Preserve current role-specific data protection:

- Admin tracker continues receiving all issues because the main workspace needs pending and
  internal audit state.
- Contractor tracker continues excluding `pending_admin_review` and
  `closed_no_contractor_action_required`.
- Contractor tracker continues returning only sent rounds.
- Contractor source details remain redacted as currently implemented.

The read-only admin snapshot performs the closed-and-never-sent exclusion using the serialized
boolean. The admin main workspace may still use an internally closed issue to mark its source and
show its admin-only outcome.

### Managed-issue reconciliation

- Add the idempotent ensure service.
- Add the admin endpoint and route.
- Reuse `CreateIssue`, `EnsureDraftRound`, `SourceIdentity`, and
  `BuildAdminCommentDraft` rather than duplicating lifecycle behavior.
- Limit mutation to invoices that can legitimately accept admin revision work.
- Return clear conflict/validation errors without partially creating a batch.
- Prefer one transaction around the reconciliation batch while retaining retry safety.

### No schema changes

This change requires no new tables, columns, foreign keys, or status values.

Sent history comes from `revision_rounds.admin_sent_at`; logical source identity already exists on
`revision_issues`; registry workflow policy already exists on the rule registries.

## Frontend Changes

### State ownership

- Extract or add an admin inline revision-workspace hook/component responsible for:
  - ensuring managed issues;
  - loading/adopting tracker data;
  - indexing issues by stable identity;
  - maintaining admin comment and close drafts;
  - saving, resetting, closing, deleting, and sending;
  - exposing focus targets and unmatched issues.
- Keep shared tracker data types stable for the contractor components. If types move out of
  `revision-tracker.tsx`, update both admin and contractor imports together.
- Keep one tracker payload as the source of truth so the inline editors and snapshot cannot drift.

### Inline editors

- Render the matching editor directly below each rule or field.
- Use status badges to distinguish:
  - awaiting admin decision;
  - ready to send/open;
  - awaiting contractor;
  - contractor responded;
  - resolved.
- Ensure save and close mutations update both the inline editor and snapshot immediately.
- Preserve disabled/read-only behavior when the invoice is owned by the contractor or has moved
  beyond first-level admin review.

### Snapshot component

- Replace the editable `RevisionTracker` rendering in the admin secondary panel with an
  admin-specific read-only snapshot.
- Apply the explicit visibility predicate before rendering counts or sections.
- Do not count hidden closed-never-sent issues in the snapshot total or resolved count.
- Present unresolved and resolved sections with clear counts.
- Retain history access without exposing mutation controls.

## Contractor Cohesion Requirements

The contractor viewer must remain behaviorally unchanged:

- Automatically created `pending_admin_review` issues are invisible.
- An issue becomes contractor-visible only after `SendRound` marks it `open` and stamps
  `admin_sent_at` on the round.
- Contractor remedies remain limited to the existing supported values:
  - correct and re-upload invoice;
  - upload supporting document;
  - provide attestation;
  - provide explanation.
- Manually selected passing or informational rules become visible after they are sent.
- `closed_no_contractor_action_required` issues remain absent, and their source identities continue
  suppressing raw program-requirement display on the contractor side.
- Previously sent issues remain visible after a contractor-facing closing disposition.
- Stable identity matching and existing unmatched outstanding/resolved contractor sections remain
  intact.

## Implementation Sequence

1. Add `was_sent_to_contractor` to tracker serialization and its TypeScript type.
2. Add serializer/request coverage for role visibility and sent-history edge cases.
3. Add the idempotent managed-rule reconciliation service and admin endpoint.
4. Add service/request coverage for the policy matrix, identity, and retry behavior.
5. Introduce the admin inline revision-workspace state layer.
6. Wire stable-identity issue matching into every rule and field accordion.
7. Add the distinct existing-issue plus behavior and focus/scroll handling.
8. Render unmatched unresolved issues in the main workspace.
9. Move all admin editing and `Send to contractor` into the main workspace.
10. Replace the secondary editable tracker with the read-only snapshot and its visibility filter.
11. Run automated backend, frontend build/lint, and end-to-end workflow testing.
12. Perform the browser-based admin/contractor acceptance walkthrough against local data.

## Automated Testing

### Service specifications

Add coverage for:

- every registry policy/result combination in the eligibility matrix;
- code-rule and GenAI-rule reconciliation;
- exact runtime UUID retention plus stable identity storage;
- distinct issues for the same rule key in different upgrade contexts;
- retry idempotency;
- concurrent reconciliation safety;
- no automatic field issue creation;
- no duplicate when a matching unresolved issue already exists;
- no automatic reopening when a matching logical issue is already closed;
- rejection/no-op outside an eligible admin workflow state;
- transaction rollback when any batch member cannot be created.

### Serializer specifications

Cover all combinations relevant to the snapshot:

| Issue state/history                                | Admin tracker receives issue | Admin snapshot shows issue | Contractor tracker receives issue |
| -------------------------------------------------- | ---------------------------- | -------------------------- | --------------------------------- |
| `pending_admin_review`, never sent                 | yes                          | yes                        | no                                |
| `open`, sent                                       | yes                          | yes                        | yes                               |
| `closed_no_contractor_action_required`, never sent | yes                          | no                         | no                                |
| contractor-facing closed status, previously sent   | yes                          | yes                        | yes                               |
| `closed_as_withdrawn`, never sent                  | yes                          | no                         | no                                |
| `closed_as_withdrawn`, previously sent             | yes                          | yes                        | yes                               |

Also verify:

- `was_sent_to_contractor` is true only when an associated round has `admin_sent_at`;
- a draft follow-up comment does not falsely mark a never-sent issue as sent;
- contractor payloads contain only sent rounds;
- contractor source redaction and suppressed identities remain unchanged.

### Request specifications

Add coverage for:

- authorized admin reconciliation;
- unauthorized and contractor access rejection;
- correct invoice scoping;
- complete tracker response after reconciliation;
- repeated endpoint calls returning the same issue IDs;
- send coverage still rejecting missing or incomplete admin decisions;
- existing create/save/reset/delete/close/send endpoints continuing to work after the frontend
  refactor.

### Frontend verification

- Run the TypeScript/Vite production build.
- Run lint on changed frontend files, or the full frontend lint command if the repository baseline
  permits it.
- Verify the TypeScript contract for `was_sent_to_contractor` and the contractor imports.
- Confirm no admin mutation control remains in the read-only snapshot component.
- Confirm snapshot counts use the filtered set.

## End-to-End Workflow Testing

The repository currently has no Playwright or Cypress suite. Implement the workflow-level portion
as automated Rails request specs spanning real services and database records, then complete the UI
portion with a documented browser walkthrough. Do not introduce a new browser framework solely for
this change without a separate decision.

### Automated end-to-end request scenario

Build one request-spec scenario that exercises the complete exchange:

1. Create an invoice in `admin_review_inbox` with:
   - one workflow-managed rule result;
   - one optional unmanaged rule result;
   - one manually selectable field.
2. Call managed reconciliation and verify exactly one `pending_admin_review` rule issue is created.
3. Call reconciliation again and verify no duplicate issue/comment/round is created.
4. Fetch the contractor tracker and verify the pending issue is absent.
5. Save the admin remedy/comment and send the round.
6. Fetch the contractor tracker and verify the issue and sent round are now visible.
7. Save a contractor response and submit it to the admin.
8. Close the issue with a contractor-facing disposition.
9. Verify the admin snapshot predicate retains it because it has sent history.
10. Verify the contractor tracker retains it as resolved.

Add companion end-to-end branches:

- Internally close a second pending issue as `closed_no_contractor_action_required`; verify it is
  absent from both the admin snapshot filtered set and contractor tracker.
- Withdraw an invoice with an unsent pending issue; verify the resulting
  `closed_as_withdrawn` issue is absent from the snapshot and contractor tracker.
- Withdraw after an issue was sent; verify the resolved issue remains in both histories.
- Create a manual rule issue for an unmanaged result and a manual field issue; verify both can be
  edited and sent through the same path.

### Browser acceptance walkthrough

Use the local admin and contractor portals with a controlled invoice and record the results:

1. Open the admin PDF viewer and confirm managed rule issues appear automatically without a manual
   plus click.
2. Confirm the existing-issue plus is visibly different, remains a plus, and focuses the inline
   editor without duplication.
3. Confirm ordinary rule and field plus controls create and focus new inline issues.
4. Confirm all editing controls are in the main workspace and the secondary Revision snapshot is
   read-only.
5. Internally close one unsent issue and confirm it disappears from the snapshot immediately while
   the source rule remains visible in the main admin workspace.
6. Send another issue and confirm it appears in the contractor `Attention Required` workspace.
7. Respond as the contractor, return to admin, and confirm the same durable issue and history are
   shown inline.
8. Close that sent issue and confirm it remains in the admin snapshot's resolved section and the
   contractor's resolved history.
9. Load a newer package version where an unresolved source no longer renders and confirm it appears
   in `Unmatched open revisions` with working admin controls.
10. Scroll and switch panel modes to confirm focus navigation, sticky controls, PDF/image display,
    and accordion behavior remain usable.

## Suggested Verification Commands

```bash
docker compose exec -T app bundle exec rspec \
  spec/services/claims/revision_issues/workflow_spec.rb \
  spec/requests/claims/invoice_revision_workflow_spec.rb

docker compose exec -T app npm run build

docker compose exec -T app npx eslint \
  app/frontend/components/domains/invoice-versions/index.tsx \
  app/frontend/components/shared/claims/revision-tracker.tsx \
  app/frontend/components/shared/claims/contractor-inline-revision-issues.tsx
```

Adjust the lint file list for any newly introduced admin workspace/snapshot files.

## Acceptance Criteria

- All admin revision mutations occur in the main review workspace.
- The secondary Revision panel is read-only.
- Every rule result selected by its registry policy gets exactly one pending work item.
- Fields remain manual.
- Every rule and field retains a plus control.
- Clicking an existing-issue plus focuses the existing inline editor and never duplicates it.
- Unmatched unresolved issues remain editable.
- The admin snapshot shows every unresolved issue.
- The admin snapshot shows a closed issue only when it was actually sent to the contractor.
- Snapshot counts exclude closed-never-sent issues.
- The contractor never sees pending or internally closed unsent issues.
- Previously sent, subsequently closed issues remain visible to both roles as read-only history.
- Existing contractor response, save-later, upload, submit, and withdrawal behavior is not
  regressed.
- Targeted service/request specs, production frontend build, and the full end-to-end workflow
  scenario pass.

## Risks and Guardrails

- Do not infer sent history solely from terminal status; use `admin_sent_at` history.
- Do not filter internal closed issues out of the complete admin tracker payload because the main
  workspace may need them for source status/audit. Filter only the snapshot presentation.
- Do not perform mutations in the GET tracker endpoint.
- Do not match current sources only by their runtime UUID; corrected package versions produce new
  runtime rows.
- Do not guess between ambiguous supporting-document fields.
- Do not fork the contractor and admin lifecycle rules. Both views must continue using the same
  durable issues and round history.
- Do not change schema or registry key uniqueness as part of this UI/workflow change.

## Implementation Record

Implemented behavior:

- `EnsureManagedIssues` runs transactionally at actual contractor-to-admin handoffs and is exposed
  through an idempotent admin repair endpoint.
- The admin viewer uses stable source identities, inline editors, distinct existing-issue plus
  controls, unmatched-open fallback editing, unsaved-change warnings, and a send confirmation.
- The secondary admin Revision panel is a read-only snapshot filtered by actual sent history.
- Tracker serialization exposes sent-history booleans/timestamps without schema changes.
- The contractor tracker now requires actual sent history for every returned issue, including the
  `closed_as_withdrawn` edge case.
- Contractor response progress is summarized as saved, unsaved, and ready to submit.

Verification completed on 2026-07-22:

- 30 targeted revision workflow service/request examples passed.
- Targeted frontend lint passed with no new errors or warnings in the new workspace component.
- The Vite frontend build passed.
