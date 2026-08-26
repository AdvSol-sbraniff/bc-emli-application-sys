# Claims Lifecycle State Cleanup — Structure-First Plan

## Plan status

Planning, the mandatory second-pass simplicity review, implementation, and
local verification were completed on 2026-08-12. Gold was not changed.

## Objective

Make each persisted state answer exactly one question:

- `claims.invoices.status`: who owns the invoice and what business stage is it
  in?
- `claims.ingest_runs`: what kind of processing run is this, and did the whole
  run finish?
- `claims.ingest_step_runs`: what logical operation did this attempt execute,
  and did that attempt finish?
- classifier evidence tables: what did the classifier identify?
- normalized located-field and rulecheck tables: what facts and validation
  results were produced?

Remove processing phase snapshots, inferred run identity, duplicate lifecycle
columns, and historical compatibility values. Local and Gold are development
databases with no external users, so the canonical rebuild DDL can change
directly. No migration or backward-compatibility layer is required.

## Scope and authorization

This change includes:

1. Canonical claims DDL and rebuild-order changes.
2. Rails models, services, jobs, controllers, blueprints, and read models.
3. Claims SQL views.
4. Claims React status, diagnostics, invoice-viewer, and grid consumers.
5. Focused and end-to-end test updates.
6. A clean local claims-schema rebuild and local test-data/package execution.

This change does not include:

- rebuilding or modifying Gold during implementation;
- changing program eligibility rules, GenAI prompts, or WFM policy;
- changing OCR, classifier, or GenAI provider selection;
- changing public users, contractors, or other legacy `public.*` records;
- adding a workflow framework, event bus, or generic orchestration DSL.

Gold will receive the new schema only through a separately requested rebuild
after the matching application image is available.

## Evidence behind the cleanup

The audit established:

- `claims.invoices.status` currently allows 21 values and mixes upload, OCR,
  GenAI, failure, and business workflow concepts.
- `upload_queued` is the invoice default even though the DDL comment explicitly
  says it is not used.
- the current structure-first ingest implementation already treats
  `claims.ingest_runs` as the authoritative end-to-end processing lifecycle and
  `claims.ingest_step_runs` as attempt history;
- the current working tree no longer writes several historical invoice phase
  values that the older deployed code wrote;
- neither local nor Gold contains an ingest run with `partial` status, and no
  production writer creates it;
- all current local and Gold ingest/supporting documents have
  `classification_status='classified'`;
- classifier completion/failure is already represented by a classifier step,
  while classification results are represented by `document_kind`,
  `supporting_document_type_id`, confidence, reasons, and `classified_at`;
- GenAI `invoice_version_upgrade_types` rows duplicate GenAI step status and
  normalized rulecheck/located-field output;
- `invoice_versions.genai_result` and `genai_raw_json` duplicate normalized
  rulechecks and retained step payloads;
- `aggregate_advice` does not construct persisted contractor advice. Contractor
  advice is built from current normalized rulechecks when requested.

## Target persistence model

### 1. Invoice business lifecycle

`claims.invoices.status` will allow exactly:

```text
contractor_precheck
admin_review_inbox
contractor_revision_inbox
in_review
approved_pending
approved_paid
ineligible
contractor_withdrawn
```

The default will be `contractor_precheck`.

Meaning:

- `contractor_precheck`: contractor owns the invoice before first submission;
- `admin_review_inbox`: submitted and awaiting first-level admin work;
- `contractor_revision_inbox`: admin sent issues to the contractor;
- `in_review`: first-level review completed and second-level review owns it;
- `approved_pending`: approved, awaiting payment/closeout;
- `approved_paid`: paid/closed successfully;
- `ineligible`: business decision that the claim is ineligible;
- `contractor_withdrawn`: contractor ended the claim.

The following invoice statuses will be removed:

```text
upload_queued
upload_in_progress
upload_failed
upload_complete
ocr_queued
ocr_in_progress
ocr_failed
ocr_complete
genai_queued
genai_in_progress
genai_failed
genai_complete
package_needs_correction
technical_failure
```

`genai_complete` is replaced by `contractor_precheck`; the other removed values
belong to run/step execution or run failure.

