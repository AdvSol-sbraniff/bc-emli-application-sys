# Workflow Management Inline Admin Review Extension Plan

## Plan Status

Planned on 2026-07-20. This document describes the next extension of the implemented
`revision_issues` / `revision_rounds` / `revision_issue_comments` workflow. It does not replace the
implemented design record in `invoice_revision_workflow_plan.md`.

No implementation described below has been completed merely by creating this plan.

## Goal

Extend workflow management from an exception-oriented revision tracker into a complete,
rule-centred admin review system while preserving the contractor revision experience.

The extension must:

- Treat a `revision_issue` as a durable invoice work item, not necessarily as proof that something
  is wrong.
- Require first-level admins to acknowledge every rule result selected by that rule's workflow
  policy, including pass/green and info/blue results when configured.
- Keep the admin's editing beside the exact rule or field being reviewed.
- Turn the admin right panel into a read-only work navigator rather than a second editing surface.
- Keep the contractor right panel as the editable response surface for open contractor-visible work.
- Retain field-level work items for attestation and extraction edge cases.
- Preserve one durable issue and its ordered comments across repeated contractor exchanges.
- Keep revision rounds as a hidden grouping/audit concept.
- Preserve `claims.invoices.status` as the source of truth for who currently owns the invoice.

## Core Mental Model

### Revision issue

A revision issue is an invoice work item associated with exactly one rule result or runtime field.
It may represent:

- a required admin review of a passing or informational rule;
- a warning or failure requiring admin analysis;
- a contractor correction, document request, explanation, or attestation;
- an admin exception;
- a manually identified field problem.

Every issue must have at least one `revision_issue_comment`. Services must create the issue and its
initial comment in one transaction; a bare issue row is invalid application state.

### Issue comments

Comments hold the ordered work performed on an issue:

- the system-prepared initial admin analysis draft;
- the admin's saved action and contractor-facing explanation;
- contractor responses;
- later admin follow-up;
- the final admin closure explanation.

### Revision rounds

Rounds remain hidden from ordinary admin and contractor navigation. They group comments that belong
to one admin review/possible contractor exchange. An admin-only review batch may remain unsent when
all of its work items are closed internally. The UI must not ask either role to select a round.

## Settled UX Decisions

### Admin rule controls

- Remove the plus icon from every rule row.
- Render a compact `Admin review` control directly below every rule result.
- Keep the compact row visible for managed and unmanaged results so the interaction pattern is
  consistent.
- Expand comment/action controls only when the current decision requires editing.
- Use the rule's runtime result and policy to determine whether a completed decision is mandatory.
- Do not make admins edit the same issue in both the left and right panels.

### Admin field controls

- Retain the plus icon beside runtime fields.
- The plus means `Open a work item about this field`.
- Clicking the plus creates an issue and initial admin comment atomically, then replaces the plus
  with the inline work-item editor/status.
- Attach a new field issue to the exact runtime row UUID selected by the admin.
- DI, invoice second-class, and supporting-document fields continue to use their appropriate exact
  runtime source route.

### Admin right panel

- Make the right-side Revision panel read-only.
- Show open work items first as a compact navigator.
- Clicking an item scrolls to and highlights its inline rule/field editor in the left panel.
- Show progress such as `Reviewed 32 of 47`, `12 remaining`, and `3 open contractor items`.
- Put closed items in a collapsed `Resolved (n)` section.
- Preserve an issue-history drawer for chronological comments and hidden round markers.
- If the corresponding source is no longer rendered in the current package version, retain the
  read-only history entry and navigate to the best deterministic current source only when there is
  exactly one logical match.

### Contractor right panel

- Continue to use the Revision panel as the contractor's editable response surface.
- Show only open issues in the primary section.
- Show previously exposed closed issues in a collapsed `Resolved (n)` section.
- Never expose internal managed pass/info confirmations that were closed without being sent.
- Continue to require a saved complete response for every open issue in the current sent exchange.
- Preserve the history drawer and chronological admin/contractor comments.

### Panel modes

Preserve the existing three modes in both PDF viewers:

