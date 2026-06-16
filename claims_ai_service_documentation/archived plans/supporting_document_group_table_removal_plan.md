# Supporting Document Group Table Removal Plan

## Goal

Remove the persisted supporting-document group model and return supporting-document evidence to a simpler shape:

- Uploaded files remain first-class `claims.supporting_documents` rows.
- Extraction runs as `supporting_document_type_extraction`: one GenAI call per supporting document type, with all files of that type attached.
- The type-level extraction call stores per-file facts in `claims.supporting_document_located_fields` and visual findings.
- Cross-file questions, such as whether a usable before/after pair exists, are handled by rules using the full supporting-document context.
- No separate `supporting_document_groups`, group type field config, or group located-field persistence remains.

This keeps extraction focused on observable file facts and keeps eligibility/review conclusions in the rule layer.

## Why

The ESP requirements PDF does not require a durable grouped evidence entity. It asks for supporting documentation such as:

- before/after photos of insulation areas;
- before/after photos of removed wood or solid fuel systems;
- before/after photos of health and safety remediation;
- manufacturer label photos for installed windows/doors.

Those requirements can be represented as uploaded supporting-document files plus per-file extracted facts. The rule layer can then reason across the package to determine whether the set is complete.

The current group model adds avoidable complexity:

- group capability is hardcoded in Ruby;
- `supporting_document_groups.group_label` duplicates document type metadata;
- the group-field admin screen implies a group-enabled state that does not exist;
- group extraction stores conclusions such as pair completeness as evidence, even though that is closer to rule reasoning;
- the pipeline splits support-doc extraction into single-file and group-file paths even though the cleaner unit of work is the supporting document type.

## Target Model

### Keep

- `claims.supporting_document_types`
- `claims.supporting_documents`
- `claims.supporting_document_type_located_fields`
- `claims.supporting_document_located_fields`
- `claims.supporting_document_visual_findings`

### Rename / Replace

- Replace `supporting_document_single_extraction` and `supporting_document_group_extraction` with `supporting_document_type_extraction`.
- `supporting_document_type_extraction` runs once for each supporting document type present on the invoice/package.
- Each call receives all uploaded files of that supporting document type.
- Each call returns per-file located fields and visual findings only.

### Remove

- `claims.supporting_document_groups`
- `claims.supporting_document_group_type_located_fields`
- `claims.supporting_document_group_located_fields`
- `supporting_document_group_id` from tables that only need file-level relationships
- the `supporting_document_group_extraction` pipeline step
- the `supporting_document_single_extraction` pipeline step, once replaced by type-level extraction
- the group-fields admin screen and API

### Revised Before/After Handling

`before_after_photo_set` remains a supporting document type, but each photo is stored as its own `claims.supporting_documents` row.

The existing per-file fields already point in the right direction:

- `photo_role`
- `visible_subject_or_area`
- `visible_condition_summary`
- `image_quality_or_legibility`
- `visible_text_or_label_values`

Rules should inspect all `before_after_photo_set` supporting documents for the invoice or upgrade type and decide whether a usable before/after pair exists.

## Stage 1: Define Type-Level Extraction Contract

### Code Changes

- Define the new step contract for `supporting_document_type_extraction`.
- Input: selected `supporting_document_type_key`, all `claims.supporting_documents` rows of that type for the invoice/package, each file attachment, each file's DI-read JSON, and the enabled per-file field tasks from `supporting_document_type_located_fields`.
- Output: per-file `supporting_document_located_fields` and per-file `supporting_document_visual_findings`.
- Do not output `supporting_document_group_located_fields`.
- Do not output cross-file conclusions such as `photo_pair_completeness_evidence`; those belong in rules.
- Keep existing group tables temporarily while introducing the new contract.

### Testing

- Run local `test014` end-to-end.
- Confirm before/after files are classified as `before_after_photo_set`.
- Confirm the planned `supporting_document_type_extraction` payload would include both before/after files in one call for `before_after_photo_set`.
- Confirm the planned output shape can populate existing per-file located fields and visual findings.

## Stage 2: Implement `supporting_document_type_extraction`

### Code Changes

- Add a runtime service/job for `supporting_document_type_extraction`.
- Schedule one job per supporting document type present for the invoice/package.
- Pass all files of that type to the GenAI call, not one job per file.
- Persist returned per-file located fields into `claims.supporting_document_located_fields`.
- Persist returned per-file visual findings into `claims.supporting_document_visual_findings`.
- Ensure a type-level call can handle one file or many files with the same code path.
- Temporarily leave existing single/group extraction code unused or behind a safe transition path until local tests pass.

### Testing

- Run local `test014` end-to-end.
- Confirm `before_after_photo_set` creates one `supporting_document_type_extraction` steprun for both before/after files.
- Confirm fenestration labels create one `supporting_document_type_extraction` steprun for all fenestration label files.
- Confirm WETT report creates one `supporting_document_type_extraction` steprun for the WETT type.
- Confirm no evidence is lost compared with the prior single/group extraction paths.
- Confirm invoice validation/advice still completes.

## Stage 3: Move Rules And Case Facts Off Group Evidence

### Code Changes

- Update case facts builder to stop serializing `supporting_document_groups`.
- Ensure `supporting_document_summary` and `supporting_document_summary_for_upgrade_type` include all per-file facts for each supporting document type.
- Update GenAI rule prompts that currently mention group located fields or group facts so they reason from per-file facts.
- Rewrite before/after rules to inspect all per-file `before_after_photo_set` facts and decide whether a usable before/after pair exists.

