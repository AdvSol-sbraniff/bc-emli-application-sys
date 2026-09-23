# Rule package AI audit: background execution plan

Status: active plan; investigation complete, implementation not started.
Date: 2026-09-21.
Requested scope: plan the move from a synchronous audit request to Sidekiq, comparing it with contractor upload processing and deciding whether to use `ingest_runs`.

This is a follow-up to [the implemented audit plan](rule_package_ai_audit_plan.md). This planning task changes documentation only. No application code, database, worker, deployment or AI evaluation is changed or run.

## 1. Decision: reuse Sidekiq, keep audit runs separate from ingest runs

Use the existing Sidekiq/Redis infrastructure, a dedicated audit worker, a small persistent audit-run record and status polling. Continue using the existing audit context builder, model configuration, Node endpoint and output validation.

Do **not** run this feature through `claims.ingest_runs`, `ingest_documents`, `ingest_step_runs` or `Claims::Ingest::AdvanceRun`.

Ingest is not restricted to new uploads: it already supports `initial_upload`, `fix_upload` and `rules_rerun`. However, all three belong to processing official invoice evidence/results. In particular, Refresh AI Advice uses the rules-rerun path to produce a new processed version and rule results. A package audit instead reads existing evidence, complaints and workflow history and returns advisory suggestions. It must not create an invoice version, replace rulechecks, change invoice status or apply a proposed rule.

The current ingest coordinator dispatches only those three kinds. Completion invokes `Claims::PipelineAudit::CheckRun`; failure can invoke contractor-upload cleanup when its flag is set. Its records, presenters and progress steps carry file-processing and resolved-version semantics. Adding an audit kind would therefore require changes across the ingest lifecycle, not just reusing a queue. It would also put an advisory operation into contractor processing/reporting concepts.

`Claims::PipelineAudit::CheckRun` is an existing pipeline consistency check. It is not the LLM package audit discussed here.

| Reuse                                                      | Keep separate                            |
| ---------------------------------------------------------- | ---------------------------------------- |
| Sidekiq, Redis, application image, worker deployment chart | Audit queue and worker process           |
| Authenticated claims admin access                          | Audit run status/result table            |
| Existing rule audit service and Node transport             | Audit start/status endpoints             |
| Polling and terminal-state interaction pattern             | Audit-specific React polling hook        |
| Authoritative invoice/supporting-document evidence         | Ingest staging, finalisation and cleanup |

This introduces durable execution tracking, not a full audit-history subsystem. There is no new history browser, approval workflow, generic job framework or regression-harness redesign.

## 2. What the code currently does

| Area                | Current implementation and implication                                                                                                                                                                                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Browser             | `app/frontend/components/domains/rule-improvement-report/package-audits.tsx` POSTs to `/audit`, waits up to 310 seconds and retains the result only in React state. Leaving/reloading can lose the result; aborting the browser request is not reliable server-side cancellation. |
| Rails               | `app/controllers/api/claims/reports_rule_improvement_controller.rb#audit` calls `Claims::RuleAudits::Audit#call` directly. The HTTP request remains open during evidence assembly, file transport and inference.                                                                  |
| Audit service       | `app/services/claims/rule_audits/audit.rb` assembles guidance/context, selects `comparison_deployment_name`, calls Node, validates output and file-transport provenance, and returns `saved: false`.                                                                              |
| Evidence            | `context_builder.rb` loads invoice versions, supporting documents, rule definitions/history, rulechecks/reasons, complaints, workflow rounds/responses/comments, conversations and internal notes. Source attachments come from evidence storage, not ingest logs.                |
| AI transport        | `claims_ai_service/src/services/rule-audit.ts` serves `/inv/rule-audit`. It has a bounded provider budget (240 seconds by default, maximum 270) and at most two provider attempts. Rails NodeClient allows a 300-second read timeout.                                             |
| Contractor upload   | `ContractorPortalController#upload_batch` calls `Claims::Ingest::CreateDraftBatch`, which stages files and queues `Claims::RunIngestReadOcrJob`; the pipeline later schedules GenAI and finalisation. The HTTP request need not await those AI stages.                            |
| Contractor progress | `app/frontend/hooks/use-claims-ingest-run.ts` polls persisted run state. Reuse this interaction pattern, not its contractor-specific route, permission or ingest response shape.                                                                                                  |
| Workers             | Local `sidekiq-claims` consumes `claims_ocr,claims_genai` with concurrency 20. General Sidekiq has its own explicit queues. Adding a queue name does not by itself reserve execution capacity.                                                                                    |
| Deployment          | `helm/main/Chart.yaml` already aliases the reusable Sidekiq chart as `sidekiqClaims`. A further alias can run the same image with a dedicated queue and small concurrency.                                                                                                        |

