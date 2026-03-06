DROP SCHEMA IF EXISTS claims CASCADE;
CREATE SCHEMA claims;


--
-- sessions
--

CREATE TABLE IF NOT EXISTS claims.sessions (
  id            uuid NOT NULL DEFAULT gen_random_uuid(),

  contractor_id uuid NOT NULL,
  submitter_id  uuid NULL,

  status        character varying NOT NULL DEFAULT 'OPENBUTNOTSUBMITTED',

  created_at    timestamp(6) without time zone NOT NULL,
  updated_at    timestamp(6) without time zone NOT NULL,
  submitted_at  timestamp(6) without time zone NULL,

  CONSTRAINT sessions_pkey PRIMARY KEY (id),

  CONSTRAINT sessions_status_chk
    CHECK (status IN ('OPENBUTNOTSUBMITTED', 'OPENANDSUBMITTED', 'CLOSED')),

  CONSTRAINT sessions_submit_fields_chk
    CHECK (
      (status = 'OPENBUTNOTSUBMITTED' AND submitter_id IS NULL AND submitted_at IS NULL)
      OR
      (status IN ('OPENANDSUBMITTED', 'CLOSED') AND submitter_id IS NOT NULL AND submitted_at IS NOT NULL)
    ),

  CONSTRAINT fk_sessions_contractor
    FOREIGN KEY (contractor_id) REFERENCES public.contractors(id),

  CONSTRAINT fk_sessions_submitter
    FOREIGN KEY (submitter_id) REFERENCES public.users(id)
);

CREATE INDEX IF NOT EXISTS index_claims_sessions_on_contractor_id
  ON claims.sessions (contractor_id);

CREATE INDEX IF NOT EXISTS index_claims_sessions_on_status
  ON claims.sessions (status);



  --
  -- invoices
  --

CREATE TABLE IF NOT EXISTS claims.invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id     uuid NOT NULL,

  system_help_notes text NULL,

  status character varying NOT NULL DEFAULT 'session_not_submitted',
  status_updated_at timestamp(6) without time zone NULL,

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
  'genai_complete',   -- this also means the invoice is with the contractor in review.
  'admin_review_inbox',    -- this also means being actively reviewed. if admin finds a problem they send the status to the revision_required
  'contractor_revision_inbox',   -- the next state after this is typically back to the upload_in_progress. In thoery a phone call or supplement-upload could allow the state to go to admin_review_inbox
  'closed_success'
  'closed_reject'
)),

  CONSTRAINT fk_claims_invoices_session
    FOREIGN KEY (session_id) REFERENCES claims.sessions(id)

);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_status
  ON claims.invoices (status);

CREATE INDEX IF NOT EXISTS index_claims_invoices_on_session_id
  ON claims.invoices (session_id);



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
-- invoice_version_located_fields
--

CREATE TABLE IF NOT EXISTS claims.invoice_version_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,

  source_engine text NOT NULL,   -- 'code' | 'genai'
  field_key     text NOT NULL,

  line_number   integer NOT NULL DEFAULT 0,  

  value_type text NOT NULL,      -- 'text' | 'currency' | 'number' | 'date' | 'bool' | 'json'
  value_text text NULL,
  value_json jsonb NULL,         -- only used when value_type='json'
  normalized_value text NULL,

  confidence smallint NOT NULL DEFAULT 0,  -- 0..100

  page    integer NULL,
  polygon jsonb NULL,                        -- DI-style polygon array, or null

  evidence_text text NULL,
  evidence_hint text NULL,

  notes text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_version_located_fields_pkey PRIMARY KEY (id),

  CONSTRAINT fk_invoice_version_located_fields_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

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
      (value_text IS NULL AND value_json IS NULL)  -- allow “not found” rows
    ),

  CONSTRAINT invoice_version_located_fields_uniq
    UNIQUE (invoice_version_id, source_engine, field_key, line_number)
);

CREATE INDEX IF NOT EXISTS idx_ivlf_invoice_version
  ON claims.invoice_version_located_fields(invoice_version_id);

CREATE INDEX IF NOT EXISTS idx_ivlf_lookup
  ON claims.invoice_version_located_fields(invoice_version_id, field_key, line_number);