- fullscreen/no right panel;
- Revision panel;
- document/image/PDF panel.

## Rule Workflow Policy

Extend both `claims.code_rules.admin_workflow_policy` and
`claims.genai_rules.admin_workflow_policy` to allow:

- `not_managed`
- `fail_only`
- `warn_and_fail`
- `all_results`

Use the UI label `All results` or `Workflow-managed for all results`, not colour names. The runtime
rule vocabulary is `pass`, `info`, `warn`, and `fail`; green/blue/yellow/red are presentation only.

The policy/result matrix is:

| Policy          | pass     | info     | warn     | fail     |
| --------------- | -------- | -------- | -------- | -------- |
| `not_managed`   | optional | optional | optional | optional |
| `fail_only`     | optional | optional | optional | required |
| `warn_and_fail` | optional | optional | required | required |
| `all_results`   | required | required | required | required |

Required means the first-level admin cannot screen the invoice into four-eyes review until the
work item has a saved admin action and has reached an allowed closed outcome.

## Policy Snapshot

Add `admin_workflow_policy` to `claims.invoice_version_rulechecks` as the policy snapshot used when
that runtime result was produced. Populate it from the owning code or GenAI registry row when the
rulecheck is created.

Reasons:

- Later configuration edits must not silently change the review obligation of an already processed
  invoice.
- Historical audits must be able to explain why a pass/info rule required admin work.
- Coverage calculations should not depend on joining to mutable current configuration.

For existing local runtime rows, backfill from the current corresponding rule registry. New clean
Gold builds receive the column through `2_create_schema.sql`; Gold data is rebuilt through the normal
weekly process.

## Work-Item Creation

### Required rule results

Add an idempotent post-rulecheck synchronization service/run step after the final code and GenAI
rulechecks for an invoice version are available and before the invoice becomes first-level-review
ready.

For every runtime rulecheck whose policy/result combination is required:

1. Find the durable logical issue for the invoice and rule identity.
2. If no issue exists, create an open `revision_issue` linked to the exact runtime rulecheck UUID.
3. Ensure the current hidden draft round exists.
4. Create the initial admin comment with:
   - no saved admin action;
   - deterministic draft text from the rule's reason, evidence, expected result, and source quote;
   - no human author yet.
5. Do not create duplicates when the synchronization step is retried.

This explicit pipeline step replaces manual rule plus clicks. It must be represented as an ordinary,
retry-safe run step rather than as a mutation hidden inside a viewer GET request.

### Unmanaged rule results

Do not automatically create an issue. The inline row displays `No workflow review required` and
allows the admin to voluntarily choose an action. Saving a voluntary action creates the issue and
initial admin comment atomically.

### Field results

Do not automatically create work items for all fields. The admin uses the field plus icon to create
one when a runtime value or extraction is problematic.

## Admin Actions and Required Inputs

The current `admin_recommended_remedy` vocabulary describes only contractor requests. It cannot
represent a managed green/info confirmation. Replace or broaden it into an admin action concept.

Proposed `admin_action` values:

- `confirmed_no_contractor_action`
- `correct_and_reupload_invoice`
- `upload_supporting_document`
- `provide_attestation`
- `provide_explanation`
- `record_no_workflow_action`

`record_no_workflow_action` is allowed only when the runtime policy/result combination is not
workflow-managed. The UI should disable or omit it and explain why when the result is managed. The
backend must reject an artificial request that attempts to bypass required workflow review.

For every required managed result, the following are mandatory before the decision is complete:

- a saved `admin_action`;
- a nonblank admin comment/analysis;
- the authenticated admin user;
- the save timestamp.

The deterministic draft may prepopulate the comment, but the admin must deliberately select an
action and save. Merely viewing the rule is not acknowledgement.

### Managed pass/info normal path

The normal action is `confirmed_no_contractor_action`. Save the admin comment and close the issue in
the same transaction using a new terminal status such as `closed_as_confirmed`. The item moves into
the collapsed Resolved section and is never sent to the contractor.

### Optional unmanaged acknowledgement

