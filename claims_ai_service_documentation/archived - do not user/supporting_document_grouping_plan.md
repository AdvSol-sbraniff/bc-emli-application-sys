# Supporting Document Grouping Plan

Status: implemented locally and tested with `Heath & Safety/test006`

Purpose: add an explicit grouping model for supporting documents that are business evidence sets rather than standalone files. The immediate driver is photo evidence such as before/after photo sets, where one uploaded JPG is one physical evidence file but the business question depends on multiple files together.

## 1. Problem

The current model treats each uploaded supporting file as one `claims.supporting_documents` row. That is still correct for file audit, storage, review, and source traceability.

The problem is that some configured located fields ask group-level questions. For example:

```text
photo_pair_completeness_evidence
```

This field cannot be answered correctly from one JPG alone. If the system extracts it per file, each file may honestly report that the pair is incomplete because it sees only itself. That creates technically correct but business-wrong evidence.

The model needs to separate:

```text
file-level evidence: what is visible in this uploaded file?
group-level evidence: what do these related supporting files prove together?
```

## 2. Target Model

Keep this rule:

```text
1 uploaded file = 1 claims.supporting_documents row
```

Add this rule:

```text
1 business evidence set = 1 claims.supporting_document_groups row
```

Example:

```text
claims.supporting_document_groups
  before_after_photo_set group for invoice A

claims.supporting_documents
  after photo 1.jpg -> group
  after photo 2.jpg -> group
```

The group foreign key on `claims.supporting_documents` should be nullable because most supporting documents are standalone.

## 3. Implemented Schema

### 3.1 `claims.supporting_document_groups`

New evidence table.

Implemented columns:

- `id`
- `invoice_id`
- `supporting_document_type_id`
- `group_label`
- `group_status`
- `created_at`
- `updated_at`

Implemented constraints:

- Foreign key to `claims.invoices`.
- Foreign key to `claims.supporting_document_types`.
- `group_status` check such as `pending`, `ready`, `extracted`, `needs_review`, `failed`.

### 3.2 `claims.supporting_documents`

Added nullable group pointer:

```sql
supporting_document_group_id uuid null
```

Suggested foreign key:

```sql
references claims.supporting_document_groups(id) on delete set null
```

Keep these existing columns on `claims.supporting_documents`:

- `invoice_id`
- `supporting_document_type_id`

This is intentional duplication. It preserves simple invoice-level queries and keeps existing UI/API paths stable while grouping becomes an optional organizing layer.

### 3.3 `claims.supporting_document_group_type_located_fields`

New registry/configuration table.

This is the group-level parallel to `claims.supporting_document_type_located_fields`.

Implemented columns:

- `id`
- `supporting_document_type_id`
- `field_key`
- `prompt_text`
- `enabled`
- `field_number`
- `created_at`
- `updated_at`

This table defines group-level extraction tasks for a supporting-document type.

### 3.4 `claims.supporting_document_group_located_fields`

New evidence table.

Implemented columns:

- `id`
- `supporting_document_group_id`
- `supporting_document_group_type_located_field_id`
- `field_key`
- `source_engine`
- `value_type`
- `value_text`
- `value_json`
- `confidence`
- `evidence_text`
- `created_at`
- `updated_at`

This table stores runtime group-level extracted facts.

### 3.5 Optional Group Visual Findings

Not implemented in this pass. Group-level outputs are stored as located-field style answers in:

```text
claims.supporting_document_group_located_fields
```

A separate `claims.supporting_document_group_visual_findings` table can wait unless the group call needs multiple free-form visual observations outside the configured field list.

## 4. Seed Refactor

The seed scripts were refactored because some previously per-file supporting-document located fields belong at group level.

Current per-file seed table:

```text
claims.supporting_document_type_located_fields
```

Future group-level seed table:

```text
claims.supporting_document_group_type_located_fields
```

Fields moved out of per-file extraction include group completeness or cross-file comparison questions.

Known candidate:

```text
photo_pair_completeness_evidence
```

Likely group-level fields for `before_after_photo_set`:

- `before_photo_present`
- `after_photo_present`
- `photo_pair_completeness_evidence`
- `same_subject_or_area_evidence`
- `group_visual_consistency_summary`

Per-file fields should remain focused on one uploaded file:

- `photo_role`
- `visible_subject_or_area`
- `visible_condition_summary`
- `image_quality_or_legibility`
- `visible_text_or_label_values`

## 5. Runtime Pipeline

### 5.1 Classification And Promotion

The classifier still classifies each staged file independently:

```text
invoice | supporting_document | unknown
```

Each supporting document is promoted as one `claims.supporting_documents` row.

### 5.2 Group Creation

After supporting-document promotion, the pipeline creates or updates groups for group-capable supporting-document types.

Initial group-capable type:

```text
before_after_photo_set
```

Grouping rule for the first version:

```text
same invoice_id + same supporting_document_type_id = one group
```

Later refinements may split groups by subject/area if the same invoice has multiple separate before/after evidence sets.

### 5.3 Per-File Extraction

`supporting_document_extraction` remains one call per supporting document.

It should answer file-level questions only.

It should not answer `photo_pair_completeness_evidence` after that field moves to group config.

### 5.4 Group Extraction

Added a new step type:

```text
supporting_document_group_extraction
```

This runs once per group that has enabled group-level located-field definitions.

The GenAI call should receive:

- Group metadata.
- All child supporting document metadata.
- DI-read summaries for each child document.
- File-level located fields for each child document.
- Visual findings for each child document.
- Attached image/PDF content where needed and supported.

It writes to:

```text
claims.supporting_document_group_located_fields
```

## 6. React Admin Work

A React configuration screen was added for group-level field definitions.

Screen:

```text
/supporting-document-group-type-fields-admin
```

The supporting-document type registry now has a "Manage group fields" action beside the existing per-file "Manage fields" action.

Implemented features:

- List supporting-document types.
- Show group-level fields for selected type.
- Add/edit/disable group-level field definitions.
- Edit `field_key`, prompt text, enabled flag, and `field_number`.

The Invoice Supporting Documents review screen and the main current-version admin PDF viewer were updated to display group-level results.

Suggested display:

```text
Supporting document groups
  Before/after photo set
    Files: after photo 1.jpg, after photo 2.jpg
    Group fields:
      before_photo_present
      after_photo_present
      photo_pair_completeness_evidence
      same_subject_or_area_evidence
```

## 7. Data Model Documentation Updates

Update `claims_ai_service_documentation/claims_data_model.md` after implementation.

Topics to add:

- Difference between physical supporting documents and grouped evidence sets.
- Nullable group foreign key on `claims.supporting_documents`.
- Group-level located fields versus file-level located fields.
- Runtime step `supporting_document_group_extraction`.
- How group results are included in case facts/context windows.

## 8. Test Results

Primary test package:

```text
claims_ai_service_documentation/Test Data/Heath & Safety/test006
```

Tested locally with:

```text
ingest_run_id = 125b0af0-8188-4c52-8ca9-de8fd5321d2c
invoice_id = 76e11b62-b03f-461f-b8ec-7793e5ce49a5
invoice_version_id = f1373707-cc9c-4bcb-86ef-da5743454849
supporting_document_group_id = c8ec565c-4213-46a4-bede-db9786564081
```

Observed result:

- Each JPG remains one `claims.supporting_documents` row.
- Both JPG rows point to the same `claims.supporting_document_groups` row.
- Per-file extraction describes each photo individually.
- Group extraction runs once for the group.
- `photo_pair_completeness_evidence` is stored once in `claims.supporting_document_group_located_fields`, not repeated once per photo.
- Invoice review UI shows both file-level evidence and group-level completeness evidence.
- Full package completed with `claims.ingest_runs.status = succeeded` and `claims.invoices.status = genai_complete`.
- Upgrade GenAI context windows included the group-level `photo_pair_completeness_evidence`.

Regression checks:

- Standalone supporting PDFs still work with `supporting_document_group_id = null`.
- Existing package flows still require exactly one invoice.
- Group extraction failure should not corrupt promoted supporting-document rows.
- Case facts include group-level results for GenAI validation.

## 9. Open Design Decisions

- Should `supporting_document_group_status` be operational only, review-facing, or both?
- Should group extraction failures be fatal to the whole package, or should they mark the group as `needs_review`?
- Should grouping initially happen only for `before_after_photo_set`, or also for `manufacturer_label_photo` if multiple label photos are uploaded?
- Should group membership ever be manually editable in the UI?
- Should group fields have history tables immediately, matching other registry configuration history patterns?