Configuration remains `claims.validationgenai_config.rule_audit_system_record` and `comparison_deployment_name`. This plan needs a new run table, but no additional model/system-prompt field and no change to comparison behavior. The previous plan records that the system-record column was subsequently added to Gold on 2026-09-18; this follow-up requires its own later additive table deployment.

## 3. Proposed user-visible behavior

1. The admin selects an invoice package and clicks **Run AI audit**.
2. Rails validates access and scope, records a queued run, submits its ID to Sidekiq and returns promptly. The browser shows **Queued**, then **Preparing evidence**, then **Running AI audit** using the recorded `status` and `current_step`.
3. The browser polls every three seconds while the run is active. It can be closed without cancelling the worker.
4. Completion saves the existing advice, optional proposals and verified provenance. Reloading/reselecting the same package can recover the active or latest completed run.
5. Failure shows a useful explanation and an explicit **Run a new audit** action. A temporary polling/network failure says that status could not be refreshed; it does not claim the audit itself failed.

Keep the current four output fields:

- `advice` — required nonempty text; can identify zero, one or several improvement options.
- `proposed_rule_prompt` — nullable.
- `proposed_precheck_action` — nullable.
- `proposed_contractor_guidance` — nullable.

Continue displaying proposals as read-only suggestions. Label a restored result with its completion time, selected version and captured rule/model references. A saved result is not automatically an assessment of today's changed rule. Do not invent percentage progress for an opaque provider call.

## 4. Minimal durable record

Add `claims.audit_runs`, represented by `Claims::AuditRun`. This is a new table, with one row per requested audit of a selected rule against an invoice package.

Its closest analogue is `ingest_runs`: it represents the complete operation, rather than one child step within a larger operation. No `audit_step_runs` table is proposed.

| Field/group                                              | Proposed purpose                                                                                                                               |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `id uuid`                                                | Stable public run identifier.                                                                                                                  |
| `request_id uuid`                                        | Client-generated idempotency token, unique per requesting admin. Reusing it with different inputs returns a conflict.                          |
| `requested_by_id uuid`                                   | Authenticated `current_user.id`, referencing the existing user table; never accepted from browser input.                                       |
| `invoice_id`, `selected_invoice_version_id`              | Requested evidence scope, validated together. Resolve an omitted version to a concrete version when creating the run.                          |
| `source_engine`, `rule_key`                              | Logical rule identity; `source_engine` is `genai` or `code`. Do not imply the current schema provides an immutable historical rule UUID.       |
| `status`                                                 | Overall lifecycle, constrained to `queued`, `running`, `succeeded`, `failed`, matching `ingest_runs.status`.                                   |
| `current_step`                                           | Nullable text identifying the execution step, such as `preparing_context` or `calling_ai`. This replaces the previously proposed name `phase`. |
| `job_id`                                                 | Sidekiq job reference for diagnosis, not the authority for business completion.                                                                |
| `created_at`, `updated_at`, `started_at`, `completed_at` | Request, execution and completion timing.                                                                                                      |
| `context_prepared_at`, `input_metadata jsonb`            | Actual selected definition/version references, model, instruction/guidance/context digests and evidence manifest captured during preparation.  |
| `result jsonb`                                           | Validated four-field response plus existing transport/evidence provenance; present only on success.                                            |
| `error_code`, `error_message`                            | Stable error category and safe admin-facing explanation. Diagnostic details remain in appropriately restricted logs.                           |

