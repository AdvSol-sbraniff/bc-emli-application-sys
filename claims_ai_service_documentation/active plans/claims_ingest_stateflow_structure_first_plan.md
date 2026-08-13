# Claims Ingest Stateflow — Structure-First Implementation Plan

## Plan status

Implemented and verified locally on 2026-08-12. The architecture, simplicity review, actual implementation, and executed test evidence are recorded below.

This plan is the programmer-facing framework for the change. It defines module ownership, call hierarchy, state flow, invariants, concurrency behavior, error behavior, and test coverage before implementation.

## Objective

Make all five invoice-package processing entry points use one stable processing model:

1. Contractor initial upload.
2. Contractor fix upload.
3. Admin contractor simulator.
4. Admin fix simulator.
5. Admin rerun-rules action.

The implementation must have:

- one definition of a logical processing step;
- one definition of retry state;
- one owner of run and invoice lifecycle transitions;
- one GenAI fan-out/fan-in flow;
- one contractor-facing run presentation contract;
- shared frontend polling and package-building primitives;
- retained attempt history for admin troubleshooting;
- monotonic terminal states;
- no DDL changes.

## Non-negotiable constraints

- No table, column, view, index, constraint, seed, or other DDL change is authorized.
- Do not delete attempt history to make state look clean.
- Do not hide retry attempts from the admin run monitor.
- Do not introduce JSON lifecycle state or another persistence mechanism.
- Do not introduce a workflow framework or generic orchestration DSL.
- Do not make React reconstruct backend lifecycle truth from several fields.
- Do not mix removal of the pre-classification shell invoice into this change.
- Preserve intentional policy differences, such as contractor-upload cleanup versus admin-simulator diagnostic retention.
- Existing unrelated working-tree changes and test-data moves must be preserved.

## Current failure being corrected

Gold run `97b58b67-3fc8-45b3-9430-32fad143c267` demonstrated the design defect:

- the first Ventilation GenAI attempt returned malformed JSON;
- the attempt was correctly retained as failed and retryable;
- Sidekiq retried it and the second attempt succeeded;
- the run ultimately became `succeeded` and the invoice became `genai_complete`;
- workers and parallel finish jobs temporarily moved the invoice through `technical_failure` three times;
- the contractor API continued returning the historical failed-attempt message after success;
- React displayed a terminal-looking error even though processing recovered.

The fix is not to suppress this one error. The fix is to remove competing lifecycle authorities.

## Existing persistence model and ownership

The existing schema is sufficient.

| Record                              | Authoritative responsibility                                    | Must not be used for                      |
| ----------------------------------- | --------------------------------------------------------------- | ----------------------------------------- |
| `claims.ingest_step_runs`           | One immutable-in-meaning execution attempt and its diagnostics  | Contractor-facing overall lifecycle       |
| `claims.ingest_runs`                | Current end-to-end processing lifecycle and terminal failure    | Detailed attempt history                  |
| `claims.invoices`                   | Invoice business/workflow lifecycle and coarse processing stage | Independent inference of retry exhaustion |
| `claims.invoice_status_transitions` | Audit trail of actual invoice workflow changes                  | Driving processing orchestration          |

An attempt row may transition from `queued` to `in_progress` to either `succeeded` or `failed`. A retry is a new attempt row for the same logical target. Historical failed rows remain failed after a later attempt succeeds.

## Target module structure

Only the following shared concepts are added. Names may move slightly to match repository conventions, but their boundaries must remain intact.

### 1. `Claims::Ingest::StepOutcome`

Purpose: calculate the effective state of a logical step across all attempts.

The logical target is identified by the existing fields:

- `ingest_run_id`
- `step_type`
- `ingest_document_id`
- `invoice_version_id`
- `invoice_upgrade_type_id`
- `supporting_document_type_id`

Public contract:

```ruby
outcome = Claims::Ingest::StepOutcome.for_step(step)
outcome = Claims::Ingest::StepOutcome.for_target(
  ingest_run_id:,
  step_type:,
  ingest_document_id: nil,
  invoice_version_id: nil,
  invoice_upgrade_type_id: nil,
  supporting_document_type_id: nil
)

Result = Data.define(
  :state,          # missing|active|retrying|succeeded|failed
  :effective_step, # the row relevant to that result
  :attempt_count,
  :attempt_limit
)
```

Precedence:

```text
any succeeded attempt                       -> succeeded
otherwise any queued/in_progress attempt    -> active
otherwise latest failure can still retry    -> retrying
otherwise a failed attempt exists           -> failed
otherwise                                   -> missing
```

Success is absorbing for a logical target. A late or duplicate failed delivery cannot make a successfully completed logical target fail.

Target scoping is a private implementation detail of this module; a separate
`StepTarget` value object is deliberately not introduced. `StepOutcome`
performs no persistence and no enqueueing.

### 2. `Claims::Ingest::RetryPolicy`

Purpose: define retryability and the maximum number of worker attempts once.

Contract:

```ruby
Claims::Ingest::RetryPolicy::MAX_ATTEMPTS
Claims::Ingest::RetryPolicy.sidekiq_retries # MAX_ATTEMPTS - 1
Claims::Ingest::RetryPolicy.retryable?(error_or_step)
Claims::Ingest::RetryPolicy.retry_pending?(attempts:)
```

All relevant Claims workers use `sidekiq_options retry: RetryPolicy.sidekiq_retries`. `StepOutcome` uses the same policy. There is no separate environment-defined coordinator attempt limit.

### 3. `Claims::Ingest::RunTransition`

Purpose: be the only module that writes lifecycle fields on `claims.ingest_runs` and the associated invoice processing status.

Public operations:

