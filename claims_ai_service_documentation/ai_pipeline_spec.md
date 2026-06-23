# AI Pipeline Specification

This document is the source-of-truth pipeline specification for claims AI ingest and validation work.

When changing, debugging, or reviewing this area, always ask:

> Is the codebase aligned to this spec?

If the implementation and this document disagree, treat that as a bug or an explicit product decision that needs to be documented.

The upgrade GenAI context-window stack is specified separately in
`claims_ai_service_documentation/genai_context_window_spec.md`.

## Display Rules

- Read each pipeline from top to bottom.
- A single package run should follow one entry path: NEW, FIX, or rule-change-only.
- Branch-specific rows should not be mixed into another branch's run history.
- A row in `claims.ingest_step_runs` means actual work was queued, ran, succeeded, or failed. Do not write a step row only to explain that prior evidence was reused.
- Step rows should describe the actual unit of work. For example, supporting-document extraction is a supporting-document-type/evidence-set operation, not an invoice OCR or invoice GenAI row.
- Reuse/clone facts should be inferred from the database state: cloned ingest documents, copied invoice/supporting-document evidence, matching SHA values, copied DI/classifier JSON, and prior/new invoice-version relationships.
- Once the flow skips to step 8, the shared GenAI/code pipeline begins.

## Step Row Contract

`claims.ingest_step_runs` is the execution timeline. It should not be used as a general-purpose explanation log.

Valid step rows fall into one of these target shapes:

| Target shape                 | Meaning                                                                       | Examples                                                                                        |
| ---------------------------- | ----------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Package-level row            | A deterministic package action happened.                                      | `upload_package_stage`, `fix_upload_package_stage`                                              |
| Ingest-document row          | Work happened for one uploaded/staged file.                                   | `ocr_read`, `fix_ocr_read`, `classifier_files`, `fix_classifier_files`                          |
| Invoice-version row          | Work happened for the resolved invoice version.                               | `ocr_invoice`, `fix_ocr_invoice`, `case_facts`, `product_lookup_enrichment`, `aggregate_advice` |
| Supporting-document-type row | Work happened for one supporting-document type / evidence set.                | `supporting_document_extraction`, `fix_supporting_document_extraction`                          |
| Upgrade-type row             | Work happened for one invoice upgrade type, or one common rule set if scoped. | `genai_common`, `genai_upgrade`, `code_common`, `code_upgrade`                                  |

Rules:

- Do not create a successful step row for work that did not execute.
- Do not create `*_ocr_read`, `*_classifier_files`, `*_supporting_document_extraction`, or `*_ocr_invoice` rows just to indicate reuse.
- A deterministic reconciliation step may have a row if it actually writes or reconciles state. Example: `fix_clone_existing_evidence`.
- UI screens may explain reuse, but that explanation should be derived from existing DB facts rather than represented as fake successful work.
- The pipeline auditor/errorchecker should read these rows and related DB facts, then flag rows that do not match this contract.

## NEW Simulation Flow

| Step      | Step Run Will Show               | Invoice Status       | Description                                                                                                                                                                                                      |
| --------- | -------------------------------- | -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1         | `upload_package_stage`           | `upload_in_progress` | Via contractor NEW simulation.                                                                                                                                                                                   |
| 2         | `ocr_read`                       | `ocr_in_progress`    | Read uploaded files.                                                                                                                                                                                             |
| 3         | `classifier_files`               | `ocr_in_progress`    | Input is the file attached and the DI-read. Output is the supporting document type. Also extracts eligibility code and product references, including `ahri_reference`, `neea_reference`, and related references. |
| 4         | `supporting_document_extraction` | `ocr_in_progress`    | Runs once per affected supporting document type / evidence set. Input is the DI-read of each file in the group plus each directly attached file. Output is per-file located fields and per-file visual findings. |
| 5         | `ocr_invoice`                    | `ocr_in_progress`    | OCR/extraction for the invoice.                                                                                                                                                                                  |
| skip to 8 |                                  |                      | Continue at the shared pipeline.                                                                                                                                                                                 |