If an admin deliberately records `record_no_workflow_action`, create the work item/comment and close
it using a status such as `closed_as_reviewed_no_workflow_action`. Leaving an unmanaged rule untouched
creates no record and does not block review.

### Contractor follow-up path

The four existing contractor-facing actions leave the issue open. They continue into the hidden
draft round and become contractor-visible only when the admin sends the open work.

### Final dispositions

Preserve the existing final closing outcomes:

- corrected documentation accepted;
- attestation accepted;
- exception granted;
- issue withdrawn.

Every final disposition remains allowed regardless of the contractor's selected response method.
The final admin comment is mandatory.

## Data Model Extension

### `claims.revision_issues`

Retain the current source FKs and add only the audit information that cannot safely be reconstructed
from mutable configuration:

- `workflow_required boolean NOT NULL DEFAULT false`
- terminal status values:
  - existing values;
  - `closed_as_confirmed`;
  - `closed_as_reviewed_no_workflow_action`.

`workflow_required=true` identifies automatically policy-required rule work. Manual field issues and
voluntary unmanaged-rule issues use `false`.

Do not add a separate stage/owner status. Invoice status continues to answer who owns the work.

### `claims.revision_issue_comments`

- Rename or replace `admin_recommended_remedy` with `admin_action`.
- Preserve contractor response fields as separate contractor-only fields.
- Add `author_user_id` referencing `public.users.id` so per-item admin and contractor work is
  attributable.
- Permit `author_user_id` to be null only for an unsaved system-generated admin draft or historical
  local rows that cannot be safely backfilled.
- Require it when an admin action or contractor response is formally saved.
- Continue requiring nonblank `comment_text` for persisted comments.
- Preserve the rule that admin fields and contractor fields cannot be mixed on one comment.

The current `author_type` remains useful for simple role rendering, while `author_user_id` proves who
performed the work.

### `claims.revision_rounds`

No new stage or status column. Continue to use the hidden round as the grouping for comments. Allow a
round containing only internally closed review items to remain unsent as an audit grouping.

## Rule and Field Source Identity

### Rules

Use the runtime rulecheck UUID as the exact source. Continue durable matching across versions using
the rule business identity and upgrade type.

### Second-class invoice fields

`claims.invoice_version_located_fields.id` remains the exact runtime source UUID. Treat `field_key`
as a globally meaningful business key across code and GenAI registries.

For logical matching across versions use:

- `field_key`
- `invoice_upgrade_type_id`

Do not include `source_engine` in logical work-item identity. Keep `source_engine` only as provenance.

### Field registry uniqueness

Keep `code_located_fields` and `genai_located_fields` separate because their attributes, ownership,
and child relationships differ:

- Code fields are trusted application/database facts and have no upgrade-type prompt mapping.
- GenAI fields have `genai_located_field_upgrade_types`, which assigns upgrade types and prompt
  order.

When an admin creates or renames a GenAI located field:

- reject a key already present in `genai_located_fields`;
- reject a key already present in `code_located_fields`;
- show a direct field-key collision error.

Code-generated keys remain developer-owned and do not need a cross-table database mechanism.

Do not add a cross-table database registry or trigger. Do not use `source_engine` to make duplicate
business keys appear valid.

### Runtime duplicate handling

Do not rely on the currently commented runtime database uniqueness constraint. Enforce the LLM
payload contract in the application before inserting runtime GenAI rows.

## GenAI Located-Field Output Contract

Strengthen the invoice GenAI system/user instructions to match the already-clear supporting-document
instruction:

- Return exactly one `located_fields[]` object for every configured field task in User record 1.
- Copy each configured `field_key` exactly.
- Do not return duplicate or unlisted keys.
- When evidence is absent, return the configured key with null value/evidence/location and zero
  confidence.
- When a task requests multiple components, represent them together in the one configured field
  value rather than returning duplicate rows.

Before `ApplyGenaiLocatedFields` inserts rows:

1. Load the expected enabled field keys for the current upgrade type.
2. Reject duplicate returned keys.
3. Reject unconfigured returned keys.
4. Reject missing configured keys, or deterministically materialize their null rows if that is the
   chosen ingestion convention.
5. Insert exactly one row per expected key for that invoice version and upgrade type.

