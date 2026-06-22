# Invoice Version Supporting Document Revision Plan

## Purpose

Support future contractor/admin revisions where the invoice PDF and supporting documents can be added, removed, or replaced while preserving a clean historical record of what evidence existed when each AI advice result was produced.

This is a backlog plan only. It should not be implemented as a small patch to the current invoice-only +1 fix flow.

Important naming decision:

- Do not rename existing tables for this version of the design.
- Keep `claims.invoice_versions` as the version boundary.
- Treat `invoice_versions` as the practical package-version table, even if the name is imperfect.
- Reparent supporting documents so they belong to `invoice_versions`.

## Current Problem

The current model treats `invoice_versions` as the versioned object, while supporting documents are effectively tied to the broader invoice/package workflow. That works for invoice-only fixes, but it becomes awkward when a contractor needs to add, remove, or replace supporting documents.

If supporting documents remain outside the version boundary, later AI advice cannot cleanly answer:

- Which supporting documents existed when version 2 advice was generated?
- Did version 3 reuse an old supporting document or receive a new one?
- Which located fields, visual findings, and classifications belong to the evidence set reviewed by the admin?
- Was a rule/advice result based on the old package or the revised package?

## Recommended Enterprise Direction

Keep the current table name `invoice_versions`, but make it the immutable evidence snapshot boundary for the whole package.

Recommended practical structure:

- `invoices`: the stable business case / claim / submission identity.
- `invoice_versions`: one immutable snapshot of the package at a point in time.
- `invoice_versions` continues to store invoice-PDF-specific fields, because the single invoice PDF is still part of the package snapshot.
- `supporting_documents`: child records of `invoice_versions`, not just the overall invoice parent.
- Current version selection can continue to use the latest `invoice_versionno` until/unless a future explicit current pointer is added.

Each `invoice_versions` row should represent a complete logical snapshot of the package. A version should include the invoice PDF, supporting documents, classifications, extracted fields, located fields, visual findings, advice checks, and run history needed to explain that version.

This is intentionally not a table-renaming project. The data-model improvement is reparenting supporting-document evidence under `invoice_versions`, not creating a new `package_versions` table.

## Clone Versus Rerun Strategy

For a new package version, clone unchanged child records instead of rerunning OCR/DI/LLM for every unchanged file.

Default behavior:

- If a file is unchanged, clone the version-level document/evidence rows and preserve provenance to the prior extraction result.
- If a file is added, replaced, or changed, run the appropriate OCR/DI/LLM steps only for that file or affected document type.
- If prompts, schemas, extraction code, model versions, or product reference data materially change, allow an explicit reanalysis flow.
- If a prior extraction failed or was marked stale, rerun that piece instead of cloning it.

This keeps versions immutable and complete without paying the cost and nondeterminism of reprocessing identical evidence.

## File Storage Model

Do not physically duplicate unchanged blobs.

Recommended approach:

- Store physical file/blob metadata separately from version membership.
- Use a stable blob URL or content hash to identify identical files.
- Let each package version have its own document membership rows pointing to reused physical file records where appropriate.

This gives the data model a full historical snapshot while keeping storage efficient.

## Provenance Fields

Add provenance fields where cloned evidence is used.

Examples:

- `source_package_version_id`
- `source_document_id`
- `source_extraction_run_id`
- `reused_from_located_field_id`
- `reused_reason`
- `extraction_model`
- `extraction_prompt_version`
- `extraction_schema_version`
- `created_by_versioning_strategy`

The goal is that an admin can tell whether evidence was newly extracted for this version or copied forward from a prior version because the file was unchanged.

## Revision UX Direction

Contractor revision actions should not open an immediate file picker inside the invoice review/PDF viewer screen.

Recommended future UX:

- The contractor invoice review screen shows a contextual action such as `Upload revised package` or `Upload revised invoice`.
- Clicking it navigates to a dedicated revision upload screen.
- The revision upload screen can reuse the high-end upload experience: drag/drop, selected files, swirling processing state, friendly technical/package correction errors, and a success confirmation button.
- After success, the contractor explicitly continues to the updated pre-check/review screen.