```ruby
RunTransition.mark_running!(run:, invoice_status:, total_files:)
RunTransition.mark_succeeded!(run:, invoice:, total_files:)
RunTransition.mark_failed!(run:, invoice:, failure:, total_files:, failed_files:)
```

Rules:

- lock the run row;
- terminal states are absorbing;
- repeated application of the same transition is idempotent;
- `running` clears terminal run failure fields and `completed_at`;
- `succeeded` clears terminal failure fields and sets `completed_at`;
- `failed` stores one authoritative run failure and sets `completed_at`;
- only terminal failure writes `technical_failure` or `package_needs_correction` to the invoice;
- a retrying attempt maps to a processing invoice status, never a failure status;
- completion runs `PipelineAudit::CheckRun` after the transaction;
- contractor cleanup occurs only after a terminal failed transition and after active attempts are absent.

This module replaces scattered direct `run.update!` lifecycle writes and worker-owned invoice status writes.

### 4. `Claims::Ingest::AdvanceRunJob`

Purpose: provide one reliable asynchronous request to re-evaluate a run.

Contract:

```ruby
Claims::Ingest::AdvanceRunJob.perform_async(ingest_run_id)
```

All workers enqueue this job after recording a success or failure. They do not directly call a branch coordinator. The advancement job retries coordination exceptions; they are logged and not swallowed.

Duplicate advancement jobs are expected and safe.

### 5. `Claims::Ingest::AdvanceRun`

Purpose: route a run to its branch coordinator, without containing branch state logic.

```text
AdvanceRun
├─ staged ingest documents exist -> AdvanceBundleRun
└─ no staged ingest documents    -> AdvanceExistingEvidenceRun
```

`FinalizeInvoiceVersionRun` should be renamed to `AdvanceExistingEvidenceRun` because it advances the rule-change branch throughout its lifecycle; it does not merely perform a terminal finalization.

Both branch coordinators consume `StepOutcome`, `RetryPolicy`, and `RunTransition`. Neither defines a second version of those concepts.

### 6. `Claims::StartGenaiValidationJob`

Purpose: begin validation for an invoice version.

Call contract:

```text
StartJob
├─ claim/build `case_facts`
├─ determine required common and upgrade ruleset targets
├─ create missing queued attempt rows
└─ enqueue one RulesetJob per missing target
```

It does not decide terminal failure, run code checks, aggregate advice, or complete the invoice.

### 7. `Claims::RunGenaiRulesetJob`

Purpose: execute exactly one common or upgrade GenAI ruleset attempt.

Call contract:

```text
RulesetJob
├─ no-op if StepOutcome is already succeeded
├─ claim/create the current attempt
├─ call GenAI
├─ persist rulechecks/located fields/manifest
├─ mark attempt succeeded or failed
└─ enqueue AdvanceRunJob
```

It does not enqueue a finish-mode `RunGenaiJob` and does not write invoice or run lifecycle state.

### 8. `Claims::FinalizeGenaiValidationJob`

Purpose: perform the single fan-in after every required logical GenAI ruleset has succeeded.

Call contract:

```text
FinalizeJob
├─ lock invoice version
├─ return if aggregate advice already succeeded
├─ verify every required ruleset StepOutcome is succeeded
├─ run common code rules idempotently
├─ run upgrade code rules idempotently
├─ aggregate advice idempotently
└─ enqueue AdvanceRunJob
```

Only a branch coordinator enqueues `FinalizeJob`, and only after all required GenAI logical targets are succeeded. Parallel ruleset jobs therefore cannot create several competing finish jobs that infer temporary failure.

The existing GenAI prompt/context and result-application helpers may remain together initially. This change separates lifecycle responsibilities; it is not permission to rewrite rule evaluation.

### 9. `Claims::Ingest::ContractorRunPresenter`

Purpose: create the sole contractor-facing interpretation of a run.

Public presentation state:

```text
processing
ready
needs_correction
failed
```

Mapping:

| Run state                                 | Presentation       | Failure fields                          |
| ----------------------------------------- | ------------------ | --------------------------------------- |
| `queued`, `running`                       | `processing`       | Always absent                           |
| `succeeded` with complete invoice/version | `ready`            | Always absent                           |
| `failed` with `package_needs_correction`  | `needs_correction` | From run only                           |
| `failed` with `technical_failure`         | `failed`           | From run only                           |
| inconsistent terminal data                | `failed`           | Safe invariant error, logged for admins |

The presenter never scans historical failed attempts and never falls back to a transient invoice failure. Attempt details remain available in admin endpoints.

### 10. Frontend shared modules

#### `useClaimsIngestRun`

One hook for contractor initial upload and contractor fix:

```typescript
const { run, presentationState, isPolling, refresh } = useClaimsIngestRun(runId);
```

It owns polling interval, authentication/error handling, response typing, and terminal detection. Screens own their wording and navigation destination.

#### `claims-fix-package`

Shared contractor/admin fix-package structures and helpers:

- current-package row model;
- cloned/new row construction;
- supported-file filtering;
- duplicate detection;
- `FormData` construction.

The contractor and admin fix screens keep different chrome and post-submit behavior but submit an identically constructed request to the existing shared endpoint.

#### `claims-evidence-files`

Shared file type/extension validation used by the contractor initial upload and admin simulator. It contains no business classification logic.

`useClaimsIngestRun` exposes the backend's four-state `presentation_state`
verbatim. A second frontend state-mapping module is deliberately not added.
Screens may choose their own wording and next navigation, but React must not
infer failure from `invoice_status` suffixes or combine competing fields.

The existing `IngestRunMonitorTabs` remains the shared admin diagnostic display for entry points 3, 4, and 5.

## Five entry-point call hierarchy

### 1. Contractor initial upload