Use a focused failure subtype/message so malformed field output is visible as a GenAI contract
failure rather than a generic database error.

## Backend Service Changes

Extend the `Claims::RevisionIssues` services rather than creating a second workflow subsystem.

Expected responsibilities:

- Determine whether a runtime rulecheck is workflow-required from its snapshotted policy/result.
- Synchronize required rule work items after rule processing.
- Build the deterministic initial admin analysis draft.
- Serialize inline workflow state keyed by exact rulecheck/field source IDs.
- Save an inline admin action and comment.
- Atomically close managed pass/info confirmations.
- Atomically create voluntary unmanaged-rule work when the admin elects an action.
- Preserve field-plus issue creation.
- Enforce action availability based on workflow-required state.
- Calculate progress and missing required decisions.
- Preserve contractor send/response and final closure behaviour.
- Record `author_user_id` from the authenticated request; never accept an arbitrary client-supplied
  author.

Update `ReviewCoverage` and `ApprovalGate` so completion requires:

- every workflow-required runtime rulecheck has its required durable work item;
- every required work item has a saved admin action/comment attributable to an admin;
- no revision issue remains open before screen-in/four-eyes review;
- internally confirmed pass/info items count as completed;
- untouched unmanaged results do not block.

## API Shape

Keep invoice-scoped APIs. Avoid one request per rule.

The admin invoice-version payload or one companion workflow payload should provide:

- issue/work-item state indexed by runtime rulecheck UUID and runtime field UUID;
- current required/optional state;
- saved action/comment and editable draft state;
- capability flags and reasons;
- total/complete/remaining/open-contractor counts;
- read-only open and resolved navigator summaries.

Admin mutation endpoints must support:

- save/close an automatically created required-rule item;
- create and save a voluntary unmanaged-rule item;
- create and save a manual field item;
- continue an open contractor issue;
- close an issue with final disposition.

The contractor API remains issue-centred and should not expose internal unsent confirmations.

## Frontend Architecture

### Shared state

Load workflow state once in the admin PDF viewer and keep it in a parent-level store/hook. Do not let
every rule row fetch its own tracker payload.

Introduce focused components such as:

- `AdminRuleWorkflowControl`
- `AdminFieldWorkflowControl`
- `AdminWorkflowNavigator`
- the existing contractor tracker/editor, simplified to open plus collapsed resolved sections.

The exact component names may differ, but editing state must have one owner so the left editor,
right navigator, progress counts, attention highlighting, and approval controls cannot drift.

### Rule row states

At minimum support:

- `Review required`
- `Not reviewed`
- `Unsaved changes`
- `Confirmed — no contractor action`
- `Ready to send`
- `Awaiting contractor`
- `Contractor responded`
- final resolved status.

Required managed items should be visually clear without turning all passing rules into warning
colours. Use badges/state text; preserve rule-result colour for the rule result itself.

### Field row states

- Plus icon when no field work item exists.
- Inline editor/status after creation.
- No duplicate plus when an open or resolved work item already exists for the exact/logical field.
- Exact source UUID controls the original polygon and historical navigation.

### Responsive behaviour

Keep the default inline control to one compact row. Expand text areas and detailed controls only for
the actively edited rule/field. Verify the layout on the small-screen configuration that motivated
the read-only right navigator.

## Existing Behaviour to Remove or Replace

- Remove rule-level plus icons and their click handlers.
- Remove admin editing controls from `revision-tracker.tsx` right-panel rendering.
- Remove admin duplication of issue reason/comment between right-panel read-only text and inline
  editable text.
- Replace `admin_recommended_remedy` wording where the broader admin action is used.
- Replace current coverage text such as `workflow-managed failing rule` with result-neutral wording
  such as `workflow-managed rule result`.
- Stop including `source_engine` in invoice-field `SourceIdentity`.
- Remove the dead commented runtime uniqueness constraint after application validation is in place,
  so the DDL no longer suggests the wrong identity.

## Migration and Compatibility

### Clean-build DDL

Update `claims_ai_service_ddl/2_create_schema.sql` with:

