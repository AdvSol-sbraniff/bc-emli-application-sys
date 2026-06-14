# Image-First Supporting Document Classification Plan

## Problem

The current intake flow asks `triage_classifier` to classify every file after `ocr_read`.

That is reasonable for PDFs with useful OCR text, but it is weak for standalone JPEG/PNG files. A photo may have little or no OCR text, so the classifier is forced to guess the supporting-document type from filename, MIME type, and sparse DI-read output.

For image files, the system should inspect the actual visual content before finalizing the supporting-document classification. Classification should only decide what the file is and how it routes. Official supporting-document evidence still belongs to the later supporting-document extraction steps.

## Current Code Reality

- `Claims::Ingest::ApplyDocumentTriageResult` writes `document_kind`, `supporting_document_type_id`, `classification_status`, confidence, reason, and routing quality to `claims.ingest_documents`.
- `Claims::SupportingDocuments::PromoteFromIngestDocument` creates/reuses `claims.supporting_documents` rows after the bundle has exactly one invoice candidate. It copies classifier fields, DI-read JSON, and file metadata only.
- `Claims::RunSupportingDocumentExtractionJob` uses the already-selected `supporting_document_type_id` to build the extraction prompt.
- `Claims::RunSupportingDocumentExtractionJob` writes its own GenAI result directly into `claims.supporting_document_located_fields` and `claims.supporting_document_visual_findings`.
- `Claims::RunSupportingDocumentGroupExtractionJob` writes group-level fields directly into `claims.supporting_document_group_located_fields` and child-file evidence into `claims.supporting_document_located_fields` / `claims.supporting_document_visual_findings`.
- Supporting-document extraction does not currently revise `supporting_document_type_id` or `classification_status`.

## Target Pipeline

Read top down.

