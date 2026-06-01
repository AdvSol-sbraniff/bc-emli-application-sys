BEGIN;

ALTER TABLE claims.ingest_documents
  ADD COLUMN IF NOT EXISTS invoice_id uuid NULL,
  ADD COLUMN IF NOT EXISTS promoted_supporting_document_id uuid NULL;

UPDATE claims.ingest_documents idoc
SET invoice_id = idoc.resolved_invoice_id
WHERE idoc.invoice_id IS NULL
  AND idoc.resolved_invoice_id IS NOT NULL;

UPDATE claims.ingest_documents idoc
SET invoice_id = iv.invoice_id
FROM claims.invoice_versions iv
WHERE idoc.invoice_id IS NULL
  AND idoc.resolved_invoice_version_id = iv.id;

ALTER TABLE claims.ingest_documents
  DROP CONSTRAINT IF EXISTS fk_ingest_documents_invoice,
  DROP CONSTRAINT IF EXISTS fk_ingest_documents_promoted_supporting_document;

ALTER TABLE claims.ingest_documents
  ADD CONSTRAINT fk_ingest_documents_invoice
    FOREIGN KEY (invoice_id)
    REFERENCES claims.invoices(id)
    ON DELETE CASCADE,
  ADD CONSTRAINT fk_ingest_documents_promoted_supporting_document
    FOREIGN KEY (promoted_supporting_document_id)
    REFERENCES claims.supporting_documents(id)
    ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_invoice_id
  ON claims.ingest_documents (invoice_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_promoted_supporting_document_id
  ON claims.ingest_documents (promoted_supporting_document_id);

ALTER TABLE claims.ingest_documents
  DROP CONSTRAINT IF EXISTS ingest_documents_classification_status_chk;

ALTER TABLE claims.ingest_documents
  ADD CONSTRAINT ingest_documents_classification_status_chk
    CHECK (classification_status IN ('pending','classified','needs_review','failed','superseded'));

ALTER TABLE claims.ingest_step_runs
  DROP CONSTRAINT IF EXISTS ingest_step_runs_step_type_chk,
  DROP CONSTRAINT IF EXISTS ingest_step_runs_target_required_chk,
  DROP CONSTRAINT IF EXISTS ingest_step_runs_target_compatibility_chk;

ALTER TABLE claims.ingest_step_runs
  ADD CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN (
      'upload',
      'upload_package_stage',
      'reprocess_package_stage',
      'ocr',
      'classifier',
      'genai',
      'case_facts',
      'genai_common',
      'genai_upgrade',
      'code_common',
      'code_upgrade',
      'aggregate_advice',
      'ocr_read',
      'triage_classifier',
      'supporting_document_extraction',
      'ocr_invoice'
    )),
  ADD CONSTRAINT ingest_step_runs_target_required_chk
    CHECK (
      step_type IN ('upload_package_stage','reprocess_package_stage')
      OR
      (invoice_version_id IS NOT NULL AND ingest_document_id IS NULL)
      OR
      (invoice_version_id IS NULL AND ingest_document_id IS NOT NULL)
    ),
  ADD CONSTRAINT ingest_step_runs_target_compatibility_chk
    CHECK (
      (
        step_type IN ('upload_package_stage','reprocess_package_stage')
        AND invoice_version_id IS NULL
        AND ingest_document_id IS NULL
      )
      OR
      (
        step_type IN ('ocr_read','triage_classifier','supporting_document_extraction')
        AND ingest_document_id IS NOT NULL
        AND invoice_version_id IS NULL
      )
      OR
      (
        step_type NOT IN (
          'upload_package_stage',
          'reprocess_package_stage',
          'ocr_read',
          'triage_classifier',
          'supporting_document_extraction'
        )
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
      )
    );

COMMIT;