## FIX Simulation Flow

| Step      | Step Run Will Show                   | Invoice Status       | Description                                                                                                                                                                                                                                                                         |
| --------- | ------------------------------------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1         | `fix_upload_package_stage`           | `upload_in_progress` | Via contractor FIX simulation.                                                                                                                                                                                                                                                      |
| 2         | `fix_ocr_read`                       | `ocr_in_progress`    | Runs only for new or replaced files that need DI-read. Cloned unchanged files must not create a `fix_ocr_read` row.                                                                                                                                                                 |
| 3         | `fix_classifier_files`               | `ocr_in_progress`    | Runs only for new or replaced files that need classification. Cloned unchanged files must not create a `fix_classifier_files` row.                                                                                                                                                  |
| 4         | `fix_clone_existing_evidence`        | `ocr_in_progress`    | Copy forward unchanged files and reusable evidence from the prior version. If a cloned supporting document's type is affected by new or replaced files, copy only document/file membership and let the next extraction step rebuild that type's located fields and visual findings. |
| 5         | `fix_supporting_document_extraction` | `ocr_in_progress`    | For each affected supporting-document type, run extraction over the full revised set of files for that type, including cloned files and new files, then write fresh per-file located fields and visual findings.                                                                    |
| 6         | `fix_ocr_invoice`                    | `ocr_in_progress`    | Runs only when the invoice file is new or replaced and invoice OCR actually executes. If the invoice is cloned unchanged, do not create a `fix_ocr_invoice` row; reuse is inferred from copied invoice OCR/DI evidence.                                                             |
| skip to 8 |                                      |                      | Continue at the shared pipeline.                                                                                                                                                                                                                                                    |

Fix-run row semantics:

- `fix_ocr_read` and `fix_classifier_files` rows are executable rows for new or replaced files only. Cloned/reused invoice or supporting-document evidence must not be recorded as successful `fix_ocr_read` or `fix_classifier_files` work.
- `fix_supporting_document_extraction` rows are executable rows for affected supporting-document types only. A type is affected when at least one new or replaced supporting document belongs to that type. If all documents for that type are cloned unchanged, no extraction row should be written.
- `fix_ocr_invoice` is an executable row for new/replaced invoice OCR only. A cloned unchanged invoice must not create a fake `fix_ocr_invoice` success row.
- `fix_clone_existing_evidence` is the bookkeeping/reconciliation step that makes reused evidence available to the revised invoice version after new/replaced file classification is known.
- If a fix contains no new/replaced files, the run should be cheap: clone/reconcile evidence, skip OCR/classifier/supporting-document extraction/invoice OCR rows, and then continue to shared validation only if the product decision is to create a new invoice version for the no-op fix.

## Rule-Change-Only Simulation Flow

| Step      | Step Run Will Show                  | Invoice Status       | Description                                                                                                                               |
| --------- | ----------------------------------- | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| 1         |                                     | `upload_in_progress` | Via contractor rulechangeonly simulator. This is a new screen that lists files and has a button indicating it will apply different rules. |
| 2         | `ruleclone_clone_existing_evidence` | `ocr_in_progress`    | Clone existing evidence into a new invoice version for a rule-only rerun.                                                                 |
| skip to 8 |                                     |                      | Continue at the shared pipeline.                                                                                                          |

## Shared Pipeline

