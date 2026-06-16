# Claims AI Pipeline Parallelization Plan

Status: draft plan, local first.

Purpose: safely parallelize the claims AI invoice-processing pipeline locally without changing the business meaning of the evidence tables or the review UI. Gold rollout is out of scope for this plan.

## 1. Goal

The goal is to make plural pipeline steps run concurrently where the data dependencies allow it.

The main candidates are:

- `ocr_read(s)`: one OCR-read call per uploaded evidence file.
- `triage_classifier(s)`: one classifier call per OCR-read evidence file.
- `supporting_document_extraction(s)`: one extraction call per supporting document file.
- `genai_upgrade(s)`: one GenAI validation call per detected upgrade type.

The goal is not to create many queue types. The current claims worker already uses:

```text
claims_ocr
claims_genai
```

Local should continue using the same queue names. Throughput should be governed by Sidekiq concurrency and by explicit step-completion barriers.

## 2. Current Runtime Settings

Local claims worker:

```text
SIDEKIQ_CONCURRENCY=20
SIDEKIQ_QUEUES=claims_ocr,claims_genai
```

Gold claims worker, for reference only:

```text
SIDEKIQ_CONCURRENCY=20
SIDEKIQ_QUEUES=claims_ocr,claims_genai
```

Gov Azure OpenAI deployment currently has enough capacity for future Gold parallel GenAI testing, but Gold rollout is out of scope for this plan:

```text
Tokens per minute: 4,475,000
Requests per minute: 44,750
```

ADSL local GenAI deployment has enough capacity for initial local testing:

```text
Deployment: gpt-5.4
Rate limit: 250,000 tokens/minute
Requests: 2,500 requests/minute
```

## 3. Design Principles

Use one orchestration path. Do not maintain separate serial and parallel implementations.

Parallel child jobs must be idempotent. Retrying a child job must not duplicate evidence rows or leave mixed old/new evidence.

Every fan-out group needs a barrier. The next pipeline step must start only after all required child step runs are terminal.

Evidence should be written by the step that owns it:

- OCR-read evidence by `ocr_read`.
- Classifier evidence by `triage_classifier`.
- Supporting-document file facts by `supporting_document_extraction`.
- Supporting-document group facts by `supporting_document_group_extraction`.
- Existing database facts by `case_facts`.
- Product-list enrichment facts by `product_lookup_enrichment`.
- Rulecheck outcomes by GenAI/code rule steps.

The context window should be assembled just-in-time by the GenAI call step from already-persisted evidence and database facts.

## 4. Proposed Pipeline Shape

The business order stays the same. Only plural steps become concurrent inside their stage.

```text
upload_package_stage
ocr_read(s)                         parallel group
triage_classifier(s)                parallel group
ocr_invoice                         single step
supporting_document_extraction(s)   parallel group
supporting_document_group_extraction(s) parallel group, if groups exist
case_facts                          single step
product_lookup_enrichment           single step
genai_common                        single step
genai_upgrade(s)                    parallel group
code_common                         single step
code_upgrade                        single step, leave serial
aggregate_advice                    single step
```

The invoice status labels may still be `evidence_prep` and `validation_advice` if/when those status names are adopted. Parallelization does not require status renaming.

## 5. Phase 0: Baseline Local Timing And Evidence Snapshot

Do not change orchestration in this phase.

Tasks:

- Use the local regression package suite in section 16.
- Record current processing time from upload start to `genai_complete`.
- Record counts from key evidence tables after completion.

Suggested evidence checks:

```sql
select count(*) from claims.ingest_step_runs;
select step_type, status, count(*) from claims.ingest_step_runs group by step_type, status order by step_type, status;
select count(*) from claims.invoice_version_located_fields;
select count(*) from claims.invoice_version_rulechecks;
select count(*) from claims.supporting_documents;
select count(*) from claims.supporting_document_located_fields;
select count(*) from claims.supporting_document_groups;
select count(*) from claims.supporting_document_group_located_fields;
```

Test gate:

- Baseline package still completes successfully before any refactor.
- Save the table counts and elapsed time as the comparison point.

## 6. Phase 1: Add Barrier Helpers Without Fan-Out

Create or refactor helper code that can answer:

- Are all step runs for this group terminal?
- Did any required step fail?
- Which child step runs are still pending or running?
- Is it safe to enqueue the next pipeline step?

This phase should keep the current mostly-serial behavior. The purpose is to add the coordination language before adding parallelism.

Likely helpers:

- `Claims::Ingest::StepGroupStatus`
- `Claims::Ingest::AdvanceBundleRun`
- existing `claims.ingest_step_runs` queries, cleaned up if needed

Test gate:

- Run the same baseline local package.
- Confirm evidence counts match Phase 0 except for any intentionally added audit rows.
- Confirm no step starts before its dependency is terminal.
- Confirm retrying a barrier/advance job does not duplicate downstream work.

## 7. Phase 2: Parallelize `supporting_document_extraction(s)` Locally

