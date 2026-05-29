BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'validationgenai_config'
      AND column_name = 'classifier_system_record'
  )
  AND NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'claims'
      AND table_name = 'validationgenai_config'
      AND column_name = 'classifier_combined_with_extraction_system_record'
  ) THEN
    ALTER TABLE claims.validationgenai_config
      RENAME COLUMN classifier_system_record
      TO classifier_combined_with_extraction_system_record;
  END IF;
END $$;

ALTER TABLE claims.validationgenai_config
  ADD COLUMN IF NOT EXISTS classifier_combined_with_extraction_system_record character varying,
  ADD COLUMN IF NOT EXISTS classifier_without_extraction_system_record character varying,
  ADD COLUMN IF NOT EXISTS supporting_document_extraction_system_record character varying,
  ADD COLUMN IF NOT EXISTS supporting_document_extraction_mode text NOT NULL DEFAULT 'combined_with_classifier';

UPDATE claims.validationgenai_config
SET classifier_without_extraction_system_record =
      COALESCE(
        NULLIF(classifier_without_extraction_system_record, ''),
        classifier_combined_with_extraction_system_record
      ),
    supporting_document_extraction_mode =
      COALESCE(NULLIF(supporting_document_extraction_mode, ''), 'combined_with_classifier');

ALTER TABLE claims.validationgenai_config
  ALTER COLUMN supporting_document_extraction_mode SET DEFAULT 'combined_with_classifier',
  ALTER COLUMN supporting_document_extraction_mode SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'validationgenai_config_supporting_document_extraction_mode_chk'
      AND conrelid = 'claims.validationgenai_config'::regclass
  ) THEN
    ALTER TABLE claims.validationgenai_config
      ADD CONSTRAINT validationgenai_config_supporting_document_extraction_mode_chk
      CHECK (supporting_document_extraction_mode IN ('combined_with_classifier','separate_extraction'));
  END IF;
END $$;

ALTER TABLE claims.ingest_step_runs
  DROP CONSTRAINT IF EXISTS ingest_step_runs_step_type_chk,
  DROP CONSTRAINT IF EXISTS ingest_step_runs_target_compatibility_chk;

ALTER TABLE claims.ingest_step_runs
  ADD CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN ('upload','ocr','classifier','genai','genai_common','genai_upgrade','code_common','code_upgrade','ocr_read','triage_classifier','supporting_document_extraction','ocr_invoice')),
  ADD CONSTRAINT ingest_step_runs_target_compatibility_chk
    CHECK (
      (
        step_type IN ('ocr_read','triage_classifier','supporting_document_extraction')
        AND ingest_document_id IS NOT NULL
        AND invoice_version_id IS NULL
      )
      OR
      (
        step_type NOT IN ('ocr_read','triage_classifier','supporting_document_extraction')
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
      )
    );

COMMIT;