| Step | Step Run                                | Invoice Status                                      | Description                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| ---- | --------------------------------------- | --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1    | `upload_package_stage`                  | `upload_in_progress`                                | Contractor simulator uploads all files. This is not a Sidekiq step. At this point the system does not know invoice vs supporting vs unknown.                                                                                                                                                                                                                                                                                                      |
| 2    | `ocr_read(s)`                           | `evidence_prep` / currently `ocr_in_progress`       | Call DI-read for every file. Even image files may have useful text, such as a label photographed on window glass.                                                                                                                                                                                                                                                                                                                                 |
| 3    | `classifier_pdfs`                       | `ocr_in_progress`                                   | For PDFs only. GenAI input is DI-read only; no file attachment, because PDF classification should stay more deterministic. Output is `document_kind` of invoice, supporting, or unknown. If invoice, also detect upgrade type(s), AHRI/product references, and eligibility code for later persistence into `invoice_version_located_fields` with `source_engine = 'classifier'`. If supporting, set supporting-document type and routing quality. |
| 4    | `classifier_imagefiles`                 | `ocr_in_progress`                                   | For image files only. GenAI input is the attached image as primary evidence, with filename, MIME type, and DI-read only as weak hints. Output is supporting-document type/routing classification. This is not the official visual findings evidence step.                                                                                                                                                                                         |
| 5    | `supporting_document_single_extraction` | `ocr_in_progress`                                   | Runs after exactly one invoice candidate has been confirmed and durable `supporting_documents` parent rows have been created. For each single supporting document, where single means a supporting document that is not handled by a `supporting_document_group`. Input is DI-read plus the attached file. Output is official per-file visual findings and supporting-document located fields, written by this step.                              |
| 6    | `supporting_document_group_extraction`  | `ocr_in_progress`                                   | For each `supporting_document_group`. Groups may contain one file or many files. Input is DI-read for each file in the group plus each attached file. Output is official group-level located fields, plus per-file visual findings and per-file supporting-document located fields.                                                                                                                                                               |
| 7a   | `plus1fix_ocr_read`                     | `ocr_in_progress`                                   | `+1 fix` path only. Starts after the replacement invoice PDF has already been uploaded and inserted as the next `invoice_versions` row. Runs DI-read for the replacement invoice PDF so the replacement can be classified on its own evidence. Normal full-package uploads skip this step.                                                                                                                                                        |
| 7b   | `plus1fix_classifier`                   | `ocr_in_progress`                                   | `+1 fix` path only. Reclassifies the replacement invoice PDF using the `plus1fix_ocr_read` output, verifies it is still an invoice, refreshes classifier-derived invoice evidence for the new version, and replaces the new version's classified upgrade types. Normal full-package uploads skip this step.                                                                                                                                       |
| 7c   | `ocr_invoice`                           | `ocr_in_progress`                                   | Normal upload path: after supporting-document evidence prep is complete, create/reuse the `invoice_versions` row for the single classified invoice PDF. `+1 fix` path: runs after `plus1fix_ocr_read` and `plus1fix_classifier` have succeeded. Calls DI-invoice ML. Output is DI-invoice JSON used to populate invoice first-class fields and line items.                                                                                        |
| 8    | `case_facts`                            | `validation_advice` / currently `genai_in_progress` | Use eligibility code extracted by the classifier. Build case-facts JSON from DB data, shown in PDF viewer as "info on record", and persist DB facts in `invoice_version_located_fields` with `source_engine = 'code'`.                                                                                                                                                                                                                            |
| 9    | `product_lookup_enrichment`             | `genai_in_progress`                                 | Use product references extracted by the classifier and build product info from download tables.                                                                                                                                                                                                                                                                                                                                                   |
| 10   | `genai_common`                          | `genai_in_progress`                                 | Create the context window just in time and call the upgrade-call GenAI once for common rules. Runs in parallel with `genai_upgrade(s)`.                                                                                                                                                                                                                                                                                                           |
| 11   | `genai_upgrade(s)`                      | `genai_in_progress`                                 | Create the context window just in time and call the upgrade-call GenAI once per classified upgrade type. Runs in parallel with `genai_common`.                                                                                                                                                                                                                                                                                                    |
| 12   | `code_common`                           | `genai_in_progress`                                 | Run code rules for common.                                                                                                                                                                                                                                                                                                                                                                                                                        |
| 13   | `code_upgrade`                          | `genai_in_progress`                                 | Run code rules for each detected upgrade type.                                                                                                                                                                                                                                                                                                                                                                                                    |
| 14   | `aggregate_advice`                      | `genai_in_progress`                                 | Aggregate outputs into final advice/result.                                                                                                                                                                                                                                                                                                                                                                                                       |

## Proposed Implementation

### 1. Add Image Detection Helper

Create a shared helper for staged ingest documents:

- image if `content_type` is `image/jpeg`, `image/png`, or other approved image MIME type.
- fallback by filename extension: `.jpg`, `.jpeg`, `.png`.

Likely location:

- `app/services/claims/ingest/file_type.rb`

### 2. Split Triage Routing For Images

Update `Claims::Ingest::AdvanceBundleRun` so image files do not rely on the normal OCR-only classifier result for final supporting-document type.

Implemented behavior:

- enqueue `classifier_pdfs` for PDF/non-image documents.
- enqueue `classifier_imagefiles` for image documents.
- keep classifier output limited to routing/classification, not official evidence extraction.

### 3. Image Classification Job

Implemented in:

- `app/jobs/claims/run_ingest_triage_job.rb`

Purpose:

- Attach the actual image to the GenAI call.
- Include filename, MIME type, byte size, and DI-read JSON as weak hints.
- Ask for routing/classification only:
  - `document_kind`
  - `supporting_document_type_key`
  - `supporting_document_type_confidence`
  - `supporting_document_type_reason`
  - `supporting_document_routing_quality`
  - `supporting_document_routing_quality_reason`
  - optional concise visual routing summary, not official visual findings evidence

This job should write its GenAI result to `claims.ingest_step_runs.genai_results_json`.

### 4. Apply Image Classification Result

Implemented through:

- `app/services/claims/ingest/apply_document_triage_result.rb`

Responsibilities:

- Update `claims.ingest_documents` with final classification values.
- Store `classifier_raw_json` or a new image-classifier payload field if we decide one is needed.
- Use the returned `supporting_document_type_key` to set `supporting_document_type_id`.
- Set `classification_status`:
  - `classified` when document kind is supporting_document and type is recognized.
  - `needs_review` when unknown or unrecognized.
- Preserve only classifier/routing metadata. Official visual findings are produced later by single/group supporting-document extraction.

### 5. Keep Classification Separate From Evidence Extraction

The image classifier should not populate official evidence tables.

Evidence ownership:

- `classifier_pdfs` and `classifier_imagefiles` decide what files are and how they route.
- `supporting_document_single_extraction` writes official per-file located fields and visual findings.
- `supporting_document_group_extraction` writes official group located fields, plus per-file located fields and visual findings for files inside the group.

### 6. Adjust Promotion

Update:

- `Claims::SupportingDocuments::PromoteFromIngestDocument`

Behavior:

- Prefer classification/routing payload from `image_supporting_document_classification` for image files.
- Continue using `supporting_document_single_extraction` and `supporting_document_group_extraction` as the source of official supporting-document evidence.
- Do not use image classifier output as visual findings evidence.

### 7. Adjust Supporting Document Extraction

For image files already classified by image-first classification:

- Run the normal single extraction when the document is not handled by a group.
- Run group extraction when the document belongs to a `supporting_document_group`.
- Avoid running both single and group extraction for the same supporting document unless we explicitly want duplicated evidence.

### 8. Prompt/Config Changes

Add explicit system config fields for the two classifier modes.

Recommended DDL change:

- Add `classifier_pdf_system_record` to `claims.validationgenai_config`.
- Add `classifier_image_system_record` to `claims.validationgenai_config`.

Reason:

- PDF classification and image classification have different prompt goals.
- PDF classification should be DI-read-first and deterministic.
- Image classification should be vision-first, with DI-read, filename, and MIME type as weak hints.
- Keeping these as separate config fields prevents future prompt edits from accidentally mixing the two behaviors.

Do not add separate user-record columns for now. The user messages should be built in code because they depend on runtime data: DI-read JSON, filename, MIME type, file attachment, and bundle context.

### 9. React System Config Screen

Update the existing React config maintenance screen so admins can edit:

- `classifier_pdf_system_record`
- `classifier_image_system_record`

Also update the backend API/model/serializer/strong params used by the System Config screen so these fields round-trip correctly.

Seed/update default text for both prompts in the validation GenAI config seed script.

## Testing Plan

### Local Test 1: Existing Image Package

Use an existing package with standalone JPEGs:

- `claims_ai_service_documentation/Test Data/Insulation/test006`

Verify:

- JPEG files get `image_supporting_document_classification` steps.
- JPEG files do not depend on OCR text to become supporting documents.
- `claims.supporting_documents.supporting_document_type_id` is populated.
- `claims.supporting_document_visual_findings` rows exist from single/group extraction, not from classifier output.
- Group-level `before_after_photo_set` extraction still runs.

### Local Test 2: Heat Pump WETT/PDF Package

Use:

- `claims_ai_service_documentation/Test Data/heat pump/test006` if present.

Verify:

- PDF supporting documents still use the existing OCR/read/classifier/extraction path.
- No regression to WETT report visual findings.

### Local Test 3: Mixed Stress Package

Use:

- `claims_ai_service_documentation/Test Data/heat pump/test014`

Verify:

- Multiple upgrade types still work.
- Mixed PDF/image supporting docs are promoted correctly.
- Rule context window includes visual findings and group facts.

## Open Decisions

- Resolved: image-first classification uses `classifier_imagefiles`; PDF classification uses `classifier_pdfs`.
- Resolved: image classifier is constrained to `supporting_document | unknown`.
- Resolved: classifier raw output remains the classifier payload, while official visual findings and located fields are written only by single/group extraction steps.
- Resolved: config uses separate `classifier_pdf_system_record` and `classifier_image_system_record` fields.
