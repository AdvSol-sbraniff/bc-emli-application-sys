DROP SCHEMA IF EXISTS claims CASCADE;
CREATE SCHEMA claims;


--
-- sessions
--

CREATE TABLE IF NOT EXISTS claims.sessions (
  id            uuid NOT NULL DEFAULT gen_random_uuid(),

  created_at    timestamp(6) without time zone NOT NULL,
  updated_at    timestamp(6) without time zone NOT NULL,

  CONSTRAINT sessions_pkey PRIMARY KEY (id)
);



  --
  -- invoices
  --

CREATE TABLE IF NOT EXISTS claims.invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  reference_number bigint GENERATED ALWAYS AS IDENTITY,
  session_id     uuid NOT NULL,
  contractor_id  uuid NOT NULL,
  submitter_id   uuid NULL,

  system_help_notes text NULL,

  status character varying NOT NULL DEFAULT 'upload_queued',
  status_subtype character varying NULL,
  status_updated_at timestamp(6) without time zone NULL,
  submitted_at timestamp(6) without time zone NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT invoices_pkey PRIMARY KEY (id),
  CONSTRAINT invoices_reference_number_key UNIQUE (reference_number),

CONSTRAINT invoices_status_chk
CHECK (status IN (
  'upload_queued',    -- not used as currently not using sidekiq for uploads but leaving incase we decide its too laggy and needs to be sidekiqed out
  'upload_in_progress',
  'upload_failed',
  'upload_complete',
  'ocr_queued',
  'ocr_in_progress',
  'ocr_failed',
  'ocr_complete',
  'genai_queued',
  'genai_in_progress',
  'genai_failed',
  'genai_complete',         -- AI processing complete; contractor-owned draft until explicit submit.
  'package_needs_correction',
  'technical_failure',
  'admin_review_inbox',    -- contractor submitted; waiting for admin review / screen-in.
  'contractor_revision_inbox', -- admin requested contractor revisions before business review resumes.
  'in_review',
  'approved_pending',
  'approved_paid',
  'ineligible',
  'contractor_withdrawn'   -- contractor voluntarily withdrew the invoice before approval.
)),

  CONSTRAINT fk_claims_invoices_session
    FOREIGN KEY (session_id) REFERENCES claims.sessions(id),

  CONSTRAINT fk_claims_invoices_contractor
    FOREIGN KEY (contractor_id) REFERENCES public.contractors(id),

  CONSTRAINT fk_claims_invoices_submitter
    FOREIGN KEY (submitter_id) REFERENCES public.users(id)

);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_status
  ON claims.invoices (status);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_status_subtype
  ON claims.invoices (status_subtype);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_submitted_at
  ON claims.invoices (submitted_at);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_session_id
  ON claims.invoices (session_id);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_contractor_id
  ON claims.invoices (contractor_id);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_submitter_id
  ON claims.invoices (submitter_id);


-- ============================================================
-- invoice_status_subtypes
-- PURPOSE: Friendly/admin-safe copy for technical failure subtypes
-- and package correction subtypes used by contractor-facing screens.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.invoice_status_subtypes (
  status text NOT NULL,
  status_subtype text NOT NULL,
  admin_label text NOT NULL,
  contractor_message text NOT NULL,
  retry_guidance text NULL,
  active boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_status_subtypes_pkey
    PRIMARY KEY (status, status_subtype),

  CONSTRAINT invoice_status_subtypes_status_chk
    CHECK (status IN ('package_needs_correction', 'technical_failure'))
);

CREATE INDEX IF NOT EXISTS idx_invoice_status_subtypes_active
  ON claims.invoice_status_subtypes (status, active);



-- ============================================================
-- ahri_sources
-- PURPOSE: Stable catalogue of BC Hydro / qualified heat-pump
-- product-list source definitions. Import runs are child/history
-- records under these source rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ahri_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT ahri_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_ahri_sources_description
  ON claims.ahri_sources (description);



