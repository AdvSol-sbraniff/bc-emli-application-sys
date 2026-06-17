-- Existing-database patch for NRCan Oil to Heat Pump Affordability
-- BC qualified product-list support.
--
-- Clean rebuilds already include these objects in:
--   2_create_schema.sql
--   3_insert_ohpa_sources.sql
--   6_views.sql

BEGIN;

CREATE TABLE IF NOT EXISTS claims.ohpa_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  description text NOT NULL,
  source_url text NOT NULL,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  CONSTRAINT ohpa_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_ohpa_sources_description
  ON claims.ohpa_sources (description);

CREATE TABLE IF NOT EXISTS claims.ohpa_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  ohpa_source_id uuid NOT NULL,
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
  CONSTRAINT ohpa_import_runs_pkey PRIMARY KEY (id),
  CONSTRAINT ohpa_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),
  CONSTRAINT ohpa_import_runs_records_imported_chk
    CHECK (records_imported >= 0),
  CONSTRAINT fk_ohpa_import_runs_source
    FOREIGN KEY (ohpa_source_id)
    REFERENCES claims.ohpa_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_ohpa_import_runs_source_started
  ON claims.ohpa_import_runs (ohpa_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_ohpa_import_runs_status
  ON claims.ohpa_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_ohpa_import_runs_storage_key
  ON claims.ohpa_import_runs (storage_key);

CREATE TABLE IF NOT EXISTS claims.ohpa_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  import_run_id uuid NOT NULL,
  ahri_reference_number text NOT NULL,
  brand text NULL,
  brand_normalized text NULL,
  model_number text NULL,
  model_number_normalized text NULL,
  model_number_regex text NULL,
  model_components jsonb NULL,
  indoor_model_numbers text NULL,
  furnace_model_number text NULL,
  product_group text NULL,
  ahri_type text NULL,
  ducting_configuration text NULL,
  model_status text NULL,
  series_name text NULL,
  rated_capacity_47f numeric NULL,
  rated_capacity_95f numeric NULL,
  capacity_maintenance_percent numeric NULL,
  cop_5f numeric NULL,
  hspf2_region_iv numeric NULL,
  hspf2_region_v numeric NULL,
  seer2 numeric NULL,
  eligibility_notes text NULL,
  raw_row_json jsonb NULL,
  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  CONSTRAINT ohpa_products_pkey PRIMARY KEY (id),
  CONSTRAINT fk_ohpa_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.ohpa_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_ohpa_products_import_run
  ON claims.ohpa_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_ohpa_products_ahri
  ON claims.ohpa_products (ahri_reference_number);

CREATE INDEX IF NOT EXISTS idx_ohpa_products_brand_normalized
  ON claims.ohpa_products (brand_normalized);

CREATE INDEX IF NOT EXISTS idx_ohpa_products_model_number_normalized
  ON claims.ohpa_products (model_number_normalized);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ohpa_products_source_row_unique
  ON claims.ohpa_products (
    import_run_id,
    ahri_reference_number,
    COALESCE(brand_normalized, ''),
    COALESCE(model_number_normalized, ''),
    COALESCE(indoor_model_numbers, ''),
    COALESCE(furnace_model_number, '')
  );

ALTER TABLE claims.invoice_versions
  ADD COLUMN IF NOT EXISTS ohpa_product_id uuid NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'fk_invoice_versions_ohpa_product'
  ) THEN
    ALTER TABLE claims.invoice_versions
      ADD CONSTRAINT fk_invoice_versions_ohpa_product
      FOREIGN KEY (ohpa_product_id)
      REFERENCES claims.ohpa_products(id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_invoice_versions_ohpa_product
  ON claims.invoice_versions (ohpa_product_id);

CREATE OR REPLACE VIEW claims.v_current_ohpa_products AS
SELECT
  p.*,
  src.id AS ohpa_source_id,
  src.source_url,
  src.description AS source_description,
  run.publishing_notes,
  run.publishing_date,
  run.storage_provider AS source_storage_provider,
  run.storage_key AS source_storage_key,
  run.content_type AS source_content_type,
  run.byte_size AS source_byte_size,
  run.file_sha256 AS source_file_sha256,
  run.completed_at AS source_import_completed_at,
  run.records_imported AS source_records_imported
FROM claims.ohpa_products p
JOIN claims.ohpa_import_runs run
  ON run.id = p.import_run_id
JOIN claims.ohpa_sources src
  ON src.id = run.ohpa_source_id
JOIN (
  SELECT DISTINCT ON (ohpa_source_id)
    id,
    ohpa_source_id
  FROM claims.ohpa_import_runs
  WHERE status = 'succeeded'
  ORDER BY ohpa_source_id, completed_at DESC NULLS LAST, started_at DESC, id DESC
) latest
  ON latest.id = run.id;

COMMIT;