This avoids modal-over-modal behavior and creates a clean path for future supporting-document add/remove changes.

## New Admin Fix Simulation Screen

Add a new admin-only React screen named `contractorfixsimulation`.

Purpose:

- Simulate a contractor/admin package fix against the current invoice version.
- Replace the old invoice-admin wrench icon behavior.
- Support invoice PDF replacement, supporting-document add, supporting-document remove, and supporting-document replacement through one explicit version-building UI.

Routing/navigation:

- The existing wrench icon on the invoice admin grid should navigate to the new `contractorfixsimulation` screen.
- The wrench should no longer immediately trigger the old invoice-only +1 fix flow.
- The screen should receive the invoice/invoice-version identity needed to load the current version.

Screen structure:

- Top section: read-only listing of all files in the current version.
- This includes both the invoice PDF and supporting documents.
- This read-only list is only for context, so admins can see the starting package before choosing changes.

Middle section:

- Drag-and-drop upload area.
- Manual file picker should also be available.
- Files added here appear in the upload/drop area with status `NEW ADDITION`.
- These are candidate files for the new version.

Bottom section:

- Editable proposed-version file list.
- Initially populated with all current-version files.
- Each current-version file has status `CLONE`.
- Each cloned row has a remove button.
- Removing a cloned file means the next version will not include that file.
- Newly uploaded files also appear in this proposed-version list with status `NEW ADDITION`.
- Newly uploaded rows should also be removable before the fix is submitted.

Primary action:

- Button label: `Click me to fix` for the simulator/admin prototype.
- Later production wording can be softened, but the prototype should keep this explicit label if desired.

Replacement model:

- Replacing a supporting document is intentionally modeled as two user-visible actions:
  - Remove the existing `CLONE` row.
  - Add the replacement file as `NEW ADDITION`.
- Replacing the invoice PDF uses the same model:
  - Remove the existing invoice `CLONE` row.
  - Add the replacement invoice PDF as `NEW ADDITION`.

Important validation behavior:

- The proposed package must contain exactly one invoice PDF after clone removals and new additions are applied.
- It may contain zero or more supporting documents.
- If no files remain, block submission.
- If multiple invoice PDFs remain, block submission or return a package-correction status, depending on whether validation is client-side or server-side.
- The server remains authoritative; React only helps the user see the intended proposed version.

Status labels:

- `CLONE`: file will be copied forward from the current version into the new version.
- `NEW ADDITION`: file was added in this fix flow and will be processed as new evidence.
- Removed files should disappear from the proposed-version list or move to an optional removed-files area if we later want an undo affordance.

Design rationale:

- A package revision is easier to reason about when the admin sees the complete proposed next version before clicking fix.
- Clone-forward is explicit instead of magical.
- Supporting-document replacement does not require a special "replace" action; it is remove old plus add new.
- This matches the future data model where each `invoice_versions` row is a complete snapshot.

## New Admin Advice Refresh Simulation Screen

Add a separate admin-only React screen for the advice-change-only path.

Working route/name:

- Route: `/advice-refresh-simulation-admin`
- User-facing title: `Refresh AI Advice`

Purpose:

- Reuse the current invoice-version evidence.
- Do not upload new files.
- Do not rerun OCR/DI or supporting-document extraction.
- Rerun case facts, product lookup enrichment, GenAI advice, code advice, and aggregate advice using current configuration.

Admin grid behavior:

- The invoice admin grid should expose two separate actions.
- Wrench/fix action: `Upload a revised package`, opens `/contractorfixsimulation`.
- Refresh action: `Refresh AI Advice`, opens `/advice-refresh-simulation-admin`.
- Do not overload the wrench icon for both actions.

Pipeline behavior:

- Create a run/step marker such as `reanalysis_clone_existing_evidence`.
- Treat the current evidence as cloned/reused.
- Then skip to the shared advice pipeline beginning at `case_facts`.
- This is different from a package fix because no files or extracted evidence change.

## Revision Types

Support at least these revision scenarios:

- Replace invoice PDF only.
- Add supporting document.
- Remove supporting document.
- Replace supporting document.
- Replace invoice PDF and supporting documents together.
- Reclassify a supporting document after upload.
- Reanalyze unchanged evidence by explicit admin/system action.

## Pipeline Impact

The pipeline should operate against the new `invoice_versions` snapshot, not against a loose mix of invoice-level and supporting-document-level evidence.

Expected behavior:

- New `invoice_versions` row is created first as an immutable target snapshot.
- Unchanged file evidence is cloned into the new version.
- Changed/new files run through OCR/DI/classification/extraction.
- Case facts are rebuilt from the new version snapshot.
- Product lookup and advice generation use only the current version snapshot.
- Prior version evidence remains readable but is not mutated.

## Pipeline Job/Class Alignment Included In This Refactor

The backlog plan `claims_ai_pipeline_job_class_alignment_plan.md` should be absorbed into this major refactor rather than handled later as a separate cleanup.

Reason:

- Supporting-document versioning changes the evidence boundary.
- The fix flow introduces new pipeline steps.
- The classifier and supporting-document extraction steps are being simplified.
- This is the right moment to align Sidekiq job names/classes with the actual pipeline vocabulary instead of preserving historical job names.

Do not implement the older backlog plan literally. Its goal is still right, but its target step names are now stale because the pipeline has evolved.

Current updated target vocabulary:

| Flow       | Step-run name                        | Intended meaning                                                                                                                                                                                                   |
| ---------- | ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| New upload | `upload_package_stage`               | Upload/stage all files and create the initial invoice/version shell rows. Usually not Sidekiq.                                                                                                                     |
| New upload | `ocr_read`                           | DI-read every uploaded file.                                                                                                                                                                                       |
| New upload | `classifier_files`                   | Classify every file using media-aware evidence priority. PDFs use DI-read as primary evidence; images use the attached image as primary evidence; both may include the original file when useful.                  |
| New upload | `supporting_document_extraction`     | Run supporting-document extraction by supporting-document type/evidence set and write per-file located fields and visual findings.                                                                                 |
| New upload | `ocr_invoice`                        | Run invoice-specific DI extraction for the classified invoice PDF and populate invoice-version fields/line items.                                                                                                  |
| Fix upload | `fix_upload_package_stage`           | Stage the proposed next version from the fix simulation screen.                                                                                                                                                    |
| Fix upload | `fix_ocr_read`                       | DI-read only new files in the proposed fix package.                                                                                                                                                                |
| Fix upload | `fix_classifier_files`               | Classify only new files in the proposed fix package.                                                                                                                                                               |
| Fix upload | `fix_clone_existing_evidence`        | Copy forward clone-selected unchanged files and reusable evidence from the prior version. For affected supporting-document types, clone file membership but let extraction rebuild located fields/visual findings. |
| Fix upload | `fix_supporting_document_extraction` | For each affected supporting-document type, rerun extraction over the full revised set of files for that type, including cloned files and new additions.                                                           |
| Fix upload | `fix_ocr_invoice`                    | Run invoice-specific DI only if the invoice PDF is new/replaced; otherwise clone/reuse invoice evidence as appropriate.                                                                                            |
| Shared     | `case_facts`                         | Build persisted case facts from the selected `invoice_versions` snapshot.                                                                                                                                          |
| Shared     | `product_lookup_enrichment`          | Match classifier references and eligibility evidence against DB/download/reference tables and write normalized UUID/product fields.                                                                                |
| Shared     | `genai_common`                       | Run common GenAI advice.                                                                                                                                                                                           |
| Shared     | `genai_upgrade`                      | Run upgrade-type-specific GenAI advice.                                                                                                                                                                            |
| Shared     | `code_common`                        | Run common deterministic code advice checks.                                                                                                                                                                       |
| Shared     | `code_upgrade`                       | Run upgrade-type-specific deterministic code advice checks.                                                                                                                                                        |
| Shared     | `aggregate_advice`                   | Aggregate all advice/results into final invoice-version advice.                                                                                                                                                    |

