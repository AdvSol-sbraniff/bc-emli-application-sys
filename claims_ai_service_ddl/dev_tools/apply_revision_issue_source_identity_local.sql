\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE claims.revision_issues
  ADD COLUMN IF NOT EXISTS opened_from_rule_key text NULL,
  ADD COLUMN IF NOT EXISTS opened_from_rule_upgrade_type_id uuid NULL,
  ADD COLUMN IF NOT EXISTS opened_from_invoice_field_key text NULL,
  ADD COLUMN IF NOT EXISTS opened_from_invoice_field_upgrade_type_id uuid NULL,
  ADD COLUMN IF NOT EXISTS opened_from_supporting_document_type_key text NULL,
  ADD COLUMN IF NOT EXISTS opened_from_supporting_field_key text NULL,
  ADD COLUMN IF NOT EXISTS opened_from_source_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb;

UPDATE claims.revision_issues issue
   SET opened_from_rule_key = rulecheck.rule_key,
       opened_from_rule_upgrade_type_id = rulecheck.invoice_upgrade_type_id
  FROM claims.invoice_version_rulechecks rulecheck
 WHERE issue.issue_type = 'rule'
   AND rulecheck.id = issue.opened_from_invoice_version_rulecheck_id
   AND (
     issue.opened_from_rule_key IS DISTINCT FROM rulecheck.rule_key
     OR issue.opened_from_rule_upgrade_type_id IS DISTINCT FROM rulecheck.invoice_upgrade_type_id
   );

UPDATE claims.revision_issues issue
   SET opened_from_invoice_field_key = located_field.field_key,
       opened_from_invoice_field_upgrade_type_id = located_field.invoice_upgrade_type_id
  FROM claims.invoice_version_located_fields located_field
 WHERE issue.issue_type = 'invoice_field'
   AND located_field.id = issue.opened_from_invoice_version_located_field_id
   AND (
     issue.opened_from_invoice_field_key IS DISTINCT FROM located_field.field_key
     OR issue.opened_from_invoice_field_upgrade_type_id IS DISTINCT FROM located_field.invoice_upgrade_type_id
   );

UPDATE claims.revision_issues issue
   SET opened_from_supporting_document_type_key = document_type.type_key,
       opened_from_supporting_field_key = located_field.field_key
  FROM claims.supporting_document_located_fields located_field
  JOIN claims.supporting_documents document
    ON document.id = located_field.supporting_document_id
  JOIN claims.supporting_document_types document_type
    ON document_type.id = document.supporting_document_type_id
 WHERE issue.issue_type = 'supporting_document_field'
   AND located_field.id = issue.opened_from_supporting_document_located_field_id
   AND (
     issue.opened_from_supporting_document_type_key IS DISTINCT FROM document_type.type_key
     OR issue.opened_from_supporting_field_key IS DISTINCT FROM located_field.field_key
   );

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_revision_issues_rule_upgrade_type'
       AND conrelid = 'claims.revision_issues'::regclass
  ) THEN
    ALTER TABLE claims.revision_issues
      ADD CONSTRAINT fk_revision_issues_rule_upgrade_type
      FOREIGN KEY (opened_from_rule_upgrade_type_id)
      REFERENCES claims.invoice_upgrade_types(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'fk_revision_issues_invoice_field_upgrade_type'
       AND conrelid = 'claims.revision_issues'::regclass
  ) THEN
    ALTER TABLE claims.revision_issues
      ADD CONSTRAINT fk_revision_issues_invoice_field_upgrade_type
      FOREIGN KEY (opened_from_invoice_field_upgrade_type_id)
      REFERENCES claims.invoice_upgrade_types(id);
  END IF;
END
$$;

ALTER TABLE claims.revision_issues
  DROP CONSTRAINT IF EXISTS revision_issues_stable_identity_chk;

ALTER TABLE claims.revision_issues
  ADD CONSTRAINT revision_issues_stable_identity_chk
  CHECK (
    (
      issue_type = 'rule'
      AND length(btrim(opened_from_rule_key)) > 0
      AND opened_from_rule_upgrade_type_id IS NOT NULL
      AND opened_from_invoice_field_key IS NULL
      AND opened_from_invoice_field_upgrade_type_id IS NULL
      AND opened_from_supporting_document_type_key IS NULL
      AND opened_from_supporting_field_key IS NULL
    )
    OR
    (
      issue_type = 'invoice_field'
      AND opened_from_rule_key IS NULL
      AND opened_from_rule_upgrade_type_id IS NULL
      AND length(btrim(opened_from_invoice_field_key)) > 0
      AND opened_from_invoice_field_upgrade_type_id IS NOT NULL
      AND opened_from_supporting_document_type_key IS NULL
      AND opened_from_supporting_field_key IS NULL
    )
    OR
    (
      issue_type = 'supporting_document_field'
      AND opened_from_rule_key IS NULL
      AND opened_from_rule_upgrade_type_id IS NULL
      AND opened_from_invoice_field_key IS NULL
      AND opened_from_invoice_field_upgrade_type_id IS NULL
      AND length(btrim(opened_from_supporting_document_type_key)) > 0
      AND length(btrim(opened_from_supporting_field_key)) > 0
    )
    OR
    (
      issue_type = 'di_field'
      AND opened_from_rule_key IS NULL
      AND opened_from_rule_upgrade_type_id IS NULL
      AND opened_from_invoice_field_key IS NULL
      AND opened_from_invoice_field_upgrade_type_id IS NULL
      AND opened_from_supporting_document_type_key IS NULL
      AND opened_from_supporting_field_key IS NULL
    )
  ) NOT VALID;

ALTER TABLE claims.revision_issues
  VALIDATE CONSTRAINT revision_issues_stable_identity_chk;

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_rule_identity
  ON claims.revision_issues (
    invoice_id,
    opened_from_rule_key,
    opened_from_rule_upgrade_type_id
  )
  WHERE issue_type = 'rule';

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_invoice_field_identity
  ON claims.revision_issues (
    invoice_id,
    opened_from_invoice_field_key,
    opened_from_invoice_field_upgrade_type_id
  )
  WHERE issue_type = 'invoice_field';

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_supporting_field_identity
  ON claims.revision_issues (
    invoice_id,
    opened_from_supporting_document_type_key,
    opened_from_supporting_field_key
  )
  WHERE issue_type = 'supporting_document_field';

COMMIT;
