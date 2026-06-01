# Redo Invoice Package Refactor Plan

## Goal

Fix the manual supporting-document upload path so unprocessed PDFs never go directly into `claims.supporting_documents`.

Target meaning:

- `claims.invoices` is the parent claim/invoice business record.
- `claims.ingest_documents` is the child table for raw uploaded PDFs that are unprocessed or in process.
- `claims.invoice_versions` is the processed main invoice PDF/version table.
- `claims.supporting_documents` is the processed supporting-document table only.

## Current Problem

The current `Invoice Supporting Documents` screen uploads PDFs directly into `claims.supporting_documents`.

That is wrong because those PDFs have not yet gone through:

- DI read OCR
- triage classifier
- supporting document type classification
- supporting-document located-field extraction

The bundle pipeline already does this correctly through `claims.ingest_documents`, but the manual supporting-document screen bypasses that pipeline.

## Design Decision

`claims.ingest_documents` should become a real child of `claims.invoices`.

Manual PDF uploads should flow through:

`Redo Invoice Package` upload -> `claims.ingest_documents` as raw/staged PDFs.

Processing should happen through one full-package action:

`Redo Entire Package` -> fresh ingest run -> fresh ingest document rows -> DI read -> classifier -> supporting-doc extraction -> invoice OCR -> GenAI.

The processed supporting-documents screen should not upload files anymore.

Do not add a separate table such as `manually_added_suppdocs`. Raw PDFs should have one home: `claims.ingest_documents`.

Redo must be additive first. It should insert/copy a fresh set of `claims.ingest_documents` rows for the new run before clearing, replacing, or superseding any existing processed outputs or staged rows.

## Database Changes

1. Add `invoice_id uuid` to `claims.ingest_documents`.

2. Add a foreign key:

```sql
ALTER TABLE claims.ingest_documents
  ADD CONSTRAINT fk_ingest_documents_invoice
  FOREIGN KEY (invoice_id)
  REFERENCES claims.invoices(id)
  ON DELETE CASCADE;
```

3. Add an index:

```sql
CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_invoice_id
  ON claims.ingest_documents (invoice_id, created_at DESC);
```

4. Backfill `invoice_id` for existing rows:

- First from `resolved_invoice_id`.
- Then from `resolved_invoice_version_id -> claims.invoice_versions.invoice_id`.
- Any rows still missing `invoice_id` should be reviewed before enforcing `NOT NULL`.

5. Keep `resolved_invoice_id` temporarily during migration.

6. Later cleanup should either remove `resolved_invoice_id` or stop using it as the parent/context invoice link.

7. Consider adding `promoted_supporting_document_id uuid NULL` to `claims.ingest_documents` for traceability after a staged supporting doc becomes a processed `claims.supporting_documents` row.

8. Add the new step types to the `claims.ingest_step_runs_step_type_chk` constraint:

- `upload_package_stage`
- `reprocess_package_stage`
- `case_facts`
- `aggregate_advice`

9. Add `superseded` as an allowed `claims.ingest_documents.classification_status`.

This status is used for raw/staged PDFs that were safely copied into a fresh redo run. It prevents old staging rows from blocking `Redo GenAI Only` after the copied rows have become the active package-processing rows.

10. Update both the clean schema and an incremental patch:

- Edit `claims_ai_service_ddl/2_create_schema.sql`.
- Add a new `claims_ai_service_ddl/8_*.sql` patch file for existing local/gold databases.
- Apply the patch to local Postgres.
- Rebuild the local schema from the clean DDL to prove `2_create_schema.sql` is complete and not relying only on patches.

## Backend Changes

1. Add model associations:

- `Claims::Invoice has_many :ingest_documents`
- `Claims::IngestDocument belongs_to :invoice`

2. Update bundle upload code so every staged PDF writes `ingest_documents.invoice_id`.

3. Replace the direct upload behavior in `Claims::SupportingDocuments::UploadPdfs`.

Recommended path:

- Retire that service for uploads.
- Introduce `Claims::Ingest::UploadInvoiceIntakeDocuments`.
- It accepts `invoice_id` and files.
- It creates `ingest_documents` rows linked to the invoice.
- It stores the raw PDFs as staged intake rows.
- It does not create processed `claims.supporting_documents` rows.

4. Add one full-package redo service.

Suggested service:

`Claims::Ingest::RedoInvoicePackage`

Responsibilities:

- Gather the full source set for the invoice.
- Insert/copy fresh `claims.ingest_documents` rows into a new `claims.ingest_runs` run.
- Only after fresh staging succeeds, mark old staged rows superseded or leave them as history.
- Run the normal pipeline against the fresh run.
- Replace processed outputs in a controlled step, not before source staging is safe.

Source PDFs must include:

- current main invoice PDF from `claims.invoice_versions`
- processed supporting PDFs from `claims.supporting_documents`
- unprocessed/manual PDFs already in `claims.ingest_documents`

5. Add a full-package advancer if the existing bundle advancer cannot safely support this.

Reason: the existing bundle advancer expects a bundle with exactly one invoice PDF. Redo should still expect one invoice candidate after classification, but it must also preserve manually staged PDFs and should have explicit replacement semantics.

Suggested service:

`Claims::Ingest::AdvanceRedoInvoicePackageRun`

Responsibilities:

- Wait for `ocr_read` on each staged doc.
- Run `triage_classifier`.
- If document is `supporting`, run `supporting_document_extraction` when configured fields exist.
- Promote processed supporting docs into `claims.supporting_documents`.
- If exactly one document is `invoice`, promote or replace the active invoice version through the existing invoice OCR path.
- If zero or multiple invoice documents are detected, fail the redo clearly without deleting the previous good processed state.
- If document is `unknown`, keep it staged/failed for review.

6. Reuse existing jobs where possible:

- `RunIngestReadOcrJob`
- `RunIngestTriageJob`
- `RunSupportingDocumentExtractionJob`
- `SupportingDocuments::PromoteFromIngestDocument`
- `RunOcrJob`
- `RunGenaiJob`

7. Update `PromoteFromIngestDocument` to write back `ingest_documents.promoted_supporting_document_id` if that traceability column is added.

8. Update `RunGenaiJob` to check for pending intake documents for the invoice.

Recommended behavior:

- If unprocessed `ingest_documents` exist for the invoice, fail fast or warn clearly.
- Do not silently run GenAI while uploaded supporting PDFs are still unprocessed.

## API Changes

Add a new controller:

`Api::Claims::RedoInvoicePackageController`

Routes:

- `GET /api/claims/admin/invoices/:invoice_id/redo_package/context`
- `GET /api/claims/admin/invoices/:invoice_id/redo_package/documents`
- `POST /api/claims/admin/invoices/:invoice_id/redo_package/documents`
- `DELETE /api/claims/admin/redo_package/documents/:id`
- `GET /api/claims/admin/redo_package/documents/:id/pdf_url`
- `POST /api/claims/admin/invoices/:invoice_id/redo_package`

The existing `InvoiceSupportingDocumentsController` should become view-only for processed supporting docs.

Remove or disable:

- `POST /api/claims/admin/invoices/:invoice_id/supporting_documents`

## React Changes

### New Screen: Redo Invoice Package

Purpose: upload and monitor raw/staged PDFs for a known invoice.

Show:

- original filename
- document kind: pending, invoice, supporting, unknown
- OCR status
- classifier status
- supporting document type
- routing quality
- extraction status
- promoted supporting document link/id
- error text
- actions: upload, open PDF, delete unpromoted row

Primary screen action:

- `Redo Entire Package`

Do not add row-level redo actions for now. The admin mental model should be simple: upload raw PDFs, then redo the whole invoice package.

### Existing Screen: Invoice Supporting Documents

Purpose: read-only view of processed supporting docs only.

Remove:

- upload box
- file picker
- upload button
- any action that creates a `claims.supporting_documents` row from a raw PDF

Keep:

- processed supporting document list
- supporting document type
- routing quality
- located fields
- open PDF action
- optional delete action, if admin cleanup is still wanted

### Navigation

Add a separate action/icon from invoice admin:

- `Redo Package` for raw/unprocessed PDFs and package-level redo
- `Supporting Documents` for processed supporting docs

Do not make the user guess which screen uploads belong to.

## Admin OCR and GenAI Screen Changes

Replace the confusing invoice-only OCR action.

Recommended buttons:

- `Redo GenAI Only`

Do not put `Redo Entire Package` on this screen. The one home for full package redo should be the `Redo Invoice Package` screen.

`Redo Entire Package` should safely rebuild the invoice package through the normal ingest pipeline:

1. Gather the current source PDFs for the invoice:

- current main invoice PDF from `claims.invoice_versions`
- processed supporting PDFs from `claims.supporting_documents`
- unprocessed/staged PDFs from `claims.ingest_documents`

2. Create a fresh `claims.ingest_runs` row and fresh `claims.ingest_documents` rows linked to the invoice.