Recommended job namespace:

- Use `Claims::Pipeline::*` for the aligned job classes.
- Keep queue names unchanged for now unless there is a separate operational reason to split them.
- Keep retry behavior consistent with the current pipeline unless a specific step requires different semantics.

Recommended job class names:

| Step-run name                        | Proposed job class                                                    |
| ------------------------------------ | --------------------------------------------------------------------- |
| `ocr_read`                           | `Claims::Pipeline::OcrReadJob`                                        |
| `classifier_files`                   | `Claims::Pipeline::ClassifierFilesJob`                                |
| `supporting_document_extraction`     | `Claims::Pipeline::SupportingDocumentExtractionJob`                   |
| `ocr_invoice`                        | `Claims::Pipeline::OcrInvoiceJob`                                     |
| `fix_upload_package_stage`           | Usually controller/service, not Sidekiq unless staging becomes async. |
| `fix_ocr_read`                       | `Claims::Pipeline::FixOcrReadJob`                                     |
| `fix_classifier_files`               | `Claims::Pipeline::FixClassifierFilesJob`                             |
| `fix_clone_existing_evidence`        | `Claims::Pipeline::FixCloneExistingEvidenceJob`                       |
| `fix_supporting_document_extraction` | `Claims::Pipeline::FixSupportingDocumentExtractionJob`                |
| `fix_ocr_invoice`                    | `Claims::Pipeline::FixOcrInvoiceJob`                                  |
| `case_facts`                         | `Claims::Pipeline::CaseFactsJob`                                      |
| `product_lookup_enrichment`          | `Claims::Pipeline::ProductLookupEnrichmentJob`                        |
| `genai_common`                       | `Claims::Pipeline::GenaiCommonJob`                                    |
| `genai_upgrade`                      | `Claims::Pipeline::GenaiUpgradeJob`                                   |
| `code_common`                        | `Claims::Pipeline::CodeCommonJob`                                     |
| `code_upgrade`                       | `Claims::Pipeline::CodeUpgradeJob`                                    |
| `aggregate_advice`                   | `Claims::Pipeline::AggregateAdviceJob`                                |

Refactor rules:

- Job class names should read like the pipeline.
- `ingest_step_runs.step_type` should remain the business-visible pipeline vocabulary.
- Avoid keeping generic jobs that switch behavior based on a passed step type when a step-specific job would be clearer.
- Every step should be independently retry-safe.
- Every step should create/update the correct `ingest_step_runs` row for the selected invoice version or staged file.
- Old job classes can remain as wrappers temporarily, but active enqueue sites should move to the new `Claims::Pipeline::*` names as part of this refactor.

Retired/stale target names from the old backlog plan:

- Replace `classifier_pdfs` and `classifier_imagefiles` with `classifier_files`.
- Replace `supporting_document_single_extraction` and `supporting_document_group_extraction` with `supporting_document_extraction`.
- Replace `plus1fix_ocr_read` and `plus1fix_classifier` with the broader fix-package names above.
- Do not build job classes around the old group-table concept.

Stage gates:

- Ruby syntax checks pass for all touched job/service files.
- Grep confirms enqueue sites use the intended new job classes for that stage.
- Sidekiq queues drain after a test package.
- `claims.ingest_step_runs` has no stuck `queued`, `in_progress`, or `failed` rows for the tested run.
- Final invoice reaches the expected status.
- Step-run names match the updated pipeline vocabulary.
- Local `test014` or its package-version successor passes after each major stage.

## Data Model Impact Areas

Likely tables needing redesign or reparenting:

- `invoice_versions`
- `supporting_documents`
- `supporting_document_located_fields`
- supporting-document visual findings tables
- supporting-document classification/routing data
- invoice located fields
- rule/advice check output tables
- ingest runs and step runs
- upload/session tables that currently assume invoice-only versioning

Primary DDL direction:

- Add `invoice_version_id` to `claims.supporting_documents`.
- Make `claims.supporting_documents.invoice_version_id` the parent relationship for version-scoped supporting documents.
- Decide whether the old `supporting_documents.invoice_id` remains temporarily as compatibility/read convenience or is removed after migration.
- All supporting-document child tables should continue to hang from `supporting_documents`, but those supporting-document rows must be version-scoped.
- Do not rename `invoice_versions`.
- Do not create `invoice_package_versions` in this plan.

## Delete Behavior

Deleting an invoice-version package snapshot should remove all child records for that version, including cloned evidence rows, step runs, located fields, visual findings, and advice outputs.

Physical blobs should only be deleted if no remaining invoice version references them.

## Reporting And Admin Impact

Admin screens should clearly show:

- Current invoice/package version.
- Prior invoice/package versions.
- Which files changed between versions.
- Which evidence was reused versus newly extracted.
- Which version produced the current advice.

The invoice review/PDF viewer should load evidence from the selected `invoice_versions` snapshot only.

## Open Decisions

- Whether `supporting_documents.invoice_id` remains temporarily during migration or is removed once all callers use `invoice_version_id`.
- Whether supporting-document add/remove should be available to contractors immediately or only after admin requests revision.
- Whether admins can revise packages on behalf of contractors.
- Whether cloned located fields should receive new primary keys per version or use a version-membership join to shared extraction results.
- Whether the first `contractorfixsimulation` implementation should be admin-only forever or later become the basis for contractor revision UX.

## Implementation Phases

1. Design the invoice-version-as-package-snapshot data model and migration strategy.
2. Update DDL/create-schema so supporting documents are children of `invoice_versions`.
3. Draft the new admin `contractorfixsimulation` React screen.
4. Route the invoice admin wrench icon to `contractorfixsimulation`.
5. Introduce/update `Claims::Pipeline::*` job classes using the updated step-run vocabulary.
6. Replace old classifier split with `classifier_files`.
7. Replace old supporting-document single/group split with `supporting_document_extraction`.
8. Add the fix-flow pipeline steps: `fix_upload_package_stage`, `fix_ocr_read`, `fix_classifier_files`, `fix_clone_existing_evidence`, `fix_supporting_document_extraction`, and `fix_ocr_invoice`.
9. Refactor upload and old +1 fix flows to create complete invoice-version snapshots.
10. Add clone-forward logic for unchanged files and evidence.
11. Update OCR/DI/LLM pipeline to process only changed/new evidence where possible.
12. Update case facts and advice context windows to read only from the selected invoice-version snapshot.
13. Update contractor revision UX to use a dedicated revised-package upload flow.
14. Update admin invoice review and grid screens to expose version history and changed evidence.
15. Add end-to-end tests for invoice-only, support-doc-only, and mixed revisions.

## Test Plan

Create fixtures for:

- Initial package with one invoice PDF and multiple supporting documents.
- Version 2 replacing only the invoice PDF.
- Version 3 adding a supporting document.
- Version 4 removing a supporting document.
- Version 5 replacing one supporting document.
- Version 6 replacing invoice PDF and supporting documents together.

For each version, verify:

- The package version has a complete logical evidence snapshot.
- Unchanged evidence is cloned/reused and marked with provenance.
- Changed/new evidence is reprocessed.
- Prior versions remain unchanged.
- Case facts and advice results are scoped to the correct version.
- PDF/image viewer highlights and accordions only show evidence from the selected version.
- Delete removes the selected version's child records without deleting blobs still referenced by other versions.
- Step-run rows use the updated vocabulary, including `classifier_files`, `supporting_document_extraction`, and the `fix_*` steps.
- Sidekiq job class names match the pipeline step names closely enough that logs can be read without translating old historical job names.