```text
ContractorUploadInvoicesScreen
├─ claims-evidence-files
├─ POST contractor/invoices/upload_batch
│  └─ ContractorPortalController#upload_batch
│     └─ CreateDraftBatch(cleanup_failed_invoice_artifacts: true)
│        ├─ stage run/shell invoice/documents
│        ├─ stage upload attempt
│        └─ enqueue document OCR jobs
├─ useClaimsIngestRun
│  └─ GET contractor/ingest/runs/:id
│     └─ ContractorRunPresenter
└─ ready -> contractor invoice review
```

### 2. Contractor fix upload

```text
ContractorFixUploadScreen
├─ claims-fix-package
├─ POST invoices/:invoice_id/upload_fix_package
│  └─ IngestController#upload_fix_package
│     └─ UploadFixPackage
│        ├─ stage cloned and new evidence
│        ├─ stage fix root attempt
│        └─ enqueue OCR for new evidence only
├─ useClaimsIngestRun
│  └─ GET contractor/ingest/runs/:id
│     └─ ContractorRunPresenter
└─ ready -> contractor invoice review
```

### 3. Admin contractor simulator

```text
SubmissionSimulatorAdminScreen
├─ claims-evidence-files
├─ POST ingest/admin_submit_batch
│  └─ IngestController#admin_submit_batch
│     └─ CreateDraftBatch(cleanup_failed_invoice_artifacts: false)
│        ├─ stage run/shell invoice/documents
│        ├─ stage upload attempt
│        └─ enqueue document OCR jobs
└─ IngestRunMonitorTabs
```

### 4. Admin fix simulator

```text
ContractorFixSimulationAdminScreen
├─ claims-fix-package
├─ POST invoices/:invoice_id/upload_fix_package
│  └─ IngestController#upload_fix_package
│     └─ UploadFixPackage
└─ IngestRunMonitorTabs
```

### 5. Admin rerun rules

```text
AdviceRefreshSimulationAdminScreen
├─ POST admin/invoices/:id/reanalyze_advice
│  └─ InvoiceGridController#reanalyze_advice
│     └─ CreateRuleChangeRun
│        ├─ clone current invoice version/evidence
│        ├─ create rule-change root attempt
│        └─ enqueue Genai::StartJob
└─ IngestRunMonitorTabs
```

### Shared downstream hierarchy for staged package runs (1–4)

```text
Document OCR worker
└─ AdvanceRunJob
   └─ AdvanceRun
      └─ AdvanceBundleRun
         ├─ document read phase
         ├─ classification phase
         ├─ invoice resolution phase
         ├─ support extraction phase
         ├─ invoice OCR phase
         └─ validation phase
            ├─ StartGenaiValidationJob
            ├─ RunGenaiRulesetJob(s)
            └─ FinalizeGenaiValidationJob
```

Each worker completion re-enters through `AdvanceRunJob`. The coordinator advances only as far as persisted outcomes permit.

### Shared downstream hierarchy for rerun rules (5)

```text
CreateRuleChangeRun
└─ StartGenaiValidationJob
   ├─ RunGenaiRulesetJob(s)
   └─ each completion -> AdvanceRunJob
      └─ AdvanceRun
         └─ AdvanceExistingEvidenceRun
            └─ when all rulesets succeeded -> FinalizeGenaiValidationJob
               └─ AdvanceRunJob
                  └─ AdvanceExistingEvidenceRun
                     └─ RunTransition.mark_succeeded!
```

## Worker contract

Every retryable processing job follows one template:

```ruby
def perform(...)
  return if logical_target_already_succeeded?

  attempt = claim_attempt!
  result = execute_work!
  persist_result!(result)
  attempt_succeeded!(attempt)
rescue StandardError => error
  attempt_failed!(attempt, error)
  raise if RetryPolicy.retryable?(error)
ensure
  AdvanceRunJob.perform_async(ingest_run_id) if ingest_run_id.present?
end
```

Required properties:

- duplicate delivery after success is a no-op;
- a retry creates a new attempt row;
- one invocation never overwrites an earlier failed attempt;
- failure diagnostics are structured consistently;
- workers never write run lifecycle or invoice failure status;
- advancement failures do not change the worker attempt result.

## Run state flow

```text
queued
  └─ running
       ├─ succeeded
       └─ failed
```

Allowed transitions:

| From        | To                  | Allowed                          |
| ----------- | ------------------- | -------------------------------- |
| `queued`    | `running`           | Yes                              |
| `queued`    | `failed`            | Yes, synchronous staging failure |
| `running`   | `running`           | Idempotent refresh               |
| `running`   | `succeeded`         | Yes                              |
| `running`   | `failed`            | Yes, exhausted/permanent failure |
| `succeeded` | any different state | No                               |
| `failed`    | any different state | No                               |
| `partial`   | any different state | No                               |

`partial` remains accepted for legacy/multi-item compatibility but is terminal. These five single-package paths should normally end in `succeeded` or `failed`.

## Effective logical-step state flow

```text
missing
  └─ active
       ├─ succeeded
       └─ failed attempt
            ├─ retrying -> active -> succeeded
            └─ exhausted/permanent -> failed
```

The persisted failed attempt never changes. `retrying` is a derived logical-target state, not a new database value.

## Invoice processing state flow

The coordinator maps pipeline phases to existing coarse invoice statuses:

```text
upload_in_progress
  -> ocr_queued / ocr_in_progress / ocr_complete
  -> genai_queued / genai_in_progress
  -> genai_complete
```

Terminal package problems map to `package_needs_correction`. Terminal infrastructure/runtime problems map to `technical_failure`.

During retry:

```text
failed attempt + retry pending -> remain in current processing phase
```