- `all_results` in both rule policy checks;
- snapshotted policy on runtime rulechecks;
- issue audit/closing extensions;
- comment admin-action and author extensions;
- updated comments documenting issue-as-work-item semantics;
- removal of the obsolete commented located-field uniqueness definition.

Update normalized/code rule seeds only as needed. Existing rule policy defaults remain unchanged
unless explicitly configured; the extension must not unexpectedly make every historical rule
`all_results` by default.

### Local live alteration

Provide an idempotent local SQL alteration that:

- adds/backfills the rulecheck policy snapshot;
- adds new issue statuses/columns;
- migrates existing `admin_recommended_remedy` values to `admin_action` unchanged;
- adds nullable historical author references;
- preserves all current rounds, issues, comments, statuses, and source FKs;
- can be rerun safely.

Do not rebuild Gold outside the user's normal explicit Gold rebuild request.

## Implementation Phases

### Phase 1: schema and policy contract

1. Add `all_results` to code and GenAI rule models, DDL checks, admin API, editor dropdowns, history,
   and tests.
2. Add the runtime rulecheck policy snapshot and populate it in code and GenAI rulecheck writers.
3. Extend issue/comment schema and models for workflow-required state, confirmation closures,
   admin actions, and attributed authors.
4. Add the idempotent local alteration and verify clean DDL.

### Phase 2: located-field identity and output integrity

1. Add GenAI field-key collision validation against both field registries on create and rename.
2. Strengthen the invoice located-field prompt contract.
3. Add expected-key/duplicate/unlisted/missing validation before persistence.
4. Remove `source_engine` from field logical identity and update focused tests.

### Phase 3: automatic required-rule work items

1. Implement the idempotent synchronization service.
2. Add it as an explicit post-rulecheck pipeline step.
3. Create required issues and deterministic initial draft comments transactionally.
4. Add retry, reanalysis, multi-upgrade, and no-duplicate coverage.

### Phase 4: inline admin editing

1. Add workflow state to the admin viewer data model.
2. Render the compact control below every rule.
3. Remove all rule plus icons.
4. Move admin comment/action/closure editing out of the right tracker and into rule/field rows.
5. Retain and adapt field plus creation.
6. Add scroll/highlight navigation from right-panel items to left-panel sources.

### Phase 5: role-specific right panels

1. Build the admin read-only open navigator and progress header.
2. Add collapsed Resolved history.
3. Simplify the contractor panel to editable open issues plus collapsed Resolved history.
4. Confirm internal pass/info confirmations never leak to the contractor.

### Phase 6: gates, transitions, and end-to-end hardening

1. Replace current warn/fail-only review coverage with the full policy matrix.
2. Require attributed saved admin decisions for all required items.
3. Preserve contractor round submission and invoice status ownership.
4. Verify screen-in remains blocked until all required work is complete and every issue is closed.
5. Exercise full first-level back-and-forth followed by second-level four-eyes approval.

## Test Plan

### Schema and models

- Clean DDL builds from scratch.
- Local alteration is idempotent and preserves existing workflow history.
- All four policy values validate for code and GenAI rules.
- Runtime rulechecks retain their policy snapshot after registry policy changes.
- New issue closure statuses validate.
- Saved admin/contractor comments require the authenticated author.
- A revision issue is never committed without at least one comment through supported services.

### Workflow policy matrix

Test every policy against every result:

- `not_managed` with pass/info/warn/fail;
- `fail_only` with pass/info/warn/fail;
- `warn_and_fail` with pass/info/warn/fail;
- `all_results` with pass/info/warn/fail.

Verify required combinations create exactly one issue and optional combinations create none until the
admin voluntarily acts.

### Automatic synchronization

- Initial run creates required work items/comments.
- Retry creates no duplicates.
- Multiple upgrade types preserve separate rule occurrences.
- Reanalysis and a new invoice version reuse or create durable issues according to logical identity.
- Closed work is not silently reopened.
- Pipeline failure reports a focused step error and does not leave bare issues.

### Admin decisions