`claims.invoices.status_subtype`, its index, and transition-history subtype
columns will be removed. There are no business-state subtypes. Failure subtypes
belong to ingest runs and failed step attempts.

### 2. Ingest-run lifecycle and identity

`claims.ingest_runs.status` will allow exactly:

```text
queued -> running -> succeeded | failed
```

`partial` will be removed.

Add required `run_kind`:

```text
initial_upload
fix_upload
rules_rerun
```

Add nullable `invoice_id` with a foreign key to `claims.invoices` and
`ON DELETE SET NULL`. Every normal run receives it at creation. It becomes null
only when contractor-upload cleanup deliberately removes a failed shell
invoice while retaining run diagnostics.

`resolved_invoice_version_id` remains the successful version produced or
validated by the run.

`failure_category` remains constrained to:

```text
package_needs_correction
technical_failure
```

These values are failure categories, not invoice statuses.

### 3. Failure catalogue ownership

Rename:

```text
claims.invoice_status_subtypes -> claims.ingest_failure_subtypes
Claims::InvoiceStatusSubtype   -> Claims::IngestFailureSubtype
3_insert_invoice_status_subtypes.sql
  -> 3_insert_ingest_failure_subtypes.sql
```

Use column names `failure_category` and `failure_code`. The current names
`failure_status` and `failure_status_subtype` will be removed from both run and
step tables because a failure category is not a second lifecycle status.
Preserve the existing
admin copy, contractor copy, retry guidance, enabled flag, and subtype values.

Application responsibility remains split into two ordinary modules:

- failure classification/diagnostic extraction from exceptions and steps;
- failure catalogue validation and user-safe copy lookup.

They will live under `Claims::Ingest`, not `Claims::Invoices`.

### 4. Step-attempt lifecycle and logical step names

Keep step statuses:

```text
queued -> in_progress -> succeeded | failed
```

Retries continue to create new attempt rows. Derived diagnostic states such as
`retrying` and `recovered` remain read-model concepts, never persisted values.

Replace 18 step types with ten:

| Canonical step type           | Replaces                                                               |
| ----------------------------- | ---------------------------------------------------------------------- |
| `stage_package`               | `upload_package_stage`, `fix_upload_package_stage`                     |
| `read_document`               | `ocr_read`, `fix_ocr_read`                                             |
| `classify_document`           | `classifier_files`, `fix_classifier_files`                             |
| `extract_supporting_document` | `supporting_document_extraction`, `fix_supporting_document_extraction` |
| `extract_invoice`             | `ocr_invoice`, `fix_ocr_invoice`                                       |
| `clone_evidence`              | `fix_clone_existing_evidence`, `ruleclone_clone_existing_evidence`     |
| `case_facts`                  | existing case-fact construction step                                   |
| `evaluate_genai_ruleset`      | `genai_common`, `genai_upgrade`                                        |
| `evaluate_code_ruleset`       | `code_common`, `code_upgrade`                                          |
| `finalize_validation`         | `aggregate_advice`                                                     |

The target columns distinguish repeated logical work:

- document steps: `ingest_document_id`;
- support extraction: `supporting_document_type_id`;
- GenAI/code rulesets: `invoice_upgrade_type_id`, including the registered
  `common` upgrade type;
- invoice extraction/finalization: `invoice_version_id`.

Workers will stop accepting legacy step-type arguments. They will own one
canonical step type each. Development queues will be drained/restarted rather
than retaining deserialization compatibility with old job signatures.

### 5. Document-classification output

Drop `classification_status` from:

- `claims.ingest_documents`;
- `claims.supporting_documents`.

Keep:

- `document_kind`, confidence, and reason;
- `supporting_document_type_id`, confidence, and reason;
- `supporting_document_routing_quality` and reason;
- `classified_at` on staging documents;
- classifier raw payloads and DI-read evidence.

Interpretation:

- no successful `classify_document` attempt / no `classified_at` means not yet
  classified;
- `document_kind='unknown'` means the classifier could not route it safely;
- a failed classifier attempt is represented by the failed step;
- routing quality describes evidence usability and remains model output.

### 6. Upgrade-type detection versus validation execution

`claims.invoice_version_upgrade_types` becomes classifier detection evidence
only.

Keep:

- invoice version and upgrade type foreign keys;
- classifier confidence;
- evidence text and explanation;
- page and polygon;
- classifier raw row JSON;
- timestamps.

