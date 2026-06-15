# Claims AI Pipeline Job Class Alignment Plan

## Purpose

Align Sidekiq job class names and responsibilities with the actual Claims AI pipeline step names.

The current job classes reflect the history of the implementation more than the current pipeline model. This makes Sidekiq logs, retry debugging, and production troubleshooting harder than they need to be. The goal is not to change business behaviour. The goal is to make the background jobs read like the pipeline.

This is a full cleanup plan, not just a cosmetic rename. The cleanup will be done in stages so each stage has a clear test gate before the next stage starts.

## Current Problem

The pipeline is understood in terms of `ingest_step_runs.step_type`, but the Sidekiq job class names do not map cleanly to those step types.

Examples:

- `RunIngestTriageJob` actually performs `classifier_pdfs` and `classifier_imagefiles`.
- `RunOcrJob` performs `ocr_invoice`, and still has older naming/comments around generic OCR.
- `RunInvoiceVersionClassifierJob` performs the `+1fix` classifier path and then queues `ocr_invoice`.
- `RunGenaiJob` performs or orchestrates many different logical steps: `case_facts`, `product_lookup_enrichment`, `genai_common`, `genai_upgrade`, `code_common`, `code_upgrade`, and `aggregate_advice`.
- `RunGenaiRulesetJob` is named as if it is GenAI work, but it actually runs code rules.

This is confusing because the code works in step-run vocabulary, but the worker/job vocabulary is different.

## Target Pipeline Vocabulary

The job names should align to these step-run names:

| Step | Step-run name                           | Intended meaning                                                                       |
| ---- | --------------------------------------- | -------------------------------------------------------------------------------------- |
| 1    | `upload_package_stage`                  | Upload files and create package/session/invoice shell rows. Usually not Sidekiq.       |
| 2    | `ocr_read`                              | DI-read every uploaded file.                                                           |
| 3    | `classifier_pdfs`                       | Classify PDF files using DI-read output only.                                          |
| 4    | `classifier_imagefiles`                 | Classify image files using the attached image as primary evidence.                     |
| 5    | `supporting_document_single_extraction` | Extract evidence from supporting documents not handled as a group.                     |
| 6    | `supporting_document_group_extraction`  | Extract group-level evidence and per-file visual evidence for grouped supporting docs. |
| 7a   | `plus1fix_ocr_read`                     | DI-read the replacement invoice PDF for +1 fix.                                        |
| 7b   | `plus1fix_classifier`                   | Re-classify the replacement invoice PDF for +1 fix.                                    |
| 7c   | `ocr_invoice`                           | DI-invoice extraction and invoice-version field/line-item population.                  |
| 8    | `case_facts`                            | Build persisted case facts from DB evidence.                                           |
| 9    | `product_lookup_enrichment`             | Match classifier references against product/download tables.                           |
| 10   | `genai_common`                          | Common AI advice call.                                                                 |
| 11   | `genai_upgrade`                         | Upgrade-type-specific AI advice calls.                                                 |
| 12   | `code_common`                           | Common code rules.                                                                     |
| 13   | `code_upgrade`                          | Upgrade-type-specific code rules.                                                      |
| 14   | `aggregate_advice`                      | Aggregate all advice/results into final invoice advice.                                |

## Proposed Job Class Names

Use a new namespace to make the pipeline intent explicit:

`Claims::Pipeline::*`

Recommended mapping:

| Step-run name                           | Current job class                                    | Proposed job class                                        |
| --------------------------------------- | ---------------------------------------------------- | --------------------------------------------------------- |
| `ocr_read`                              | `Claims::RunIngestReadOcrJob`                        | `Claims::Pipeline::OcrReadJob`                            |
| `classifier_pdfs`                       | `Claims::RunIngestTriageJob`                         | `Claims::Pipeline::ClassifierPdfsJob`                     |
| `classifier_imagefiles`                 | `Claims::RunIngestTriageJob`                         | `Claims::Pipeline::ClassifierImagefilesJob`               |
| `supporting_document_single_extraction` | `Claims::RunSupportingDocumentExtractionJob`         | `Claims::Pipeline::SupportingDocumentSingleExtractionJob` |
| `supporting_document_group_extraction`  | `Claims::RunSupportingDocumentGroupExtractionJob`    | `Claims::Pipeline::SupportingDocumentGroupExtractionJob`  |
| `plus1fix_ocr_read`                     | `Claims::RunInvoiceVersionClassifierJob`             | `Claims::Pipeline::Plus1FixOcrReadJob`                    |
| `plus1fix_classifier`                   | `Claims::RunInvoiceVersionClassifierJob`             | `Claims::Pipeline::Plus1FixClassifierJob`                 |
| `ocr_invoice`                           | `Claims::RunOcrJob`                                  | `Claims::Pipeline::OcrInvoiceJob`                         |
| `case_facts`                            | `Claims::RunGenaiJob`                                | `Claims::Pipeline::CaseFactsJob`                          |
| `product_lookup_enrichment`             | `Claims::RunGenaiJob`                                | `Claims::Pipeline::ProductLookupEnrichmentJob`            |
| `genai_common`                          | `Claims::RunGenaiJob`                                | `Claims::Pipeline::GenaiCommonJob`                        |
| `genai_upgrade`                         | `Claims::RunGenaiJob`                                | `Claims::Pipeline::GenaiUpgradeJob`                       |
| `code_common`                           | `Claims::RunGenaiRulesetJob` / `Claims::RunGenaiJob` | `Claims::Pipeline::CodeCommonJob`                         |
| `code_upgrade`                          | `Claims::RunGenaiRulesetJob` / `Claims::RunGenaiJob` | `Claims::Pipeline::CodeUpgradeJob`                        |
| `aggregate_advice`                      | `Claims::RunGenaiJob`                                | `Claims::Pipeline::AggregateAdviceJob`                    |

## Guiding Rules

- Keep `ingest_step_runs.step_type` unchanged.
- Keep DB schema unchanged.
- Keep queue names unchanged for now: `claims_ocr` and `claims_genai`.
- Keep all claims pipeline jobs at `retry: 3`.
- Prefer wrappers first, then move logic later.
- Avoid changing business output while renaming/refactoring.
- Every step should be independently retry-safe and should reuse/update the same `ingest_step_runs` row where possible.

## Implementation Strategy

This work should be done as a sequence of safe, tested stages:

1. Introduce new pipeline-named jobs as wrappers.
2. Switch enqueue sites to the new names.
3. Move evidence-prep logic into the new step-specific jobs.
4. Move +1 fix logic into the new step-specific jobs.
5. Move invoice OCR logic into the new step-specific job.
6. Split validation/advice orchestration into the new step-specific jobs.
7. Remove old job classes only after local and Gold validation.

Each stage must end with a concrete local test. Do not proceed to the next stage if the current stage leaves stuck, failed, duplicated, or missing `ingest_step_runs`.

## Stage Gates

Every stage must satisfy these general gates:

- All touched Ruby files pass syntax checks.
- Grep confirms enqueue sites point to the intended job classes for that stage.
- Sidekiq queues drain after the test package.
- `claims.ingest_step_runs` has no `queued`, `in_progress`, or `failed` rows for the tested run.
- Final invoice reaches the expected status.
- The step-run names remain the same business pipeline names.

## Implementation Plan

### Stage 1: Add Pipeline Namespace Wrappers

Create new wrapper job classes under:

`app/jobs/claims/pipeline/`

Initial wrappers should delegate to existing working job classes. This gives Sidekiq/log visibility using the new names without moving all logic immediately. This stage is intentionally mechanical and should not change pipeline output.

Example:

```ruby
module Claims
  module Pipeline
    class ClassifierPdfsJob
      include Sidekiq::Job
      sidekiq_options queue: :claims_genai, retry: 3

      def perform(ingest_document_id, ingest_run_id)
        Claims::RunIngestTriageJob.new.perform(
          ingest_document_id,
          ingest_run_id,
          "classifier_pdfs"
        )
      end
    end
  end
end
```

Test after Stage 1:

- Run Ruby syntax checks for all new wrapper jobs.
- Confirm each wrapper class can be constantized by Rails.
- Run a small local package and confirm old worker behaviour still succeeds.
- Confirm Sidekiq can constantize the new classes.
- Confirm no enqueue sites have been changed yet unless this stage is combined with Stage 2.

Decision gate:

- Proceed only if wrappers load cleanly and do not alter existing behaviour.

### Stage 2: Change Enqueue Sites To New Job Names

Update orchestration code to enqueue the new pipeline job classes instead of the old names.

Likely files:

- `app/services/claims/ingest/create_draft_batch.rb`
- `app/services/claims/ingest/advance_bundle_run.rb`
- `app/services/claims/ingest/upload_fix_pdf.rb`
- `app/controllers/api/claims/ingest_controller.rb`
- Any direct `perform_async` calls found by grep.

Test after Stage 2:

- Run local `test014` full package.
- Confirm Sidekiq/logs show new job class names.
- Confirm `ingest_step_runs.step_type` rows remain exactly the same.
- Confirm final invoice reaches `genai_complete`.
- Confirm all expected `test014` counts match the known-good baseline:
- `ocr_read`: 6
- `classifier_pdfs`: 2
- `classifier_imagefiles`: 4
- `supporting_document_single_extraction`: 3
- `supporting_document_group_extraction`: 1
- `ocr_invoice`: 1
- `case_facts`: 1
- `product_lookup_enrichment`: 1
- `genai_common`: 1
- `genai_upgrade`: 3
- `code_common`: 1
- `code_upgrade`: 3
- `aggregate_advice`: 1

Decision gate:

- Proceed only if local `test014` succeeds with the new job names visible in Sidekiq/logs.

### Stage 3: Split Evidence-Prep Jobs Internally

Move evidence-prep logic into step-specific jobs.

Move OCR-read logic out of `RunIngestReadOcrJob` into:

- `Claims::Pipeline::OcrReadJob`

Move classifier-specific logic out of `RunIngestTriageJob` into:

- `Claims::Pipeline::ClassifierPdfsJob`
- `Claims::Pipeline::ClassifierImagefilesJob`

Move supporting-document extraction logic out of the old supporting-document jobs into:

- `Claims::Pipeline::SupportingDocumentSingleExtractionJob`
- `Claims::Pipeline::SupportingDocumentGroupExtractionJob`

Shared helper/service code can remain shared, but the job classes should no longer need a `requested_step_type` argument to decide what they are.

Test after Stage 3:

- Run local `test014`.
- Confirm `classifier_pdfs` and `classifier_imagefiles` both create/update the correct step rows.
- Confirm image classifier sends attachment and PDF classifier does not.
- Confirm exactly one invoice candidate is enforced after PDF classifier completion.
- Confirm single supporting documents and grouped supporting documents both extract evidence.
- Confirm visual findings are present for image files.
- Confirm no `RunIngestReadOcrJob`, `RunIngestTriageJob`, `RunSupportingDocumentExtractionJob`, or `RunSupportingDocumentGroupExtractionJob` enqueue calls remain.

Decision gate:

- Proceed only if a mixed PDF/image package succeeds and evidence tables match the prior known-good shape.

### Stage 4: Split +1 Fix Jobs

Move +1 fix logic out of `RunInvoiceVersionClassifierJob` into:

- `Claims::Pipeline::Plus1FixOcrReadJob`
- `Claims::Pipeline::Plus1FixClassifierJob`

The +1 flow should show these two step-runs explicitly and then continue to `ocr_invoice`.

Test after Stage 4:

- Run a +1 fix with a valid replacement invoice.
- Confirm `plus1fix_ocr_read`, `plus1fix_classifier`, and `ocr_invoice` all succeed.
- Confirm replacement invoice version is reclassified.
- Confirm supporting-document evidence is not rebuilt for +1 fix.
- Confirm a replacement PDF that is not an invoice hard-fails before validation.
- Confirm no `RunInvoiceVersionClassifierJob` enqueue calls remain.

Decision gate:

- Proceed only if +1 fix behaves correctly and still only replaces the invoice PDF.

### Stage 5: Split Invoice OCR Job

Move invoice extraction/promotion logic into:

- `Claims::Pipeline::OcrInvoiceJob`

Keep `ocr_read` file DI-read separate from `ocr_invoice` invoice DI extraction.

Test after Stage 5:

- Run local `test014`.
- Confirm `ocr_read` rows are per uploaded file.
- Confirm `ocr_invoice` is a version-specific step.
- Confirm invoice first-class fields and line items populate correctly.
- Confirm the invoice version row is created/reused correctly for normal upload.
- Confirm the invoice version row is already present for +1 fix and is updated correctly.
- Confirm no `RunOcrJob` enqueue calls remain for Claims AI pipeline work.

Decision gate:

- Proceed only if invoice fields and line items match the known-good `test014` output.

### Stage 6: Split Validation/Advice Jobs From `RunGenaiJob`

This is the largest cleanup and should be done last.

Extract the current `RunGenaiJob` phases into explicit jobs:

- `Claims::Pipeline::CaseFactsJob`
- `Claims::Pipeline::ProductLookupEnrichmentJob`
- `Claims::Pipeline::GenaiCommonJob`
- `Claims::Pipeline::GenaiUpgradeJob`
- `Claims::Pipeline::CodeCommonJob`
- `Claims::Pipeline::CodeUpgradeJob`
- `Claims::Pipeline::AggregateAdviceJob`