No invoice transition to a failure state occurs until the run transition is terminally failed.

## Branch coordinator structure

`AdvanceBundleRun#call` becomes a short ordered dispatcher. It does not retain one 500-line conditional method.

```ruby
def call
  context = BundleContext.load(ingest_run_id)
  return if context.run_terminal?

  advance_document_read(context) ||
    advance_classification(context) ||
    advance_invoice_resolution(context) ||
    advance_support_extraction(context) ||
    advance_invoice_ocr(context) ||
    advance_validation(context) ||
    complete_run(context)
end
```

Phase methods return a small internal result:

```text
waiting        work already queued/in progress
enqueued       new work was queued
retrying       failed attempt has a retry pending
failed         coordinator terminally failed the run
advanced       phase completed; continue evaluation
complete       run completed
```

This result can be a symbol. Do not create a class hierarchy for phases.

`AdvanceExistingEvidenceRun` uses the same validation-phase method or helper as `AdvanceBundleRun`; it must not duplicate GenAI completion/retry interpretation.

## Concurrency and idempotency

- `RunTransition` locks the run before checking and writing state.
- A branch coordinator returns immediately for a terminal run.
- Logical step success wins over any failed attempt.
- Unique partial indexes remain the database backstop for concurrent nonfailed attempts.
- Jobs must check effective success before creating/claiming an attempt so the index is not normal control flow.
- `Genai::FinalizeJob` locks the invoice version and checks for succeeded aggregate advice before work.
- Code rules and aggregate advice retain existing idempotent step checks.
- Cleanup runs only after a locked terminal failure decision.
- A late success after terminal failure is retained diagnostically but cannot reopen the run or recreate deleted contractor artifacts.

## Failure ownership and presentation

| Concern                    | Owner                                    |
| -------------------------- | ---------------------------------------- |
| Error categorization       | `Claims::Invoices::FailureSubtypes`      |
| Retryability/attempt limit | `Claims::Ingest::RetryPolicy`            |
| Attempt diagnostics        | Worker + `ingest_step_runs`              |
| Effective logical outcome  | `Claims::Ingest::StepOutcome`            |
| Terminal run failure       | `Claims::Ingest::RunTransition`          |
| Contractor-safe copy       | `Claims::Invoices::StatusSubtypes`       |
| Contractor response shape  | `Claims::Ingest::ContractorRunPresenter` |
| Admin diagnostic selection | Existing admin serializer/monitor        |

No controller should independently select a failed attempt as the contractor outcome.

## Node GenAI malformed-response boundary

The Node service currently retries provider-call errors internally, then logs `request.succeeded` before parsing model JSON. Parsing failure is returned immediately to Rails as retryable.

Change the short internal retry boundary to cover provider call plus JSON extraction/parsing:

```text
attempt
├─ call Responses API
├─ extract output text
├─ extract JSON payload
└─ parse JSON
```

Only after parsing succeeds should it log `claims.genai.request.succeeded`.

Malformed output retry requirements:

- reuse the existing small internal attempt count;
- log each malformed attempt without logging document contents beyond bounded diagnostics;
- retain the Rails/Sidekiq outer retry after internal attempts exhaust;
- do not add JSON repair heuristics;
- do not make a separate “repair” model call.

## Implementation sequence

### Phase A — lock characterization with failing tests

Add tests that reproduce:

- retryable first GenAI failure with run remaining `running`;
- successful second attempt winning over historical failure;
- contractor presenter returning processing during retry and ready after success;
- rule-change branch not terminally failing while retry remains;
- terminal run cannot reopen;
- late duplicate worker after success is a no-op.

These should fail against current behavior before production changes.

### Phase B — shared backend primitives

Implement and test:

- `RetryPolicy`
- `StepOutcome`
- `RunTransition`
- `AdvanceRunJob`

No branch refactor until these contracts pass in isolation.

### Phase C — worker contract and GenAI fan-in

- migrate document OCR, classifier, supporting extraction, invoice OCR, and GenAI ruleset jobs to the shared worker contract;
- introduce `StartGenaiValidationJob`, `RunGenaiRulesetJob`, and `FinalizeGenaiValidationJob` responsibilities;
- remove finish-mode fan-out;
- remove worker invoice/run lifecycle writes;
- ensure each outcome requests `AdvanceRunJob`.

### Phase D — branch coordinators

- refactor `AdvanceBundleRun` into named phases;
- rename/refactor `FinalizeInvoiceVersionRun` to `AdvanceExistingEvidenceRun`;
- make both use `StepOutcome` and `RunTransition`;
- add terminal-state guard and cleanup ordering;
- preserve new upload, fix upload, and rule-change branch-specific preparation.

### Phase E — API and frontend consolidation

- add `ContractorRunPresenter`;
- make contractor run endpoint return one `presentation_state`;
- add `useClaimsIngestRun` and pure presentation helpers;
- migrate contractor initial and fix screens;
- share fix-package row/FormData helpers between contractor/admin fix;
- share evidence-file validation between contractor initial/admin simulator;
- keep admin diagnostic monitor detailed.

### Phase F — Node response parsing retry

- move JSON parsing inside the bounded Node retry operation;
- correct success/failure diagnostic event ordering;
- add malformed-first/valid-second and exhausted malformed tests.

### Phase G — remove obsolete paths

- delete superseded `contractor_ingest_run_failure_payload` history scanning;
- remove duplicate frontend inference;
- remove unused finish mode and helper methods;
- remove duplicated retry-limit code;
- remove dead direct coordinator calls;
- update comments to describe the target flow.

## Automated test matrix

### Shared primitives