Remove:

- `source_engine`;
- `call_status`;
- `result`;
- `admin_advice`;
- GenAI manifest rows and manifest upsert code;
- the call-status index.

The unique key becomes `(invoice_version_id, invoice_upgrade_type_id)`.

API terminology changes from `upgrade_type_results` to
`detected_upgrade_types`. No React consumer will filter classifier and GenAI
rows from the same array because GenAI rows will no longer exist.

### 7. Validation result and raw model output

Drop from `claims.invoice_versions`:

- `genai_result`;
- `genai_raw_json`;
- the associated result check constraint.

The canonical validation result is derived as the worst persisted normalized
rulecheck for an invoice version using severity:

```text
fail > warn > info > pass
```

Expose this read-only value as `validation_result` and
`latest_validation_result` in APIs/views. The admin AI dot and version diff use
that derived value.

Raw provider results remain in the relevant retained
`claims.ingest_step_runs.genai_results_json`; normalized located fields and
rulechecks remain the application evidence used by review and WFM.

`finalize_validation` remains a real fan-in boundary. It:

1. confirms every required GenAI ruleset logical target succeeded;
2. runs each required code ruleset once;
3. marks the finalization logical target succeeded;
4. requests run advancement.

It will not rebuild a raw aggregate, write an overall snapshot, or call the
contractor-advice presenter merely to store a boolean.

## Target ownership rules

### Invoice status writes

Only business actions write invoice status:

```text
CreateDraftBatch
  -> creates contractor_precheck

Contractor submit
  contractor_precheck | contractor_revision_inbox
  -> admin_review_inbox

Admin screen-in
  admin_review_inbox -> in_review

Admin approval
  in_review -> approved_pending -> approved_paid

Admin ineligible decision
  admin_review_inbox | in_review -> ineligible

Admin sends revision round
  admin_review_inbox -> contractor_revision_inbox

Contractor submits revision round
  contractor_revision_inbox -> admin_review_inbox

Contractor withdraws
  allowed active business stage -> contractor_withdrawn
```

No ingest worker, coordinator, retry handler, or run transition writes invoice
status.

### Run writes

`Claims::Ingest::RunTransition` remains the sole lifecycle writer for
`ingest_runs`. Its operations become:

```ruby
mark_running!(run:, total_files:)
mark_succeeded!(run:, total_files:)
mark_failed!(run:, total_files:, failed_files:, failure_category:,
             failure_code:, pipeline_error_code:,
             pipeline_error_description:)
```

It no longer accepts or synchronizes an invoice.

### Business-transition gate

Business transitions are rejected while the invoice has a queued or running
ingest run. The check belongs in the shared invoice transition service rather
than five controllers. This prevents submit, approval, revision movement, or
withdrawal while a new version is incomplete.

## Target call hierarchy

### Entry points

```text
1. Contractor initial upload ----\
                                   -> CreateDraftBatch(run_kind=initial_upload)
3. Admin contractor simulator ---/

2. Contractor fix upload --------\
                                   -> UploadFixPackage(run_kind=fix_upload)
4. Admin fix simulator ----------/

5. Admin rerun rules
  -> CreateRuleChangeRun(run_kind=rules_rerun)
```

Initial and fix uploads create `stage_package`; rule reruns create
`clone_evidence`.

### Run routing

```text
AdvanceRun
|- initial_upload -> AdvanceBundleRun
|- fix_upload     -> AdvanceBundleRun
`- rules_rerun    -> AdvanceExistingEvidenceRun
```

Routing never infers run kind from whether documents or specially named child
steps happen to exist.

### Bundle pipeline

```text
AdvanceBundleRun
  -> read_document per new ingest document
  -> classify_document per new ingest document
  -> resolve exactly one invoice PDF
  -> clone_evidence when fix evidence is retained
  -> extract_supporting_document per applicable support type
  -> extract_invoice once unless valid cloned invoice evidence is reused
  -> shared validation flow
  -> RunTransition.mark_succeeded!
```

Fix-specific decisions use `run.run_kind == 'fix_upload'`. The operation names
remain identical because the operation itself is identical.

### Shared validation pipeline

```text
ValidationScheduler.start!
  -> case_facts
  -> enqueue evaluate_genai_ruleset per required common/upgrade target