-- ============================================================
-- ahri_import_runs
-- PURPOSE: Track refresh attempts for external reference data used by
-- code-owned rules, such as BC Hydro heat pump product-list validation.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ahri_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  ahri_source_id uuid NOT NULL,
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

  CONSTRAINT ahri_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT ahri_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT ahri_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_ahri_import_runs_source
    FOREIGN KEY (ahri_source_id)
    REFERENCES claims.ahri_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_ahri_import_runs_source_started
  ON claims.ahri_import_runs (ahri_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_ahri_import_runs_status
  ON claims.ahri_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_ahri_import_runs_storage_key
  ON claims.ahri_import_runs (storage_key);



-- ============================================================
-- ahri_products
-- PURPOSE: Cached BC Hydro / qualified heat pump product-list rows
-- used by code-owned AHRI and heat-pump performance rule checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ahri_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  ahri_reference_number text NOT NULL,
  heat_pump_type text NULL,
  make text NULL,
  outdoor_model text NULL,
  indoor_model_or_air_handler text NULL,
  furnace_model text NULL,

  rated_capacity_btu_at_minus_5c numeric NULL,
  seer numeric NULL,
  seer2 numeric NULL,
  hspf numeric NULL,
  hspf2 numeric NULL,
  cop numeric NULL,
  capacity_maintenance_percent numeric NULL,
  cold_climate_rated boolean NULL,

  eligibility_notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT ahri_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ahri_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.ahri_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_ahri_products_ahri
  ON claims.ahri_products (ahri_reference_number);

CREATE INDEX IF NOT EXISTS idx_ahri_products_import_run
  ON claims.ahri_products (import_run_id);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ahri_products_source_row_unique
  ON claims.ahri_products (
    import_run_id,
    ahri_reference_number,
    heat_pump_type,
    make,
    outdoor_model,
    indoor_model_or_air_handler,
    COALESCE(furnace_model, '')
  );



-- ============================================================
-- neea_sources
-- PURPOSE: Stable catalogue of NEEA product-list source definitions.
-- Import runs are child/history records under these source rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.neea_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT neea_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_neea_sources_description
  ON claims.neea_sources (description);



-- ============================================================
-- neea_import_runs
-- PURPOSE: Track refresh attempts for NEEA product-list PDFs used
-- by code-owned heat pump water heater checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.neea_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  neea_source_id uuid NOT NULL,
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

  CONSTRAINT neea_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT neea_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT neea_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_neea_import_runs_source
    FOREIGN KEY (neea_source_id)
    REFERENCES claims.neea_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_neea_import_runs_source_started
  ON claims.neea_import_runs (neea_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_neea_import_runs_status
  ON claims.neea_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_neea_import_runs_storage_key
  ON claims.neea_import_runs (storage_key);



-- ============================================================
-- neea_products
-- PURPOSE: Cached NEEA HPWH qualified product-list rows used by
-- code-owned heat pump water heater product-list and tier checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.neea_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  brand text NULL,
  brand_normalized text NULL,

  model_number text NOT NULL,
  model_number_normalized text NULL,
  model_number_regex text NULL,
  model_components jsonb NULL,

  storage_volume_gallons numeric NULL,

  indoor_tier integer NULL,
  indoor_cce numeric NULL,

  outdoor_tier integer NULL,
  outdoor_scop numeric NULL,

  configuration text NULL,

  flex_load_connectivity text NULL,
  plug_in_endorsement boolean NULL,

  qualified_date date NULL,
  specification_version text NULL,

  eligibility_notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT neea_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_neea_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.neea_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_neea_products_import_run
  ON claims.neea_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_neea_products_brand_normalized
  ON claims.neea_products (brand_normalized);

CREATE INDEX IF NOT EXISTS idx_neea_products_model_number_normalized
  ON claims.neea_products (model_number_normalized);

CREATE INDEX IF NOT EXISTS idx_neea_products_tiers
  ON claims.neea_products (indoor_tier, outdoor_tier);

CREATE UNIQUE INDEX IF NOT EXISTS idx_neea_products_source_row_unique
  ON claims.neea_products (
    import_run_id,
    COALESCE(brand_normalized, ''),
    model_number_normalized,
    COALESCE(configuration, ''),
    COALESCE(storage_volume_gallons, -1),
    COALESCE(qualified_date, DATE '1900-01-01'),
    COALESCE(specification_version, '')
  );



-- ============================================================
-- awhp_sources
-- PURPOSE: Stable catalogue of Better Homes BC air-to-water /
-- combined heat pump product-list source definitions. Import runs
-- are child/history records under these source rows.
-- ============================================================

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



-- ============================================================
-- awhp_import_runs
-- PURPOSE: Track refresh attempts for Better Homes BC air-to-water /
-- combined heat pump product-list PDFs used by code-owned checks.
-- ============================================================

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



-- ============================================================
-- awhp_products
-- PURPOSE: Cached Better Homes BC air-to-water / combined heat pump
-- qualifying-product-list rows used by code-owned hydronic heat
-- pump product-list checks.
-- ============================================================

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



-- ============================================================
-- ohpa_sources
-- PURPOSE: Stable catalogue of NRCan Oil to Heat Pump
-- Affordability product-list source definitions. Import runs are
-- child/history records under these source rows.
-- ============================================================

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



-- ============================================================
-- ohpa_import_runs
-- PURPOSE: Track refresh attempts for NRCan Oil to Heat Pump
-- Affordability CSV data used by code-owned oil heat-pump checks.
-- ============================================================

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



-- ============================================================
-- ohpa_products
-- PURPOSE: Cached NRCan Oil to Heat Pump Affordability BC
-- qualified-product-list rows used by code-owned oil heat-pump
-- product-list checks.
-- ============================================================

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


-- ============================================================
-- herv_sources
-- PURPOSE: Stable catalogue of NRCan ENERGY STAR heat/energy
-- recovery ventilator product-list source definitions. Import
-- runs are child/history records under these source rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.herv_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT herv_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_herv_sources_description
  ON claims.herv_sources (description);



-- ============================================================
-- herv_import_runs
-- PURPOSE: Track refresh attempts for NRCan ENERGY STAR heat/
-- energy recovery ventilator CSV data used by code-owned
-- ventilation checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.herv_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  herv_source_id uuid NOT NULL,
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

  CONSTRAINT herv_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT herv_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT herv_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_herv_import_runs_source
    FOREIGN KEY (herv_source_id)
    REFERENCES claims.herv_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_herv_import_runs_source_started
  ON claims.herv_import_runs (herv_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_herv_import_runs_status
  ON claims.herv_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_herv_import_runs_storage_key
  ON claims.herv_import_runs (storage_key);



-- ============================================================
-- herv_products
-- PURPOSE: Cached NRCan ENERGY STAR heat/energy recovery
-- ventilator product-list rows used by code-owned ventilation
-- HRV/ERV product-list checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.herv_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  brand text NULL,
  brand_normalized text NULL,
  model_number text NOT NULL,
  model_number_normalized text NULL,
  model_number_regex text NULL,
  model_type text NULL,

  sensible_heat_recovery_efficiency_sre_at_0c numeric NULL,
  sensible_heat_recovery_efficiency_sre_at_minus_25c numeric NULL,
  associated_net_supply_airflow_at_0c_cfm numeric NULL,
  associated_net_supply_airflow_at_minus_25c_cfm numeric NULL,
  associated_power_consumption_at_0c_w numeric NULL,
  associated_power_consumption_at_minus_25c_w numeric NULL,
  associated_net_supply_airflow_at_0c_ls numeric NULL,
  associated_net_supply_airflow_at_minus_25c_ls numeric NULL,
  marked_for_outdoor_use_at_minus_10c_or_higher boolean NULL,
  max_rated_airflow_at_0c_cfm numeric NULL,
  max_rated_airflow_at_0c_ls numeric NULL,
  power_consumption_at_0c_w numeric NULL,

  eligibility_notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT herv_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_herv_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.herv_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_herv_products_import_run
  ON claims.herv_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_herv_products_brand_normalized
  ON claims.herv_products (brand_normalized);

CREATE INDEX IF NOT EXISTS idx_herv_products_model_number_normalized
  ON claims.herv_products (model_number_normalized);

CREATE UNIQUE INDEX IF NOT EXISTS idx_herv_products_source_row_unique
  ON claims.herv_products (
    import_run_id,
    COALESCE(brand_normalized, ''),
    model_number_normalized,
    COALESCE(model_type, ''),
    COALESCE(sensible_heat_recovery_efficiency_sre_at_0c, -1),
    COALESCE(associated_net_supply_airflow_at_0c_cfm, -1),
    COALESCE(power_consumption_at_0c_w, -1)
  );



-- ============================================================
-- vent_fan_sources
-- PURPOSE: Stable catalogue of ENERGY STAR certified
-- ventilating-fan product-list source definitions. Import runs
-- are child/history records under these source rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.vent_fan_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT vent_fan_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_vent_fan_sources_description
  ON claims.vent_fan_sources (description);



-- ============================================================
-- vent_fan_import_runs
-- PURPOSE: Track refresh attempts for ENERGY STAR certified
-- ventilating-fan CSV data used by code-owned ventilation checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.vent_fan_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  vent_fan_source_id uuid NOT NULL,
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

  CONSTRAINT vent_fan_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT vent_fan_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT vent_fan_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_vent_fan_import_runs_source
    FOREIGN KEY (vent_fan_source_id)
    REFERENCES claims.vent_fan_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_vent_fan_import_runs_source_started
  ON claims.vent_fan_import_runs (vent_fan_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_vent_fan_import_runs_status
  ON claims.vent_fan_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_vent_fan_import_runs_storage_key
  ON claims.vent_fan_import_runs (storage_key);



-- ============================================================
-- vent_fan_products
-- PURPOSE: Cached ENERGY STAR certified ventilating-fan
-- product-list rows used by code-owned ventilation fan checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.vent_fan_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  energy_star_unique_id text NULL,
  energy_star_partner text NULL,
  brand text NOT NULL,
  brand_normalized text NOT NULL,
  product_model_name text NULL,
  model_number text NOT NULL,
  model_number_normalized text NOT NULL,
  model_number_regex text NULL,
  additional_model_information text NULL,
  upc text NULL,

  fan_type text NULL,
  merv_of_in_line_fan_filter text NULL,
  number_of_speeds text NULL,
  duct_size text NULL,
  sound_level_sones numeric NULL,
  bathroom_utility_sound_level_sones_at_0_25_in_wg numeric NULL,
  bathroom_utility_airflow_at_0_25_in_wg numeric NULL,

  lighting text NULL,
  shipped_with_energy_star_lamps text NULL,
  energy_star_lamp_esuid text NULL,
  alternate_energy_star_lamps_esuids text NULL,
  energy_star_lamp_partner text NULL,
  lamp_model_number text NULL,
  lighting_technology text NULL,
  total_light_output_lumens numeric NULL,
  total_input_power_watts numeric NULL,
  luminaire_efficacy numeric NULL,
  power_factor numeric NULL,
  cct_kelvin integer NULL,
  cri integer NULL,
  light_source_life_hours integer NULL,
  special_features text NULL,

  airflow_1_cfm numeric NULL,
  airflow_2_cfm numeric NULL,
  airflow_3_cfm numeric NULL,
  efficacy_1_cfm_watt numeric NULL,
  efficacy_2_cfm_watt numeric NULL,
  efficacy_3_cfm_watt numeric NULL,
  ventilating_fan_features text NULL,

  date_available_on_market date NULL,
  date_qualified date NULL,
  markets text NULL,
  cb_model_identifier text NULL,
  meets_most_efficient_criteria text NULL,
  notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT vent_fan_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_vent_fan_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.vent_fan_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_import_run
  ON claims.vent_fan_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_brand_model_norm
  ON claims.vent_fan_products (brand_normalized, model_number_normalized);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_model_norm
  ON claims.vent_fan_products (model_number_normalized);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_energy_star_unique_id
  ON claims.vent_fan_products (energy_star_unique_id);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_cb_model_identifier
  ON claims.vent_fan_products (cb_model_identifier);

CREATE UNIQUE INDEX IF NOT EXISTS idx_vent_fan_products_source_row_unique
  ON claims.vent_fan_products (
    import_run_id,
    COALESCE(energy_star_unique_id, ''),
    brand_normalized,
    model_number_normalized,
    COALESCE(cb_model_identifier, '')
  );


-- 
-- users_eligibilitycodes
-- how we get the participant_id
--
CREATE TABLE IF NOT EXISTS claims.users_eligibilitycodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL,

  eligibility_code character varying NOT NULL,
  income_level integer NOT NULL,

  applied_at timestamp(6) without time zone NOT NULL,
  approved_at timestamp(6) without time zone NOT NULL,
  expires_at timestamp(6) without time zone NOT NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT users_eligibilitycodes_pkey PRIMARY KEY (id),

  CONSTRAINT fk_users_eligibilitycodes_user
    FOREIGN KEY (user_id) REFERENCES public.users(id),

  -- code must be globally unique
  CONSTRAINT users_eligibilitycodes_code_uniq
    UNIQUE (eligibility_code),

  -- a user shouldn't have duplicate code records (defensive)
  CONSTRAINT users_eligibilitycodes_user_code_uniq
    UNIQUE (user_id, eligibility_code),

  CONSTRAINT users_eligibilitycodes_dates_chk
    CHECK (expires_at > applied_at),

  CONSTRAINT users_eligibilitycodes_income_level_chk
    CHECK (income_level IN (1, 2, 3)),

  CONSTRAINT users_eligibilitycodes_income_level_code_chk
    CHECK (
      (
        (
          upper(trim(eligibility_code)) LIKE 'ESP1%'
          OR upper(trim(eligibility_code)) LIKE 'ESPI%'
        )
        AND income_level = 1
      )
      OR (
        upper(trim(eligibility_code)) LIKE 'ESP2%'
        AND income_level = 2
      )
      OR (
        upper(trim(eligibility_code)) LIKE 'ESP3%'
        AND income_level = 3
      )
    )
);

CREATE INDEX IF NOT EXISTS index_claims_users_eligibilitycodes_on_user_id
  ON claims.users_eligibilitycodes (user_id);

CREATE INDEX IF NOT EXISTS index_claims_users_eligibilitycodes_on_expires_at
  ON claims.users_eligibilitycodes (expires_at);

CREATE INDEX IF NOT EXISTS index_claims_users_eligibilitycodes_on_income_level
  ON claims.users_eligibilitycodes (income_level);



  -- 
  -- invoice_versions
  --

CREATE TABLE IF NOT EXISTS claims.invoice_versions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_id        uuid NOT NULL,
  invoice_versionno integer NOT NULL,

  -- PDF storage pointer(s) (same pattern as supporting_documents)
  storage_provider  character varying NULL,  -- e.g., 'azure_blob'
  storage_key       text NOT NULL,           -- blob path / object key (canonical locator)
  original_filename character varying NULL,
  content_type      character varying NULL,  -- e.g., 'application/pdf'
  byte_size         bigint NULL,
  sha256            character varying NULL,

  -- from the genai
  genai_raw_json jsonb NULL,
  genai_overall_confidence  smallint NOT NULL DEFAULT 0,
  genai_result text NULL,

  -- any parent level genai outputs such as overall conf and overall pass flags
  -- TBD

  -- from the DI (retention indefinite for now)
  di_raw_json jsonb NULL,
  di_page_map jsonb NULL,

  -- the first class di fields stright from the firstclass section
  di_ocr_invoice_id     character varying NULL,  -- paper invoice number (NOT DB invoice id)
  di_ocr_invoice_id_page integer NULL,
  di_ocr_invoice_id_polygon jsonb NULL,
  di_ocr_invoice_date   date NULL,
  di_ocr_invoice_date_page integer NULL,
  di_ocr_invoice_date_polygon jsonb NULL,
  di_ocr_vendor_name    character varying NULL,
  di_ocr_vendor_name_page integer NULL,
  di_ocr_vendor_name_polygon jsonb NULL,
  di_ocr_vendor_address    character varying NULL,
  di_ocr_vendor_address_page integer NULL,
  di_ocr_vendor_address_polygon jsonb NULL,
  di_ocr_customer_name  character varying NULL,
  di_ocr_customer_name_page integer NULL,
  di_ocr_customer_name_polygon jsonb NULL,
  di_ocr_customer_address  character varying NULL,
  di_ocr_customer_address_page integer NULL,
  di_ocr_customer_address_polygon jsonb NULL,
  di_ocr_customer_address_recipient  character varying NULL,
  di_ocr_customer_address_recipient_page integer NULL,
  di_ocr_customer_address_recipient_polygon jsonb NULL,
  di_ocr_service_address  character varying NULL,
  di_ocr_service_address_page integer NULL,
  di_ocr_service_address_polygon jsonb NULL,
  di_ocr_service_address_recipient  character varying NULL,
  di_ocr_service_address_recipient_page integer NULL,
  di_ocr_service_address_recipient_polygon jsonb NULL,
  di_ocr_billing_address  character varying NULL,
  di_ocr_billing_address_page integer NULL,
  di_ocr_billing_address_polygon jsonb NULL,
  di_ocr_billing_address_recipient  character varying NULL,
  di_ocr_billing_address_recipient_page integer NULL,
  di_ocr_billing_address_recipient_polygon jsonb NULL,
  di_ocr_sub_total      numeric(12,2) NULL,
  di_ocr_sub_total_page integer NULL,
  di_ocr_sub_total_polygon jsonb NULL,
  di_ocr_total_tax      numeric(12,2) NULL,
  di_ocr_total_tax_page integer NULL,
  di_ocr_total_tax_polygon jsonb NULL,
  di_ocr_invoice_total  numeric(12,2) NULL,
  di_ocr_invoice_total_page integer NULL,
  di_ocr_invoice_total_polygon jsonb NULL,
  di_ocr_amount_due     numeric(12,2) NULL,
  di_ocr_amount_due_page integer NULL,
  di_ocr_amount_due_polygon jsonb NULL,

  -- code-owned point-in-time AHRI / BC Hydro heat-pump product-list match
  ahri_product_id uuid NULL,
  -- code-owned point-in-time NEEA HPWH qualified product-list match
  neea_product_id uuid NULL,
  -- code-owned point-in-time Better Homes BC AWHP qualifying-list match
  awhp_product_id uuid NULL,
  -- code-owned point-in-time NRCan OHPA BC product-list match
    ohpa_product_id uuid NULL,
    -- code-owned point-in-time NRCan ENERGY STAR HERV product-list match
    herv_product_id uuid NULL,
    -- code-owned point-in-time ENERGY STAR ventilating-fan product-list match
    vent_fan_product_id uuid NULL,
    -- code-owned point-in-time eligibility-code / participant match
    users_eligibilitycode_id uuid NULL,
    participant_user_id uuid NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT invoice_versions_pkey PRIMARY KEY (id),

  CONSTRAINT fk_claims_versions_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id),

  CONSTRAINT fk_invoice_versions_ahri_product
    FOREIGN KEY (ahri_product_id)
    REFERENCES claims.ahri_products(id),

  CONSTRAINT fk_invoice_versions_neea_product
    FOREIGN KEY (neea_product_id)
    REFERENCES claims.neea_products(id),

  CONSTRAINT fk_invoice_versions_awhp_product
    FOREIGN KEY (awhp_product_id)
    REFERENCES claims.awhp_products(id),

  CONSTRAINT fk_invoice_versions_ohpa_product
    FOREIGN KEY (ohpa_product_id)
    REFERENCES claims.ohpa_products(id),

    CONSTRAINT fk_invoice_versions_herv_product
      FOREIGN KEY (herv_product_id)
      REFERENCES claims.herv_products(id),

    CONSTRAINT fk_invoice_versions_vent_fan_product
      FOREIGN KEY (vent_fan_product_id)
      REFERENCES claims.vent_fan_products(id),

    CONSTRAINT fk_invoice_versions_users_eligibilitycode
      FOREIGN KEY (users_eligibilitycode_id)
      REFERENCES claims.users_eligibilitycodes(id),

  CONSTRAINT fk_invoice_versions_participant_user
    FOREIGN KEY (participant_user_id)
    REFERENCES public.users(id),

  CONSTRAINT invoice_versions_invoice_id_versionno_uniq
    UNIQUE (invoice_id, invoice_versionno),

  CONSTRAINT invoice_versions_versionno_chk
    CHECK (invoice_versionno >= 1),

  CONSTRAINT invoice_versions_genai_result_chk
    CHECK (genai_result IS NULL OR genai_result IN ('pass','info','warn','fail'))
);

-- Common access paths
CREATE INDEX IF NOT EXISTS index_invoice_versions_on_invoice_id
  ON claims.invoice_versions (invoice_id);

-- Helps "get max version for invoice"
CREATE INDEX IF NOT EXISTS index_invoice_versions_on_invoice_id_and_versionno_desc
  ON claims.invoice_versions (invoice_id, invoice_versionno DESC);

-- Useful for blob lookup / integrity checks
CREATE INDEX IF NOT EXISTS index_invoice_versions_on_storage_key
  ON claims.invoice_versions (storage_key);

-- Enables composite FKs so other tables can prove "this version belongs to this invoice"
CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_versions_id_invoice_id
  ON claims.invoice_versions (id, invoice_id);

CREATE INDEX IF NOT EXISTS idx_invoice_versions_ahri_product
  ON claims.invoice_versions (ahri_product_id);

CREATE INDEX IF NOT EXISTS idx_invoice_versions_neea_product
  ON claims.invoice_versions (neea_product_id);

CREATE INDEX IF NOT EXISTS idx_invoice_versions_awhp_product
  ON claims.invoice_versions (awhp_product_id);

CREATE INDEX IF NOT EXISTS idx_invoice_versions_ohpa_product
  ON claims.invoice_versions (ohpa_product_id);

  CREATE INDEX IF NOT EXISTS idx_invoice_versions_herv_product
    ON claims.invoice_versions (herv_product_id);

  CREATE INDEX IF NOT EXISTS idx_invoice_versions_vent_fan_product
    ON claims.invoice_versions (vent_fan_product_id);

CREATE INDEX IF NOT EXISTS index_invoice_versions_on_users_eligibilitycode_id
  ON claims.invoice_versions (users_eligibilitycode_id);

CREATE INDEX IF NOT EXISTS index_invoice_versions_on_participant_user_id
  ON claims.invoice_versions (participant_user_id);


-- ============================================================
-- invoice_status_transitions
-- PURPOSE: Append-only history of every real invoice workflow
-- status/subtype change, including initial and repeat submissions.
-- ============================================================

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
    FOREIGN KEY (invoice_id)
    REFERENCES claims.invoices(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_invoice_status_transitions_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE SET NULL,

  CONSTRAINT fk_invoice_status_transitions_actor
    FOREIGN KEY (actor_user_id)
    REFERENCES public.users(id)
    ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_invoice_status_transitions_invoice
  ON claims.invoice_status_transitions (invoice_id, created_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_invoice_status_transitions_version
  ON claims.invoice_status_transitions (invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_invoice_status_transitions_to_status
  ON claims.invoice_status_transitions (to_status, created_at DESC);


--
-- invoice_upgrade_types
-- Catalogue of AI invoice upgrade domains.
--
CREATE TABLE IF NOT EXISTS claims.invoice_upgrade_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  upgrade_type_key character varying NOT NULL, -- e.g. common, windows_doors, air_source_heat_pump_oil
  description character varying(100) NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT invoice_upgrade_types_pkey PRIMARY KEY (id),

  CONSTRAINT invoice_upgrade_types_key_uniq
    UNIQUE (upgrade_type_key)
);



-- ============================================================
-- code_rules
-- PURPOSE: Admin-visible registry for code-owned validation rules.
-- The actual rule logic remains in source code; this table stores the
-- current admin overlay such as enabled/disabled state and optional
-- human-facing guidance messages.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  code_rule_key text NOT NULL,
  contractor_display_name text NOT NULL,
  description text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  pass_admin_message text NULL,
  warn_admin_message text NULL,
  fail_admin_message text NULL,
  info_admin_message text NULL,
  admin_notes text NULL,
  source_quote text NOT NULL,
  contractor_action text NULL,
  contractor_visibility text NOT NULL DEFAULT 'fail_only',
  contractor_blocking_policy text NOT NULL DEFAULT 'non_blocking',
  admin_workflow_policy text NOT NULL DEFAULT 'fail_only',

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT code_rules_pkey PRIMARY KEY (id),
  CONSTRAINT code_rules_key_uniq UNIQUE (code_rule_key),
  CONSTRAINT code_rules_source_quote_present_chk
    CHECK (btrim(source_quote) <> ''),
  CONSTRAINT code_rules_contractor_visibility_chk
    CHECK (contractor_visibility IN ('hidden','fail_only','warn_and_fail')),
  CONSTRAINT code_rules_contractor_blocking_policy_chk
    CHECK (contractor_blocking_policy IN ('non_blocking','block_on_fail')),
  CONSTRAINT code_rules_admin_workflow_policy_chk
    CHECK (admin_workflow_policy IN ('not_managed','fail_only','warn_and_fail','all_results')),
  CONSTRAINT code_rules_visible_blocker_chk
    CHECK (contractor_blocking_policy <> 'block_on_fail' OR contractor_visibility <> 'hidden')
);

CREATE INDEX IF NOT EXISTS idx_code_rules_enabled
  ON claims.code_rules (enabled);



-- ============================================================
-- code_rule_upgrade_types
-- PURPOSE: Declares which invoice upgrade types each code-owned rule
-- applies to. This lets the admin registry show multiple upgrade-type
-- icons per code rule and lets runtime check applicability without
-- scattering upgrade-type lists across the app.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_rule_upgrade_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  code_rule_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT code_rule_upgrade_types_pkey PRIMARY KEY (id),

  CONSTRAINT fk_code_rule_upgrade_types_code_rule
    FOREIGN KEY (code_rule_id)
    REFERENCES claims.code_rules(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_code_rule_upgrade_types_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT code_rule_upgrade_types_uniq
    UNIQUE (code_rule_id, invoice_upgrade_type_id)
);

CREATE INDEX IF NOT EXISTS idx_code_rule_upgrade_types_rule
  ON claims.code_rule_upgrade_types (code_rule_id);

CREATE INDEX IF NOT EXISTS idx_code_rule_upgrade_types_upgrade_type
  ON claims.code_rule_upgrade_types (invoice_upgrade_type_id);



-- ============================================================
-- code_located_fields
-- PURPOSE: Admin-visible registry for code/DB located-field
-- definitions that may be carried into the GenAI context window
-- and/or persisted into runtime located-field output.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  code_field_key text NOT NULL,
  contractor_display_name text NOT NULL,
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
-- genai_rules
-- PURPOSE: Canonical admin/config registry for GenAI rule
-- definitions, separate from the published runtime blob snapshots.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_rules (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  genai_rule_key text NOT NULL,
  contractor_display_name text NOT NULL,
  prompt_text text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  source_quote text NOT NULL,
  contractor_action text NULL,
  contractor_visibility text NOT NULL DEFAULT 'fail_only',
  contractor_blocking_policy text NOT NULL DEFAULT 'non_blocking',
  admin_workflow_policy text NOT NULL DEFAULT 'fail_only',

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT genai_rules_pkey PRIMARY KEY (id),
  CONSTRAINT genai_rules_key_uniq UNIQUE (genai_rule_key),
  CONSTRAINT genai_rules_source_quote_present_chk
    CHECK (btrim(source_quote) <> ''),
  CONSTRAINT genai_rules_contractor_visibility_chk
    CHECK (contractor_visibility IN ('hidden','fail_only','warn_and_fail')),
  CONSTRAINT genai_rules_contractor_blocking_policy_chk
    CHECK (contractor_blocking_policy IN ('non_blocking','block_on_fail')),
  CONSTRAINT genai_rules_admin_workflow_policy_chk
    CHECK (admin_workflow_policy IN ('not_managed','fail_only','warn_and_fail','all_results')),
  CONSTRAINT genai_rules_visible_blocker_chk
    CHECK (contractor_blocking_policy <> 'block_on_fail' OR contractor_visibility <> 'hidden')
);

CREATE INDEX IF NOT EXISTS idx_genai_rules_enabled
  ON claims.genai_rules (enabled);

CREATE INDEX IF NOT EXISTS idx_genai_rules_updated_at
  ON claims.genai_rules (updated_at DESC);


-- ============================================================
-- genai_rule_upgrade_types
-- PURPOSE: Declares which invoice upgrade types each GenAI rule
-- applies to.
-- ============================================================

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
    UNIQUE (genai_rule_id, invoice_upgrade_type_id)
);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_types_rule
  ON claims.genai_rule_upgrade_types (genai_rule_id);

CREATE INDEX IF NOT EXISTS idx_genai_rule_upgrade_types_upgrade_type
  ON claims.genai_rule_upgrade_types (invoice_upgrade_type_id);


-- ============================================================
-- genai_located_fields
-- PURPOSE: Canonical admin/config registry for GenAI located-field
-- definitions, separate from runtime located-field values.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  genai_field_key text NOT NULL,
  contractor_display_name text NOT NULL,
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


-- ============================================================
-- genai_located_field_upgrade_types
-- PURPOSE: Declares which invoice upgrade types each GenAI
-- located field applies to, and its order within that type.
-- ============================================================

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


-- 
-- invoice_version_located_fields
--

CREATE TABLE IF NOT EXISTS claims.invoice_version_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL DEFAULT 'd5eaa9f3-342f-4f30-b444-d54ca0c142f2',

  source_engine text NOT NULL,   -- 'classifier' | 'code' | 'genai'
  field_key     text NOT NULL,

  value_type text NOT NULL,      -- 'text' | 'currency' | 'number' | 'date' | 'bool' | 'json'
  value_text text NULL,
  value_json jsonb NULL,         -- only used when value_type='json'

  confidence smallint NOT NULL DEFAULT 0,  -- 0..100

  page    integer NULL,
  polygon jsonb NULL,                        -- DI-style polygon array, or null

  evidence_text text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_version_located_fields_pkey PRIMARY KEY (id),

  CONSTRAINT fk_invoice_version_located_fields_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_invoice_version_located_fields_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT invoice_version_located_fields_source_engine_chk
    CHECK (source_engine IN ('classifier','code','genai')),


  CONSTRAINT invoice_version_located_fields_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),


  CONSTRAINT invoice_version_located_fields_value_type_chk
    CHECK (value_type IN ('text','currency','number','date','bool','json')),

  CONSTRAINT invoice_version_located_fields_value_storage_chk
    CHECK (
      (value_type = 'json' AND value_json IS NOT NULL AND value_text IS NULL)
      OR
      (value_type <> 'json' AND value_text IS NOT NULL AND value_json IS NULL)
      OR
      (value_text IS NULL AND value_json IS NULL)  -- allow not found rows
    )