This is the first useful fan-out target because each supporting document file can be extracted independently.

Tasks:

- Change the parent pipeline step to enqueue one child extraction job per promoted supporting document.
- Each child job writes its own `supporting_document_extraction` step run.
- The group barrier advances only after all supporting-document extraction child runs are terminal.
- If one supporting document extraction fails, hard-fail the package noisily. Extraction runtime failure should not become `needs_review`; it should be treated as an unexpected processing failure.

Test gate:

- Run a package with at least two supporting documents.
- Confirm multiple extraction step runs can be `in_progress` around the same time.
- Confirm each supporting document has only its own located fields.
- Confirm no duplicate `supporting_document_located_fields`.
- Confirm the pipeline advances only after all extraction children finish.
- Confirm any extraction runtime failure moves the package/invoice to a failed processing state and leaves clear error text in the relevant step run.

## 8. Phase 3: Parallelize `supporting_document_group_extraction(s)` Locally

Do this after file-level supporting-document extraction is stable. Group extraction is still a good parallelization target, but it depends on the grouping model and multi-file evidence, so it should not be bundled into the first file-level extraction fan-out change.

Tasks:

- Enqueue one child extraction job per `claims.supporting_document_groups` row that needs group-level extraction.
- Each child job writes its own `supporting_document_group_extraction` step run.
- Each child job writes group-level evidence to `claims.supporting_document_group_located_fields`.
- The group barrier advances only after all supporting-document group extraction child runs are terminal.
- Keep file-level extraction and group-level extraction evidence separate.

Test gate:

- Run a package with a grouped photo/document set.
- Confirm group extraction has one step run per supporting-document group.
- Confirm group-level fields such as `photo_pair_completeness_evidence` are written to group-level located fields, not file-level located fields.
- Confirm no duplicate group located fields appear after retry.
- Confirm the pipeline advances only after all group extraction children finish.

## 9. Phase 4: Parallelize `triage_classifier(s)` Locally

Classifier calls are independent per OCR-read file, but the package cannot be resolved until all classifiers finish.

Tasks:

- Enqueue one classifier child job per OCR-read ingest document.
- Keep package-shape validation after all classifier children are terminal.
- Confirm exactly-one-invoice validation still happens once, after the classifier group finishes.
- Persist classifier-owned evidence into evidence tables, not by re-reading ingest JSON later.

Test gate:

- Run a package with one invoice and multiple supporting documents.
- Confirm all files receive classifier rows.
- Confirm package resolution still creates exactly one invoice version.
- Confirm supporting documents are promoted once.
- Confirm no validation/GenAI step starts while classifier children are still running.

## 10. Phase 5: Parallelize `ocr_read(s)` Locally

OCR-read fan-out can speed package intake, but it touches external Document Intelligence and blob bytes, so it should come after classifier/extraction orchestration is stable.

Tasks:

- Enqueue one OCR-read child job per staged evidence file.
- Barrier waits until all OCR-read children are terminal before classifier fan-out.
- Keep file-level errors attached to the correct ingest document.

Test gate:

- Run a package with PDFs and image files if image support is enabled.
- Confirm each file has one OCR-read step run.
- Confirm failed/unsupported file behavior is clear and does not block unrelated successful files incorrectly.
- Confirm classifier fan-out begins only after OCR-read group completion.

## 11. Phase 6: Parallelize `genai_upgrade(s)` Locally

This is the highest-value validation parallelization step.

Tasks:

- Keep `genai_common` single.
- Enqueue one `genai_upgrade` child job per detected upgrade type.
- Each upgrade child builds its own context window just-in-time.
- Each upgrade child writes only its own upgrade-scoped located fields, rulechecks, and upgrade result/advice.
- Barrier waits for all upgrade children before code/aggregate steps.

Test gate:

- Run a multi-upgrade invoice package.
- Confirm `genai_upgrade` has one step run per detected upgrade type.
- Confirm rulechecks are grouped under the correct `invoice_upgrade_type_id`.
- Confirm `common` stays separate from upgrade-specific rulechecks.
- Confirm aggregate advice waits for all upgrade GenAI children.
- Confirm rerunning the package does not duplicate old upgrade rulechecks.

## 12. Phase 7: Keep Code Validation Serial

Do not parallelize deterministic code validation for this project. The code-rule steps are database/code work, not expensive external GenAI calls, and keeping them serial reduces coordination risk.

Tasks:

- Keep `code_common` single.
- Keep `code_upgrade` single.
- Confirm `code_upgrade` still runs after the GenAI upgrade barrier and before aggregate advice.

Test gate:

- Run packages with AHRI, NEEA, AWHP, and OHPA product-list checks.
- Confirm product match foreign keys remain stable.
- Confirm code rulechecks are not duplicated.
- Confirm aggregate advice still waits for code checks.

## 13. Phase 8: Local Load Test

Use local first before touching Gold.

Tasks:

- Run two invoice packages at roughly the same time.
- Run one larger package with multiple supporting documents and multiple upgrade types.
- Watch Sidekiq logs and database step status.

