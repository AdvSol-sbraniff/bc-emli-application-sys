# Evidence File Type Support Plan

Status: draft plan

Purpose: update the claims AI package intake pipeline so uploaded evidence files are not treated as PDF-only. The immediate driver is the Health and Safety `test006` package, which contains one invoice PDF plus standalone JPG after-photo files.

## 1. Problem

The current intake path mostly assumes uploaded package files are PDFs.

Known symptoms:

- The submission simulator filters uploads to PDF files only.
- The file picker accepts only `application/pdf,.pdf`.
- Ingest services use `pdfs[]` naming and PDF fallback filenames/content types.
- The Node upload and OCR code path often defaults content type to `application/pdf`.
- The pipeline language still contains legacy terms such as `supplement`, while the intended domain term is supporting document.

This breaks realistic evidence packages where contractors upload photos directly from phones, such as:

- Window energy performance labels glued to panes.
- Manufacturer nameplate photos.
- Before/after remediation photos.
- Attic, insulation, pest, mould, asbestos, or structural remediation photos.

## 2. Target Mental Model

The package contains evidence files, not just PDFs.

Logical classification should be:

- `invoice`: the resolved invoice document, normally a PDF.
- `supporting_document`: a non-invoice evidence file, which can be PDF, JPG, JPEG, PNG, or a future supported type.
- `unknown`: a file the system cannot safely route.

Physical file type is separate from logical role:

```text
PDF invoice -> claims.ingest_documents -> claims.invoice_versions
PDF supporting document -> claims.ingest_documents -> claims.supporting_documents
JPG/PNG supporting document -> claims.ingest_documents -> claims.supporting_documents
```

The data model already has the right durable parent for photos: `claims.supporting_documents`. A photo is a supporting document entity with `content_type = 'image/jpeg'` or similar.

## 3. Design Decisions

### 3.1 Keep Images As Supporting Documents

Standalone JPG/PNG files should become `claims.supporting_documents` rows after classification and promotion.

Do not invent a separate top-level `supporting_images` parent. Images are evidence files in the same business category as supporting PDFs.

### 3.2 Keep DI Read For Images

Document Intelligence read/OCR should still run for image files when the file type is supported.

Reasons:

- Contractor photos may contain printed label text.
- Window labels may show U-factor, ENERGY STAR, manufacturer, model, CPD, NRCan, or other product evidence.
- Manufacturer labels may show model, serial, AHRI, or equipment type.

DI-read output for images should still be stored in:

- `claims.ingest_documents.di_read_raw_json`
- `claims.ingest_step_runs.di_results_json`

### 3.3 Use Vision-Capable GenAI For Visual Meaning

DI-read is OCR. It is not enough for visual evidence.

Supporting-document extraction should use a vision-capable GenAI path when the supporting evidence file is an image or when a PDF contains important visual/photo evidence.

The visual extraction should answer questions such as:

- Does this appear to be a before photo, after photo, label, nameplate, permit, or other visual evidence?
- Is the label/photo legible?
- What visible objects or conditions are relevant?
- Are there visible model/reference numbers?
- Does the image appear to support the claimed document type?

Visual findings should be stored in the supporting-document evidence model, not directly as invoice-level rulechecks.

### 3.4 Prefer Domain Language Over Legacy Wording

User-facing docs/UI/plans should say supporting document, not supplement.

Existing database enum values such as `document_kind = 'supplement'` and columns such as `supplement_routing_quality` may remain temporarily, but they should be treated as legacy implementation names.

## 4. Proposed Pipeline Changes

### 4.1 Upload And Staging

Allow package upload to accept:

- `.pdf` / `application/pdf`
- `.jpg` / `image/jpeg`
- `.jpeg` / `image/jpeg`
- `.png` / `image/png`

Update UI labels from PDF-specific language to evidence-file/package language.

Potential UI wording:

```text
Upload invoice and supporting evidence files
Accepted file types: PDF, JPG, JPEG, PNG
```

### 4.2 Blob Upload

Preserve original filename and content type.

Storage keys should not force every file to end in `.pdf`. Use a safe extension derived from the uploaded filename/content type.

Example:

```text
sessions/<session_id>/evidence/<ingest_document_id>/original.pdf
sessions/<session_id>/evidence/<ingest_document_id>/original.jpg
```

### 4.3 OCR Read

`ocr_read` should call the Document Intelligence read model with the correct content type.

For PDFs:

```text
contentType = application/pdf
```

For JPG:

```text
contentType = image/jpeg
```

For PNG:

```text
contentType = image/png
```

The Node service should not hard-code `application/pdf` for all OCR bytes.

### 4.4 Triage Classifier