1. No attempt -> `missing`.
2. Queued/in-progress -> `active`.
3. Retryable failed attempt below limit -> `retrying`.
4. Nonretryable failure -> `failed`.
5. Exhausted retryable failures -> `failed`.
6. Any succeeded attempt plus failures -> `succeeded`.
7. Retry policy and every worker's Sidekiq options agree.
8. Terminal run transitions are absorbing.
9. Repeated identical transitions are idempotent.

### Worker behavior

10. Success records success and queues advancement.
11. Retryable failure records diagnostics, queues advancement, and raises.
12. Permanent failure records diagnostics, queues advancement, and does not raise for retry.
13. Duplicate delivery after logical success makes no provider call.
14. Concurrent duplicate attempt claim does not produce an unhandled uniqueness error.

### GenAI fan-out/fan-in

15. Start enqueues each required ruleset once.
16. One ruleset failure with retry pending does not enqueue finalization.
17. Other parallel rulesets may succeed while one retries.
18. Finalization is enqueued once after all logical rulesets succeed.
19. Duplicate finalizer delivery is a no-op after aggregate success.
20. Code-rule failure follows the same terminal policy.

### Branch coordinators

21. Initial upload clean success.
22. Fix upload clean success.
23. Rule rerun clean success.
24. Each branch remains active while a retry is pending.
25. Each branch terminally fails only after permanent/exhausted failure.
26. A terminal branch cannot reopen from a late job.
27. Contractor cleanup occurs only after terminal failure.
28. Admin simulator diagnostic artifacts are retained according to policy.
29. Fix scope-change rejection remains a package correction.
30. No-invoice and multiple-invoice packages remain package corrections.

### Contractor API and React

31. Running run plus failed attempt -> `processing`, no failure message.
32. Succeeded run plus historical failed attempt -> `ready`, no failure message.
33. Terminal correction -> `needs_correction`, run-owned message.
34. Terminal technical failure -> `failed`, run-owned message.
35. Contractor initial and fix hooks continue polling through retry.
36. They stop polling on `ready`, `needs_correction`, or `failed`.
37. No UI code derives terminal failure from invoice status.

### Node service

38. Provider error then success within internal attempts.
39. Malformed JSON then valid JSON within internal attempts.
40. Repeated malformed JSON returns one structured retryable error to Rails.
41. Success diagnostic emitted only after parsed JSON.

## Fault-injection strategy

Add test-only dependency seams rather than production debug flags:

- stub `Claims::Genai::NodeClient.call` with an ordered outcome sequence;
- invoke jobs synchronously to control attempt timing;
- use Sidekiq fake/testing mode to inspect retry/enqueue behavior;
- issue contractor status requests between attempts;
- invoke duplicate jobs and advancement jobs deliberately;
- raise from a phase evaluator once, then allow the advancement job retry;
- test Node service with mocked Responses results returning malformed then valid output.

Do not add a runtime endpoint that lets users force errors.

## Human-style end-to-end test packages

Use multiple existing current demo packages so coverage is not tied to one invoice shape:

- `demo1_aug4_ASHP-WOOD_VENT` — multiple upgrade rulesets and parallel fan-in.
- `demo2_aug4_ASHP-GAS_HS` — multiple support documents and health/safety evidence.
- `demo3_aug7_ESU` — electrical-service rules and supporting evidence/fix behavior.
- `demo4_aug11_HPWH` — different upgrade path and homeowner.

Test journeys:

### Journey A — contractor initial clean upload

- upload a complete package through the real contractor screen;
- observe run rows from staging through completion;
- confirm success modal and Next;
- open invoice review and confirm advice exists.

### Journey B — contractor initial recoverable malformed GenAI response

- force one ruleset's first response malformed;
- poll every three seconds during the delay;
- confirm no contractor failure is exposed;
- confirm admin monitor shows `retrying`, then `retried`;
- confirm final success and review navigation.

### Journey C — contractor initial permanent/exhausted failure

- force every allowed attempt for one ruleset to fail;
- confirm processing continues until exhaustion;
- confirm exactly one terminal contractor error;
- confirm cleanup executes only after the terminal transition;
- confirm retained sanitized attempt diagnostics.

### Journey D — contractor fix

- begin with a successfully processed invoice;
- replace the invoice or add supporting evidence;
- exercise recoverable first-attempt failure;
- confirm previous invoice remains usable while processing;
- confirm the new version becomes ready without transient terminal UI.

### Journey E — admin simulator

- upload at least two distinct packages;
- confirm shared staging and lifecycle behavior;
- confirm monitor shows every attempt and pipeline checker passes.

### Journey F — admin fix simulator

- build the same fix package structure as the contractor path;
- compare the outgoing request parts;
- confirm the same backend run path and admin diagnostic retention.

### Journey G — admin rerun rules

- rerun a completed package with no new files;
- force a retryable first GenAI failure;
- confirm the rule-change run remains active rather than becoming failed;
- confirm successful final version and advice.

### Journey H — package validation errors

- no invoice;
- two invoice PDFs;
- unsupported file;
- replacement changing upgrade-type scope;
- confirm each uses `needs_correction`, never a generic technical failure.

### Journey I — concurrency and duplicate delivery

- enqueue duplicate advancement requests;
- invoke a completed ruleset job again;
- invoke finalizer twice;
- confirm one successful logical result, no duplicate advice, and no terminal reopening.

## Full regression commands

At minimum:

- all focused Rails specs for ingest services, jobs, API requests, cleanup, and pipeline audit;
- full Claims Rails spec set;
- full Rails spec suite if runtime permits;
- Node unit tests and e2e tests;
- TypeScript compile/build;
- ESLint on every modified frontend file;
- Ruby syntax checks and formatting checks;
- `git diff --check`;
- local pipeline checker for every successful test run;
- SQL invariant queries against local test/demo records.

