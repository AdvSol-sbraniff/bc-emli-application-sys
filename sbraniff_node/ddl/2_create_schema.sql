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



  -- note the participant_id is only figured out AFTER we ocr the pdf and get the eligibility code and then 
  -- lookup up the unique matching users_eligibilitycodes record and then take the users_eligibilitycodes.user_id
  --
  -- invoices
  --
CREATE TABLE IF NOT EXISTS claims.invoices (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  session_id     uuid NOT NULL,

  -- contractors can add help notes at the invoice (parent) level
  system_help_notes text NULL,

  -- cache pointer (always = max version); add FK later after invoice_versions exists
  -- current_invoice_version_id uuid NULL,

  status character varying NOT NULL DEFAULT 'session_not_submitted',
  status_updated_at timestamp(6) without time zone NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT invoices_pkey PRIMARY KEY (id),

CONSTRAINT invoices_status_chk
CHECK (status IN (
  'draft',

  'upload_in_progress',
  'upload_failed',
  'ocr_in_progress',
  'ocr_failed',
  'validation_in_progress',
  'validation_failed',

  'awaiting_contractor_submit',
  'awaiting_admin_review',
  'contractor_revision_required',
  'closed'
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

  -- Azure DI raw output (retention indefinite for now)
  di_raw_json jsonb NULL,
  di_page_map jsonb NULL,

  -- Minimal canonical header OCR fields... ie in this table
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
  --
  --
  -- in code i need to insert a record for these code located fields...
  --
  --
  --

  -- fields found via regex on the ocr data like result.content for example
  -- regex_eligibility_code character varying NULL,
  -- postregex_ec_lookup_participantname character varying NULL,
  --  postregex_ec_lookup_participantaddress character varying NULL,

-- at this point in time i have the firstclass (aka di firstclass) fields in non- 3nf so this table is SOLELY for secondclass fields
-- as such it currently makes no sense to have the sourceengine = di since this di can only return first class fields by definition
CREATE TABLE IF NOT EXISTS claims.invoice_version_located_fields (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  invoice_version_id uuid NOT NULL,

  source_engine text NOT NULL,   -- 'code' | 'genai' | 'di'
  field_key     text NOT NULL,

  line_number   integer NULL,  

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
    CHECK (source_engine IN ('code','genai','di')),


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
  -- lineitems (firstclass di fields only)
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



--
-- validation_runs
--
CREATE TABLE IF NOT EXISTS claims.validation_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_version_id uuid NOT NULL,
  validationgenai_ruleset_id uuid NOT NULL,
  -- genAI artifacts (retention indefinite for now)
  genai_results_json  jsonb NULL,
  context_window_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT validation_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_validation_runs_invoice_version
    FOREIGN KEY (invoice_version_id) REFERENCES claims.invoice_versions(id),

  CONSTRAINT fk_validation_runs_ruleset
    FOREIGN KEY (validationgenai_ruleset_id) REFERENCES claims.validationgenai_rulesets(id)

);

CREATE INDEX IF NOT EXISTS index_claims_validation_runs_on_invoice_version_id
  ON claims.validation_runs (invoice_version_id);

CREATE INDEX IF NOT EXISTS index_claims_validation_runs_on_ruleset_id
  ON claims.validation_runs (validationgenai_ruleset_id);




  --
-- upload_runs
-- Tracks attempts to upload/store the PDF blob for a given invoice_version.
--
CREATE TABLE IF NOT EXISTS claims.upload_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_version_id uuid NOT NULL,
  error_text text NULL,
  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,

  CONSTRAINT upload_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_upload_runs_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE

);

CREATE INDEX IF NOT EXISTS index_claims_upload_runs_on_invoice_version_id
  ON claims.upload_runs (invoice_version_id);



  --
-- di_runs
-- Tracks attempts to run Azure Document Intelligence for a given invoice_version.
--
CREATE TABLE IF NOT EXISTS claims.di_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_version_id uuid NOT NULL,
  error_text text NULL,
  created_at timestamp(6) without time zone NOT NULL,
  updated_at timestamp(6) without time zone NOT NULL,


  CONSTRAINT di_runs_pkey PRIMARY KEY (id),

  CONSTRAINT fk_di_runs_invoice_version
    FOREIGN KEY (invoice_version_id)
    REFERENCES claims.invoice_versions(id)
    ON DELETE CASCADE

);

CREATE INDEX IF NOT EXISTS index_claims_di_runs_on_invoice_version_id
  ON claims.di_runs (invoice_version_id);




  --
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