each ruleset completion
  -> AdvanceRunJob
  -> ValidationOutcome

all required GenAI targets succeeded
  -> ValidationScheduler.finalize!
  -> FinalizeGenaiValidationJob
     -> evaluate_code_ruleset per enabled common/upgrade target
     -> finalize_validation
     -> AdvanceRunJob

ValidationOutcome sees finalize_validation succeeded
  -> RunTransition.mark_succeeded!
```

## Backend implementation map

### Models

- `Claims::Invoice`: remove failure-state constants; add `ingest_runs`
  association.
- `Claims::IngestRun`: add `invoice` association plus run-kind/active/terminal
  constants and an `active` scope.
- `Claims::IngestFailureSubtype`: replace the invoice-named catalogue model.
- `Claims::InvoiceVersionUpgradeType`: classifier detection rows only.

### Ingest preparation

- `CreateDraftBatch`: create the shell invoice as `contractor_precheck`, create
  the initial run linked to it, and create canonical `stage_package` steps.
- `UploadFixPackage`: create linked `fix_upload` run and canonical steps.
- `CreateRuleChangeRun`: create linked `rules_rerun` run and canonical
  `clone_evidence` step without changing invoice business status.
- `CleanupFailedContractorUpload`: identify the shell through `run.invoice_id`,
  retain diagnostics, and allow the FK to become null when the shell is
  deleted.

### Orchestration

- `AdvanceRun`: route only by `run_kind`.
- `AdvanceBundleRun`: remove dynamic/prefixed step-type selection and
  `fix_run?` database inference.
- `AdvanceExistingEvidenceRun`: consume canonical preparation/validation
  targets.
- `ValidationOutcome` and `ValidationScheduler`: consume canonical step names.
- `RunTransition`: write only the run.
- retry, step-claim, step-outcome, diagnostics, and pipeline audit modules:
  update canonical step/run values without changing their responsibilities.

### Workers

- hardcode one step type per document/extraction worker;
- remove old optional compatibility arguments;
- make one GenAI ruleset job target `evaluate_genai_ruleset` and distinguish
  common/upgrade by `invoice_upgrade_type_id`;
- remove GenAI manifest writes;
- simplify finalization to code rules plus the fan-in success marker;
- move failure helpers to the ingest namespace.

### Controllers and presenters

- contractor run presentation resolves invoice through `run.invoice_id`;
- admin run APIs include `run_kind` and canonical step labels;
- invoice APIs expose `detected_upgrade_types` and `validation_result`;
- invoice grid filters `processing` and `failed` through the latest ingest run,
  not invoice business status;
- backend business actions rely on the shared active-run transition gate.

## SQL-view implementation map

`claims.v_current_invoice_versions`:

- remove raw/overall snapshot columns;
- add derived `validation_result` from normalized rulechecks.

`claims.v_invoice_grid`:

- remove invoice status subtype;
- expose `latest_validation_result`;
- expose latest ingest run ID, kind, status, failure category/code, and
  timestamps using the explicit `ingest_runs.invoice_id` relation;
- retain detected upgrade types from the classifier-only detection table.

`claims.v_ingest_runs`:

- expose run kind and linked invoice naturally through `ir.*`;
- keep contractor display and duration.

`claims.v_ingest_step_runs`:

- retain one row per physical attempt and readable target data;
- display canonical step types only.

Reporting and compatibility views will use `validation_result` and the reduced
invoice lifecycle. Deprecated aliases tied to removed physical columns will
not be recreated.

## React implementation map

### Shared invoice status copy

Reduce invoice status copy/options to eight business statuses and rename
`genai_complete` display semantics to `contractor_precheck`.

Processing and failure presentation comes from latest-run fields:

```text
queued/running                  -> Preparing AI Advice
failed/package_needs_correction -> Package Needs Correction
failed/technical_failure        -> Needs Technical Help
succeeded/no active failure     -> show invoice business status
```

This mapping is presentational and is not saved as invoice status.

### Admin invoice grid

- retain business-status filtering;
- map the existing synthetic `processing` and `failed` filter choices to latest
  run status on the server;
- render the AI dot from `latest_validation_result`;
- retain run diagnostics as a separate concept from invoice ownership.

### Contractor portal/review/fix screens

- use `contractor_precheck` wherever `genai_complete` currently gates review,
  fix, submit, or continue actions;
- rely on run presentation for active upload/fix feedback;
- do not inspect old OCR/GenAI invoice phase names;
- keep contractor conversation, revision workspace, and WFM behavior
  unchanged.

### Admin/contractor PDF viewers and version diff

- consume `detected_upgrade_types` directly;
- remove classifier-versus-GenAI filtering from the upgrade-type array;
- consume `validation_result` for version-level comparison;
- continue grouping normalized located fields and rulechecks by upgrade type.

### Ingest diagnostics

- display `run_kind`;
- replace old step labels with canonical operation labels;
- keep UUIDs in drawers, not grids;
- keep derived `retrying`/`recovered` attempt presentation.

## DDL and rebuild files

Expected canonical file changes:

- `claims_ai_service_ddl/2_create_schema.sql`;
- rename the failure-copy seed to
  `3_insert_ingest_failure_subtypes.sql`;
- `claims_ai_service_ddl/4_create_views.sql`;
- `claims_ai_service_ddl/README_REBUILD_ORDER.txt`;
- `claims_ai_service_documentation/claims_data_model.md`.

No archived patch script or migration will be added. The clean rebuild path is
the product for these development databases.

## State invariants

Database/application tests must enforce:

```text
invoice.status is always one of the eight business states
invoice has no processing/failure subtype column