`current_step` follows the existing step terminology in `ingest_step_runs` / `step_type`; it is not a column copied from `ingest_runs`, which has no current-step column. Unlike the parent run, `ingest_step_runs.status` uses `in_progress`; retain `running` for the audit's overall status to match the parent-run convention.

For example, `status = 'running'` and `current_step = 'preparing_context'` can display **Running - Preparing evidence**. A queued run has no current step yet. Update the step as execution progresses, clear it on successful completion, and retain the last reached step on failure for diagnosis. Terminal `status` takes precedence in the UI, so a retained failed step is not displayed as ongoing work. This field is operational progress, not one of the numbered steps in the human improvement guide.

Add indexes for package/rule/latest lookups and stale active runs. Add a partial unique index for active `(source_engine, rule_key, invoice_id, selected_invoice_version_id)` so simultaneous clicks cannot start duplicate active audits of the same selection. A duplicate request from an authorized admin returns the existing active run. A deliberately new audit after completion uses a new request token.

Use the repository's UUID, timestamp, foreign-key and deletion conventions. Do not silently introduce cascaded deletion of audit records or block existing package removal without handling it: select and document the deletion behavior during DDL implementation against the actual invoice-deletion paths. Preserve the existing local fixture cleanup contract by explicitly removing owned audit runs before owned invoices where needed.

Store output and provenance needed for recovery. Do not duplicate PDF bytes, introduce raw-document storage in this table or add one column for every possible AI analytical heading. Full synthetic-message bodies need not be persisted for this transport change; retain existing digest/manifest guarantees and state that hashes alone cannot reconstruct subsequently edited evidence.

Retention is not specified by the current feature. Do not add an automatic purge policy in this change. Record count/storage growth and the need to include these records in any future evidence-retention policy should be documented.

### Rule type and code-rule advice

Retain support for both GenAI and code-based rules. The existing `audit_scope` faux record sent to the LLM explicitly includes the rule type:

```json
{
  "source_engine": "code",
  "rule_key": "the_selected_rule_key"
}
```

`source_engine` is the existing rule-type indicator; no separate `rule_type` field is needed. Guidance is also selected for the corresponding engine. For code rules the context includes registry configuration/history, package evidence and recorded outcomes, and explicitly discloses that executable Ruby and historical code revisions are not supplied.

The maintained default system record tells the model to return `proposed_rule_prompt: null` for a code rule and describe any required developer/configuration change in `advice`. Rails additionally rejects a non-null replacement prompt for a code rule. Recommendations can identify observed behavior, the intended correction, the responsible developer and verification cases, but must not claim to diagnose an unseen implementation. Nullable pre-check and contractor-guidance proposals remain available when justified. Preserve these instructions when maintaining a custom system-record override.

## 5. API and authorization

Use a separate asynchronous resource under the existing scoped report route:

- `POST /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key/audit_runs`
- `GET /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key/audit_runs/:id`
- `GET /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key/audit_runs/latest?invoice_id=...&selected_invoice_version_id=...`

Create accepts the existing package/version arguments plus `request_id`. It returns HTTP 202 with `id`, `status`, `current_step`, timestamps and a status URL for a new active run. An idempotent replay of an already terminal run returns HTTP 200 with its current state. The latest endpoint prefers an active run, otherwise the most recent terminal run for that selection; it is not an unbounded history listing. Declare the literal `latest` route before `:id`.

All endpoints use the existing `claims.configuration` permission and server-side scope checks. A run UUID alone grants no access. Verify route rule identity, invoice/version membership and the same evidence-access rules as the existing audit. Do not return raw stored context, credentials or internal exception traces in a status response. Authorized admins with the same report/evidence access can inspect the run; this is not requester-only private data.