| Step | Step Run Will Show          | Invoice Status      | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| ---- | --------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 8    | `case_facts`                | `genai_in_progress` | Uses the eligibility code extracted via the classifier. Builds case facts JSON from the database, labels it in the PDF viewer accordion as `info on record`, and persists database facts in `invoice_version_located_fields` with `source_engine = 'code'`. Also resolves `claims.users_eligibilitycodes` and the associated participant user from the classifier eligibility code, then populates `invoice_versions.users_eligibilitycode_id` and `invoice_versions.participant_user_id` so later code rules can use those UUIDs directly without lookup work. |
| 9    | `product_lookup_enrichment` | `genai_in_progress` | Uses product references extracted by the classifier to build product info from download tables. This step owns product/reference enrichment only; participant/user/eligibility UUID population belongs to `case_facts`.                                                                                                                                                                                                                                                                                                                                         |
| 10   | `genaai_common`             | `genai_in_progress` | Runs in parallel with the following GenAI/code work. The spreadsheet labels this as `genaai_common`; current implementation may spell this `genai_common`, so confirm before renaming either side. Also does just-in-time CW creation, then calls the upgrade-call GenAI LLM only once.                                                                                                                                                                                                                                                                         |
| 11   | `genai_upgrade`             | `genai_in_progress` | Upgrade-specific GenAI rule execution.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| 12   | `code_common`               | `genai_in_progress` | Common code rule execution.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| 13   | `code_upgrade`              | `genai_in_progress` | Upgrade-specific code rule execution.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| 14   | `aggregate_advice`          | `genai_in_progress` | Aggregates final advice.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        |

## Step 8 Supporting Document Context

Step 8 also builds the structured supporting-document context that later GenAI rules use.

It includes:

- `supporting_document_summary`: the full list of supporting documents attached to the invoice package, regardless of upgrade type. Example: WETT report, two fenestration labels, two before/after insulation photos. This is just a list.
- `supporting_document_summary_for_upgrade_type`: a filtered view of that same evidence scoped to one upgrade type. Example: for `windows_doors`, it only cares about support-doc types configured as relevant to windows/doors. This can be a subset list.
- `configured_type_keys`: applicable supporting document type keys for the upgrade type, based on configuration. For `windows/doors`, this might include `fenestration_energy_performance_label`, `manufacturer_label_photo`, and `preapproval_quote`.
- `configured_types`: the same idea as `configured_type_keys`, but with descriptions. This is the human-readable version of the configured type list.
- `present_configured_type_keys`: of the applicable configured types, which ones were actually uploaded in this package. Example: package has `fenestration_energy_performance_label`.
- `not_present_applicable_type_keys`: applicable configured types that were not uploaded. This does not automatically mean required or failed; it means the type is relevant to the upgrade type but not attached.
- `present_configured_type_counts`: counts of uploaded applicable document types. Example: `fenestration_energy_performance_label: 2`, `before_after_photo_set: 2`.
- `configured_documents`: the actual uploaded supporting document records that match configured/applicable types for that upgrade. This is where the LLM sees filenames, routing quality, located fields, and visual findings.

## Alignment Checks

Use these checks when reviewing code, database rows, or UI output:

- A NEW run should not show `fix_*` or `ruleclone_*` steps.
- A FIX run should not show NEW upload/classifier/OCR step names except where explicitly cloned or reused by design.
- A rule-change-only run should not rerun OCR/classifier/supporting-document extraction unless the rule-change-only flow is intentionally expanded.
- A rule-change-only run should create a new invoice version; it must not regenerate advice in place on the prior current version.
- `supporting_document_extraction` and `fix_supporting_document_extraction` should appear once per affected supporting-document type/evidence set.
- A fix run must not show `fix_ocr_read`, `fix_classifier_files`, `fix_supporting_document_extraction`, or `fix_ocr_invoice` rows for cloned unchanged evidence.
- Type-level supporting-document extraction rows should not also be displayed as invoice rows.
- A completed step should not continue to display a stale `in_progress` row for the same unit of work.
- `case_facts` should not start before the relevant OCR/classifier/supporting-document extraction prerequisites are complete.
- The shared pipeline starts at `case_facts`; later GenAI/code rows should not appear as active before step 8 prerequisites are satisfied.
- If a row exists in `claims.ingest_step_runs`, the auditor should be able to identify the actual work target and prove why that row was allowed by this spec.