3. Stage/copy all source PDFs successfully before deleting, replacing, or superseding anything.

4. Only once staging succeeds, clear stale processed AI outputs for that invoice in a controlled replacement step.

5. Run the normal pipeline:

- DI read OCR for each staged PDF
- classifier
- supporting-document extraction
- invoice DI OCR for the detected invoice PDF
- GenAI validation
- code rules
- final aggregation

`Redo GenAI Only` should keep existing OCR/classifier/supporting-document extraction results and rerun validation only.

Remove or hide the narrow invoice-only `Run OCR` button. If kept temporarily for debugging, label it explicitly as `Debug: OCR Invoice Version Only`.

Optionally show a warning if the invoice has pending intake documents:

`This invoice has unprocessed package PDFs. Use Redo Entire Package before running GenAI.`

The full package redo endpoint should be called only from:

- `Redo Invoice Package`

This avoids two buttons in different screens that appear to do the same dangerous thing.

## Migration Plan

1. Add additive DDL in `claims_ai_service_ddl/2_create_schema.sql`.

2. Add a new incremental patch SQL file for current local/gold databases.

3. Apply the patch to local Postgres and backfill `claims.ingest_documents.invoice_id`.

4. Rebuild the local schema from clean DDL and confirm the new columns, indexes, FKs, and step-type constraint are present.

5. Update Rails models and services to write `ingest_documents.invoice_id`.

6. Add new redo package upload API and screen.

7. Remove upload UI from `Invoice Supporting Documents`.

8. Add `Redo Entire Package` endpoint and wire it only from the `Redo Invoice Package` screen.

9. Keep old columns/routes briefly if needed for compatibility, but stop using direct supporting-doc upload.

10. Run local end-to-end tests.

11. Apply DB patch and seed/code deployment to gold.

12. After confidence, consider enforcing `ingest_documents.invoice_id NOT NULL`.

## Test Plan

### Local Tests

1. Bundle upload with invoice plus supporting docs still succeeds.

Expected:

- `ingest_documents.invoice_id` populated for every uploaded PDF.
- one invoice document becomes an `invoice_version`.
- supporting docs become `supporting_documents`.
- support-doc located fields are present.
- GenAI case facts include supporting-doc fields.

2. Manual supporting-document upload through new `Redo Invoice Package` screen.

Expected:

- upload creates `ingest_documents`, not `supporting_documents`.
- no processed supporting-document row is created merely by uploading.

3. Redo after manual supporting-document upload.

Expected:

- redo creates a fresh `ingest_run`.
- redo creates fresh `ingest_documents` rows before cleanup.
- newly uploaded manual PDFs are included in the fresh run.
- DI read runs.
- classifier runs.
- support-doc extraction runs.
- processed row appears in `Invoice Supporting Documents`.

4. Redo with a manually added invoice-like PDF in redo package screen.

Expected:

- classifier marks it as invoice.
- if this creates zero or multiple invoice candidates, redo fails clearly.
- previous good processed state is not destroyed before staging succeeds.

5. Run GenAI while intake docs are pending.

Expected:

- either blocked with a clear message or visibly warned.

6. Run GenAI after intake docs are processed.

Expected:

- no classifier rerun from GenAI.
- case facts include processed supporting-document located fields.

7. Redo preservation test.

Expected:

- add a new intake PDF.
- click `Redo Entire Package`.
- verify the new PDF is included in the fresh run.
- verify the new PDF is not lost even if the redo later fails classification.

## Open Decisions

1. Should processed supporting documents remain deletable from the read-only screen?

2. Should `Redo Invoice Package` allow invoice-like PDFs at all, or reject them after classifier?

3. Should `ingest_documents.invoice_id` become `NOT NULL` immediately, or only after a gold data backfill check?

4. Should we add `promoted_supporting_document_id` now for traceability?

5. Should old ingest rows be marked `superseded`, or simply retained as historical rows attached to older `ingest_runs`?

## Recommended Implementation Order

1. Schema and model associations.

2. Update `claims_ai_service_ddl/2_create_schema.sql`, add patch SQL, apply patch locally, and rebuild the local schema from clean DDL.

3. New redo package upload service/controller.

4. Full-package redo service and endpoint.

5. React `Redo Invoice Package` screen.

6. Remove upload from `Invoice Supporting Documents`.

7. Replace confusing OCR button with `Redo GenAI Only` on the OCR & GenAI screen, and keep full package redo only on `Redo Invoice Package`.

8. Add pending-intake warning/block to GenAI rerun.

9. Local tests.

10. Gold DB patch and deployment.