Do lightweight validation before enqueueing: identifiers, access, rule existence, package/version relation and available configuration. The worker revalidates before execution. Large context assembly, document retrieval and inference belong in the worker.

Persist first, enqueue after commit. Store the resulting job ID. If enqueueing is rejected or Redis fails, conditionally mark a still-queued run failed with an enqueue-specific error and return a useful failure response. If a worker has already claimed it despite a lost acknowledgement, return its actual persisted state instead of marking it failed. A late-delivered job skips a run already marked failed. This handles ambiguous enqueue acknowledgement without submitting another AI call automatically.

The existing synchronous `/audit` route may remain during a short compatibility rollout for cached old clients. New React uses only `/audit_runs`. Remove the old route after confirming rollout; do not silently change its response to 202 while old clients expect advice JSON. Direct service evaluation can continue through `Audit#call` without maintaining a second audit implementation.

## 6. Worker, evidence timing and failure rules

Add `Claims::RunRulePackageAuditJob`, with only the audit-run UUID as its argument and queue `claims_rule_audit`.

1. Atomically change `queued` to `running`. Return without inference for an already running, failed or successful run. Do not rely solely on browser disabling or Sidekiq uniqueness middleware.
2. Revalidate inputs; prepare the existing context, guidance, system instruction and deployment selection. Persist safe preparation metadata and `current_step` updates.
3. Call the existing Node audit service and validate the complete response and transport evidence using existing code.
4. Persist result and `succeeded` together. Publish `saved: true` only after that transaction succeeds. Completion must conditionally update a still-running run, so a late worker cannot overwrite a terminal failure.
5. Convert known failures into persisted error categories. Log unexpected failures using the run ID and safe diagnostics, and finish the run as failed when possible.

Extract preparation/execution methods from `Claims::RuleAudits::Audit` only where needed for current-step reporting and snapshot consistency. Keep its existing `call` entry point as a composition of those methods for direct tests/evaluation. Do not copy its evidence assembly or validation into the job.

The run records the selection at request time, but reads current evidence/configuration when the worker prepares it. Explicitly label these two times. Use a short, read-only consistent database snapshot for related context queries, then close it before reading remote attachments or calling Node. Preserve the prepared messages and configuration for that invocation and any existing Node-internal retry. Record missing/deleted evidence as a clear failure or existing disclosed limitation, not an invented historical value.

Continue authoritative attachment resolution from `invoice_versions` and `supporting_documents`. Keep source hashes/ETag checks, all existing size limits, explicit oversize errors and no silent truncation. Later workflow information must remain distinguished from original-decision evidence. Queueing does not resolve missing historical snapshots or supply the complete published policy PDF.

### Bounded retries and recovery

Use `retry: false` on the Sidekiq audit job initially. The Node call already has a bounded provider retry policy; do not multiply it by ingest's four-attempt policy. Network timeouts may mean the provider processed a request despite a lost response, so do not promise exactly-once inference or automatic recovery without another charge.

An explicit retry creates a new run and prepares fresh evidence/configuration, with the same user-visible warning that it starts a new AI call. Automatic duplicate job delivery must not start another call for an already claimed run.

Add a small stale-run reconciliation job on the existing general queue, using the existing cron loader. Proposed initial deadlines are 30 minutes queued and 10 minutes running, checked every minute. Validate the running deadline against actual context-build plus transport time during local testing. These are operational constants/environment settings, not more editable business-config columns.

Expired queued runs report a dispatch/worker-availability problem. Expired running runs report an interrupted/timed-out audit; neither is silently replayed. This covers crashes between database commit and enqueue, lost jobs and worker termination. A provider may still finish after an interruption, but a failed run cannot subsequently be overwritten by that late result. The UI must not spin forever.

