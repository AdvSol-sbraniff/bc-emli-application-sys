BEGIN;

ALTER TABLE claims.validationgenai_config
  ADD COLUMN IF NOT EXISTS classifier_system_record character varying,
  ADD COLUMN IF NOT EXISTS classifier_pdf_system_record character varying,
  ADD COLUMN IF NOT EXISTS classifier_image_system_record character varying,
  ADD COLUMN IF NOT EXISTS supporting_document_extraction_system_record character varying;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'validationgenai_config'
      AND column_name = 'classifier_without_extraction_system_record'
  )
  AND EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'validationgenai_config'
      AND column_name = 'classifier_combined_with_extraction_system_record'
  ) THEN
    EXECUTE $sql$
      UPDATE claims.validationgenai_config
      SET classifier_system_record =
            COALESCE(
              NULLIF(classifier_system_record, ''),
              NULLIF(classifier_without_extraction_system_record, ''),
              NULLIF(classifier_combined_with_extraction_system_record, '')
            )
    $sql$;
  ELSIF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'validationgenai_config'
      AND column_name = 'classifier_without_extraction_system_record'
  ) THEN
    EXECUTE $sql$
      UPDATE claims.validationgenai_config
      SET classifier_system_record =
            COALESCE(
              NULLIF(classifier_system_record, ''),
              NULLIF(classifier_without_extraction_system_record, '')
            )
    $sql$;
  ELSIF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'validationgenai_config'
      AND column_name = 'classifier_combined_with_extraction_system_record'
  ) THEN
    EXECUTE $sql$
      UPDATE claims.validationgenai_config
      SET classifier_system_record =
            COALESCE(
              NULLIF(classifier_system_record, ''),
              NULLIF(classifier_combined_with_extraction_system_record, '')
            )
    $sql$;
  END IF;
END $$;

UPDATE claims.validationgenai_config
SET classifier_pdf_system_record =
      COALESCE(NULLIF(classifier_pdf_system_record, ''), NULLIF(classifier_system_record, '')),
    classifier_image_system_record =
      COALESCE(NULLIF(classifier_image_system_record, ''), NULLIF(classifier_system_record, ''))
WHERE classifier_system_record IS NOT NULL;

ALTER TABLE claims.validationgenai_config
  DROP CONSTRAINT IF EXISTS validationgenai_config_supporting_document_extraction_mode_chk;

ALTER TABLE claims.validationgenai_config
  DROP COLUMN IF EXISTS classifier_combined_with_extraction_system_record,
  DROP COLUMN IF EXISTS classifier_without_extraction_system_record,
  DROP COLUMN IF EXISTS supporting_document_extraction_mode,
  DROP COLUMN IF EXISTS supporting_document_group_extraction_system_record;

ALTER TABLE claims.ingest_step_runs
  ADD COLUMN IF NOT EXISTS supporting_document_type_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_ingest_step_runs_supporting_document_type'
      AND conrelid = 'claims.ingest_step_runs'::regclass
  ) THEN
    ALTER TABLE claims.ingest_step_runs
      ADD CONSTRAINT fk_ingest_step_runs_supporting_document_type
        FOREIGN KEY (supporting_document_type_id)
        REFERENCES claims.supporting_document_types(id)
        ON DELETE CASCADE;
  END IF;
END $$;

ALTER TABLE claims.ingest_step_runs
  DROP CONSTRAINT IF EXISTS ingest_step_runs_step_type_chk,
  DROP CONSTRAINT IF EXISTS ingest_step_runs_target_required_chk,
  DROP CONSTRAINT IF EXISTS ingest_step_runs_target_compatibility_chk;

ALTER TABLE claims.ingest_step_runs
  ADD CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN ('upload','upload_package_stage','ocr','classifier','genai','case_facts','product_lookup_enrichment','genai_common','genai_upgrade','code_common','code_upgrade','aggregate_advice','ocr_read','triage_classifier','classifier_pdfs','classifier_imagefiles','supporting_document_extraction','supporting_document_type_extraction','plus1fix_ocr_read','plus1fix_classifier','ocr_invoice')),
  ADD CONSTRAINT ingest_step_runs_target_required_chk
    CHECK (
      step_type = 'upload_package_stage'
      OR (
        invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NULL
      )
      OR (
        invoice_version_id IS NULL
        AND ingest_document_id IS NOT NULL
        AND supporting_document_type_id IS NULL
      )
      OR (
        invoice_version_id IS NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NOT NULL
      )
    ),
  ADD CONSTRAINT ingest_step_runs_target_compatibility_chk
    CHECK (
      (
        step_type = 'upload_package_stage'
        AND invoice_version_id IS NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NULL
      )
      OR
      (
        step_type IN ('ocr_read','triage_classifier','classifier_imagefiles','supporting_document_extraction')
        AND ingest_document_id IS NOT NULL
        AND invoice_version_id IS NULL
        AND supporting_document_type_id IS NULL
      )
      OR
      (
        step_type = 'classifier_pdfs'
        AND supporting_document_type_id IS NULL
        AND (
          (
            ingest_document_id IS NOT NULL
            AND invoice_version_id IS NULL
          )
          OR
          (
            ingest_document_id IS NULL
            AND invoice_version_id IS NOT NULL
          )
        )
      )
      OR
      (
        step_type IN ('plus1fix_ocr_read','plus1fix_classifier')
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NULL
      )
      OR
      (
        step_type = 'supporting_document_type_extraction'
        AND supporting_document_type_id IS NOT NULL
        AND invoice_version_id IS NULL
        AND ingest_document_id IS NULL
      )
      OR
      (
        step_type NOT IN ('ocr_read','triage_classifier','classifier_pdfs','classifier_imagefiles','supporting_document_extraction','supporting_document_type_extraction')
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NULL
      )
    );

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_supporting_document_type_id
  ON claims.ingest_step_runs (supporting_document_type_id);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_supporting_document_type_step
  ON claims.ingest_step_runs (supporting_document_type_id, step_type, created_at DESC);

COMMIT;