The classifier should classify the logical document role and supporting-document type.

Desired logical output language:

```json
{
  "document_kind": "invoice | supporting_document | unknown",
  "supporting_document_type_key": "before_after_photo_set | manufacturer_label_photo | ...",
  "routing_quality": "usable | needs_review | requires_visual_review | unusable"
}
```

If the database still stores `supplement`, the Rails apply service can translate:

```text
supporting_document -> supplement
```

That keeps the model stable while letting prompts and UI use the right term.

### 4.5 Supporting-Document Extraction

For supporting PDFs:

- Use DI-read text.
- Include PDF or rendered pages only if visual evidence is important and supported by the GenAI endpoint.

For supporting JPG/PNG:

- Use DI-read text as OCR context.
- Send the image to the vision-capable GenAI extraction path.
- Store structured located fields in `claims.supporting_document_located_fields`.
- Store visual interpretation in the supporting-document visual findings child table.

### 4.6 Promotion

Promotion should copy image metadata into `claims.supporting_documents` the same way it copies PDF metadata:

- `storage_key`
- `original_filename`
- `content_type`
- `file_size_bytes`
- `di_read_raw_json`
- `classifier_raw_json`
- classification fields
- routing quality fields

## 5. Data Model Notes

No new top-level image parent is needed.

Existing durable parent:

```text
claims.supporting_documents
```

Visual child table already planned/introduced:

```text
claims.supporting_document_visual_findings
```

Recommended use:

- One row per visual finding or per image-level finding, depending on extraction output.
- For standalone JPG/PNG supporting documents, the `supporting_document_id` already identifies the file.
- `page` can be null or `1` for standalone images.
- `finding_type` can describe `before_photo`, `after_photo`, `label_photo`, `nameplate`, `site_condition`, or similar.

## 6. Files Likely To Change

Frontend:

- `app/frontend/components/domains/submission-simulator-admin/index.tsx`
- Any supporting-document upload/add-file screens that currently say PDF-only.

Rails ingest:

- `app/services/claims/ingest/create_draft_batch.rb`
- `app/services/claims/ingest/redo_invoice_package.rb`
- `app/services/claims/ingest/upload_redo_package_documents.rb`
- Older upload paths only if still used.

Sidekiq jobs:

- `app/jobs/claims/run_ingest_read_ocr_job.rb`
- `app/jobs/claims/run_ingest_triage_job.rb`
- `app/jobs/claims/run_supporting_document_extraction_job.rb`

Node claims AI service:

- `claims_ai_service/src/controllers/inv.controller.ts`
- `claims_ai_service/src/services/inv.service.ts`
- GenAI API wrapper if image content needs a different request shape.

Seeds/prompts:

- `claims_ai_service_ddl/5_insert_validationgenai_config.sql`
- Supporting-document extraction prompt/config records if image-specific guidance is needed.

Docs:

- `claims_ai_service_documentation/claims_data_model.md`
- `claims_ai_service_documentation/genai_upgrade_context_window_refactor_plan.md`, if the context-window stack references visual findings.

## 7. Test Package

Primary test case:

```text
claims_ai_service_documentation/Test Data/Heath & Safety/test006
```

Files:

- `Health & Safety invoice.pdf`
- `Health & Safety after photo (1).jpg`
- `Health & Safety after photo (2).jpg`

Expected high-level result:

- The invoice PDF is promoted to `claims.invoice_versions`.
- Each JPG is staged, OCR-read if supported, classified as a supporting document, and promoted to `claims.supporting_documents`.
- The JPG files keep `content_type = 'image/jpeg'`.
- Supporting-document extraction produces located fields and/or visual findings.
- Health and safety GenAI validation can see that photo evidence exists.

## 8. Open Questions

- Should the DB enum physically change from `supplement` to `supporting_document`, or should we keep a translation layer for now?
- Should `before_after_photo_set` represent one file, multiple files, or a grouped logical set?
- Should two standalone photos be grouped together for review, or remain separate supporting-document rows with the same type?
- Should image OCR failures be fatal, or should image files continue to visual extraction with `requires_visual_review`?
- Which image MIME types are approved for go-live: JPG/JPEG/PNG only, or also HEIC from iPhones?

## 9. Recommended First Implementation Slice

1. Allow JPG/JPEG/PNG in the upload UI and ingest validation.
2. Preserve image content type and extension in Blob storage.
3. Update Node OCR to pass the actual content type into Document Intelligence read.
4. Update classifier prompts to use `supporting_document` language while mapping to current DB values if needed.
5. Promote image supporting documents into `claims.supporting_documents`.
6. Run Health and Safety `test006` end to end.
7. Only after that, expand visual extraction behavior if needed.
