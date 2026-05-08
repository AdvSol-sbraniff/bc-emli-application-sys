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
  session_id     uuid NOT NULL,
  contractor_id  uuid NOT NULL,
  submitter_id   uuid NULL,
  -- Legacy upgrade/domain choice. Points at public.permit_classifications
  -- rows where type='SubmissionVariant' under the Invoice submission type.
  upgrade_type_id uuid NULL,

  system_help_notes text NULL,

  status character varying NOT NULL DEFAULT 'upload_queued',
  status_updated_at timestamp(6) without time zone NULL,
  submitted_at timestamp(6) without time zone NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT invoices_pkey PRIMARY KEY (id),

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
  'admin_review_inbox',    -- contractor submitted; waiting for admin review / screen-in.
  'contractor_revision_inbox', -- admin requested contractor revisions before business review resumes.
  'in_review',
  'approved_pending',
  'approved_paid',
  'ineligible'
)),

  CONSTRAINT fk_claims_invoices_session
    FOREIGN KEY (session_id) REFERENCES claims.sessions(id),

  CONSTRAINT fk_claims_invoices_contractor
    FOREIGN KEY (contractor_id) REFERENCES public.contractors(id),

  CONSTRAINT fk_claims_invoices_submitter
    FOREIGN KEY (submitter_id) REFERENCES public.users(id),

  CONSTRAINT fk_claims_invoices_upgrade_type
    FOREIGN KEY (upgrade_type_id) REFERENCES public.permit_classifications(id)

);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_status
  ON claims.invoices (status);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_submitted_at
  ON claims.invoices (submitted_at);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_session_id
  ON claims.invoices (session_id);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_contractor_id
  ON claims.invoices (contractor_id);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_submitter_id
  ON claims.invoices (submitter_id);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_upgrade_type_id
  ON claims.invoices (upgrade_type_id);



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
  genai_all_rulechecks_pass_flag boolean NULL,
  genai_admin_advice text NULL,

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
  di_ocr_billing_address  character varying NULL,
  di_ocr_billing_address_page integer NULL,
  di_ocr_billing_address_polygon jsonb NULL,
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

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT invoice_versions_pkey PRIMARY KEY (id),

  CONSTRAINT fk_claims_versions_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id),

  CONSTRAINT invoice_versions_invoice_id_versionno_uniq
    UNIQUE (invoice_id, invoice_versionno),

  CONSTRAINT invoice_versions_versionno_chk
    CHECK (invoice_versionno >= 1)
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

-- Optional: prevent reusing the same blob path within the same invoice
CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_versions_invoice_storage_key
  ON claims.invoice_versions (invoice_id, storage_key);

-- Enables composite FKs so other tables can prove "this version belongs to this invoice"
CREATE UNIQUE INDEX IF NOT EXISTS uniq_invoice_versions_id_invoice_id
  ON claims.invoice_versions (id, invoice_id);


--
-- invoice_upgrade_types
-- Catalogue of AI invoice upgrade domains, separate from legacy public.permit_classifications.
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


-- 
-- invoice_version_located_fields
--

CREATE TABLE IF NOT EXISTS claims.invoice_version_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL DEFAULT 'd5eaa9f3-342f-4f30-b444-d54ca0c142f2',

  source_engine text NOT NULL,   -- 'code' | 'genai'
  field_key     text NOT NULL,

  line_number   integer NOT NULL DEFAULT 0,  

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
    CHECK (source_engine IN ('code','genai')),


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
      (value_text IS NULL AND value_json IS NULL)  -- allow �not found� rows
    )

--  CONSTRAINT invoice_version_located_fields_uniq
--    UNIQUE (invoice_version_id, source_engine, field_key, line_number)
);