- Managed pass/info cannot use `record_no_workflow_action`.
- Managed pass/info confirmation saves comment/author and atomically closes the issue.
- Managed warn/fail requires action and comment.
- Contractor-facing actions remain open and become sendable.
- Unmanaged rules do not block when untouched.
- Voluntary unmanaged action creates a work item.
- Final closure requires a final comment and permits every final disposition.

### Field workflow

- Field plus creates one issue/comment for the exact runtime UUID.
- Duplicate plus/action is prevented.
- Invoice, supporting-document, and DI field sources retain exact page/polygon history.
- Logical current-version matching excludes `source_engine` and remains deterministic.

### Located-field contract

- GenAI field creation/rename rejects collisions with GenAI and code keys.
- One returned row per configured key succeeds.
- Duplicate, unconfigured, and missing keys follow the selected explicit failure/materialization rule.
- Multi-component fields remain one configured row.
- Multiple upgrade types may use the same global field key in their separate upgrade contexts.

### API and authorization

- Only first-level authorized admins may save admin actions.
- `author_user_id` always comes from authentication.
- Contractor endpoints cannot see unsent/internal confirmation issues.
- Cross-invoice source/issue/comment access is rejected.
- Capability flags and progress counts match backend gates.

### Frontend

- No rule plus icons remain.
- Every rule displays the compact admin review control.
- Managed/unmanaged states and disabled explanations are correct.
- Field plus icons remain and are replaced after creation.
- Admin right panel is read-only and navigates to the inline editor.
- Both panels default open items first and keep Resolved collapsed.
- All accordions begin collapsed where intended.
- Tooltips dismiss correctly.
- Fullscreen/Revision/document modes still work.
- Small-screen layout remains usable.
- Focused ESLint/Prettier checks and production Vite build pass.

### End-to-end scenario

1. Process an invoice containing pass, info, warn, and fail rule results.
2. Configure examples across all four WFM policies.
3. Verify the post-rulecheck step creates only required rule work items.
4. Open the admin viewer and verify every rule has an inline control and no rule has a plus.
5. Confirm managed pass/info items internally and verify they move to Resolved.
6. Leave unmanaged results untouched and verify they do not block.
7. Voluntarily open work for one unmanaged rule.
8. Open one field work item using its plus icon.
9. Send only open contractor-facing issues.
10. Respond as contractor and submit back to first-level admin.
11. Close remaining issues with several final dispositions.
12. Verify the admin navigator has no open work and Resolved contains complete attributed history.
13. Screen into four-eyes review and complete second-level approval.
14. Reload both viewers after every transition to verify persistence and visibility.

## Non-Goals

- Do not replace `conversation_messages` or internal notes.
- Do not expose rounds as a selectable user concept.
- Do not move first-level contractor back-and-forth to the second-level reviewer.
- Do not add an invoice workflow-stage column.
- Do not make every located field automatically workflow-managed.
- Do not unify code and GenAI located-field registries.
- Do not add cross-table field-key database triggers or a canonical one-to-one key registry.
- Do not implement Excel export; only preserve clean source/result/action data for a future export.
- Do not alter the legacy non-Claims CHEFS revision system.

## Definition of Done

- Rule plus icons are gone; every rule has one compact inline admin review control.
- Field plus icons remain and open exact-source field work items.
- `all_results` can require pass/info/warn/fail review per rule.
- Required rule work items are created by an explicit idempotent pipeline step.
- Managed pass/info decisions are attributed, commented, and closed without contractor exposure.
- Admin editing exists only beside the relevant rule/field.
- The admin right panel is a read-only open-work navigator with collapsed Resolved history.
- The contractor right panel edits open exposed issues and shows collapsed resolved history.
- Coverage and approval gates enforce every required decision and every open issue.
- Field keys are globally collision-checked at GenAI definition creation/rename.
- Invoice GenAI output is validated as exactly one row per configured located-field task.
- `source_engine` remains provenance but is not logical field/work-item identity.
- Existing revision history survives the local alteration.
- Focused model, service, request, frontend, production-build, and complete end-to-end tests pass.
- The implementation record is appended to this plan with files changed, migration outcome, commands,
  test counts, and any deliberately deferred items.