run.kind is always initial_upload | fix_upload | rules_rerun
run.status is always queued | running | succeeded | failed
queued/running run has no terminal failure fields and completed_at is null
succeeded run has resolved_invoice_version_id and no failure fields
failed run has failure category/code and completed_at
terminal run cannot reopen

step.status is always queued | in_progress | succeeded | failed
step.type is always one of the ten canonical operation names
retry creates a new physical row
effective success absorbs historical failed attempts

invoice business status does not change because a run starts, retries,
succeeds, or fails
business transition cannot occur while a run for that invoice is active

upgrade detection rows are classifier evidence only
validation_result equals the worst normalized rulecheck
no persisted overall GenAI snapshot or GenAI manifest is required
```

## Testing plan

### 1. Static and schema-contract tests

- validate exact invoice, run, run-kind, step-status, and step-type constraints;
- assert removed columns/tables/status values do not exist;
- assert new foreign keys and `ON DELETE SET NULL` behavior;
- assert all active rebuild scripts reference the renamed failure catalogue;
- run the complete rebuild with `ON_ERROR_STOP=1`;
- verify every active view can be selected after rebuild.

### 2. Focused unit/service tests

- `RunTransition`: monotonic run-only transitions and failure fields;
- `TransitionStatus`: business transition allowed with no active run and
  rejected with queued/running run;
- `AdvanceRun`: all three run kinds and invalid-kind defense;
- `AdvanceBundleRun`: initial and fix phases using identical canonical steps;
- `AdvanceExistingEvidenceRun`: rules rerun and retry paths;
- `ValidationOutcome`/scheduler/finalizer: common plus multiple upgrade targets,
  code rules, failure, retry, duplicate delivery, and finalization;
- classifier application and cloned evidence without classification status;
- classifier-only upgrade detection replacement/cloning/scope guard;
- validation-result severity derivation;
- cleanup after failed contractor initial upload with retained run/step history
  and null run invoice FK.

### 3. Fault-injected processing tests

Force each path rather than relying on provider randomness:

- upload storage failure;
- OCR timeout followed by successful retry;
- unreadable OCR terminal failure;
- classifier malformed response followed by successful retry;
- unknown document kind/package correction;
- no invoice and multiple invoice packages;
- unsupported upgrade type;
- supporting-document extraction failure and retry;
- GenAI ruleset malformed output and retry;
- one upgrade ruleset terminal failure;
- code-rule exception;
- finalizer exception and retry;
- duplicate advancement and duplicate completed-worker delivery;
- cleanup error while preserving the original terminal failure.

For every case assert the invoice business state remains correct and the run,
not the invoice, owns processing/failure truth.

### 4. Five-entry-point journeys

Exercise exactly:

1. contractor initial upload;
2. contractor fix upload;
3. admin contractor simulator;
4. admin fix simulator;
5. admin rerun rules.

For each journey verify controller -> preparation service -> run kind ->
coordinator -> canonical steps -> final run -> API/React contract.

### 5. Multiple real invoice packages

Use at least the four current demo families:

- demo1 ASHP/wood/ventilation;
- demo2 ASHP/gas/health-and-safety;
- demo3 electrical service upgrade;
- demo4 heat-pump water heater.

Verify multi-file routing, classifier upgrade detection, supporting-document
promotion/extraction, invoice OCR, common and upgrade-specific validation,
derived validation result, contractor advice, and pipeline audit.

Provider calls may be deterministic doubles for exhaustive failure ordering,
but at least one local real-service smoke journey should traverse upload, OCR,
classifier, GenAI, normalized persistence, and read APIs when services are
available.

### 6. API and React tests

- contractor run presenter four states;
- invoice grid business/processing/failed filters;
- contractor portal status labels and action gates;
- admin PDF viewer and contractor PDF viewer data loading;
- version diff validation result;
- ingest run grid/drawer with run kind and canonical steps;
- TypeScript build and targeted lint.

### 7. Regression and runtime checks

- all Claims model/service/job/request specs;
- full Rails suite, recording unrelated failures without hiding them;
- Node unit/e2e tests and production build;
- frontend production build;
- RuboCop and Ruby syntax for changed files;
- `git diff --check`;
- local Rails and Claims Sidekiq restart;
- health endpoint and relevant read endpoints;
- SQL invariant audit against completed and failed runs;
- pipeline checker for every successful local package.

## Implementation order

1. Complete and record the required second-pass simplicity review.
2. Change canonical DDL, seed name/order, and views.
3. Change models and failure catalogue namespaces.
4. Change preparation services and explicit run identity.
5. Change run transitions, routing, coordinators, canonical step types, and
   workers.
6. Remove classification lifecycle duplication.
7. Remove GenAI manifests and overall snapshots; add derived validation result.
8. Change controllers, presenters, blueprints, and grid filters.
9. Change React consumers.
10. Update tests and documentation.
11. Rebuild local claims schema.
12. Execute the complete testing plan and record evidence in this file.

## Acceptance criteria

- The database contains one business state machine, one run state machine, and
  one step-attempt state machine with no overlap.
- All five processing entry points set explicit run kind and share canonical
  downstream operations.
- No code infers fix/rerun identity from a child step or document presence.
- Processing/retry/failure cannot overwrite invoice business ownership.
- No obsolete invoice phase state, `partial` run, prefixed step name,
  classification status, GenAI manifest, or overall snapshot remains in active
  DDL or production code.
- Admin and contractor UX retain their current capabilities and obtain
  processing state from the run contract.
- Failure-injected tests and all five end-to-end journeys pass.
- Multiple real invoice packages pass the local stateflow and pipeline audit.
- Gold remains untouched until a separate rebuild request.

## Mandatory second-pass simplicity review

Completed on 2026-08-12 before implementation.

### Review method

The plan was reread end to end against the active DDL, all five preparation
entry points, both coordinators, every processing worker, run/step diagnostics,
the contractor presenter, invoice grid/view SQL, and the current uncommitted
structure-first ingest refactor. Each proposed table, column, module, step, and
API name was challenged on whether it removes inference or merely moves code.

### Simplifications confirmed

1. **Keep the eight invoice business states.** A separate persisted
   `processing` invoice state was rejected. It would continue mixing business
   ownership with execution, merely with fewer names.
2. **Keep four run and four step statuses.** Queued versus running is required
   for claiming/concurrency, while succeeded versus failed is required for
   terminality and retry interpretation.
3. **Keep `run_kind`.** This one column removes document-presence routing,
   `fix_run?` child-step queries, prefixed step families, and ambiguous admin
   diagnostics. It earns its existence.
4. **Keep `ingest_runs.invoice_id`.** The explicit relationship removes
   session/document/version inference from presenters, cleanup, views, active
   transition gates, and destroy logic. Nullable plus `ON DELETE SET NULL` is
   necessary only because failed contractor shells are deliberately deleted
   while their diagnostic runs are retained.
5. **Keep ten step types.** None can be removed without losing a real external
   call, retry boundary, synchronous failure boundary, fan-out target, or
   idempotent fan-in marker. Common/upgrade and initial/fix duplicates are
   removed because their existing target/run columns already express the
   difference.
6. **Do not add a workflow engine, generic phase object, step class hierarchy,
   or transition DSL.** Existing coordinators remain ordinary ordered Ruby
   methods consuming `StepOutcome` and `RunTransition`.
7. **Do not add a validation-result table or service object.** A small model
   query supports version-detail APIs, and SQL views derive the same severity
   for grids. Persisting it would recreate the snapshot being removed.
8. **Do not add a document-classification state replacement.** Existing step
   outcome, result columns, and `classified_at` already answer every required
   question.
9. **Keep the failure catalogue table.** Its editable safe copy and retry
   guidance are useful configuration; only its incorrect invoice ownership is
   changed.
10. **Keep `finalize_validation`.** Removing it would make several parallel
    ruleset workers compete to complete the run again. Its payload is removed,
    but its idempotent fan-in state remains.

### Refinements made by the review

1. Rename run/step diagnostic columns from `failure_status` and
   `failure_status_subtype` to `failure_category` and `failure_code`. Keeping a
   second field named “status” would undermine the state-boundary cleanup.
   `pipeline_error_code` remains distinct because it identifies the failed
   orchestration boundary while `failure_code` identifies the safe failure
   taxonomy.
2. Put the active-run business-transition guard directly in the existing
   `TransitionStatus` service using the invoice association and an
   `IngestRun.active` scope. Do not add a forwarding `ProcessingGate` service
   or an invoice predicate used only once.
3. Create the initial shell invoice, linked run, and root `stage_package` step
   in one database transaction. This prevents a database exception between
   those writes from leaving ambiguous root artifacts. External file storage
   calls remain outside that short transaction.
4. Use constants/scopes on the existing run and step models for the small
   canonical value sets. Do not introduce enum registry classes whose only job
   would be to return strings.
5. Rename the API arrays to `detected_upgrade_types` now. Retaining the old
   `upgrade_type_results` alias would be compatibility code for an application
   with no external users and would preserve the conceptual error.
6. Drain/restart development Sidekiq queues as part of the local rebuild. Do
   not preserve old variable-arity worker signatures or old step-type aliases.

### Complexity budget after review

- Net persisted lifecycle values must decrease substantially despite adding
  `run_kind`.
- New schema columns are limited to `ingest_runs.run_kind` and
  `ingest_runs.invoice_id`; all other schema work removes or renames existing
  state/snapshot data.
- No new production class is allowed solely to forward one call or humanize a
  string.
- Prefer deleting conditional branches and compatibility arguments over
  wrapping them.
- Existing retry, step outcome, coordinator, and presenter boundaries are
  reused rather than duplicated.
- The final call hierarchy must remain traceable from each controller to one
  run transition and must contain no worker-owned invoice transition.

The reviewed plan is approved for implementation.

## Implementation record

Completed on 2026-08-12 after the second-pass review.

### Structure delivered

- `claims.invoices.status` now contains only the eight business ownership
  states in this plan. Processing workers never write invoice status.
- `claims.ingest_runs` now owns processing lifecycle, explicit `run_kind`, the
  invoice relationship, terminal failure category/code, and terminal shape.
- `claims.ingest_step_runs` now uses the ten canonical logical operations and
  four attempt states.
- all three run kinds route through `AdvanceRun`; initial and fix bundles share
  `AdvanceBundleRun`, and rules reruns use `AdvanceExistingEvidenceRun` before
  entering the same validation scheduler/outcome flow;
- initial upload preparation creates the shell invoice, linked run, and root
  step atomically; external upload happens after that short transaction;
- run transitions are run-only, and business transitions reject queued or
  running work for the invoice;
- failure catalogue ownership and column names now describe ingest failures,
  not invoice status subtypes;
- document classification status duplication, upgrade-type GenAI manifest
  rows, invoice-version raw/overall GenAI snapshots, and the `partial` run
  state are gone;
- upgrade detection is classifier evidence only, while version validation
  severity is derived from normalized rulechecks;
- SQL views and React consumers now compose business status with latest-run
  presentation rather than persisting synthetic processing invoice states;
- ingest diagnostics show run kind and canonical steps, with identifiers kept
  in drawers instead of primary grids.

### Additional simplicity review during implementation

The implemented code was reread from all five entry points through terminal
run transition after the main edit. Four further simplifications were made:

1. `PipelineAudit::CheckRun` now maps directly from `run_kind` to one allowed
   canonical step set. Branch-root inference and duplicate forbidden-step
   lists were removed.
2. package deletion now follows the explicit invoice-to-runs relationship.
   Session/document/version inference and the associated family of small
   deletion helpers were removed.
3. the old aggregate-advice formatter and its isolated test were deleted. The
   `finalize_validation` row is only the idempotent fan-in marker it needs to
   be.
4. a remaining coordinator retry-exhaustion caller that still supplied an
   invoice to `RunTransition` was found by the broad suite and removed. The
   invoice remains in its business state when coordination fails.

No workflow framework, compatibility adapter, generic state abstraction, or
new persisted snapshot was introduced.

## Verification record

### Schema and local data

- stopped the Claims worker and rebuilt the local `claims` schema from every
  active rebuild file with `ON_ERROR_STOP=1`;
- created and selected all 14 Claims views successfully;
- added a focused schema-contract spec for exact invoice states, run kinds,
  run/step states, canonical steps, terminal shape, FK delete behaviour, and
  removed columns;
- verified retired lifecycle/snapshot columns are absent from active tables;
- ran all six reference-data downloads/imports and verified row counts:
  AHRI 20,436; NEEA 630; AWHP 101; OHPA 30,523; HERV 215; ventilation fans
  1,106;
- Gold was not queried, rebuilt, or modified during this implementation.

### Focused and regression tests

- all Claims model/service/job/request specs: **184 examples, 0 failures**;
- focused ingest suite: **62 examples, 0 failures**;
- schema/state-transition focus: **13 examples, 0 failures**;
- Claims AI Node unit suite: **9 tests, 0 failures**;
- Claims AI Node HTTP e2e suite: **1 test, 0 failures**;
- Claims AI Node production build: passed;
- frontend ESLint: **0 errors** (16 existing warnings outside this change);
- direct Vite application bundle: completed successfully in 33.34 seconds;
- `git diff --check`: passed;
- Ruby files changed by this work were normalized with the repository's
  SyntaxTree formatter.

The repository-wide Rails suite was also run: 695 examples, 261 failures, and
44 pending. The non-Claims legacy suite has a large existing fixture/model
drift baseline (for example obsolete `jurisdiction=` factory attributes). It
did expose one Claims constant rename missed by a presenter; that defect was
fixed, the example was rerun successfully, and the complete 184-example Claims
suite then passed. Raw repository-wide `tsc --noEmit` likewise has an existing
legacy baseline across unrelated modules; the production Vite bundle and
Claims-aware ESLint checks pass.

### Multi-package and fault-path execution

The four physical demo package families completed the canonical stateflow in
tests:

- demo1 ASHP/wood/ventilation, including an injected malformed first GenAI
  response followed by successful retry;
- demo2 ASHP/gas/health-and-safety;
- demo3 electrical service upgrade plus the real replacement/fix PDF;
- demo4 heat-pump water heater.

Deliberately exercised failures include atomic initialization failure, upload
exception, unsupported file, no invoice, two invoices, changed replacement
upgrade scope, permanent classifier failure, retryable failure and exhaustion,
ruleset failure, coordination retry exhaustion, duplicate worker delivery,
terminal-run reopening, and failed-upload cleanup. Assertions confirm these
failures belong to runs/steps and do not overwrite invoice business ownership.

Finally, the real demo4 invoice was sent through the running local services
without provider doubles. In 57 seconds it completed upload, DI read,
classification, invoice extraction, case facts, two GenAI rulesets, two code
rulesets, and finalization. It classified
`heat_pump_water_heater` at 100%, produced normalized rulechecks, derived the
version result, left the invoice in `contractor_precheck`, returned the
contractor `ready` presentation, and passed the pipeline audit. The temporary
invoice was then removed through `DestroyPackage`; its invoice, version, run,
ten attempts, document, and session were deleted, and all six reference-data
counts remained unchanged.