## Runtime data invariants to verify without DDL

```text
succeeded run -> failure fields null, completed_at present
failed run -> failure status/subtype present, completed_at present
queued/running run -> failure fields null, completed_at null
succeeded run -> resolved invoice version present
succeeded contractor upload -> associated invoice is genai_complete
terminal run -> no later run status transition in application behavior
logical target with success -> historical failures allowed, effective result succeeded
```

## Acceptance criteria

- All five entry points follow the documented call hierarchy.
- Initial upload pairs share `CreateDraftBatch`.
- Fix pairs share `UploadFixPackage` and shared frontend package construction.
- All five share retry, logical outcome, advancement, run transition, and GenAI fan-in concepts.
- Rerun rules has different preparation but no different retry/state semantics.
- No worker writes terminal invoice or run state.
- A retryable attempt never creates contractor-visible terminal failure.
- A historical failure never contaminates a later successful presentation.
- Terminal runs never reopen.
- Admins retain complete attempt visibility.
- Contractor cleanup never races a pending retry.
- Fault-injected tests cover recoverable, exhausted, permanent, duplicate, and coordinator-error paths.
- Multiple real invoice packages succeed end to end.
- No DDL file is changed.

## Required second-pass simplicity review

Before implementation, review this plan for:

- modules that merely rename a one-line helper;
- duplicated state calculation;
- excessive value objects or result classes;
- phase abstractions that obscure ordinary Ruby control flow;
- frontend sharing that couples distinct screen layouts;
- broad rewrites unrelated to lifecycle correctness;
- opportunity to delete more old logic than is added;
- whether every module has one clear caller/callee contract.

Record the review outcome and exact simplifications in the next section before changing application code.

## Second-pass simplicity review outcome

Completed before implementation.

### Simplifications made

1. Removed the proposed `StepTarget` class. Logical target scoping belongs in
   `StepOutcome`; a separate value object would have added indirection without
   owning behavior.
2. Removed the proposed frontend `claims-ingest-presentation` module. The
   backend presenter owns the four-state decision, and `useClaimsIngestRun`
   should pass that decision through rather than map it again.
3. Retained symbolic phase results rather than introducing phase/result class
   hierarchies.
4. Kept the existing `Claims::RunGenaiRulesetJob` name. It already represents
   the correct one-ruleset responsibility; its lifecycle side effects will be
   removed instead of replacing it for naming purity.
5. Chose ordinary job names (`StartGenaiValidationJob` and
   `FinalizeGenaiValidationJob`) in the existing `Claims` job namespace rather
   than creating a nested job namespace with no practical benefit.
6. Limited frontend sharing to stateful/repeated mechanics: polling, evidence
   validation, and fix-package construction. Distinct screen layout and copy
   remain local.
7. Kept branch-specific staging services. Combining initial upload, fix upload,
   and evidence cloning into a generic intake abstraction would hide meaningful
   differences and increase conditional behavior.
8. Kept both branch coordinators because staged bundles and cloned-evidence
   reruns have different prerequisites. They share state primitives and the
   validation-phase contract instead of being forced into one large generic
   coordinator.
9. Rejected new database state, workflow gems, event buses, and repair-model
   calls.

### Modules retained and why they earn their existence

| Module                      | Single reason it exists                                              |
| --------------------------- | -------------------------------------------------------------------- |
| `RetryPolicy`               | Prevent Sidekiq/coordinator retry-count drift                        |
| `StepOutcome`               | Give all branches one interpretation of attempts                     |
| `RunTransition`             | Make terminality and invoice/run writes single-owner                 |
| `AdvanceRunJob`             | Make coordination failure retryable instead of swallowed             |
| `AdvanceRun`                | Route to the correct branch without duplicating state logic          |
| Start/ruleset/finalize jobs | Make GenAI fan-out/fan-in explicit and remove competing finish jobs  |
| `ContractorRunPresenter`    | Prevent historical attempts from becoming contractor lifecycle truth |
| Three frontend helpers      | Remove demonstrable polling/package/file duplication only            |

### Complexity budget

- Prefer deleting superseded lifecycle and inference code over wrapping it.
- No new production class may exist solely to forward one call.
- No new persisted state.
- No generic base worker or metaprogrammed workflow DSL.
- A phase helper remains a private method unless it is consumed by both branch
  coordinators.
- The final call hierarchy must be traceable from each controller to a terminal
  transition without circular callbacks.

The reviewed plan is considered structurally approved for implementation.

## Implementation record

Completed on 2026-08-12.

### Final backend call hierarchy

```text
contractor initial upload ---------\
                                     -> CreateDraftBatch -> staged documents
admin contractor simulator --------/

contractor fix upload -------------\
                                     -> UploadFixPackage -> staged documents
admin fix simulator ----------------/

admin rerun rules -> CreateRuleChangeRun -> cloned existing evidence

every asynchronous worker outcome
  -> AdvanceRunJob
     -> AdvanceRun
        |- staged documents present -> AdvanceBundleRun
        `- no staged documents      -> AdvanceExistingEvidenceRun

either coordinator's validation phase
  -> ValidationOutcome
     |- missing           -> ValidationScheduler.start! -> RunGenaiJob
     |- active/retrying   -> remain running
     |- failed            -> RunTransition.mark_failed!
     |- ready_to_finalize -> ValidationScheduler.finalize!
     |                       -> FinalizeGenaiValidationJob
     `- succeeded         -> RunTransition.mark_succeeded!

contractor status request
  -> ContractorRunPresenter
     -> processing | ready | needs_correction | failed
```

