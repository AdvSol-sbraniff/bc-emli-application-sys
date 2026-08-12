\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE claims.invoice_version_rulechecks
  ADD COLUMN IF NOT EXISTS compliance_score smallint NULL;

ALTER TABLE claims.invoice_version_rulechecks
  DROP CONSTRAINT IF EXISTS invoice_version_rulechecks_confidence_chk;

ALTER TABLE claims.invoice_version_rulechecks
  DROP CONSTRAINT IF EXISTS invoice_version_rulechecks_compliance_score_chk;

ALTER TABLE claims.invoice_version_rulechecks
  ADD CONSTRAINT invoice_version_rulechecks_compliance_score_chk
  CHECK (compliance_score IS NULL OR compliance_score BETWEEN 0 AND 100);

ALTER TABLE claims.invoice_version_rulechecks
  DROP COLUMN IF EXISTS confidence;

ALTER TABLE claims.invoice_versions
  DROP COLUMN IF EXISTS genai_overall_confidence;

ALTER TABLE claims.invoice_version_upgrade_types
  ALTER COLUMN confidence DROP NOT NULL,
  ALTER COLUMN confidence DROP DEFAULT;

UPDATE claims.invoice_version_upgrade_types
SET confidence = NULL
WHERE source_engine = 'genai';

COMMIT;
