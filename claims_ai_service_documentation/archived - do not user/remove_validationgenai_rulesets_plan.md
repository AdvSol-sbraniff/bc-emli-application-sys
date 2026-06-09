# Remove `validationgenai_rulesets` Runtime Dependency Plan

## Status

Implemented locally on 2026-06-03.

- Runtime now compiles GenAI prompt text directly from normalized rule and located-field mappings.
- `claims.validationgenai_rulesets` and its seed file were removed from the active local rebuild path.
- `validationgenai_ruleset_id` was removed from active runtime plumbing, API payloads, and local schema.
- The upgrade GenAI context window now separates case facts, raw DI invoice JSON, and the final ask into distinct user records.
- Gold was not updated as part of this plan.

## 1. Purpose

Remove `claims.validationgenai_rulesets` from the active GenAI validation architecture.

The table currently stores a compiled `user_record1` prompt blob for each upgrade type. That made sense during the early ruleset prototype, but the system now has normalized source-of-truth tables for GenAI rules, located fields, and upgrade-type mappings. The runtime should compile from those normalized tables directly and store the actual context window used for audit.

This plan is local-only until manual testing is complete. Do not apply these schema or seed changes to Gold as part of this work.

## 2. Current Problem

`claims.validationgenai_rulesets` is a compiled prompt cache, but it looks like a stable business object.

Current design flaws:

- It duplicates the normalized GenAI rule model.
- It creates a second place where rule text can appear: normalized rule tables and compiled `user_record1`.
- It makes auditing confusing because the actual LLM prompt is stored elsewhere.
- It forces runtime to depend on a prepublished row being present.
- It uses timestamp ordering to determine the current compiled prompt.
- It keeps old "ruleset" language alive even though rules are now mapped N-to-N to upgrade types.

The correct audit artifact is `claims.ingest_step_runs.context_window_json`, not `claims.validationgenai_rulesets.user_record1`.

## 3. Current Live Dependencies

### 3.1 Runtime

`Claims::RunGenaiJob` currently:

- finds the latest `claims.validationgenai_rulesets` row for each upgrade type
- reads `ruleset.user_record1`
- injects that compiled text into the GenAI context window
- stores `validationgenai_ruleset_id` on step/output rows

Relevant files:

- `app/jobs/claims/run_genai_job.rb`
- `app/services/claims/genai_ruleset_compiler/compile.rb`
- `app/services/claims/genai_ruleset_publisher/publish.rb`

### 3.2 Pipeline Parameter Passing

Several ingest/OCR/redo services pass `validationgenai_ruleset_id` through the pipeline even though the value is only meaningful to GenAI runtime.

Relevant files:

- `app/controllers/api/claims/ingest_controller.rb`
- `app/controllers/api/claims/redo_invoice_package_controller.rb`
- `app/services/claims/ingest/create_draft_batch.rb`
- `app/services/claims/ingest/redo_invoice_package.rb`
- `app/services/claims/ingest/advance_bundle_run.rb`
- `app/jobs/claims/run_ocr_job.rb`
- `app/jobs/claims/run_ingest_read_ocr_job.rb`
- `app/jobs/claims/run_ingest_triage_job.rb`
- `app/jobs/claims/run_supporting_document_extraction_job.rb`

### 3.3 Schema

Current schema dependencies:

- `claims.validationgenai_rulesets`
- `claims.invoice_version_upgrade_types.validationgenai_ruleset_id`
- `claims.ingest_step_runs.validationgenai_ruleset_id`
- FK from `invoice_version_upgrade_types` to `validationgenai_rulesets`
- FK from `ingest_step_runs` to `validationgenai_rulesets`
- check constraint requiring `validationgenai_ruleset_id` for GenAI step types

Relevant file:

- `claims_ai_service_ddl/2_create_schema.sql`

### 3.4 Rule Publishing

The normalized validation rule admin flow currently publishes compiled rows into `claims.validationgenai_rulesets` after GenAI rule or located-field changes.

Relevant file:

- `app/controllers/api/claims/validation_rules_admin_controller.rb`

### 3.5 Old UI / Dead Code

Old ruleset editor components still exist, but no active React route was found for `/rulesets-admin` or `/ruleset-editor`.

Relevant files:

- `app/frontend/components/domains/rulesets-admin/index.tsx`
- `app/frontend/components/domains/ruleset-editor/index.tsx`
- `app/controllers/api/claims/validationgenai_rulesets_controller.rb`

The config portion of `ValidationgenaiRulesetsController` is still live and should be preserved or moved because `validationgenai_config` remains valid.

## 4. Target Design

Runtime should compile GenAI prompt text directly from normalized tables at call time.

Target source-of-truth tables:

- `claims.validationgenai_config`
- `claims.genai_rules`
- `claims.genai_rule_upgrade_types`
- `claims.genai_located_fields`
- `claims.genai_located_field_upgrade_types`
- `claims.supporting_document_types`
- `claims.supporting_document_type_upgrade_types`
- `claims.supporting_document_type_located_fields`

Target runtime audit table:

- `claims.ingest_step_runs.context_window_json`

No runtime path should need `claims.validationgenai_rulesets`.

## 5. Implementation Plan

### 5.1 Replace Ruleset Id as Pipeline Control Flow

Before removing `validationgenai_ruleset_id`, replace its current control-flow role.

Today, some OCR/package paths use the presence of `validationgenai_ruleset_id` as the signal to continue from OCR into GenAI. That must be replaced with an explicit boolean/option.

Recommended runtime flags:

- `enqueue_genai_after: true|false`
- `genai_mode`

The pipeline should no longer mean "run GenAI" by passing a ruleset id.

Affected examples:

- `Claims::RunOcrJob` currently enqueues GenAI only when `validationgenai_ruleset_id.present? && enqueue_genai_after`.
- `Claims::Ingest::CreateDraftBatch` resolves a default ruleset before staging.
- `Claims::Ingest::RedoInvoicePackage` resolves a default ruleset before staging.
- `Claims::Ingest::AdvanceBundleRun` passes the id through triage, supporting-document extraction, invoice OCR, and GenAI steps.

New behavior:

- OCR/package flows pass `enqueue_genai_after` explicitly.
- GenAI runtime determines applicable upgrade types and compiles prompts from normalized mappings.
- No OCR or classifier job should need a validation ruleset id.

### 5.2 Plan 0 Rule Prompt Self-Containment Prerequisite

Before removing the compiled `validationgenai_rulesets.user_record1` blob, complete Plan 0:

- `claims_ai_service_documentation/remove_validationgenai_rulesets_plan0_rule_prompt_plan.md`

This prerequisite ensures rebate/math rules do not rely on invisible "summary-table values above", "cap above", "background section", or category/top-up text from the old compiled prompt.

Plan 0 must move the useful cap/category/top-up/formula values from the compiled seed into normalized `claims.genai_rules.prompt_text` rows. It should also remove or neutralize the compiled ruleset seed artifact so no business rule content remains hidden in `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql`.

Do not proceed to runtime removal until normalized rule prompts are self-contained and local Postgres has been updated from the normalized seed.

### 5.3 Runtime Refactor

Change `Claims::RunGenaiJob` so `ruleset_for_upgrade_type!` no longer queries `Claims::ValidationgenaiRuleset`.

Instead, build a lightweight runtime object from normalized tables:

```ruby
compiled_user_record1 =
  Claims::GenaiRulesetCompiler::Compile.call(
    invoice_upgrade_type: upgrade_type
  )
```

Then pass that compiled text into `build_contextwindowjson`.

Recommended naming:

- Replace `ruleset` variable with `compiled_prompt` or `compiled_rules_prompt`.
- Replace `ruleset.user_record1` with `compiled_prompt.user_record1` or just `compiled_user_record1`.
- Remove runtime dependence on `ruleset.id`.

Before deleting the old table, compare runtime-compiled prompt text against the currently published `validationgenai_rulesets.user_record1` for every upgrade type. This is a regression guard for ordering, disabled/enabled filters, and prompt text composition.

Expected:

- Differences should be understood and intentional.
- If the compiler output is identical, runtime behavior should be equivalent except for removal of ruleset id plumbing.

### 5.4 Context Window Audit

Keep storing the actual generated context window here:

- `claims.ingest_step_runs.context_window_json`

Also clean up the upgrade GenAI context-window shape while touching runtime composition.

Target message order:

- `system`: `validationgenai_config.system_record`
- `user record 0`: `validationgenai_config.user_record0`, shared DI/OCR reading guidance
- `user record 1`: compiled normalized located-field tasks and GenAI rule prompts
- `user record 2`: `case_facts` JSON only, including DB facts and supporting-document located fields
- `user record 3`: raw DI invoice JSON only
- `user record 4`: actual ask, for example "perform the location tasks and rulecheck tasks"

Reason:

- case facts and raw DI invoice JSON are conceptually different payloads
- splitting them makes `context_window_json` easier to audit and debug
- the one-line actual ask should remain last

Also fix the failed-call audit gap:

- if `contextwindowjson` is built and the LLM call or result application fails, persist `context_window_json` on the failed step before re-raising.

### 5.5 Output Manifest Cleanup

Remove or deprecate `validationgenai_ruleset_id` from runtime output structures.

Affected persisted rows:

- `claims.invoice_version_upgrade_types`
- `claims.ingest_step_runs`
- `invoice_version.genai_raw_json.ruleset_results[]`

Replacement audit fields:

- `invoice_upgrade_type_id`
- `invoice_upgrade_type_key`
- `context_window_json`
- optional future `context_window_sha256`
- optional future `compiled_prompt_sha256`

Clean API serializers and frontend grids before dropping columns.

Known output/display areas to review:

- `app/controllers/api/claims/ingest_controller.rb`
- `app/controllers/api/claims/contractor_portal_controller.rb`
- `app/controllers/api/claims/invoice_versions_controller.rb`
- `app/controllers/api/claims/invoice_versions_admin_controller.rb`
- `app/frontend/components/domains/ai-admin/index.tsx`
- `app/frontend/components/domains/redo-invoice-package/index.tsx`
- `app/frontend/components/domains/invoice-version-viewer-by-version/index.tsx`

### 5.6 Pipeline Parameter Cleanup

Remove `validationgenai_ruleset_id` from pipeline signatures where it is passed through only to satisfy the old runtime dependency.

Likely cleanup areas:

- upload package creation
- redo package flow
- OCR job enqueue calls
- triage job enqueue calls
- supporting-document extraction enqueue calls
- GenAI job enqueue calls
- API params that accept a ruleset id

After this, the pipeline should not need to choose a ruleset. It should choose documents, run OCR/classification/extraction, detect upgrade types, and then compile rules from normalized mappings.

### 5.7 Stop Publishing Compiled Ruleset Rows

Remove `publish_genai_rulesets_for!` calls from normalized rule admin create/update flows.

Affected flows:

- create/update GenAI rule
- create/update GenAI located field
- changes to N-to-N upgrade-type mappings

The admin UI should save normalized rules/mappings only. There should be no second publish step into `claims.validationgenai_rulesets`.

After this step, remove `Claims::GenaiRulesetPublisher::Publish` unless another intentional use remains.

### 5.8 Config Controller Cleanup

Split live `validationgenai_config` endpoints away from `ValidationgenaiRulesetsController` before deleting ruleset controller code.

Create or use a clearer controller:

- `Claims::ValidationgenaiConfigController`

Move these live routes/actions:

- `GET /api/claims/admin/validationgenai_config`
- `PATCH /api/claims/admin/validationgenai_config`

Only after the config endpoints are moved should ruleset list/show/create/update code be removed.

### 5.9 DDL Cleanup

Update `claims_ai_service_ddl/2_create_schema.sql`.

Remove:

- `claims.validationgenai_rulesets`
- `validationgenai_ruleset_id` from `claims.invoice_version_upgrade_types`
- `validationgenai_ruleset_id` from `claims.ingest_step_runs`
- FK constraints pointing to `claims.validationgenai_rulesets`
- indexes on `validationgenai_ruleset_id`
- check constraint requiring ruleset id for GenAI step types

Review and update seed files:

- `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql`
- `claims_ai_service_ddl/4_insert_invoice_upgrade_types.sql`
- `claims_ai_service_ddl/README_REBUILD_ORDER.txt`

Likely seed split:

- keep `validationgenai_config` seed content
- remove compiled `validationgenai_rulesets` inserts
- rename the seed file later if appropriate, for example `5_insert_validationgenai_config.sql`

Do this only after runtime/API/frontend references have been removed.

Gold is intentionally out of scope for this implementation pass. For any later Gold rollout, dropping the id columns is acceptable only if `claims.ingest_step_runs.context_window_json` and result payloads are retained as the audit source. If the team wants a lightweight historical pointer before dropping columns, add a text/hash field first and backfill it from existing rows.

### 5.10 Controller Cleanup

Remove dead ruleset endpoints if not routed and no caller remains:

- ruleset list
- ruleset show
- ruleset create
- ruleset update
- current ruleset lookup

Remove or simplify `ValidationgenaiRulesetsController` after config routes are moved.

### 5.11 Frontend Cleanup

Remove old dead components if no active route depends on them:

- `rulesets-admin`
- `ruleset-editor`

Keep active normalized portals:

- `validation-rules-admin`
- `validation-rules-alphabetic-admin`
- `validation-rules-config`

Update labels/help text that still says ruleset when it means normalized validation rule or GenAI prompt config.

### 5.12 Dev Tool Cleanup

Update or remove dev tools that read `claims.validationgenai_rulesets`:

- `claims_ai_service_ddl/dev_tools/run_local_genai_e2e.rb`
- `claims_ai_service_ddl/dev_tools/generate_normalized_genai_seed.py`

The local GenAI E2E test should compile directly from normalized mappings.

## 6. Migration Strategy

Recommended sequence:

1. Add explicit GenAI continuation flags so OCR/package flow no longer depends on a ruleset id being present.
2. Complete `remove_validationgenai_rulesets_plan0_rule_prompt_plan.md`.
3. Refactor runtime to compile from normalized tables while leaving old DB columns/table in place.
4. Compare runtime-compiled prompts against current `validationgenai_rulesets.user_record1` for every upgrade type.
5. Update tests/dev tools to no longer require ruleset rows.
6. Remove ruleset publishing from normalized admin saves.
7. Remove ruleset id pipeline parameters.
8. Remove API/frontend display dependencies on `validationgenai_ruleset_id`.
9. Move `validationgenai_config` endpoints out of `ValidationgenaiRulesetsController`.
10. Rebuild local schema without `claims.validationgenai_rulesets`.
11. Run local end-to-end tests.
12. Stop here for this implementation pass. Manual local testing happens before any Gold work.
13. Later, after manual sign-off, create a separate Gold rollout plan and apply compatible code/schema/seed changes there.

Avoid dropping the table before runtime no longer references it.

Avoid dropping columns before serializers/frontends no longer expect `validationgenai_ruleset_id`.

## 7. Verification Plan

### 7.1 Static Checks

Run:

```bash
rg -n "ValidationgenaiRuleset|validationgenai_rulesets|validationgenai_ruleset_id|ruleset-editor|rulesets-admin" app config claims_ai_service_ddl -S
```

Expected after full cleanup:

- no runtime references to `Claims::ValidationgenaiRuleset`
- no DDL table or FK references
- no active frontend routes to old ruleset editor/admin
- no seed insert into `claims.validationgenai_rulesets`
- no API payloads requiring `validationgenai_ruleset_id`
- no package/OCR flow using ruleset id as a GenAI continuation flag

Some archived plan references can remain if intentionally archived.

### 7.2 Local DB Rebuild

Run the documented local rebuild order after DDL/seed changes.

Verify:

```sql
SELECT to_regclass('claims.validationgenai_rulesets');
```

Expected:

- `NULL`

### 7.3 Local Runtime Tests

Run at least:

- one invoice package with one detected upgrade type
- one invoice package with multiple detected upgrade types
- one package with supporting documents and supporting-document located fields
- one redo GenAI-only flow
- one redo entire invoice package flow
- one package flow that proves OCR still continues into GenAI using the new explicit flag
- one package flow that runs OCR/classifier but intentionally does not continue into GenAI, if such a mode remains supported

Verify:

- GenAI calls succeed.
- `claims.ingest_step_runs.context_window_json` is populated for each GenAI call.
- `context_window_json` includes system record, shared user record, compiled normalized rules, case facts, DI invoice JSON, and actual ask.
- `context_window_json` stores case facts and raw DI invoice JSON as separate user messages, with the actual ask last.
- rebate/math rules no longer depend on invisible "summary-table values above", "cap above", "background section", category mapping, top-up, or formula text.
- outputs still populate `invoice_version_rulechecks`.
- outputs still populate `invoice_version_located_fields`.
- no code path requires `validationgenai_ruleset_id`.
- step history screens load without displaying or depending on ruleset id.

### 7.4 UI/API Verification

Open and verify:

- AI Admin step history
- Redo Invoice Package step tracker
- invoice review/read screens
- contractor portal history/status views
- Validation Rules Portal by Upgrade Type
- Validation Rules Portal Alphabetic
- Validation Rules Config

Verify:

- no screen errors from missing `validationgenai_ruleset_id`
- no visible old "GenAI Rulesets Admin" path is required
- GenAI config still loads and saves after moving config endpoints

### 7.5 Failed-Call Audit Test

Force or simulate a GenAI failure after context-window build.

Verify:

- failed `ingest_step_runs` row stores `context_window_json`
- failed row stores `error_text`

## 8. Risks

- Removing the table too early will break `RunGenaiJob`.
- Removing `validationgenai_ruleset_id` before adding an explicit `enqueue_genai_after` flag can stop flows after OCR.
- Existing Gold data may have FK references from historical rows.
- UI screens may display `validationgenai_ruleset_id` in step history grids; these columns need to be removed or replaced with more useful labels.
- Some legacy API clients may still pass `validationgenai_ruleset_id`; ignore or remove this param carefully.
- If compiling at runtime becomes expensive, add a deterministic in-memory/request-local cache, not a mutable database ruleset table.
- Gold is not part of this implementation pass; do not update Gold until the local app has been manually tested and explicitly approved.

## 9. Preferred End State

The final architecture should be easy to explain:

1. Normalized tables define what rules and fields exist.
2. Mappings define which rules and fields apply to each upgrade type.
3. Runtime compiles the prompt from normalized source-of-truth records.
4. Runtime sends the LLM the compiled prompt plus case facts and DI JSON.
5. Runtime stores the full actual context window in `ingest_step_runs.context_window_json`.
6. Auditors inspect the actual context window, not a reconstructed prompt cache.