CREATE INDEX IF NOT EXISTS idx_ivlf_invoice_version
  ON claims.invoice_version_located_fields(invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_ivlf_upgrade_type
  ON claims.invoice_version_located_fields(invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS idx_ivlf_lookup
  ON claims.invoice_version_located_fields(invoice_version_id, invoice_upgrade_type_id, field_key, line_number);

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

  rule_number integer NOT NULL,
  rule_key text NULL,
  source_requirement_id text NULL,
  evidence_source text NULL,     -- invoice_pdf|supporting_document|database|external_list|admin_review, or pipe/comma combo
  rule_name   text NOT NULL,

  rule_pass_flag boolean NOT NULL,
  confidence smallint NOT NULL DEFAULT 0,  -- 0..100

  expected_text text NULL,
  observed_text text NULL,

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

  CONSTRAINT invoice_version_rulechecks_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT invoice_version_rulechecks_rule_number_chk
    CHECK (rule_number >= 0),

  CONSTRAINT invoice_version_rulechecks_uniq
    UNIQUE (invoice_version_id, invoice_upgrade_type_id, source_engine, rule_number)
);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_invoice_version_id
  ON claims.invoice_version_rulechecks (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_upgrade_type_id
  ON claims.invoice_version_rulechecks (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_invoice_version_id_se
  ON claims.invoice_version_rulechecks (invoice_version_id, invoice_upgrade_type_id, source_engine);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_rule_key
  ON claims.invoice_version_rulechecks (rule_key);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_source_requirement_id
  ON claims.invoice_version_rulechecks (source_requirement_id);



  -- 
  -- lineitems 
  --
  CREATE TABLE IF NOT EXISTS claims.lineitems (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  invoice_upgrade_type_id uuid NOT NULL DEFAULT 'd5eaa9f3-342f-4f30-b444-d54ca0c142f2',
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

  CONSTRAINT fk_claims_lineitems_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id) REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT lineitems_invoice_version_seqno_uniq
    UNIQUE (invoice_version_id, lineitem_seqno),

  CONSTRAINT lineitems_seqno_chk
    CHECK (lineitem_seqno >= 1)
);

CREATE INDEX IF NOT EXISTS index_claims_lineitems_on_invoice_version_id
  ON claims.lineitems (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_claims_lineitems_on_upgrade_type_id
  ON claims.lineitems (invoice_upgrade_type_id);



-- 
-- supporting documents
--
CREATE TABLE IF NOT EXISTS claims.supporting_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_id uuid NOT NULL,

  -- storage pointer(s)
  storage_provider character varying NULL,   -- e.g., 'azure_blob', 'aws_s3' (optional)
  storage_key      text NOT NULL,            -- blob path / object key (your canonical locator)

  original_filename character varying NULL,
  content_type      character varying NULL,  -- e.g., 'application/pdf'
  byte_size         bigint NULL,
  sha256            character varying NULL,  -- optional but handy for dedupe/integrity

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT supporting_documents_pkey PRIMARY KEY (id),

  CONSTRAINT fk_claims_supporting_documents_invoice
    FOREIGN KEY (invoice_id) REFERENCES claims.invoices(id)
);

CREATE INDEX IF NOT EXISTS index_claims_supporting_documents_on_invoice_id
  ON claims.supporting_documents (invoice_id);

-- Optional: prevent duplicate uploads of same blob/key under the same invoice
CREATE UNIQUE INDEX IF NOT EXISTS uniq_supporting_documents_invoice_storage_key
  ON claims.supporting_documents (invoice_id, storage_key);



-- 
-- revision_requests
--
CREATE TABLE IF NOT EXISTS claims.admin_revision_requests (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,
  revreq_seqno       integer NOT NULL,

  requester_id uuid NOT NULL,   -- admin user (public.users.id)
  status character varying NOT NULL DEFAULT 'OPEN',

  request_text  text NOT NULL,
  response_text text NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,
  closed_at  timestamp(6) without time zone NULL,

  CONSTRAINT revision_requests_pkey PRIMARY KEY (id),

  CONSTRAINT fk_revision_requests_invoice_version
    FOREIGN KEY (invoice_version_id) REFERENCES claims.invoice_versions(id),

  CONSTRAINT fk_revision_requests_requester
    FOREIGN KEY (requester_id) REFERENCES public.users(id),

  CONSTRAINT revision_requests_status_chk
    CHECK (status IN ('OPEN', 'CLOSED')),

  CONSTRAINT revision_requests_seqno_chk
    CHECK (revreq_seqno >= 1),

  CONSTRAINT revision_requests_version_seqno_uniq
    UNIQUE (invoice_version_id, revreq_seqno)
);

CREATE INDEX IF NOT EXISTS index_claims_revision_requests_on_invoice_version_id
  ON claims.admin_revision_requests (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_claims_revision_requests_on_requester_id
  ON claims.admin_revision_requests (requester_id);

CREATE INDEX IF NOT EXISTS index_claims_revision_requests_on_status
  ON claims.admin_revision_requests (status);




--
-- Validationgenai_config
-- Singleton-style editable GenAI config, like env/config in table form for system admins.
--
CREATE TABLE IF NOT EXISTS claims.validationgenai_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  system_record character varying NULL,
  classifier_system_record character varying NULL,
  user_record0 character varying NULL,
  admin_advice_intro character varying NULL,
  admin_advice_closing character varying NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT validationgenai_config_pkey PRIMARY KEY (id)
);


--
-- Validationgenai_rulesets
--
CREATE TABLE IF NOT EXISTS claims.validationgenai_rulesets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_upgrade_type_id uuid NOT NULL,
  ruleset_shortname character varying NOT NULL,
  user_record1 character varying NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT validationgenai_rulesets_pkey PRIMARY KEY (id),

  CONSTRAINT fk_validationgenai_rulesets_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  -- lets you have multiple versions over time under the same shortname
  CONSTRAINT validationgenai_rulesets_shortname_created_uniq
    UNIQUE (ruleset_shortname, created_at)
);

CREATE INDEX IF NOT EXISTS index_validationgenai_rulesets_on_shortname
  ON claims.validationgenai_rulesets (ruleset_shortname);

CREATE INDEX IF NOT EXISTS index_validationgenai_rulesets_on_upgrade_type_id
  ON claims.validationgenai_rulesets (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS index_validationgenai_rulesets_on_created_at
  ON claims.validationgenai_rulesets (created_at);


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
  evidence_text text NULL,
  classifier_notes text NULL,
  classifier_raw_json jsonb NULL,

  validationgenai_ruleset_id uuid NULL,
  genai_raw_json jsonb NULL,
  genai_overall_confidence smallint NULL,
  genai_all_rulechecks_pass_flag boolean NULL,
  genai_admin_advice text NULL,

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

  CONSTRAINT fk_invoice_version_upgrade_types_ruleset
    FOREIGN KEY (validationgenai_ruleset_id)
    REFERENCES claims.validationgenai_rulesets(id),

  CONSTRAINT invoice_version_upgrade_types_source_engine_chk
    CHECK (source_engine IN ('classifier','genai')),

  CONSTRAINT invoice_version_upgrade_types_call_status_chk
    CHECK (call_status IN ('classified','queued','in_progress','succeeded','failed','skipped')),

  CONSTRAINT invoice_version_upgrade_types_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT invoice_version_upgrade_types_genai_confidence_chk
    CHECK (
      genai_overall_confidence IS NULL
      OR genai_overall_confidence BETWEEN 0 AND 100
    ),

  CONSTRAINT invoice_version_upgrade_types_uniq
    UNIQUE (invoice_version_id, invoice_upgrade_type_id, source_engine)
);

CREATE INDEX IF NOT EXISTS idx_ivut_invoice_version
  ON claims.invoice_version_upgrade_types (invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_ivut_upgrade_type
  ON claims.invoice_version_upgrade_types (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS idx_ivut_ruleset
  ON claims.invoice_version_upgrade_types (validationgenai_ruleset_id);

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

  status text NOT NULL DEFAULT 'queued',  -- queued|running|succeeded|failed|partial

  total_files     integer NOT NULL DEFAULT 0,
  completed_files integer NOT NULL DEFAULT 0,
  failed_files    integer NOT NULL DEFAULT 0,

  messages jsonb NULL, -- array of strings, optional

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  completed_at timestamp(6) without time zone NULL,

  CONSTRAINT ingest_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ingest_runs_session
    FOREIGN KEY (session_id)
    REFERENCES claims.sessions(id)
    ON DELETE CASCADE,

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

CREATE INDEX IF NOT EXISTS idx_ingest_runs_status
  ON claims.ingest_runs (status);



-- ============================================================
-- ingest_step_runs
-- PURPOSE: Single table combining upload_runs + ocr_runs + genai_runs
-- DESIGN: Keep ALL former validation_runs fields (nullable as needed)
-- NOTE:
-- - session_id is REQUIRED so orphan/manual steps can always be filtered.
-- - status is authoritative lifecycle state for each step attempt.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ingest_step_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  -- Parent batch run (nullable so 1-off troubleshooting steps can exist)
  ingest_run_id uuid NULL,

  -- Session is ALWAYS known (even for orphans)
  session_id uuid NOT NULL,

  -- Target invoice version (always required)
  invoice_version_id uuid NOT NULL,

  -- GenAI subcall target. Null for upload/ocr/classifier/legacy genai summary rows.
  invoice_upgrade_type_id uuid NULL,

  -- Which step this attempt represents
  step_type text NOT NULL,  -- upload | ocr | classifier | genai | genai_common | genai_upgrade

  status character varying NOT NULL DEFAULT 'queued',

  -- failed states must provide error details
  error_text text NULL,

  -- unlike invoice_versions this is a per run record which can be multiple
  di_results_json  jsonb NULL,

  -- GENAI RUN FIELDS (kept from former validation_runs; now nullable)
  validationgenai_ruleset_id uuid NULL,

  -- unlike invoice_versions table this is a per run genAI artifacts (retention indefinite for now)
  genai_results_json  jsonb NULL,
  context_window_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT ingest_step_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_ingest_step_runs_ingest_run
    FOREIGN KEY (ingest_run_id)
    REFERENCES claims.ingest_runs(id)
    ON DELETE SET NULL,

  CONSTRAINT fk_ingest_step_runs_session
    FOREIGN KEY (session_id)
    REFERENCES claims.sessions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_step_runs_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT fk_ingest_step_runs_upgrade_type
    FOREIGN KEY (invoice_upgrade_type_id)
    REFERENCES claims.invoice_upgrade_types(id),

  CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN ('upload','ocr','classifier','genai','genai_common','genai_upgrade')),

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

  -- Only require ruleset_id when the step is a GenAI validation call.
  CONSTRAINT ingest_step_runs_ruleset_required_for_genai_chk
    CHECK (
      (step_type NOT IN ('genai','genai_common','genai_upgrade'))
      OR
      (validationgenai_ruleset_id IS NOT NULL)
    ),

  -- Only require upgrade type for the new typed GenAI calls.
  CONSTRAINT ingest_step_runs_upgrade_type_required_for_typed_genai_chk
    CHECK (
      (step_type NOT IN ('genai_common','genai_upgrade'))
      OR
      (invoice_upgrade_type_id IS NOT NULL)
    ),

  CONSTRAINT fk_ingest_step_runs_ruleset
    FOREIGN KEY (validationgenai_ruleset_id)
    REFERENCES claims.validationgenai_rulesets(id)
);

-- Batch run drill-down
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_ingest_run_id
  ON claims.ingest_step_runs (ingest_run_id, created_at DESC);

-- Session filtering (works for BOTH pipeline + orphan steps)
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_session_id
  ON claims.ingest_step_runs (session_id, created_at DESC);

-- Invoice-version drill-down
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_invoice_version_id
  ON claims.ingest_step_runs (invoice_version_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_invoice_version_step
  ON claims.ingest_step_runs (invoice_version_id, step_type, created_at DESC);

-- GenAI filtering
CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_ruleset_id
  ON claims.ingest_step_runs (validationgenai_ruleset_id);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_upgrade_type_id
  ON claims.ingest_step_runs (invoice_upgrade_type_id);

CREATE INDEX IF NOT EXISTS idx_ingest_step_runs_on_iv_upgrade_step
  ON claims.ingest_step_runs (invoice_version_id, invoice_upgrade_type_id, step_type, created_at DESC);



  --
  -- users_eligibilitycodes
  -- how we get the participant_id
  --
  CREATE TABLE IF NOT EXISTS claims.users_eligibilitycodes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  user_id uuid NOT NULL,

  eligibility_code character varying NOT NULL,

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
    CHECK (expires_at > applied_at)
);

CREATE INDEX IF NOT EXISTS index_claims_users_eligibilitycodes_on_user_id
  ON claims.users_eligibilitycodes (user_id);

CREATE INDEX IF NOT EXISTS index_claims_users_eligibilitycodes_on_expires_at
  ON claims.users_eligibilitycodes (expires_at);