CREATE INDEX IF NOT EXISTS idx_ivlf_engine
  ON claims.invoice_version_located_fields(invoice_version_id, source_engine);


--
-- invoice_version_rulechecks
--

  CREATE TABLE IF NOT EXISTS claims.invoice_version_rulechecks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,

  source_engine text NOT NULL,   -- 'code' | 'genai'

  rule_number integer NOT NULL,
  rule_name   text NOT NULL,

  rule_pass_flag boolean NULL,   -- null = unknown / not evaluated
  confidence smallint NOT NULL DEFAULT 0,  -- 0..100

  expected_text text NULL,
  observed_text text NULL,

  calculation text NULL,
  tolerance_notes text NULL,

  evidence_text text NULL,
  evidence_hint text NULL,

  reason_and_likely_causes text NULL,

  notes text NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT invoice_version_rulechecks_pkey PRIMARY KEY (id),

  CONSTRAINT fk_invoice_version_rulechecks_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE,

  CONSTRAINT invoice_version_rulechecks_source_engine_chk
    CHECK (source_engine IN ('code','genai')),

  CONSTRAINT invoice_version_rulechecks_confidence_chk
    CHECK (confidence BETWEEN 0 AND 100),

  CONSTRAINT invoice_version_rulechecks_rule_number_chk
    CHECK (rule_number >= 0),

  CONSTRAINT invoice_version_rulechecks_uniq
    UNIQUE (invoice_version_id, source_engine, rule_number)
);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_invoice_version_id
  ON claims.invoice_version_rulechecks (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_invoice_version_rulechecks_on_invoice_version_id_se
  ON claims.invoice_version_rulechecks (invoice_version_id, source_engine);



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
    CHECK (status IN ('OPEN', 'RESOLVED', 'CLOSED')),

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
-- Validationgenai_rulesets
--
CREATE TABLE IF NOT EXISTS claims.validationgenai_rulesets (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  ruleset_shortname character varying NOT NULL,
  system_record character varying NULL,
  user_record1 character varying NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT validationgenai_rulesets_pkey PRIMARY KEY (id),

  -- lets you have multiple versions over time under the same shortname
  CONSTRAINT validationgenai_rulesets_shortname_created_uniq
    UNIQUE (ruleset_shortname, created_at)
);

CREATE INDEX IF NOT EXISTS index_validationgenai_rulesets_on_shortname
  ON claims.validationgenai_rulesets (ruleset_shortname);

CREATE INDEX IF NOT EXISTS index_validationgenai_rulesets_on_created_at
  ON claims.validationgenai_rulesets (created_at);




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
-- - ok is NULL for queued/in-progress, TRUE for success, FALSE for failure.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.ingest_step_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  -- Parent batch run (nullable so 1-off troubleshooting steps can exist)
  ingest_run_id uuid NULL,

  -- Session is ALWAYS known (even for orphans)
  session_id uuid NOT NULL,

  -- Target invoice version (always required)
  invoice_version_id uuid NOT NULL,

  -- Which step this attempt represents
  step_type text NOT NULL,  -- 'ocr' | 'genai'

  -- Generic outcome:
  -- NULL = queued/in_progress (no final outcome yet)
  -- TRUE = succeeded
  -- FALSE = failed (must have error_text)
  ok boolean NULL,
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

  CONSTRAINT ingest_step_runs_step_type_chk
    CHECK (step_type IN ('ocr','genai')),

  -- Allow queued/in-progress (ok NULL), success (ok TRUE), failure (ok FALSE + error_text)
  CONSTRAINT ingest_step_runs_ok_error_chk
    CHECK (
      (ok IS NULL AND error_text IS NULL)
      OR
      (ok = true AND error_text IS NULL)
      OR
      (ok = false AND error_text IS NOT NULL)
    ),

  -- Only require ruleset_id when step_type='genai'
  CONSTRAINT ingest_step_runs_ruleset_required_for_genai_chk
    CHECK (
      (step_type <> 'genai')
      OR
      (validationgenai_ruleset_id IS NOT NULL)
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
