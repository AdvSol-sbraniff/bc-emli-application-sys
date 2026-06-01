BEGIN;

ALTER TABLE claims.validationgenai_config
  ADD COLUMN IF NOT EXISTS classifier_system_record character varying,
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

ALTER TABLE claims.validationgenai_config
  DROP CONSTRAINT IF EXISTS validationgenai_config_supporting_document_extraction_mode_chk;

ALTER TABLE claims.validationgenai_config
  DROP COLUMN IF EXISTS classifier_combined_with_extraction_system_record,
  DROP COLUMN IF EXISTS classifier_without_extraction_system_record,
  DROP COLUMN IF EXISTS supporting_document_extraction_mode;

ALTER TABLE claims.ingest_step_runs
  DROP CONSTRAINT IF EXISTS ingest_step_runs_step_type_chk,
  DROP CONSTRAINT IF EXISTS ingest_step_runs_target_compatibility_chk;

ALTER TABLE claims.ingest_step_runs
  ADD CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN ('upload','upload_package_stage','reprocess_package_stage','ocr','classifier','genai','case_facts','genai_common','genai_upgrade','code_common','code_upgrade','aggregate_advice','ocr_read','triage_classifier','supporting_document_extraction','ocr_invoice')),
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
        step_type NOT IN ('ocr_read','triage_classifier','supporting_document_extraction')
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
      )
    );

COMMIT;