Log run ID, `current_step`, elapsed time, model, diagnostic ID and error category. Do not log entire package documents, comments or API keys. Operational visibility should expose queue age, running age and failures without creating ingest log records.

## 7. Worker configuration

- Add local Compose service `sidekiq-rule-audits`, using the application image/config, `SIDEKIQ_QUEUES=claims_rule_audit` and `SIDEKIQ_CONCURRENCY=1` initially.
- Add Helm alias `sidekiqRuleAudits` using `helm/_sidekiq`, with matching values, a single initial replica and suitable database pool/resources. Include its image tag in future deployment commands.
- Keep existing contractor OCR/GenAI queues and concurrency unchanged. Do not add the new queue to broad fallback consumers if that would let general/contractor workers consume it; verify explicit queue lists and fallback behavior in `config/initializers/sidekiq.rb`.
- A dedicated queue without a separate worker does not isolate worker slots. The separate process is the intended isolation. Node, Redis, database and the model deployment still share capacity, so concurrency one does not guarantee zero effect on contractor traffic.
- Keep existing provider budgets and model configuration. Do not increase HTTP timeouts simply because the browser now polls.
- Rebuild/check Helm dependencies when adding the alias: this repository can render vendored chart archives instead of the raw subchart changes. Inspect rendered queue, concurrency, environment and image settings before any deployment.

## 8. React and shared guidance

Extract a small `use-rule-package-audit-run.ts` hook for create, recover and poll. Follow the existing ingest hook's cleanup/error-handling pattern without coupling to contractor endpoints or its presentation state.

Persist the selected run ID in the page URL if the existing navigation conventions permit it; use the scoped latest endpoint to recover when reopening the package. Abort only browser polling on unmount, not server execution. Ignore stale responses when the selected package/rule changes. Stop polling terminal runs and on lost authorization. Handle intermittent network errors with bounded polling backoff and a visible retry-status control.

Keep the four advice/proposal fields and current invoice grid. Prevent duplicate start clicks; recover an existing active run returned by the API. If the newest run fails, do not display an older success as though it were the failed run's output.

Replace the current text saying results are not saved. Explain that this is a saved advisory result for the captured evidence and that changes still require review/testing. Update maintained React guidance and regenerate `config/claims/rule_improvement_guidance.json` using the existing export script, so human and AI references remain aligned. No new policy advice or changes to the seven improvement options are needed for background execution.

## 9. File inventory

| Files                                                                         | Planned work                                                                                                                                                                         |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `claims_ai_service_ddl/2_create_schema.sql`                                   | Include the new table, constraints, comments and indexes in future full rebuilds. Never execute this destructive rebuild to add the table to an existing database.                   |
| New `claims_ai_service_ddl/dev_tools/apply_audit_runs.sql`                    | Additive, transaction-protected installation for an explicitly selected database; verify existing definitions on rerun instead of hiding incompatible tables behind `IF NOT EXISTS`. |
| New `app/models/claims/audit_run.rb`                                          | `Claims::AuditRun` mapped to `claims.audit_runs`; scope, state, idempotency and persisted-output validation.                                                                         |
| New `app/jobs/claims/run_rule_package_audit_job.rb` and stale-run job         | Background execution, duplicate guards and bounded failure recovery.                                                                                                                 |
| New service under `app/services/claims/rule_audits/`                          | Small create/enqueue orchestration shared by controllers/tests; no generic pipeline framework.                                                                                       |
| `app/services/claims/rule_audits/audit.rb`                                    | Reusable prepare/execute composition and progress metadata; preserve validation and direct-call behavior.                                                                            |
| `config/routes.rb`; new scoped admin audit-runs controller                    | Create/latest/show resources under existing report scope and permission. Existing reporting controller changes only for eventual synchronous-route retirement.                       |
| `package-audits.tsx`, `package-audit-data.ts`, `detail.tsx`; new React hook   | Start/poll/recover lifecycle, durable result types, errors and guidance.                                                                                                             |
| Shared guidance source files and generated JSON                               | Replace temporary-output wording and keep exported reference fresh.                                                                                                                  |
| `docker-compose.yml`; `helm/main/Chart.yaml`, values and dependency artifacts | Dedicated audit worker with the same application image.                                                                                                                              |
| `config/sidekiq_cron_schedule.yml`; initializer only as required              | Stale-run reconciliation and verified queue configuration.                                                                                                                           |
| New model/job/request/hook tests; existing audit service specs                | Lifecycle, authorization, duplicate/failure/recovery and contract coverage.                                                                                                          |
| Existing local audit evaluation helper/docs                                   | Clean up owned run rows and add a queued end-to-end smoke path while retaining direct service evaluation.                                                                            |