--  CONSTRAINT invoice_version_located_fields_uniq
--    UNIQUE (invoice_version_id, source_engine, field_key)
);

CREATE INDEX IF NOT EXISTS idx_ivlf_invoice_version
  ON claims.invoice_version_located_fields(invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_ivlf_upgrade_type
  ON claims.invoice_version_located_fields(invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS idx_ivlf_lookup
  ON claims.invoice_version_located_fields(invoice_version_id, invoice_upgrade_type_id, field_key);

CREATE INDEX IF NOT EXISTS idx_ivlf_engine
  ON claims.invoice_version_located_fields(invoice_version_id, invoice_upgrade_type_id, source_engine);


--
-- invoice_version_rulechecks
--

  CREATE TABLE IF NOT EXISTS claims.invoice_version_rulechecks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL DEFAULT 'd5eaa9f3-342f-4f30-b444-d54ca0c142f2',

  source_engine text NOT NULL,   -- 'code' | 'genai'

  rule_key text NOT NULL,
  contractor_display_name text NOT NULL,

  rule_result text NOT NULL DEFAULT 'fail',
  confidence smallint NOT NULL DEFAULT 0,  -- 0..100

  expected_text text NULL,
  calculation text NULL,

  evidence_text text NULL,

  reason_and_likely_causes text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_version_rulechecks_pkey PRIMARY KEY (id),

  CONSTRAINT fk_invoice_version_rulechecks_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_invoice_version_rulechecks_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT invoice_version_rulechecks_source_engine_chk
    CHECK (source_engine IN ('code','genai')),

  CONSTRAINT invoice_version_rulechecks_rule_result_chk
    CHECK (rule_result IN ('pass','info','warn','fail')),

  CONSTRAINT invoice_version_rulechecks_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT invoice_version_rulechecks_uniq
    UNIQUE (invoice_version_id, invoice_upgrade_type_id, source_engine, rule_key)
);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_invoice_version_id
  ON claims.invoice_version_rulechecks (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_upgrade_type_id
  ON claims.invoice_version_rulechecks (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_invoice_version_id_se
  ON claims.invoice_version_rulechecks (invoice_version_id, invoice_upgrade_type_id, source_engine);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_rule_key
  ON claims.invoice_version_rulechecks (rule_key);

CREATE OR REPLACE FUNCTION claims.set_invoice_version_rulecheck_contractor_display_name()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.contractor_display_name IS NULL OR btrim(NEW.contractor_display_name) = '' THEN
    IF NEW.source_engine = 'code' THEN
      SELECT cr.contractor_display_name
        INTO NEW.contractor_display_name
        FROM claims.code_rules cr
       WHERE cr.code_rule_key = NEW.rule_key;
    ELSIF NEW.source_engine = 'genai' THEN
      SELECT gr.contractor_display_name
        INTO NEW.contractor_display_name
        FROM claims.genai_rules gr
       WHERE gr.genai_rule_key = NEW.rule_key;
    END IF;
  END IF;

  IF NEW.contractor_display_name IS NULL OR btrim(NEW.contractor_display_name) = '' THEN
    NEW.contractor_display_name := initcap(replace(NEW.rule_key, '_', ' '));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ivrc_contractor_display_name
  ON claims.invoice_version_rulechecks;

CREATE TRIGGER trg_ivrc_contractor_display_name
BEFORE INSERT OR UPDATE OF source_engine, rule_key, contractor_display_name
ON claims.invoice_version_rulechecks
FOR EACH ROW
EXECUTE FUNCTION claims.set_invoice_version_rulecheck_contractor_display_name();


  -- 
  -- lineitems 
  --
  CREATE TABLE IF NOT EXISTS claims.lineitems (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  lineitem_seqno     integer NOT NULL,

  -- Minimal canonical line-item OCR fields (trim/extend as needed)
  ocr_description character varying NULL,
  ocr_description_page integer NULL,
  ocr_description_polygon jsonb NULL,
  ocr_quantity    numeric(12,3) NULL,
  ocr_quantity_page integer NULL,
  ocr_quantity_polygon jsonb NULL,
  ocr_unit_price  numeric(12,4) NULL,
  ocr_unit_price_page integer NULL,
  ocr_unit_price_polygon jsonb NULL,
  ocr_amount      numeric(12,2) NULL,
  ocr_amount_page integer NULL,
  ocr_amount_polygon jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT lineitems_pkey PRIMARY KEY (id),

  CONSTRAINT fk_claims_lineitems_invoice_version
    FOREIGN KEY (invoice_version_id) REFERENCES claims.invoice_versions(id),

  CONSTRAINT lineitems_invoice_version_seqno_uniq
    UNIQUE (invoice_version_id, lineitem_seqno),

  CONSTRAINT lineitems_seqno_chk
    CHECK (lineitem_seqno >= 1)
);

CREATE INDEX IF NOT EXISTS index_claims_lineitems_on_invoice_version_id
  ON claims.lineitems (invoice_version_id);



-- 
-- supporting document types
--
CREATE TABLE IF NOT EXISTS claims.supporting_document_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  type_key text NOT NULL,
  description text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_types_pkey PRIMARY KEY (id),
  CONSTRAINT supporting_document_types_type_key_uniq UNIQUE (type_key)
);

CREATE INDEX IF NOT EXISTS idx_supporting_document_types_enabled
  ON claims.supporting_document_types (enabled);


--
-- supporting_document_type_upgrade_types
-- PURPOSE: Declares which invoice upgrade types each supporting
-- document type applies to. This keeps supporting-document applicability
-- normalized the same way code/genai rules are mapped to upgrade types.
--
CREATE TABLE IF NOT EXISTS claims.supporting_document_type_upgrade_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  supporting_document_type_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_type_upgrade_types_pkey PRIMARY KEY (id),

  CONSTRAINT fk_supporting_document_type_upgrade_types_type
    FOREIGN KEY (supporting_document_type_id)
    REFERENCES claims.supporting_document_types(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_supporting_document_type_upgrade_types_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT supporting_document_type_upgrade_types_uniq
    UNIQUE (supporting_document_type_id, invoice_upgrade_type_id)
);

CREATE INDEX IF NOT EXISTS idx_supporting_document_type_upgrade_types_type
  ON claims.supporting_document_type_upgrade_types (supporting_document_type_id);

CREATE INDEX IF NOT EXISTS idx_supporting_document_type_upgrade_types_upgrade_type
  ON claims.supporting_document_type_upgrade_types (invoice_upgrade_type_id);


-- ============================================================
-- 
-- supporting documents
--
CREATE TABLE IF NOT EXISTS claims.supporting_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  supporting_document_type_id uuid NULL,

  -- storage pointer(s)
  storage_provider character varying NULL,   -- e.g., 'azure_blob', 'aws_s3' (optional)
  storage_key      text NOT NULL,            -- blob path / object key (your canonical locator)

  original_filename character varying NULL,
  content_type      character varying NULL,  -- e.g., 'application/pdf'
  byte_size         bigint NULL,
  sha256            character varying NULL,  -- optional but handy for dedupe/integrity

  -- supporting-document OCR / triage retention
  di_read_raw_json jsonb NULL,
  classifier_raw_json jsonb NULL,

  classification_status text NOT NULL DEFAULT 'pending',
  classification_confidence smallint NOT NULL DEFAULT 0,
  classification_reason text NULL,
  supporting_document_routing_quality text NULL,
  supporting_document_routing_quality_reason text NULL,
  classified_at timestamp(6) without time zone NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT supporting_documents_pkey PRIMARY KEY (id),

  CONSTRAINT fk_claims_supporting_documents_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_claims_supporting_documents_type
    FOREIGN KEY (supporting_document_type_id)
    REFERENCES claims.supporting_document_types(id),

  CONSTRAINT supporting_documents_classification_status_chk
    CHECK (classification_status IN ('pending','classified','needs_review','failed')),

  CONSTRAINT supporting_documents_routing_quality_chk
    CHECK (
      supporting_document_routing_quality IS NULL OR
      supporting_document_routing_quality IN ('usable','needs_review','requires_visual_review','unusable')
    )
);

CREATE INDEX IF NOT EXISTS index_claims_supporting_documents_on_invoice_version_id
  ON claims.supporting_documents (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_claims_supporting_documents_on_type_id
  ON claims.supporting_documents (supporting_document_type_id);

-- Prevent duplicate uploads of same blob/key under the same invoice version snapshot.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_supporting_documents_invoice_version_storage_key
  ON claims.supporting_documents (invoice_version_id, storage_key);



-- ============================================================
-- supporting_document_type_located_fields
-- PURPOSE: Defines the fields GenAI/vision should locate for each
-- supporting document type, and the order used in prompts/admin UI.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.supporting_document_type_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  supporting_document_type_id uuid NOT NULL,

  field_key text NOT NULL,
  contractor_display_name text NOT NULL,
  prompt_text text NOT NULL,
  field_number integer NOT NULL,
  enabled boolean NOT NULL DEFAULT true,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_type_located_fields_pkey PRIMARY KEY (id),

  CONSTRAINT fk_supporting_document_type_located_fields_type
    FOREIGN KEY (supporting_document_type_id)
    REFERENCES claims.supporting_document_types(id)
    ON DELETE CASCADE,

  CONSTRAINT supporting_document_type_located_fields_field_number_chk
    CHECK (field_number >= 1),

  CONSTRAINT supporting_document_type_located_fields_key_uniq
    UNIQUE (supporting_document_type_id, field_key),

  CONSTRAINT supporting_document_type_located_fields_order_uniq
    UNIQUE (supporting_document_type_id, field_number)
);

CREATE INDEX IF NOT EXISTS idx_sdtlf_type
  ON claims.supporting_document_type_located_fields (supporting_document_type_id);

CREATE INDEX IF NOT EXISTS idx_sdtlf_enabled
  ON claims.supporting_document_type_located_fields (enabled);


-- ============================================================
-- supporting_document_located_fields
-- PURPOSE: Runtime values located inside one uploaded supporting
-- document, separate from the field definitions above.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.supporting_document_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  supporting_document_id uuid NOT NULL,
  supporting_document_type_located_field_id uuid NULL,

  source_engine text NOT NULL DEFAULT 'genai',
  field_key text NOT NULL,

  value_type text NOT NULL,
  value_text text NULL,
  value_json jsonb NULL,

  confidence smallint NOT NULL DEFAULT 0,

  page integer NULL,
  polygon jsonb NULL,
  evidence_text text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_located_fields_pkey PRIMARY KEY (id),

  CONSTRAINT fk_supporting_document_located_fields_document
    FOREIGN KEY (supporting_document_id)
    REFERENCES claims.supporting_documents(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_supporting_document_located_fields_definition
    FOREIGN KEY (supporting_document_type_located_field_id)
    REFERENCES claims.supporting_document_type_located_fields(id)
    ON DELETE SET NULL,

  CONSTRAINT supporting_document_located_fields_source_engine_chk
    CHECK (source_engine IN ('genai','vision','code','manual')),

  CONSTRAINT supporting_document_located_fields_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT supporting_document_located_fields_value_type_chk
    CHECK (value_type IN ('text','currency','number','date','bool','json')),

  CONSTRAINT supporting_document_located_fields_value_storage_chk
    CHECK (
      (value_type = 'json' AND value_json IS NOT NULL AND value_text IS NULL)
      OR
      (value_type <> 'json' AND value_text IS NOT NULL AND value_json IS NULL)
      OR
      (value_text IS NULL AND value_json IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_sdlf_document
  ON claims.supporting_document_located_fields (supporting_document_id);

CREATE INDEX IF NOT EXISTS idx_sdlf_definition
  ON claims.supporting_document_located_fields (supporting_document_type_located_field_id);

CREATE INDEX IF NOT EXISTS idx_sdlf_lookup
  ON claims.supporting_document_located_fields (supporting_document_id, field_key);

CREATE INDEX IF NOT EXISTS idx_sdlf_engine
  ON claims.supporting_document_located_fields (supporting_document_id, source_engine);


-- ============================================================
-- supporting_document_visual_findings
-- PURPOSE: Runtime visual observations found inside one uploaded
-- supporting document PDF. These are one row per useful visual
-- finding, not one row per embedded PDF image object.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.supporting_document_visual_findings (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  supporting_document_id uuid NOT NULL,

  finding_seqno integer NOT NULL,
  source_engine text NOT NULL DEFAULT 'genai',
  finding_type text NOT NULL,

  page integer NULL,
  summary text NOT NULL,
  legibility text NOT NULL DEFAULT 'not_applicable',
  confidence smallint NOT NULL DEFAULT 0,
  raw_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT supporting_document_visual_findings_pkey PRIMARY KEY (id),

  CONSTRAINT fk_supporting_document_visual_findings_document
    FOREIGN KEY (supporting_document_id)
    REFERENCES claims.supporting_documents(id)
    ON DELETE CASCADE,

  CONSTRAINT supporting_document_visual_findings_seqno_chk
    CHECK (finding_seqno >= 1),

  CONSTRAINT supporting_document_visual_findings_source_engine_chk
    CHECK (source_engine IN ('genai','vision','manual')),

  CONSTRAINT supporting_document_visual_findings_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT supporting_document_visual_findings_legibility_chk
    CHECK (legibility IN ('legible','partially_legible','illegible','not_applicable')),

  CONSTRAINT supporting_document_visual_findings_seqno_uniq
    UNIQUE (supporting_document_id, source_engine, finding_seqno)
);

CREATE INDEX IF NOT EXISTS idx_sdvf_document
  ON claims.supporting_document_visual_findings (supporting_document_id);

CREATE INDEX IF NOT EXISTS idx_sdvf_lookup
  ON claims.supporting_document_visual_findings (supporting_document_id, finding_type);


-- ============================================================
-- revision_rounds
-- PURPOSE: One lightweight admin-to-contractor exchange. The
-- greatest round_number is the current/latest round.
-- ============================================================

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
    FOREIGN KEY (invoice_id)
    REFERENCES claims.invoices(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_revision_rounds_invoice_version
    FOREIGN KEY (invoice_version_id, invoice_id)
    REFERENCES claims.invoice_versions(id, invoice_id),

  CONSTRAINT revision_rounds_number_chk
    CHECK (round_number >= 1),

  CONSTRAINT revision_rounds_invoice_number_uniq
    UNIQUE (invoice_id, round_number),

  CONSTRAINT revision_rounds_timestamp_chk
    CHECK (
      contractor_response_submitted_at IS NULL
      OR (
        admin_sent_at IS NOT NULL
        AND contractor_response_submitted_at >= admin_sent_at
      )
    )
);

CREATE INDEX IF NOT EXISTS idx_revision_rounds_invoice
  ON claims.revision_rounds (invoice_id, round_number DESC);


-- ============================================================
-- revision_issues
-- PURPOSE: One durable workflow problem that survives across
-- revision rounds. Status records only whether/how it closed.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.revision_issues (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_id uuid NOT NULL,
  issue_type text NOT NULL,

  opened_from_invoice_version_rulecheck_id uuid NULL,
  opened_from_invoice_version_located_field_id uuid NULL,
  opened_from_supporting_document_located_field_id uuid NULL,
  opened_from_di_invoice_version_id uuid NULL,
  opened_from_di_field_key text NULL,

  -- Stable logical source identity. The exact runtime UUIDs above remain
  -- the historical pointers; these values let one durable issue follow the
  -- same rule/field across later invoice versions.
  opened_from_rule_key text NULL,
  opened_from_rule_upgrade_type_id uuid NULL,
  opened_from_invoice_field_key text NULL,
  opened_from_invoice_field_upgrade_type_id uuid NULL,
  opened_from_supporting_document_type_key text NULL,
  opened_from_supporting_field_key text NULL,
  opened_from_source_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,

  status text NOT NULL DEFAULT 'pending_admin_review',
  disposition_comment text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT revision_issues_pkey PRIMARY KEY (id),

  CONSTRAINT fk_revision_issues_invoice
    FOREIGN KEY (invoice_id)
    REFERENCES claims.invoices(id)
    ON DELETE CASCADE,

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

  CONSTRAINT fk_revision_issues_rule_upgrade_type
    FOREIGN KEY (opened_from_rule_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT fk_revision_issues_invoice_field_upgrade_type
    FOREIGN KEY (opened_from_invoice_field_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT revision_issues_type_chk
    CHECK (
      issue_type IN (
        'rule',
        'invoice_field',
        'supporting_document_field',
        'di_field'
      )
    ),

  CONSTRAINT revision_issues_status_chk
    CHECK (
      status IN (
        'pending_admin_review',
        'open',
        'closed_no_contractor_action_required',
        'closed_via_corrected_documentation',
        'closed_via_attestation',
        'closed_via_exception',
        'closed_as_withdrawn'
      )
    ),

  CONSTRAINT revision_issues_disposition_comment_chk
    CHECK (
      (
        status IN ('pending_admin_review', 'open')
        AND disposition_comment IS NULL
      )
      OR
      (
        status NOT IN ('pending_admin_review', 'open')
        AND length(btrim(disposition_comment)) > 0
      )
    ),

  CONSTRAINT revision_issues_source_chk
    CHECK (
      (
        issue_type = 'rule'
        AND opened_from_invoice_version_rulecheck_id IS NOT NULL
        AND opened_from_invoice_version_located_field_id IS NULL
        AND opened_from_supporting_document_located_field_id IS NULL
        AND opened_from_di_invoice_version_id IS NULL
        AND opened_from_di_field_key IS NULL
      )
      OR
      (
        issue_type = 'invoice_field'
        AND opened_from_invoice_version_rulecheck_id IS NULL
        AND opened_from_invoice_version_located_field_id IS NOT NULL
        AND opened_from_supporting_document_located_field_id IS NULL
        AND opened_from_di_invoice_version_id IS NULL
        AND opened_from_di_field_key IS NULL
      )
      OR
      (
        issue_type = 'supporting_document_field'
        AND opened_from_invoice_version_rulecheck_id IS NULL
        AND opened_from_invoice_version_located_field_id IS NULL
        AND opened_from_supporting_document_located_field_id IS NOT NULL
        AND opened_from_di_invoice_version_id IS NULL
        AND opened_from_di_field_key IS NULL
      )
      OR
      (
        issue_type = 'di_field'
        AND opened_from_invoice_version_rulecheck_id IS NULL
        AND opened_from_invoice_version_located_field_id IS NULL
        AND opened_from_supporting_document_located_field_id IS NULL
        AND opened_from_di_invoice_version_id IS NOT NULL
        AND length(btrim(opened_from_di_field_key)) > 0
      )
    ),

  CONSTRAINT revision_issues_stable_identity_chk
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
    )
);

CREATE INDEX IF NOT EXISTS idx_revision_issues_invoice
  ON claims.revision_issues (invoice_id, status, created_at, id);

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_rule_source
  ON claims.revision_issues (
    invoice_id,
    opened_from_invoice_version_rulecheck_id
  )
  WHERE issue_type = 'rule';

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_invoice_field_source
  ON claims.revision_issues (
    invoice_id,
    opened_from_invoice_version_located_field_id
  )
  WHERE issue_type = 'invoice_field';

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_supporting_field_source
  ON claims.revision_issues (
    invoice_id,
    opened_from_supporting_document_located_field_id
  )
  WHERE issue_type = 'supporting_document_field';

CREATE UNIQUE INDEX IF NOT EXISTS uq_revision_issues_di_field_source
  ON claims.revision_issues (invoice_id, opened_from_di_field_key)
  WHERE issue_type = 'di_field';

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


-- ============================================================
-- revision_issue_comments
-- PURPOSE: Ordered admin/contractor comments for one issue. Each
-- comment belongs to the round in which it occurred.
-- ============================================================

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
    FOREIGN KEY (revision_issue_id)
    REFERENCES claims.revision_issues(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_revision_issue_comments_round
    FOREIGN KEY (revision_round_id)
    REFERENCES claims.revision_rounds(id)
    ON DELETE CASCADE,

  CONSTRAINT revision_issue_comments_author_chk
    CHECK (author_type IN ('admin', 'contractor')),

  CONSTRAINT revision_issue_comments_text_chk
    CHECK (length(btrim(comment_text)) > 0),

  CONSTRAINT revision_issue_comments_admin_remedy_chk
    CHECK (
      admin_recommended_remedy IS NULL
      OR admin_recommended_remedy IN (
        'correct_and_reupload_invoice',
        'upload_supporting_document',
        'provide_attestation',
        'provide_explanation'
      )
    ),

  CONSTRAINT revision_issue_comments_contractor_method_chk
    CHECK (
      contractor_response_method IS NULL
      OR contractor_response_method IN (
        'corrected_invoice_uploaded',
        'supporting_document_uploaded',
        'attestation_provided',
        'explanation_provided',
        'unable_to_resolve'
      )
    ),

  CONSTRAINT revision_issue_comments_author_fields_chk
    CHECK (
      (
        author_type = 'admin'
        AND contractor_response_method IS NULL
        AND contractor_asserted_value IS NULL
      )
      OR
      (
        author_type = 'contractor'
        AND admin_recommended_remedy IS NULL
        AND contractor_response_method IS NOT NULL
      )
    ),

  CONSTRAINT revision_issue_comments_asserted_value_chk
    CHECK (
      contractor_asserted_value IS NULL
      OR (
        author_type = 'contractor'
        AND contractor_response_method = 'attestation_provided'
      )
    )
);

CREATE INDEX IF NOT EXISTS idx_revision_issue_comments_issue
  ON claims.revision_issue_comments (revision_issue_id, created_at, id);

CREATE INDEX IF NOT EXISTS idx_revision_issue_comments_round
  ON claims.revision_issue_comments (revision_round_id, created_at, id);


--
-- internal_notes
--
CREATE TABLE IF NOT EXISTS claims.internal_notes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_id uuid NOT NULL,
  admin_user_id uuid NOT NULL,
  note_text text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT internal_notes_pkey PRIMARY KEY (id),

  CONSTRAINT fk_internal_notes_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id),

  CONSTRAINT fk_internal_notes_admin_user
    FOREIGN KEY (admin_user_id) REFERENCES public.users(id),

  CONSTRAINT internal_notes_text_present_chk
    CHECK (length(btrim(note_text)) > 0)
);

CREATE INDEX IF NOT EXISTS index_claims_internal_notes_on_invoice_id
  ON claims.internal_notes (invoice_id, created_at DESC);

CREATE INDEX IF NOT EXISTS index_claims_internal_notes_on_admin_user_id
  ON claims.internal_notes (admin_user_id);



-- 
-- conversation_messages
-- Ordinary admin/contractor back-and-forth. Formal revision
-- workflow is stored in revision_issues, revision_rounds, and their comments.
--
CREATE TABLE IF NOT EXISTS claims.conversation_messages (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_id uuid NOT NULL,
  invoice_version_id uuid NULL,
  revreq_seqno       integer NOT NULL,

  requester_id uuid NOT NULL,   -- message author (public.users.id)
  message_type text NOT NULL DEFAULT 'admin_message',

  request_text  text NOT NULL,  -- single message body for both admin requests and contractor notes
  recipient_read_at timestamp(6) without time zone NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT conversation_messages_pkey PRIMARY KEY (id),

  CONSTRAINT fk_conversation_messages_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id),

  CONSTRAINT fk_conversation_messages_invoice_version
    FOREIGN KEY (invoice_version_id) REFERENCES claims.invoice_versions(id),

  CONSTRAINT fk_conversation_messages_requester
    FOREIGN KEY (requester_id) REFERENCES public.users(id),

  CONSTRAINT conversation_messages_message_type_chk
    CHECK (message_type IN ('admin_message', 'contractor_note')),

  CONSTRAINT conversation_messages_seqno_chk
    CHECK (revreq_seqno >= 1),

  CONSTRAINT conversation_messages_invoice_seqno_uniq
    UNIQUE (invoice_id, revreq_seqno)
);

CREATE INDEX IF NOT EXISTS index_claims_conversation_messages_on_invoice_id
  ON claims.conversation_messages (invoice_id);

CREATE INDEX IF NOT EXISTS index_claims_conversation_messages_on_invoice_version_id
  ON claims.conversation_messages (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_claims_conversation_messages_on_requester_id
  ON claims.conversation_messages (requester_id);

CREATE INDEX IF NOT EXISTS index_claims_conversation_messages_on_message_type
  ON claims.conversation_messages (message_type);




--
-- Validationgenai_config
-- Singleton-style editable prompt and advice config for system admins.
--
CREATE TABLE IF NOT EXISTS claims.validationgenai_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  system_record character varying NULL,
  document_triage_system_record character varying NULL,
  supporting_document_extraction_system_record character varying NULL,
  user_record0 character varying NULL,
  admin_advice_intro character varying NULL,
  admin_advice_closing character varying NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT validationgenai_config_pkey PRIMARY KEY (id)
);


-- ============================================================
-- code_rule_history
-- PURPOSE: Pre-change audit snapshots for claims.code_rules.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_rule_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  code_rule_key text NOT NULL,
  contractor_display_name text NOT NULL,
  description text NOT NULL,
  enabled boolean NOT NULL,

  pass_admin_message text NULL,
  warn_admin_message text NULL,
  fail_admin_message text NULL,
  info_admin_message text NULL,
  admin_notes text NULL,
  source_quote text NULL,
  contractor_action text NULL,
  contractor_visibility text NOT NULL,
  contractor_blocking_policy text NOT NULL,
  admin_workflow_policy text NOT NULL,

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


-- ============================================================
-- code_rule_upgrade_type_history
-- PURPOSE: Pre-change audit snapshots for claims.code_rule_upgrade_types.
-- ============================================================

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


-- ============================================================
-- code_located_field_history
-- PURPOSE: Pre-change audit snapshots for claims.code_located_fields.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.code_located_field_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  code_field_key text NOT NULL,
  contractor_display_name text NOT NULL,
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
-- genai_rule_history
-- PURPOSE: Pre-change audit snapshots for claims.genai_rules.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_rule_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  genai_rule_key text NOT NULL,
  contractor_display_name text NOT NULL,
  prompt_text text NOT NULL,
  enabled boolean NOT NULL,
  source_quote text NULL,
  contractor_action text NULL,
  contractor_visibility text NOT NULL,
  contractor_blocking_policy text NOT NULL,
  admin_workflow_policy text NOT NULL,

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


-- ============================================================
-- genai_rule_upgrade_type_history
-- PURPOSE: Pre-change audit snapshots for claims.genai_rule_upgrade_types.
-- ============================================================

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
-- genai_located_field_history
-- PURPOSE: Pre-change audit snapshots for claims.genai_located_fields.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.genai_located_field_history (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  source_id uuid NULL,

  genai_field_key text NOT NULL,
  contractor_display_name text NOT NULL,
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


-- ============================================================
-- genai_located_field_upgrade_type_history
-- PURPOSE: Pre-change audit snapshots for
-- claims.genai_located_field_upgrade_types.
-- ============================================================

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


--
-- invoice_version_upgrade_types
-- Manifest/result table for the upgrade types found on a specific invoice version.
-- This is not a parent of lineitems/located_fields/rulechecks; those rows point
-- directly at claims.invoice_upgrade_types.
--
CREATE TABLE IF NOT EXISTS claims.invoice_version_upgrade_types (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL,

  source_engine text NOT NULL DEFAULT 'classifier',
  call_status text NOT NULL DEFAULT 'classified',

  confidence smallint NOT NULL DEFAULT 0,
  result text NULL,
  admin_advice text NULL,
  evidence_text text NULL,
  classification_explanation text NULL,
  page integer NULL,
  polygon jsonb NULL,
  raw_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_version_upgrade_types_pkey PRIMARY KEY (id),

  CONSTRAINT fk_invoice_version_upgrade_types_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_invoice_version_upgrade_types_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT invoice_version_upgrade_types_source_engine_chk
    CHECK (source_engine IN ('classifier','genai')),

  CONSTRAINT invoice_version_upgrade_types_call_status_chk
    CHECK (call_status IN ('classified','queued','in_progress','succeeded','failed','skipped')),

  CONSTRAINT invoice_version_upgrade_types_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT invoice_version_upgrade_types_page_chk
    CHECK (page IS NULL OR page >= 1),

  CONSTRAINT invoice_version_upgrade_types_result_chk
    CHECK (result IS NULL OR result IN ('pass','info','warn','fail')),

  CONSTRAINT invoice_version_upgrade_types_uniq
    UNIQUE (invoice_version_id, invoice_upgrade_type_id, source_engine)
);

CREATE INDEX IF NOT EXISTS idx_ivut_invoice_version
  ON claims.invoice_version_upgrade_types (invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_ivut_upgrade_type
  ON claims.invoice_version_upgrade_types (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS idx_ivut_invoice_upgrade_status
  ON claims.invoice_version_upgrade_types (invoice_version_id, invoice_upgrade_type_id, call_status);


  -- ============================================================
-- ingest_runs
-- One row per "Run end-to-end" click (batch)
-- Parent = sessions
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ingest_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  session_id uuid NOT NULL,
  contractor_id uuid NULL,
  resolved_invoice_version_id uuid NULL,

  status text NOT NULL DEFAULT 'queued',  -- queued|running|succeeded|failed|partial
  cleanup_failed_invoice_artifacts boolean NOT NULL DEFAULT false,

  total_files     integer NOT NULL DEFAULT 0,
  completed_files integer NOT NULL DEFAULT 0,
  failed_files    integer NOT NULL DEFAULT 0,

  messages jsonb NULL, -- array of strings, optional
  pipeline_error_code text NULL,
  pipeline_error_description text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  completed_at timestamp(6) without time zone NULL,

  CONSTRAINT ingest_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ingest_runs_session
    FOREIGN KEY (session_id)
    REFERENCES claims.sessions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_runs_contractor
    FOREIGN KEY (contractor_id)
    REFERENCES public.contractors(id),

  CONSTRAINT fk_ingest_runs_resolved_invoice_version
    FOREIGN KEY (resolved_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE SET NULL,

  CONSTRAINT ingest_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed','partial')),

  CONSTRAINT ingest_runs_counts_chk
    CHECK (
      total_files >= 0
      AND completed_files >= 0
      AND failed_files >= 0
      AND completed_files <= total_files
      AND failed_files <= total_files
    )
);

CREATE INDEX IF NOT EXISTS idx_ingest_runs_session_created
  ON claims.ingest_runs (session_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_runs_contractor_created
  ON claims.ingest_runs (contractor_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_runs_resolved_invoice_version
  ON claims.ingest_runs (resolved_invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_ingest_runs_status
  ON claims.ingest_runs (status);



-- ============================================================
-- ingest_documents
-- PURPOSE: Staging records for mixed bundle intake prior to
-- resolving which uploaded file is the real invoice versus
-- supporting documents.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ingest_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  ingest_run_id uuid NOT NULL,
  session_id uuid NOT NULL,
  contractor_id uuid NOT NULL,

  invoice_id uuid NULL,
  resolved_invoice_id uuid NULL,
  resolved_invoice_version_id uuid NULL,
  promoted_supporting_document_id uuid NULL,

  storage_provider character varying NOT NULL DEFAULT 'azure_blob',
  storage_key character varying NOT NULL,
  original_filename character varying NOT NULL,
  content_type character varying NULL,
  byte_size bigint NULL,
  sha256 character varying NULL,

  di_read_raw_json jsonb NULL,
  classifier_raw_json jsonb NULL,

  document_kind text NULL,
  document_kind_confidence smallint NOT NULL DEFAULT 0,
  document_kind_reason text NULL,

  supporting_document_type_id uuid NULL,
  classification_status text NOT NULL DEFAULT 'pending',
  classification_confidence smallint NOT NULL DEFAULT 0,
  classification_reason text NULL,
  supporting_document_routing_quality text NULL,
  supporting_document_routing_quality_reason text NULL,
  classified_at timestamp(6) without time zone NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT ingest_documents_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ingest_documents_ingest_run
    FOREIGN KEY (ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_documents_session
    FOREIGN KEY (session_id)
    REFERENCES claims.sessions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_documents_contractor
    FOREIGN KEY (contractor_id)
    REFERENCES public.contractors(id),

  CONSTRAINT fk_ingest_documents_invoice
    FOREIGN KEY (invoice_id)
    REFERENCES claims.invoices(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_documents_resolved_invoice
    FOREIGN KEY (resolved_invoice_id)
    REFERENCES claims.invoices(id)
    ON DELETE SET NULL,

  CONSTRAINT fk_ingest_documents_resolved_invoice_version
    FOREIGN KEY (resolved_invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE SET NULL,

  CONSTRAINT fk_ingest_documents_promoted_supporting_document
    FOREIGN KEY (promoted_supporting_document_id)
    REFERENCES claims.supporting_documents(id)
    ON DELETE SET NULL,

  CONSTRAINT fk_ingest_documents_supporting_document_type
    FOREIGN KEY (supporting_document_type_id)
    REFERENCES claims.supporting_document_types(id),

  CONSTRAINT ingest_documents_document_kind_chk
    CHECK (document_kind IS NULL OR document_kind IN ('invoice','supporting_document','unknown')),

  CONSTRAINT ingest_documents_document_kind_confidence_chk
    CHECK (document_kind_confidence BETWEEN 0 AND 100),

  CONSTRAINT ingest_documents_classification_status_chk
    CHECK (classification_status IN ('pending','classified','needs_review','failed','superseded')),

  CONSTRAINT ingest_documents_classification_confidence_chk
    CHECK (classification_confidence BETWEEN 0 AND 100),

  CONSTRAINT ingest_documents_routing_quality_chk
    CHECK (
      supporting_document_routing_quality IS NULL OR
      supporting_document_routing_quality IN ('usable','needs_review','requires_visual_review','unusable')
    )
);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_ingest_run_id
  ON claims.ingest_documents (ingest_run_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_session_id
  ON claims.ingest_documents (session_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_contractor_id
  ON claims.ingest_documents (contractor_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_invoice_id
  ON claims.ingest_documents (invoice_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_document_kind
  ON claims.ingest_documents (document_kind, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_resolved_invoice_id
  ON claims.ingest_documents (resolved_invoice_id);

CREATE INDEX IF NOT EXISTS idx_ingest_documents_on_promoted_supporting_document_id
  ON claims.ingest_documents (promoted_supporting_document_id);


-- ============================================================
-- ingest_step_runs
-- PURPOSE: Single table combining upload_runs + ocr_runs + genai_runs
-- DESIGN: Keep ALL former validation_runs fields (nullable as needed)
-- NOTE:
-- - Every step belongs to an ingest_run; session_id remains required for filtering/debugging.
-- - status is authoritative lifecycle state for each step attempt.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ingest_step_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  -- Parent pipeline run. Every step row belongs to exactly one run.
  ingest_run_id uuid NOT NULL,

  -- Session is always known for filtering/debugging.
  session_id uuid NOT NULL,

  -- Target invoice version (required for resolved-invoice work)
  invoice_version_id uuid NULL,

  -- Target ingest staging document (required for pre-resolution bundle work)
  ingest_document_id uuid NULL,

  -- GenAI subcall target. Null for upload/ocr/classifier/legacy genai summary rows.
  invoice_upgrade_type_id uuid NULL,

  -- Supporting document type target. Used by type-level support-doc extraction steps.
  supporting_document_type_id uuid NULL,

  -- Which step this attempt represents
  step_type text NOT NULL,  -- upload_package_stage | ocr_read | classifier_files | supporting_document_extraction | ocr_invoice | fix_upload_package_stage | fix_ocr_read | fix_classifier_files | fix_clone_existing_evidence | fix_supporting_document_extraction | fix_ocr_invoice | ruleclone_clone_existing_evidence | case_facts | genai_common | genai_upgrade | code_common | code_upgrade | aggregate_advice

  status character varying NOT NULL DEFAULT 'queued',

  -- failed states must provide error details
  error_text text NULL,

  -- unlike invoice_versions this is a per run record which can be multiple
  di_results_json  jsonb NULL,

  -- unlike invoice_versions table this is a per run genAI artifacts (retention indefinite for now)
  genai_results_json  jsonb NULL,
  context_window_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT ingest_step_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ingest_step_runs_ingest_run
    FOREIGN KEY (ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_step_runs_session
    FOREIGN KEY (session_id)
    REFERENCES claims.sessions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_step_runs_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_step_runs_ingest_document
    FOREIGN KEY (ingest_document_id)
    REFERENCES claims.ingest_documents(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_step_runs_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT fk_ingest_step_runs_supporting_document_type
    FOREIGN KEY (supporting_document_type_id)
    REFERENCES claims.supporting_document_types(id)
    ON DELETE CASCADE,

  CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN ('upload_package_stage','fix_upload_package_stage','ocr_read','fix_ocr_read','classifier_files','fix_classifier_files','supporting_document_extraction','fix_supporting_document_extraction','ocr_invoice','fix_ocr_invoice','fix_clone_existing_evidence','ruleclone_clone_existing_evidence','case_facts','genai_common','genai_upgrade','code_common','code_upgrade','aggregate_advice')),

  CONSTRAINT ingest_step_runs_status_chk
    CHECK (status IN ('queued','in_progress','succeeded','failed')),

  -- Keep lifecycle semantics explicit and consistent with error payload.
  CONSTRAINT ingest_step_runs_status_error_chk
    CHECK (
      (status IN ('queued','in_progress') AND error_text IS NULL)
      OR
      (status = 'succeeded' AND error_text IS NULL)
      OR
      (status = 'failed' AND error_text IS NOT NULL)
    ),

  -- Only require upgrade type for the new typed GenAI calls.
  CONSTRAINT ingest_step_runs_upgrade_type_required_for_typed_genai_chk
    CHECK (
      (step_type NOT IN ('genai_common','genai_upgrade','code_common','code_upgrade'))
      OR
      (invoice_upgrade_type_id IS NOT NULL)
    ),

  CONSTRAINT ingest_step_runs_target_required_chk
    CHECK (
      step_type IN ('upload_package_stage','fix_upload_package_stage')
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
        invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NOT NULL
      )
    ),

  CONSTRAINT ingest_step_runs_target_compatibility_chk
    CHECK (
      (
        step_type IN ('upload_package_stage','fix_upload_package_stage')
        AND invoice_version_id IS NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NULL
      )
      OR
      (
        step_type IN ('ocr_read','fix_ocr_read','classifier_files','fix_classifier_files')
        AND ingest_document_id IS NOT NULL
        AND invoice_version_id IS NULL
        AND supporting_document_type_id IS NULL
      )
      OR
      (
        step_type IN ('supporting_document_extraction','fix_supporting_document_extraction')
        AND supporting_document_type_id IS NOT NULL
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
      )
      OR
      (
        step_type NOT IN ('upload_package_stage','fix_upload_package_stage','ocr_read','fix_ocr_read','classifier_files','fix_classifier_files','supporting_document_extraction','fix_supporting_document_extraction')
        AND invoice_version_id IS NOT NULL
        AND ingest_document_id IS NULL
        AND supporting_document_type_id IS NULL
      )
    ),

  CONSTRAINT ingest_step_runs_context_window_json_type_chk
    CHECK (context_window_json IS NULL OR jsonb_typeof(context_window_json) = 'array')
);

-- Batch run drill-down
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_ingest_run_id
  ON claims.ingest_step_runs (ingest_run_id, created_at DESC);

-- Session filtering across pipeline runs
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_session_id
  ON claims.ingest_step_runs (session_id, created_at DESC);

-- Invoice-version drill-down
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_invoice_version_id
  ON claims.ingest_step_runs (invoice_version_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_invoice_version_step
  ON claims.ingest_step_runs (invoice_version_id, step_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_ingest_document_id
  ON claims.ingest_step_runs (ingest_document_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_ingest_document_step
  ON claims.ingest_step_runs (ingest_document_id, step_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_upgrade_type_id
  ON claims.ingest_step_runs (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_supporting_document_type_id
  ON claims.ingest_step_runs (supporting_document_type_id);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_supporting_document_type_step
  ON claims.ingest_step_runs (supporting_document_type_id, step_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_iv_upgrade_step
  ON claims.ingest_step_runs (invoice_version_id, invoice_upgrade_type_id, step_type, created_at DESC);

-- Prevent concurrent pipeline advancement from creating duplicate active/success
-- rows for the same logical step target. Failed rows remain repeatable so worker
-- retry history is preserved.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_ingest_step_runs_document_nonfailed
  ON claims.ingest_step_runs (ingest_run_id, ingest_document_id, step_type)
  WHERE ingest_document_id IS NOT NULL
    AND step_type IN ('ocr_read','fix_ocr_read','classifier_files','fix_classifier_files')
    AND status IN ('queued','in_progress','succeeded');

CREATE UNIQUE INDEX IF NOT EXISTS uniq_ingest_step_runs_invoice_nonfailed
  ON claims.ingest_step_runs (ingest_run_id, invoice_version_id, step_type)
  WHERE invoice_version_id IS NOT NULL
    AND ingest_document_id IS NULL
    AND supporting_document_type_id IS NULL
    AND invoice_upgrade_type_id IS NULL
    AND status IN ('queued','in_progress','succeeded');

CREATE UNIQUE INDEX IF NOT EXISTS uniq_ingest_step_runs_support_type_nonfailed
  ON claims.ingest_step_runs (
    ingest_run_id,
    invoice_version_id,
    supporting_document_type_id,
    step_type
  )
  WHERE invoice_version_id IS NOT NULL
    AND supporting_document_type_id IS NOT NULL
    AND ingest_document_id IS NULL
    AND status IN ('queued','in_progress','succeeded');

CREATE UNIQUE INDEX IF NOT EXISTS uniq_ingest_step_runs_upgrade_nonfailed
  ON claims.ingest_step_runs (
    ingest_run_id,
    invoice_version_id,
    invoice_upgrade_type_id,
    step_type
  )
  WHERE invoice_version_id IS NOT NULL
    AND invoice_upgrade_type_id IS NOT NULL
    AND ingest_document_id IS NULL
    AND status IN ('queued','in_progress','succeeded');