Keep orchestration rules explicit:

- `case_facts` must run before product lookup and AI advice.
- `product_lookup_enrichment` must run before product-dependent code rules.
- `genai_common` and `genai_upgrade` can run in parallel after product lookup.
- `code_common` and `code_upgrade` can run after their required evidence/advice inputs exist.
- `aggregate_advice` runs after all required GenAI and code-rule steps are complete.

Test after Stage 6:

- Run local `test014`.
- Confirm all 14 pipeline step types appear in order/logically.
- Confirm 3 detected upgrade types create 3 `genai_upgrade` and 3 `code_upgrade` rows.
- Confirm final invoice reaches `genai_complete`.
- Compare key DB counts with the previous known-good `test014` run.
- Confirm `genai_common` and all `genai_upgrade` rows can run concurrently without losing aggregation.
- Confirm code rules run once for common and once per detected upgrade type.
- Confirm `RunGenaiJob` and `RunGenaiRulesetJob` are no longer active enqueue targets.

Decision gate:

- Proceed only if validation/advice output and final aggregate advice match the known-good behaviour.

### Stage 7: Remove Old Job Classes

Only after local and Gold tests pass, remove or deprecate old job classes:

- `Claims::RunIngestReadOcrJob`
- `Claims::RunIngestTriageJob`
- `Claims::RunSupportingDocumentExtractionJob`
- `Claims::RunSupportingDocumentGroupExtractionJob`
- `Claims::RunOcrJob`
- `Claims::RunInvoiceVersionClassifierJob`
- `Claims::RunGenaiJob`
- `Claims::RunGenaiRulesetJob`

Before deleting, check Sidekiq retry/dead sets for jobs using the old class names.

Test after Stage 7:

- Grep for old class names returns no active references.
- Sidekiq queues contain only new pipeline job classes.
- Full local `test014` still succeeds.
- Gold `test014` still succeeds after image deploy.

Decision gate:

- Delete old job classes only when there are no old-class jobs in Sidekiq queue, retry, scheduled, or dead sets.

## Regression Suite

Minimum local test set:

- `heatpump/test014`: multi-upgrade, mixed PDFs/images, groups and singles.
- `insulation/test006`: image-heavy before/after photo group.
- A normal single-upgrade heat pump package with WETT report.
- A +1 fix replacement invoice test.

For each test:

- Confirm final invoice status.
- Confirm no failed or stuck `ingest_step_runs`.
- Confirm expected step-run counts by `step_type`.
- Confirm invoice fields, line items, supporting docs, visual findings, upgrade types, rules, and aggregate advice are populated.

## Known-Good Test014 Baseline

The latest known-good Gold/local shape for `heatpump/test014` is:

- Upload files: 6 total files.
- Invoice: `HP-TEST014-MULTI`.
- Detected upgrade types: `air_source_heat_pump_wood`, `insulation`, `windows_doors`.
- `ocr_read`: 6 succeeded.
- `classifier_pdfs`: 2 succeeded.
- `classifier_imagefiles`: 4 succeeded.
- `supporting_document_single_extraction`: 3 succeeded.
- `supporting_document_group_extraction`: 1 succeeded.
- `ocr_invoice`: 1 succeeded.
- `case_facts`: 1 succeeded.
- `product_lookup_enrichment`: 1 succeeded.
- `genai_common`: 1 succeeded.
- `genai_upgrade`: 3 succeeded.
- `code_common`: 1 succeeded.
- `code_upgrade`: 3 succeeded.
- `aggregate_advice`: 1 succeeded.
- Final invoice status: `genai_complete`.

Use this as the first-pass regression signature after each stage.

## Risks

- Renaming all jobs at once could strand jobs already queued under old class names.
- Splitting `RunGenaiJob` is higher risk because it currently contains orchestration and dependency checks for many later phases.
- If wrappers call existing job classes directly, logs improve but code organization does not fully improve until later steps.
- Existing Sidekiq retry/dead jobs may reference old class names during deploy cutover.

## Recommended Rollout

1. Complete Stage 1 and Stage 2 locally.
2. Run `test014` locally.
3. Push image.
4. Deploy to Gold.
5. Run `test014` on Gold.
6. Continue one stage at a time locally.
7. After each major stage, push/deploy only when local regression passes.
8. Keep old job classes until the final stage so rollback is simple.

This keeps each change bounded and testable while still moving toward the full cleanup.