No planned change to `2_create_schema_for_testharness.sql`, ingest DDL/coordinators, rule seeds or comparison behavior. Node transport changes only if a concrete defect or correlation need is found; otherwise use it as-is.

## 10. Implementation sequence and prerequisites

- [x] Read bootstrap/rebuild instructions and compare audit with upload/rerun processing.
- [x] Decide against using ingest runs; record dedicated Sidekiq design and scope.
- [ ] Confirm source deletion behavior, request/result serialization and current worker budgets; settle exact DDL and API contracts.
- [ ] Add rebuild DDL plus additive patch, model and idempotent create/enqueue service. Apply only to explicitly targeted local databases during implementation.
- [ ] Implement job, service preparation boundaries, safe errors and stale-run recovery; test with controlled transport before paid AI calls.
- [ ] Add authenticated start/status/latest APIs and request tests.
- [ ] Add dedicated Compose/Helm worker configuration; prove an actual local worker consumes the new queue.
- [ ] Wire React polling/recovery and update/export shared guidance.
- [ ] Run focused automated checks and queued local AI smoke/evidence checks below.
- [ ] Record actual commands/results, remaining limitations and local fixture cleanup here.
- [ ] Prepare schema-first deployment notes and compatibility-route retirement. Do not treat this plan request as permission to alter Gold or deploy.

Before each phase, confirm the required database schema, worker configuration, Node service and generated guidance are available. Do not report a queued-run integration as working if only inline/fake Sidekiq tests were used.

## 11. Verification plan

| Check                         | Required evidence                                                                                                                                                                                                                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Authorization and scoping     | Unauthenticated/unauthorized start and polling fail; another rule's run ID and mismatched invoice/version cannot expose or audit evidence.                                                                                                                                           |
| Fast request                  | Start returns a queued run without context construction or inference in the web request. Status responses never depend on provider completion.                                                                                                                                       |
| Persistence and idempotency   | Concurrent starts and lost-response replay create one active run for the same selection. A reused request ID with different input fails. Terminal runs cannot be re-executed by duplicate jobs.                                                                                      |
| Execution lifecycle           | Overall `status`, `current_step` and terminal result/error are persisted correctly; queued/succeeded steps are null and failures retain the last reached step. `saved: true` requires a committed result. Database row locks/transactions are not held across provider calls.        |
| Rule type                     | Both `genai` and `code` travel through the queued audit with the correct `audit_scope.source_engine` and guidance. Code-rule advice uses the flexible `advice` field for developer changes; replacement prompt proposals are rejected and missing executable code remains disclosed. |
| Evidence and configuration    | Selected version belongs to the package; job-start timing is disclosed; prepared rule/config/guidance and file identities match returned provenance. Existing history, comments, attachment and missing-evidence tests remain green.                                                 |
| Failure categories            | Cover enqueue failure, missing worker, worker interruption, stale guidance, changed/missing files, oversized input, absent model, provider timeout, invalid JSON and invalid transport provenance. No unbounded automatic AI retries.                                                |
| Database/provider uncertainty | Simulate a failure after inference but before result persistence and an ambiguous enqueue acknowledgement. Report uncertainty honestly; no duplicate automatic inference and no late overwrite of failed runs.                                                                       |
| Browser flow                  | Start, progress, completion, nullable proposals, retry status, reload, leave/reopen and switching selected package during polling. Old results cannot be attributed to a new selection.                                                                                              |
| Queue isolation               | Dedicated worker consumes only audit jobs; contractor workers do not consume the audit queue. Cron reconciliation still works when the audit worker is down.                                                                                                                         |
| Existing behavior             | Focused existing upload/rerun and audit service tests remain unchanged in outcome. No new ingest rows, invoice versions, official rulechecks or business-status changes are caused by an audit.                                                                                      |