### Testing

- Run local `test014` end-to-end.
- Confirm before/after rules can pass/fail from per-file facts alone.
- Confirm windows/doors label rules reason across all label files for that type.
- Confirm the PDF viewer still displays supporting-doc evidence.

## Stage 4: Remove Single/Group Extraction Runtime

### Code Changes

- Remove `Claims::SupportingDocumentGroups::EnsureForInvoice` from the bundle advancement path.
- Remove `groups_requiring_supporting_document_group_extraction`.
- Remove `enqueue_supporting_document_group_extraction_jobs!`.
- Remove `Claims::RunSupportingDocumentGroupExtractionJob` or leave it unused only until final cleanup.
- Remove or retire the old per-file `supporting_document_single_extraction` scheduling path.
- Stop writing `supporting_document_group_extraction` stepruns.
- Stop writing `supporting_document_single_extraction` stepruns once the type-level path is live.
- Update simulator steprun grid expectations so the support-doc extraction stage displays `supporting_document_type_extraction`.

### Testing

- Run local `test014` end-to-end.
- Confirm no `supporting_document_group_extraction` stepruns are created.
- Confirm no `supporting_document_single_extraction` stepruns are created.
- Confirm support docs are processed by `supporting_document_type_extraction`, one row per supporting document type.
- Confirm no package remains stuck waiting for group extraction.
- Confirm invoice validation/advice still completes.

## Stage 5: UI Cleanup

### Code Changes

- Remove the Supporting Document Group Fields admin screen and navigation entry.
- Remove group sections from invoice support-doc admin screens and PDF viewer payloads.
- Remove any UI badges or labels implying group extraction is separately enabled.
- Keep support-doc display grouped visually by document type if useful, but do not back that visual grouping with a persisted group row.
- Update simulator copy/grid labels to show `supporting_document_type_extraction`.

### Testing

- Open supporting document type admin screens.
- Confirm only per-file supporting document fields are configurable.
- Open PDF viewer for `test014`.
- Confirm before/after files appear as normal uploaded support docs with their per-file fields.
- Confirm no empty or broken group accordion remains.

## Stage 6: DDL Cleanup

### Code Changes

Update `claims_ai_service_ddl/2_create_schema.sql`:

- Drop creation of `supporting_document_groups`.
- Drop creation of `supporting_document_group_type_located_fields`.
- Drop creation of `supporting_document_group_located_fields`.
- Remove `supporting_document_group_id` from `supporting_documents`, unless a temporary compatibility window is needed.
- Remove `supporting_document_group_id` from `ingest_step_runs`.
- Remove `supporting_document_group_extraction` from step type checks.
- Remove `supporting_document_single_extraction` from step type checks after the type-level replacement is complete.
- Add `supporting_document_type_extraction` to step type checks.
- Remove related indexes and foreign keys.

Update seed files:

- Remove group field seed rows from `4_insert_supporting_document_type_located_fields.sql`.
- Remove `supporting_document_group_extraction_system_record` from validation GenAI config if no longer used.
- Replace the single/group support-doc extraction system records with a `supporting_document_type_extraction` system record.
- Remove any rule text that depends on group-level located fields.

### Local DB Practice

For local only, use realtime `ALTER TABLE` / `DROP TABLE` commands as needed while testing.

Do not store local alter scripts in text files.

Gold remains rebuilt from the complete `create_schema` flow.

### Testing

- Rebuild local claims schema from the documented rebuild order.
- Reload seed/download tables as usual.
- Run local `test014` end-to-end.
- Verify no references to removed group tables remain in runtime code.
- Verify app boots and TypeScript compiles.

## Stage 7: Gold Rebuild Validation

This plan does not require Codex to rebuild Gold automatically.

When ready:

- Rebuild Gold from the full create schema flow.
- Reload the four download tables.
- Run Gold `test014` end-to-end.
- Confirm the contractor simulator and admin PDF viewer behave without group tables.

## Migration Risks

- Rules may currently rely on group-level facts such as `photo_pair_completeness_evidence`; those must be rewritten to inspect per-file facts.
- Existing single-file extraction assumptions may be baked into the job scheduler, steprun grid, or retry logic; these must move to type-level units.
- PDF viewer may currently expect `uploaded_supporting_document_groups`; that payload must become optional and then removed.
- Existing local test data may contain group rows; tests should be run after a clean local schema rebuild.
- If a before/after pair requires comparing two images, the rule prompt must receive all relevant per-file summaries and visual findings in the context window.
- The type-level GenAI call may have more attachments than the old single-file path; diagnostics should record document count, filenames, elapsed time, and provider failures.

## Acceptance Criteria

- No runtime code depends on `claims.supporting_document_groups`.
- Support-doc evidence extraction runs as `supporting_document_type_extraction`.
- There is one support-doc extraction steprun per supporting document type, not one per file and not one per persisted group.
- No admin UI exposes group field configuration.
- Before/after photo requirements are evaluated from per-file supporting-document facts.
- `test014` completes end-to-end locally.
- PDF viewer still shows before/after supporting documents and their extracted evidence.
- Gold can be rebuilt from `2_create_schema.sql` without group tables.
