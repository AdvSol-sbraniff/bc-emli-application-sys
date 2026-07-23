BEGIN;

ALTER TABLE claims.code_rules
  ADD COLUMN IF NOT EXISTS contractor_action text NULL;

ALTER TABLE claims.genai_rules
  ADD COLUMN IF NOT EXISTS contractor_action text NULL;

ALTER TABLE claims.code_rule_history
  ADD COLUMN IF NOT EXISTS contractor_action text NULL;

ALTER TABLE claims.genai_rule_history
  ADD COLUMN IF NOT EXISTS contractor_action text NULL;

UPDATE claims.code_rules
SET
  contractor_action = COALESCE(
    contractor_action,
    NULLIF(
      btrim(substring(source_quote FROM '(?is)\n+\*\*Action:\*\*\s*(.*)$')),
      ''
    )
  ),
  source_quote = btrim(
    regexp_replace(
      source_quote,
      '(?is)\n+\*\*Action:\*\*\s*.*$',
      ''
    )
  )
WHERE source_quote ~* E'\\n+\\*\\*Action:\\*\\*';

UPDATE claims.genai_rules
SET
  contractor_action = COALESCE(
    contractor_action,
    NULLIF(
      btrim(substring(source_quote FROM '(?is)\n+\*\*Action:\*\*\s*(.*)$')),
      ''
    )
  ),
  source_quote = btrim(
    regexp_replace(
      source_quote,
      '(?is)\n+\*\*Action:\*\*\s*.*$',
      ''
    )
  )
WHERE source_quote ~* E'\\n+\\*\\*Action:\\*\\*';

UPDATE claims.code_rule_history
SET
  contractor_action = COALESCE(
    contractor_action,
    NULLIF(
      btrim(substring(source_quote FROM '(?is)\n+\*\*Action:\*\*\s*(.*)$')),
      ''
    )
  ),
  source_quote = btrim(
    regexp_replace(
      source_quote,
      '(?is)\n+\*\*Action:\*\*\s*.*$',
      ''
    )
  )
WHERE source_quote ~* E'\\n+\\*\\*Action:\\*\\*';

UPDATE claims.genai_rule_history
SET
  contractor_action = COALESCE(
    contractor_action,
    NULLIF(
      btrim(substring(source_quote FROM '(?is)\n+\*\*Action:\*\*\s*(.*)$')),
      ''
    )
  ),
  source_quote = btrim(
    regexp_replace(
      source_quote,
      '(?is)\n+\*\*Action:\*\*\s*.*$',
      ''
    )
  )
WHERE source_quote ~* E'\\n+\\*\\*Action:\\*\\*';

COMMIT;