Run Rails specs with **both** `RAILS_ENV=test` and `DATABASE_URL=postgres://postgres:password@postgres:5432/app_test`; the Compose app otherwise points to development even when `RAILS_ENV=test` is set. Use targeted lint/type/browser checks for changed frontend files, guidance export/check, and Compose/Helm configuration rendering. Restart relevant local application/audit-worker processes before manual verification after Ruby changes to avoid stale classes.

### Actual queued AI smoke test

Use the existing local demo scenario preparation protocol and its owned-record manifest. Create one identifiable test package with rule results, complaint text and workflow/conversation history, retaining original rule values and existing cleanup guarantees. Do not alter permanent seeds or Gold.

Start through the new authenticated HTTP endpoint with a real Sidekiq worker and real Node/model transport. Observe the database lifecycle, navigate away, return and retrieve the committed advice. Confirm the context/attachment hashes, counts, selected rule/config references and relevant history reached the model; useful-looking text alone is insufficient. Verify the proposal fields remain advisory and that invoice/rule/ingest records were not changed by execution.

Use controlled failures for crash/timeout/concurrency tests to avoid repeatedly paying for large audits. Moving execution to Sidekiq should not change the audit's analytical contract, so do not automatically repeat all previous 13 audits and 24 candidate checks. If the implementation changes inputs/instructions or uncovers an advice regression, rerun the affected documented scenarios and appropriate unchanged controls. Distinguish lifecycle tests from any limited AI behavior observations.

## 12. Rollout, limitations and completion evidence

Future rollout order: install the additive table; deploy compatible API/job code and the dedicated worker from the same image; confirm queue consumption; deploy/enable the updated frontend; then retire the synchronous route after old-client compatibility is addressed. Retain the table/results on an application rollback; do not drop saved audit output as part of rollback. Drain or explicitly fail in-flight runs before worker/schema incompatibility.

Known boundaries remain: no durable reconstruction of every mutable source from a digest alone, no immutable historical rule UUID introduced, no full policy PDF added, no automatic application of suggestions, no exactly-once provider guarantee, and shared model capacity remains a possible contention point.

Completion must record:

- Implemented files, additive schema and actual worker deployment settings.
- Commands for local schema installation, worker startup, focused tests and queued AI smoke.
- Observed start-to-completion/recovery behavior and verified source provenance.
- Duplicate/failure/stale-run outcomes and actual provider attempt bounds.
- Confirmation of unchanged official invoice results, no unintended ingest writes, and fixture/rule restoration.
- Any unimplemented safeguards, observed failures and outstanding retention/deletion decisions.

### Planning activity log

- 2026-09-21: inspected the synchronous audit endpoint/UI/service, contractor staging/jobs/polling, ingest run kinds/coordinator/finalisation, Sidekiq queue configuration, Helm worker aliases, bootstrap and rebuild instructions.
- 2026-09-21: selected independent audit execution records and worker; deliberately avoided adding an ingest run kind or reusing ingest source/log tables.
- 2026-09-21: created this plan only. Implementation, automated tests, real AI calls and database/deployment operations have not been performed for this follow-up.
- 2026-09-21: incorporated the naming discussion: table `claims.audit_runs`, model `Claims::AuditRun`, and progress column `current_step`. Documented the parent-run analogy, exact status convention, code-rule context/output safeguards, and corresponding API/test expectations. These remain planned changes only.
