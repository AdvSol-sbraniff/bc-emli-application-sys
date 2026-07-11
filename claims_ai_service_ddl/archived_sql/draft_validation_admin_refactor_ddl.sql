-- ============================================================
-- DRAFT ONLY
-- AI validation normalization / admin refactor DDL
-- Date: 2026-05-26
--
-- PURPOSE:
-- - normalize GenAI rules and GenAI located fields
-- - add a registry for code located fields
-- - keep active/current rows separate from history rows
-- - add config-history support for both code and GenAI
-- - keep claims.validationgenai_rulesets as the bundled runtime
--   snapshot artifact for executed GenAI runs
--
-- IMPORTANT:
-- - This file is a draft and is NOT wired into rebuild order.
-- - This file does NOT remove or replace existing runtime tables.
-- - Active rows are editable; history rows store pre-change snapshots.
-- ============================================================


-- ============================================================
-- ACTIVE TABLES: GenAI rules
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  genai_rule_key text NOT NULL,
  prompt_text text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_rules_pkey PRIMARY KEY (id),
  CONSTRAINT genai_rules_key_uniq UNIQUE (genai_rule_key)
);

CREATE INDEX IF NOT EXISTS idx_genai_rules_enabled
  ON claims.genai_rules (enabled);

CREATE INDEX IF NOT EXISTS idx_genai_rules_updated_at
  ON claims.genai_rules (updated_at DESC);


CREATE TABLE IF NOT EXISTS claims.genai_rule_upgrade_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  genai_rule_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_rule_upgrade_types_pkey PRIMARY KEY (id),

  CONSTRAINT fk_genai_rule_upgrade_types_rule
    FOREIGN KEY (genai_rule_id)
    REFERENCES claims.genai_rules(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_genai_rule_upgrade_types_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT genai_rule_upgrade_types_uniq
    UNIQUE (genai_rule_id, invoice_upgrade_type_id),

  CONSTRAINT genai_rule_upgrade_types_order_uniq
    UNIQUE (genai_rule_id, invoice_upgrade_type_id)
);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_types_rule
  ON claims.genai_rule_upgrade_types (genai_rule_id);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_types_upgrade_type
  ON claims.genai_rule_upgrade_types (invoice_upgrade_type_id);


-- ============================================================
-- ACTIVE TABLES: GenAI located fields
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  genai_field_key text NOT NULL,
  prompt_text text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_located_fields_pkey PRIMARY KEY (id),
  CONSTRAINT genai_located_fields_key_uniq UNIQUE (genai_field_key)
);

CREATE INDEX IF NOT EXISTS idx_genai_located_fields_enabled
  ON claims.genai_located_fields (enabled);

CREATE INDEX IF NOT EXISTS idx_genai_located_fields_updated_at
  ON claims.genai_located_fields (updated_at DESC);


CREATE TABLE IF NOT EXISTS claims.genai_located_field_upgrade_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  genai_field_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL,
  field_number integer NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_located_field_upgrade_types_pkey PRIMARY KEY (id),

  CONSTRAINT fk_genai_located_field_upgrade_types_field
    FOREIGN KEY (genai_field_id)
    REFERENCES claims.genai_located_fields(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_genai_located_field_upgrade_types_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT genai_located_field_upgrade_types_field_number_chk
    CHECK (field_number >= 1),

  CONSTRAINT genai_located_field_upgrade_types_uniq
    UNIQUE (genai_field_id, invoice_upgrade_type_id),

  CONSTRAINT genai_located_field_upgrade_types_order_uniq
    UNIQUE (invoice_upgrade_type_id, field_number)
);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_upgrade_types_field
  ON claims.genai_located_field_upgrade_types (genai_field_id);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_upgrade_types_upgrade_type
  ON claims.genai_located_field_upgrade_types (invoice_upgrade_type_id);


-- ============================================================
-- ACTIVE TABLES: code located fields
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  code_field_key text NOT NULL,
  description text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT code_located_fields_pkey PRIMARY KEY (id),
  CONSTRAINT code_located_fields_key_uniq UNIQUE (code_field_key)
);

CREATE INDEX IF NOT EXISTS idx_code_located_fields_enabled
  ON claims.code_located_fields (enabled);

CREATE INDEX IF NOT EXISTS idx_code_located_fields_updated_at
  ON claims.code_located_fields (updated_at DESC);


-- ============================================================
-- HISTORY TABLES: code rules
-- Pre-change snapshots only.
-- source_id columns intentionally do NOT FK back to active tables.
-- They are audit references, not current-state dependencies.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_rule_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  code_rule_key text NOT NULL,
  description text NOT NULL,
  enabled boolean NOT NULL,

  pass_admin_message text NULL,
  warn_admin_message text NULL,
  fail_admin_message text NULL,
  info_admin_message text NULL,
  admin_notes text NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT code_rule_history_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_code_rule_history_source_id
  ON claims.code_rule_history (source_id);

