-- One-time existing-schema patch for Better Homes BC air-to-water /
-- combined heat pump qualifying product-list support.
--
-- Clean rebuilds from 2_create_schema.sql already include this structure.
-- After this patch, also run:
--   3_insert_awhp_sources.sql
--   5_insert_code_rules.sql
--   6_views.sql

BEGIN;

CREATE TABLE IF NOT EXISTS claims.awhp_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT awhp_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_awhp_sources_description
  ON claims.awhp_sources (description);

CREATE TABLE IF NOT EXISTS claims.awhp_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  awhp_source_id uuid NOT NULL,
  storage_provider character varying NULL,
  storage_key text NULL,
  content_type character varying NULL,
  byte_size bigint NULL,
  status text NOT NULL DEFAULT 'queued',

  started_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  completed_at timestamp(6) without time zone NULL,

  records_imported integer NOT NULL DEFAULT 0,
  publishing_notes text NULL,
  publishing_date date NULL,
  file_sha256 text NULL,
  error_text text NULL,
  metadata_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT awhp_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT awhp_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT awhp_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_awhp_import_runs_source
    FOREIGN KEY (awhp_source_id)
    REFERENCES claims.awhp_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_awhp_import_runs_source_started
  ON claims.awhp_import_runs (awhp_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_awhp_import_runs_status
  ON claims.awhp_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_awhp_import_runs_storage_key
  ON claims.awhp_import_runs (storage_key);

CREATE TABLE IF NOT EXISTS claims.awhp_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  brand text NULL,
  brand_normalized text NULL,

  model_number text NOT NULL,
  model_number_normalized text NULL,
  model_number_regex text NULL,
  model_components jsonb NULL,

  system_type text NULL,
  eligibility_notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT awhp_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_awhp_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.awhp_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_awhp_products_import_run
  ON claims.awhp_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_awhp_products_brand_normalized
  ON claims.awhp_products (brand_normalized);

CREATE INDEX IF NOT EXISTS idx_awhp_products_model_number_normalized
  ON claims.awhp_products (model_number_normalized);

CREATE UNIQUE INDEX IF NOT EXISTS idx_awhp_products_source_row_unique
  ON claims.awhp_products (
    import_run_id,
    COALESCE(brand_normalized, ''),
    model_number_normalized,
    COALESCE(system_type, '')
  );

ALTER TABLE claims.invoice_versions
  ADD COLUMN IF NOT EXISTS awhp_product_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_invoice_versions_awhp_product'
      AND conrelid = 'claims.invoice_versions'::regclass
  ) THEN
    ALTER TABLE claims.invoice_versions
      ADD CONSTRAINT fk_invoice_versions_awhp_product
      FOREIGN KEY (awhp_product_id)
      REFERENCES claims.awhp_products(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_invoice_versions_awhp_product
  ON claims.invoice_versions (awhp_product_id);

COMMIT;
