\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF to_regclass('claims.admin_revision_requests') IS NOT NULL
     AND to_regclass('claims.conversation_messages') IS NULL THEN
    ALTER TABLE claims.admin_revision_requests RENAME TO conversation_messages;
  END IF;
END
$$;

DO $$
BEGIN
  IF to_regclass('claims.conversation_messages') IS NOT NULL THEN
    ALTER TABLE claims.conversation_messages
      DROP CONSTRAINT IF EXISTS revision_requests_message_type_chk;
    ALTER TABLE claims.conversation_messages
      DROP CONSTRAINT IF EXISTS conversation_messages_message_type_chk;

    UPDATE claims.conversation_messages
       SET message_type = 'admin_message'
     WHERE message_type = 'admin_revision_request';

    ALTER TABLE claims.conversation_messages
      ADD CONSTRAINT conversation_messages_message_type_chk
      CHECK (message_type IN ('admin_message', 'contractor_note'));
    ALTER TABLE claims.conversation_messages
      ALTER COLUMN message_type SET DEFAULT 'admin_message';
  END IF;
END
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_versions_id_invoice_id
  ON claims.invoice_versions (id, invoice_id);

CREATE TABLE IF NOT EXISTS claims.invoice_status_transitions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  invoice_version_id uuid NULL,
  actor_user_id uuid NULL,
  from_status text NULL,
  from_status_subtype text NULL,
  to_status text NOT NULL,
  to_status_subtype text NULL,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  CONSTRAINT invoice_status_transitions_pkey PRIMARY KEY (id),
  CONSTRAINT fk_invoice_status_transitions_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id) ON DELETE CASCADE,
  CONSTRAINT fk_invoice_status_transitions_invoice_version
    FOREIGN KEY (invoice_version_id) REFERENCES claims.invoice_versions(id) ON DELETE SET NULL,
  CONSTRAINT fk_invoice_status_transitions_actor
    FOREIGN KEY (actor_user_id) REFERENCES public.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_invoice_status_transitions_invoice
  ON claims.invoice_status_transitions (invoice_id, created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_invoice_status_transitions_version
  ON claims.invoice_status_transitions (invoice_version_id);
CREATE INDEX IF NOT EXISTS idx_invoice_status_transitions_to_status
  ON claims.invoice_status_transitions (to_status, created_at DESC);

CREATE TABLE IF NOT EXISTS claims.revision_rounds (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  invoice_version_id uuid NOT NULL,
  round_number integer NOT NULL,
  admin_sent_at timestamp(6) without time zone NULL,
  contractor_response_submitted_at timestamp(6) without time zone NULL,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  CONSTRAINT revision_rounds_pkey PRIMARY KEY (id),
  CONSTRAINT fk_revision_rounds_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id) ON DELETE CASCADE,
  CONSTRAINT fk_revision_rounds_invoice_version
    FOREIGN KEY (invoice_version_id, invoice_id)
    REFERENCES claims.invoice_versions(id, invoice_id),
  CONSTRAINT revision_rounds_number_chk CHECK (round_number >= 1),
  CONSTRAINT revision_rounds_invoice_number_uniq UNIQUE (invoice_id, round_number),
  CONSTRAINT revision_rounds_timestamp_chk CHECK (
    contractor_response_submitted_at IS NULL OR (
      admin_sent_at IS NOT NULL AND contractor_response_submitted_at >= admin_sent_at
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_revision_rounds_invoice
  ON claims.revision_rounds (invoice_id, round_number DESC);

CREATE TABLE IF NOT EXISTS claims.revision_issues (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  issue_type text NOT NULL,
  opened_from_invoice_version_rulecheck_id uuid NULL,
  opened_from_invoice_version_located_field_id uuid NULL,
  opened_from_supporting_document_located_field_id uuid NULL,
  opened_from_di_invoice_version_id uuid NULL,
  opened_from_di_field_key text NULL,
  status text NOT NULL DEFAULT 'open',
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  CONSTRAINT revision_issues_pkey PRIMARY KEY (id),
  CONSTRAINT fk_revision_issues_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id) ON DELETE CASCADE,
  CONSTRAINT fk_revision_issues_rulecheck
    FOREIGN KEY (opened_from_invoice_version_rulecheck_id)
    REFERENCES claims.invoice_version_rulechecks(id),
  CONSTRAINT fk_revision_issues_invoice_field
    FOREIGN KEY (opened_from_invoice_version_located_field_id)
    REFERENCES claims.invoice_version_located_fields(id),
  CONSTRAINT fk_revision_issues_supporting_field
    FOREIGN KEY (opened_from_supporting_document_located_field_id)
    REFERENCES claims.supporting_document_located_fields(id),
  CONSTRAINT fk_revision_issues_di_version
    FOREIGN KEY (opened_from_di_invoice_version_id, invoice_id)
    REFERENCES claims.invoice_versions(id, invoice_id),
  CONSTRAINT revision_issues_type_chk CHECK (
    issue_type IN ('rule', 'invoice_field', 'supporting_document_field', 'di_field')
  ),
  CONSTRAINT revision_issues_status_chk CHECK (
    status IN (
      'open',
      'closed_via_corrected_documentation',
      'closed_via_attestation',
      'closed_via_exception',
      'closed_as_withdrawn'
    )
  ),
  CONSTRAINT revision_issues_source_chk CHECK (
    (issue_type = 'rule' AND opened_from_invoice_version_rulecheck_id IS NOT NULL AND opened_from_invoice_version_located_field_id IS NULL AND opened_from_supporting_document_located_field_id IS NULL AND opened_from_di_invoice_version_id IS NULL AND opened_from_di_field_key IS NULL) OR
    (issue_type = 'invoice_field' AND opened_from_invoice_version_rulecheck_id IS NULL AND opened_from_invoice_version_located_field_id IS NOT NULL AND opened_from_supporting_document_located_field_id IS NULL AND opened_from_di_invoice_version_id IS NULL AND opened_from_di_field_key IS NULL) OR
    (issue_type = 'supporting_document_field' AND opened_from_invoice_version_rulecheck_id IS NULL AND opened_from_invoice_version_located_field_id IS NULL AND opened_from_supporting_document_located_field_id IS NOT NULL AND opened_from_di_invoice_version_id IS NULL AND opened_from_di_field_key IS NULL) OR
    (issue_type = 'di_field' AND opened_from_invoice_version_rulecheck_id IS NULL AND opened_from_invoice_version_located_field_id IS NULL AND opened_from_supporting_document_located_field_id IS NULL AND opened_from_di_invoice_version_id IS NOT NULL AND length(btrim(opened_from_di_field_key)) > 0)
  )
);

CREATE INDEX IF NOT EXISTS idx_revision_issues_invoice
  ON claims.revision_issues (invoice_id, status, created_at, id);
CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_rule_source
  ON claims.revision_issues (invoice_id, opened_from_invoice_version_rulecheck_id)
  WHERE issue_type = 'rule';
CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_invoice_field_source
  ON claims.revision_issues (invoice_id, opened_from_invoice_version_located_field_id)
  WHERE issue_type = 'invoice_field';
CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_supporting_field_source
  ON claims.revision_issues (invoice_id, opened_from_supporting_document_located_field_id)
  WHERE issue_type = 'supporting_document_field';
CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_di_field_source
  ON claims.revision_issues (invoice_id, opened_from_di_field_key)
  WHERE issue_type = 'di_field';

CREATE TABLE IF NOT EXISTS claims.revision_issue_comments (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  revision_issue_id uuid NOT NULL,
  revision_round_id uuid NOT NULL,
  author_type text NOT NULL,
  admin_recommended_remedy text NULL,
  contractor_response_method text NULL,
  comment_text text NOT NULL,
  contractor_asserted_value text NULL,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  CONSTRAINT revision_issue_comments_pkey PRIMARY KEY (id),
  CONSTRAINT fk_revision_issue_comments_issue
    FOREIGN KEY (revision_issue_id) REFERENCES claims.revision_issues(id) ON DELETE CASCADE,
  CONSTRAINT fk_revision_issue_comments_round
    FOREIGN KEY (revision_round_id) REFERENCES claims.revision_rounds(id) ON DELETE CASCADE,
  CONSTRAINT revision_issue_comments_author_chk CHECK (author_type IN ('admin', 'contractor')),
  CONSTRAINT revision_issue_comments_text_chk CHECK (length(btrim(comment_text)) > 0),
  CONSTRAINT revision_issue_comments_admin_remedy_chk CHECK (
    admin_recommended_remedy IS NULL OR admin_recommended_remedy IN (
      'correct_and_reupload_invoice', 'upload_supporting_document',
      'provide_attestation', 'provide_explanation'
    )
  ),
  CONSTRAINT revision_issue_comments_contractor_method_chk CHECK (
    contractor_response_method IS NULL OR contractor_response_method IN (
      'corrected_invoice_uploaded', 'supporting_document_uploaded',
      'attestation_provided', 'explanation_provided', 'unable_to_resolve'
    )
  ),
  CONSTRAINT revision_issue_comments_author_fields_chk CHECK (
    (author_type = 'admin' AND contractor_response_method IS NULL AND contractor_asserted_value IS NULL) OR
    (author_type = 'contractor' AND admin_recommended_remedy IS NULL AND contractor_response_method IS NOT NULL)
  ),
  CONSTRAINT revision_issue_comments_asserted_value_chk CHECK (
    contractor_asserted_value IS NULL OR (
      author_type = 'contractor' AND contractor_response_method = 'attestation_provided'
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_revision_issue_comments_issue
  ON claims.revision_issue_comments (revision_issue_id, created_at, id);
CREATE INDEX IF NOT EXISTS idx_revision_issue_comments_round
  ON claims.revision_issue_comments (revision_round_id, created_at, id);

-- Preserve any local history created by the superseded two-table model.
DO $$
BEGIN
  IF to_regclass('claims.revision_requests') IS NULL
     OR to_regclass('claims.revision_request_entries') IS NULL THEN
    RETURN;
  END IF;

  CREATE TEMP TABLE legacy_revision_entry_keys ON COMMIT DROP AS
  SELECT
    e.id AS entry_id,
    r.id AS round_id,
    r.invoice_id,
    e.entry_type AS issue_type,
    e.created_at AS entry_created_at,
    r.created_at AS round_created_at,
    CASE e.entry_type
      WHEN 'rule' THEN concat_ws(':', 'rule', rc.source_engine, rc.rule_key, rc.invoice_upgrade_type_id::text)
      WHEN 'invoice_field' THEN concat_ws(':', 'invoice_field', ivlf.source_engine, ivlf.field_key, ivlf.invoice_upgrade_type_id::text)
      WHEN 'supporting_document_field' THEN concat_ws(':', 'supporting_document_field', COALESCE(sdlf.supporting_document_type_located_field_id::text, sdlf.field_key))
      WHEN 'di_field' THEN concat_ws(':', 'di_field', e.di_field_key)
    END AS logical_key
  FROM claims.revision_request_entries e
  JOIN claims.revision_requests r ON r.id = e.revision_request_id
  LEFT JOIN claims.invoice_version_rulechecks rc ON rc.id = e.invoice_version_rulecheck_id
  LEFT JOIN claims.invoice_version_located_fields ivlf ON ivlf.id = e.invoice_version_located_field_id
  LEFT JOIN claims.supporting_document_located_fields sdlf ON sdlf.id = e.supporting_document_located_field_id;

  CREATE TEMP TABLE legacy_revision_issue_groups ON COMMIT DROP AS
  SELECT
    gen_random_uuid() AS issue_id,
    invoice_id,
    issue_type,
    logical_key,
    (array_agg(entry_id ORDER BY round_created_at, entry_created_at, entry_id))[1] AS origin_entry_id,
    (array_agg(entry_id ORDER BY round_created_at DESC, entry_created_at DESC, entry_id DESC))[1] AS latest_entry_id
  FROM legacy_revision_entry_keys
  GROUP BY invoice_id, issue_type, logical_key;

  INSERT INTO claims.revision_rounds (
    id, invoice_id, invoice_version_id, round_number,
    admin_sent_at, contractor_response_submitted_at, created_at, updated_at
  )
  SELECT
    r.id,
    r.invoice_id,
    r.reviewed_invoice_version_id,
    row_number() OVER (PARTITION BY r.invoice_id ORDER BY r.created_at, r.id),
    r.sent_at,
    r.responded_at,
    r.created_at,
    r.updated_at
  FROM claims.revision_requests r
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO claims.revision_issues (
    id, invoice_id, issue_type,
    opened_from_invoice_version_rulecheck_id,
    opened_from_invoice_version_located_field_id,
    opened_from_supporting_document_located_field_id,
    opened_from_di_invoice_version_id,
    opened_from_di_field_key,
    status, created_at, updated_at
  )
  SELECT
    g.issue_id,
    g.invoice_id,
    g.issue_type,
    origin.invoice_version_rulecheck_id,
    origin.invoice_version_located_field_id,
    origin.supporting_document_located_field_id,
    CASE WHEN g.issue_type = 'di_field' THEN origin_request.reviewed_invoice_version_id END,
    origin.di_field_key,
    CASE
      WHEN latest.admin_action = 'exception_granted' OR latest.admin_disposition = 'accepted_as_exception'
        THEN 'closed_via_exception'
      WHEN latest.admin_disposition = 'accepted' AND latest.contractor_response_type = 'contractor_attestation'
        THEN 'closed_via_attestation'
      WHEN latest.admin_disposition = 'accepted'
        THEN 'closed_via_corrected_documentation'
      ELSE 'open'
    END,
    origin.created_at,
    GREATEST(origin.updated_at, latest.updated_at)
  FROM legacy_revision_issue_groups g
  JOIN claims.revision_request_entries origin ON origin.id = g.origin_entry_id
  JOIN claims.revision_requests origin_request ON origin_request.id = origin.revision_request_id
  JOIN claims.revision_request_entries latest ON latest.id = g.latest_entry_id
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO claims.revision_issue_comments (
    revision_issue_id, revision_round_id, author_type,
    admin_recommended_remedy, comment_text, created_at, updated_at
  )
  SELECT
    g.issue_id,
    e.revision_request_id,
    'admin',
    CASE
      WHEN e.admin_action = 'request_correction' AND e.entry_type = 'supporting_document_field'
        THEN 'upload_supporting_document'
      WHEN e.admin_action = 'request_correction'
        THEN 'correct_and_reupload_invoice'
      ELSE NULL
    END,
    COALESCE(NULLIF(btrim(e.comment), ''), 'Administrator review recorded.'),
    e.created_at,
    e.updated_at
  FROM claims.revision_request_entries e
  JOIN legacy_revision_entry_keys k ON k.entry_id = e.id
  JOIN legacy_revision_issue_groups g
    ON g.invoice_id = k.invoice_id AND g.issue_type = k.issue_type AND g.logical_key = k.logical_key;

  INSERT INTO claims.revision_issue_comments (
    revision_issue_id, revision_round_id, author_type,
    contractor_response_method, comment_text, contractor_asserted_value,
    created_at, updated_at
  )
  SELECT
    g.issue_id,
    e.revision_request_id,
    'contractor',
    CASE e.contractor_response_type
      WHEN 'corrected_invoice' THEN 'corrected_invoice_uploaded'
      WHEN 'supporting_document' THEN 'supporting_document_uploaded'
      WHEN 'contractor_attestation' THEN 'attestation_provided'
      WHEN 'unable_to_resolve' THEN 'unable_to_resolve'
    END,
    COALESCE(NULLIF(btrim(e.contractor_comment), ''), 'Contractor response recorded.'),
    CASE WHEN e.contractor_response_type = 'contractor_attestation' THEN e.contractor_asserted_value_text END,
    COALESCE(e.contractor_responded_at, e.updated_at),
    COALESCE(e.contractor_responded_at, e.updated_at)
  FROM claims.revision_request_entries e
  JOIN legacy_revision_entry_keys k ON k.entry_id = e.id
  JOIN legacy_revision_issue_groups g
    ON g.invoice_id = k.invoice_id AND g.issue_type = k.issue_type AND g.logical_key = k.logical_key
  WHERE e.contractor_response_type IS NOT NULL;

  INSERT INTO claims.revision_issue_comments (
    revision_issue_id, revision_round_id, author_type,
    comment_text, created_at, updated_at
  )
  SELECT
    g.issue_id,
    e.revision_request_id,
    'admin',
    COALESCE(
      NULLIF(btrim(e.admin_comment), ''),
      CASE e.admin_disposition
        WHEN 'accepted' THEN 'The contractor response was accepted.'
        WHEN 'accepted_as_exception' THEN 'An exception was granted.'
      END
    ),
    COALESCE(e.decided_at, e.updated_at),
    COALESCE(e.decided_at, e.updated_at)
  FROM claims.revision_request_entries e
  JOIN legacy_revision_entry_keys k ON k.entry_id = e.id
  JOIN legacy_revision_issue_groups g
    ON g.invoice_id = k.invoice_id AND g.issue_type = k.issue_type AND g.logical_key = k.logical_key
  WHERE e.admin_disposition IN ('accepted', 'accepted_as_exception');

  DROP TABLE claims.revision_request_entries;
  DROP TABLE claims.revision_requests;
END
$$;

ALTER TABLE claims.code_rules
  ADD COLUMN IF NOT EXISTS admin_workflow_policy text NOT NULL DEFAULT 'fail_only';
ALTER TABLE claims.code_rules
  DROP CONSTRAINT IF EXISTS code_rules_admin_workflow_policy_chk;
ALTER TABLE claims.code_rules
  ADD CONSTRAINT code_rules_admin_workflow_policy_chk
  CHECK (admin_workflow_policy IN ('not_managed', 'fail_only', 'warn_and_fail'));

ALTER TABLE claims.genai_rules
  ADD COLUMN IF NOT EXISTS admin_workflow_policy text NOT NULL DEFAULT 'fail_only';
ALTER TABLE claims.genai_rules
  DROP CONSTRAINT IF EXISTS genai_rules_admin_workflow_policy_chk;
ALTER TABLE claims.genai_rules
  ADD CONSTRAINT genai_rules_admin_workflow_policy_chk
  CHECK (admin_workflow_policy IN ('not_managed', 'fail_only', 'warn_and_fail'));

ALTER TABLE claims.code_rule_history
  ADD COLUMN IF NOT EXISTS admin_workflow_policy text NOT NULL DEFAULT 'fail_only';
ALTER TABLE claims.genai_rule_history
  ADD COLUMN IF NOT EXISTS admin_workflow_policy text NOT NULL DEFAULT 'fail_only';

ALTER TABLE claims.validationgenai_config
  DROP COLUMN IF EXISTS revision_rule_coverage_mode;

COMMIT;