CREATE INDEX IF NOT EXISTS idx_code_rule_history_key
  ON claims.code_rule_history (code_rule_key);

CREATE INDEX IF NOT EXISTS idx_code_rule_history_created_at
  ON claims.code_rule_history (history_created_at DESC);


CREATE TABLE IF NOT EXISTS claims.code_rule_upgrade_type_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,
  code_rule_id uuid NULL,
  invoice_upgrade_type_id uuid NOT NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT code_rule_upgrade_type_history_pkey PRIMARY KEY (id),

  CONSTRAINT fk_code_rule_upgrade_type_history_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id)
);

CREATE INDEX IF NOT EXISTS idx_code_rule_upgrade_type_history_source_id
  ON claims.code_rule_upgrade_type_history (source_id);

CREATE INDEX IF NOT EXISTS idx_code_rule_upgrade_type_history_rule_id
  ON claims.code_rule_upgrade_type_history (code_rule_id);

CREATE INDEX IF NOT EXISTS idx_code_rule_upgrade_type_history_upgrade_type
  ON claims.code_rule_upgrade_type_history (invoice_upgrade_type_id);


CREATE TABLE IF NOT EXISTS claims.code_located_field_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  code_field_key text NOT NULL,
  description text NOT NULL,
  enabled boolean NOT NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT code_located_field_history_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_code_located_field_history_source_id
  ON claims.code_located_field_history (source_id);

CREATE INDEX IF NOT EXISTS idx_code_located_field_history_key
  ON claims.code_located_field_history (code_field_key);

CREATE INDEX IF NOT EXISTS idx_code_located_field_history_created_at
  ON claims.code_located_field_history (history_created_at DESC);


-- ============================================================
-- HISTORY TABLES: GenAI rules
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_rule_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  genai_rule_key text NOT NULL,
  prompt_text text NOT NULL,
  enabled boolean NOT NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_rule_history_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_genai_rule_history_source_id
  ON claims.genai_rule_history (source_id);

CREATE INDEX IF NOT EXISTS idx_genai_rule_history_key
  ON claims.genai_rule_history (genai_rule_key);

CREATE INDEX IF NOT EXISTS idx_genai_rule_history_created_at
  ON claims.genai_rule_history (history_created_at DESC);


CREATE TABLE IF NOT EXISTS claims.genai_rule_upgrade_type_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,
  genai_rule_id uuid NULL,
  invoice_upgrade_type_id uuid NOT NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_rule_upgrade_type_history_pkey PRIMARY KEY (id),
  CONSTRAINT fk_genai_rule_upgrade_type_history_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id)
);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_type_history_source_id
  ON claims.genai_rule_upgrade_type_history (source_id);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_type_history_rule_id
  ON claims.genai_rule_upgrade_type_history (genai_rule_id);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_type_history_upgrade_type
  ON claims.genai_rule_upgrade_type_history (invoice_upgrade_type_id);


-- ============================================================
-- HISTORY TABLES: GenAI located fields
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_located_field_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  genai_field_key text NOT NULL,
  prompt_text text NOT NULL,
  enabled boolean NOT NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_located_field_history_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_history_source_id
  ON claims.genai_located_field_history (source_id);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_history_key
  ON claims.genai_located_field_history (genai_field_key);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_history_created_at
  ON claims.genai_located_field_history (history_created_at DESC);


CREATE TABLE IF NOT EXISTS claims.genai_located_field_upgrade_type_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,
  genai_field_id uuid NULL,
  invoice_upgrade_type_id uuid NOT NULL,
  field_number integer NOT NULL,

  source_created_at timestamp(6) without time zone NULL,
  source_updated_at timestamp(6) without time zone NULL,

  history_created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_located_field_upgrade_type_history_pkey PRIMARY KEY (id),
  CONSTRAINT genai_located_field_upgrade_type_history_field_number_chk
    CHECK (field_number >= 1),

  CONSTRAINT fk_genai_located_field_upgrade_type_history_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id)
);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_upgrade_type_history_source_id
  ON claims.genai_located_field_upgrade_type_history (source_id);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_upgrade_type_history_field_id
  ON claims.genai_located_field_upgrade_type_history (genai_field_id);

CREATE INDEX IF NOT EXISTS idx_genai_located_field_upgrade_type_history_upgrade_type
  ON claims.genai_located_field_upgrade_type_history (invoice_upgrade_type_id);


-- ============================================================
-- NOTE
-- claims.validationgenai_rulesets remains the published bundled
-- runtime artifact for executed GenAI runs and run-audit reproducibility.
-- ============================================================