Test gate:

- No stuck `in_progress` step runs.
- No duplicate evidence rows.
- No package advances out of order.
- No unexpected `429` or external-service timeout pattern.
- UI still shows correct step progress and final advice.

## 14. Gold Out Of Scope

Gold changes are deliberately out of scope for this plan.

After local implementation and testing are complete, a separate deployment step is needed:

- Build and push a new app image.
- Restart the Gold app and claims Sidekiq deployments.
- Run a separate Gold smoke-test plan.

Do not treat local success as automatically deployed to Gold.

## 15. Rollback Plan

Rollback is local-code based for this plan.

- Revert the local orchestration code change that introduced the break.
- If a package is stuck, mark failed/in-progress step runs explicitly and rerun from a clean package upload path.

Avoid creating a separate serial implementation unless a specific production issue proves it is needed.

## 16. Open Questions

No open questions remain for the first implementation pass.

## 17. Implementation Notes

Implemented locally:

- `genai_common` and `genai_upgrade(s)` now fan out into `Claims::RunGenaiRulesetJob` child jobs.
- `Claims::RunGenaiJob` remains the validation conductor. It runs `case_facts` and `product_lookup_enrichment`, then queues common and upgrade GenAI ruleset child jobs together.
- A `finish_validation` mode on `Claims::RunGenaiJob` acts as the barrier/finalizer. It waits until `genai_common` and every `genai_upgrade` child step has succeeded before running serial code checks and `aggregate_advice`.
- Code validation remains serial.
- No DDL changes were made.

Local smoke test completed:

- Package: `claims_ai_service_documentation/Test Data/Heat Pump/test013`.
- Ingest run: `e5d6820f-8fc2-47b8-8ac5-7c10351a743c`.
- Result: `claims.ingest_runs.status = succeeded`; invoice reached `genai_complete`.
- Initial smoke test observed three concurrent `genai_upgrade` rows for `air_source_heat_pump_gas_propane`, `electrical_service_upgrade`, and `ventilation`, followed by serial `code_common`, `code_upgrade`, and `aggregate_advice`.
- Follow-up implementation change made `genai_common` a parallel ruleset child as well, so the expected final GenAI phase is `genai_common` plus all `genai_upgrade` rows queued together.
- Follow-up smoke test passed with ingest run `9340da9f-5fce-4cc1-9aa8-7369dcaa44fe`. It observed `genai_common` and all three `genai_upgrade` rows in progress together, then serial `code_common`, `code_upgrade`, and `aggregate_advice`, ending with `claims.ingest_runs.status = succeeded`.

Remaining future implementation phases:

- Keep observing the already fan-out-shaped `ocr_read(s)`, `triage_classifier(s)`, `supporting_document_extraction(s)`, and `supporting_document_group_extraction(s)` paths under larger local packages.
- Run the full local regression package suite before any Gold image is built.

## 18. Local Regression Package Suite

Use these local packages as the official parallelization regression suite. The point is not to run every historical test package; it is to cover the pipeline shapes that can break when child jobs start running concurrently.

Core suite:

- `claims_ai_service_documentation/Test Data/Heat Pump/test006`: heat-pump invoice plus WETT report PDF. Covers invoice plus supporting-document PDF extraction, visual evidence inside a PDF, and heat-pump validation.
- `claims_ai_service_documentation/Test Data/Heath & Safety/test006`: health/safety invoice plus two standalone JPG supporting documents. Covers non-PDF evidence files, grouped photo behavior, and group-level extraction.
- `claims_ai_service_documentation/Test Data/Insulation/test006`: insulation invoice plus before/after JPG photos. Covers before/after photo grouping and group-level located fields such as `photo_pair_completeness_evidence`.
- `claims_ai_service_documentation/Test Data/Heat Pump/test013`: one invoice with heat pump, ventilation, and electrical service upgrade. Covers multi-upgrade `genai_upgrade(s)` fan-out and upgrade-scoped rulechecks.
- `claims_ai_service_documentation/Test Data/windows doors/test002`: typo PDF followed by corrected PDF through the `+1 fix` path. Covers versioning, invoice-version diffs, and validation restart from persisted evidence.

Phase-specific add-ons:

- `claims_ai_service_documentation/Test Data/windows doors/test006`: fenestration invoice plus energy-tag JPEGs. Use when touching image handling, supporting-document classification, or windows/doors located fields.
- `claims_ai_service_documentation/Test Data/Electric Service Upgrade/test005`: simple electrical-service-upgrade invoice. Use as a smaller smoke test for ESU validation when the full multi-upgrade package is too slow.

Recommended run pattern:

- For small orchestration refactors, run `Heat Pump/test006`, `Heath & Safety/test006`, and `Heat Pump/test013`.
- For versioning or `+1 fix` changes, also run `windows doors/test002`.
- For image/file-type changes, also run `Insulation/test006` and `windows doors/test006`.
- Before declaring the parallelization work complete, run the full core suite and then the two phase-specific add-ons.