The existing `RunGenaiJob` remains the GenAI execution engine. Its lifecycle
authority was removed rather than copying its prompt/result machinery into new
workers. `ValidationScheduler` owns the two idempotent enqueue boundaries, and
`FinalizeGenaiValidationJob` owns the single aggregate fan-in delivery.

The proposed `StartGenaiValidationJob` was intentionally not created after the
simplicity review. `ValidationScheduler.start!` can atomically create the
`case_facts` attempt and enqueue the existing job directly; an extra job would
have been a one-line forwarding layer with no independent failure boundary.

### Implemented shared backend modules

| Module                       | Implemented responsibility                                                                                |
| ---------------------------- | --------------------------------------------------------------------------------------------------------- |
| `RetryPolicy`                | One retry count and retryability decision for every Claims processing worker                              |
| `StepClaim`                  | Idempotently claim a queued logical attempt before checking or calling an external dependency             |
| `StepOutcome`                | Derive effective logical state across retained attempts, with success taking precedence                   |
| `RunTransition`              | Sole writer of run lifecycle and associated invoice processing transitions; terminal states are absorbing |
| `AdvanceRunJob`              | Retryable asynchronous re-entry, including terminal handling when coordinator retries exhaust             |
| `AdvanceRun`                 | Route only between staged-bundle and existing-evidence coordinators                                       |
| `ValidationOutcome`          | One interpretation of case-facts, ruleset, code-rule, and aggregate outcomes                              |
| `ValidationScheduler`        | Idempotently start validation and enqueue its single fan-in                                               |
| `AdvanceExistingEvidenceRun` | Advance the file-free rerun branch using the same validation and transition contracts                     |
| `FixPackageContext`          | Centralize source-version, replacement, retained-document, and package context for fix processing         |
| `ContractorRunPresenter`     | Return contractor lifecycle solely from the authoritative run, never historical failed attempts           |

`AdvanceBundleRun#call` is now an ordered phase dispatcher:

```text
load_context
  -> advance_document_read
  -> advance_classification
  -> resolve_invoice
  -> advance_supporting_extraction
  -> advance_invoice_ocr
  -> advance_validation
  -> complete_run
```

Workers now claim an attempt, persist only their attempt result, and request
`AdvanceRunJob` in `ensure`. Prerequisite failures are recorded against a
claimed attempt instead of leaving a queued row forever. Duplicate delivery
after logical success is a no-op. Coordinator exhaustion terminally fails the
run through `RunTransition` rather than leaving it spinning.

### Implemented API and frontend sharing

- Both initial upload controllers call `CreateDraftBatch`; their only intended
  policy difference is contractor cleanup versus admin diagnostic retention.
- Both fix screens post an identically built package to the one
  `UploadFixPackage` endpoint.
- The rerun controller calls `CreateRuleChangeRun`, then enters the shared
  existing-evidence validation flow.
- `useClaimsIngestRun` is used by both contractor upload screens and consumes
  backend `presentation_state` directly. Temporary network, 429, and 5xx
  polling failures retain the last run and continue polling; authentication
  and permanent 4xx errors stop.
- `claims-evidence-files` shares evidence validation between the contractor
  initial upload and admin simulator.
- `claims-fix-package` shares rows, validation, duplicate handling, and
  `FormData` construction between contractor and admin fix screens.
- Screen layout, wording, and navigation remain local rather than being forced
  into a generic upload-screen component.

### Implemented Node boundary

The Responses API call, output extraction, JSON extraction, and JSON parse now
share the existing bounded internal retry. A success event is emitted only
after valid JSON exists. Repeated malformed output returns a structured,
retryable 503 to Rails. No JSON repair heuristic or second repair-model call was
added.

### Removal and scope record

- Removed `FinalizeInvoiceVersionRun`; `AdvanceExistingEvidenceRun` now names
  and owns that branch accurately.
- Removed contractor lifecycle inference from historical failed attempt rows.
- Removed worker-owned terminal run/invoice decisions and competing validation
  finish scheduling.
- Preserved the unused positional OCR argument needed to deserialize jobs that
  may already be queued by an older application image.
- No SQL, migration, schema, view, index, constraint, or seed file was changed.
  A pre-existing modified archived reference PDF under
  `claims_ai_service_ddl` is unrelated and was left untouched.

## Test execution record

Completed on 2026-08-12.

### Deterministic fault and stateflow coverage

- Focused worker/coordinator/request characterization: 61 examples, 0 failures.
- Fault-injection group: 13 examples, 0 failures. Covered transient provider
  failure followed by success, exhausted retry, permanent prerequisite
  failure, duplicate delivery after success, coordinator retry and exhaustion,
  and authoritative contractor presentation.
- Four-package stateflow suite: 4 examples, 0 failures. It used the actual files
  from:
  - `demo1_aug4_ASHP-WOOD_VENT` (seven files, two rulesets, injected malformed
    first case-facts response);
  - `demo2_aug4_ASHP-GAS_HS` (seven files, two rulesets);
  - `demo3_aug7_ESU` (fixed invoice and handover support);
  - `demo4_aug11_HPWH` (single-file HPWH path).
- Those package journeys execute real Rails staging, coordinator, relational
  persistence, transition, validation-fan-in, presenter, and pipeline-audit
  code. External OCR/classifier/GenAI boundaries are deterministic test doubles
  so error ordering and retries can be forced rather than hoped for.
- Real-file fix journey: 1 example, 0 failures. It exercises
  `UploadFixPackage`, fix read/classification, upgrade-scope guard, atomic v2
  promotion, fix OCR, shared validation/fan-in, and terminal success.
- File-free rule-rerun journey: 2 examples, 0 failures. It covers retry then
  success and validation-start failure becoming a terminal technical failure.
- Package correction coverage includes missing invoice, multiple invoices,
  unsupported evidence, duplicate conflict, and replacement upgrade-type
  change.
- Concurrency/idempotency coverage includes duplicate advancement, late worker
  delivery, duplicate finalizer delivery, effective-success precedence, and
  terminal states refusing to reopen.

### Final regression and build results

| Check                                           | Result                                                                                                                                 |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Claims model/service/job/request regression     | 173 examples, 0 failures                                                                                                               |
| New Ruby module compilation                     | All files `Syntax OK`                                                                                                                  |
| Shared Sidekiq retry audit                      | All seven processing/coordinator jobs resolve to retry `3`                                                                             |
| New-module RuboCop                              | 17 files, 0 offenses                                                                                                                   |
| Node unit tests                                 | 3 suites, 9 tests, all passed                                                                                                          |
| Node HTTP E2E                                   | 1 suite, 1 real endpoint request, passed                                                                                               |
| Node production build                           | Passed                                                                                                                                 |
| Frontend targeted ESLint                        | Passed                                                                                                                                 |
| Frontend Vite production build/type compilation | Passed                                                                                                                                 |
| Changed-file whitespace check                   | Passed                                                                                                                                 |
| Schema-source audit                             | No DDL/SQL/view changes from this implementation                                                                                       |
| Read-only local runtime invariant audit         | 0 malformed succeeded runs, 0 malformed failed runs, 0 active runs with terminal fields, 0 active steps beneath terminal runs          |
| Local runtime restart and smoke test            | Rails `/up` returned 200; AI `POST /inv/HelloWorld` returned 201; Claims Sidekiq is running at concurrency 20 with 0 busy and 0 queued |

The frontend build still reports the repository's pre-existing Quill `eval`,
CSS, dynamic-import, and large-chunk warnings; they are unrelated to Claims
ingest and did not fail the build.

The full repository Rails suite was also attempted. It is not globally green:
it fails in pre-existing, unrelated areas including jurisdiction/controller,
external-API, automated-compliance, and legacy schema/code-drift coverage.
The complete Claims regression above is green, including every Claims path
changed by this implementation. Those unrelated failures were not masked or
changed as part of this plan.

Restart observation: restarting Rails and Claims Sidekiq simultaneously caused
both existing container entrypoints to request the same Searchkick reindex.
Searchkick rejected the worker entrypoint's duplicate reindex, as designed; the
worker continued to boot, the app completed the reindex, and all three runtime
processes were healthy afterward. This pre-existing startup-order race is not
part of the ingest state machine and was not broadened into this refactor.

## Admin diagnostics presentation follow-up

Completed on 2026-08-12.

The standalone Ingest Runs screen and the compact monitor embedded in upload
and simulator screens now consume the same backend attempt interpretation and
use one shared diagnostics drawer. This prevents either React surface from
independently guessing whether a failed row is terminal, retrying, or recovered.

### Diagnostic call hierarchy

```text
IngestRunsAdminController index/show/steps/step_show ----\
                                                           -> AttemptDiagnostics
IngestController run_show --------------------------------/
                                                              -> StepOutcome
                                                              -> FailureSubtypes

standalone Ingest Runs --------\
                                -> admin diagnostic APIs
embedded IngestRunMonitorTabs --/       -> IngestDiagnosticDrawer
```

`AttemptDiagnostics` is a read model, not another lifecycle owner. It groups
persisted rows by the existing logical step target, delegates attempt precedence
to `StepOutcome`, annotates each physical attempt for display, and selects a
terminal error only from logical targets that remain failed. It performs no
writes and adds no persisted state.

### Canonical diagnostic states

```text
failed attempt + later succeeded attempt -> recovered
failed retryable attempt in active run    -> retrying
failed attempt + active next attempt      -> retrying
effective failed target in failed run     -> terminal failure
historical failure on recovered target    -> never a terminal failure
```

The API exposes the resulting attempt number/count, logical state, display
status, effective-attempt flag, run attempt summary, and terminal failure. The
generic run endpoint retains `primary_failure` as a compatibility alias, but it
points to the canonical terminal failure rather than historical failure data.

### Grid and drawer boundary

- Grids show operational facts: time, duration, contractor, lifecycle status,
  file progress, attempt history, terminal error, readable target, provider,
  and payload count.
- UUIDs and diagnostic IDs were removed from grid columns. They remain
  searchable and are available with copy actions in the details drawer.
- Upgrade and supporting-document targets use registry keys/descriptions and
  filenames instead of UUIDs in the grid.
- The shared drawer renders structured run, invoice, step, error, provider,
  attempt, and identifier sections. Raw payload/JSON data remains available
  behind an explicit disclosure rather than being the primary diagnostic UI.
- Both polling surfaces preserve the last successful data during a transient
  request failure, identify it as stale, and continue polling active work.

### Verification

| Check                                            | Result                                                                                 |
| ------------------------------------------------ | -------------------------------------------------------------------------------------- |
| Attempt diagnostic and API focused suite         | 11 examples, 0 failures                                                                |
| Full Claims model/service/job/request regression | 179 examples, 0 failures                                                               |
| Targeted frontend ESLint                         | Passed                                                                                 |
| Full Vite build/type compilation                 | Passed                                                                                 |
| New diagnostic service/spec RuboCop              | 2 files, 0 offenses                                                                    |
| Ruby syntax                                      | All three changed backend files `Syntax OK`                                            |
| Read-only current local run audit                | Succeeded run: 30 attempts, 2 historical failures, both recovered, no terminal failure |
| Schema-source audit                              | No DDL, migration, SQL, view, index, constraint, or seed change                        |

The Vite build continues to report the repository's pre-existing Quill,
legacy CSS, dynamic-import, and chunk-size warnings; none are caused by this
diagnostic follow-up.
