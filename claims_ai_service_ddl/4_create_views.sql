-- Claims AI views and reporting read models
-- Replaces archived 6_views.sql and 7_reporting_views.sql.

DROP VIEW IF EXISTS claims.v_reporting_invoice_business;
DROP VIEW IF EXISTS claims.v_revision_request_grid;
DROP VIEW IF EXISTS claims.v_invoice_grid;
DROP VIEW IF EXISTS claims.v_current_invoice_versions;

CREATE OR REPLACE VIEW claims.v_current_invoice_versions AS
SELECT DISTINCT ON (iv.invoice_id)
  i.session_id,
  i.status AS invoice_status,
  i.status_subtype AS invoice_status_subtype,
  iv.id,
  iv.invoice_id,
  iv.invoice_versionno,
  iv.storage_provider,
  iv.storage_key,
  iv.original_filename,
  iv.content_type,
  iv.byte_size,
  iv.sha256,
  iv.genai_raw_json,
  iv.genai_overall_confidence,
  iv.genai_result,
  iv.genai_admin_advice,
  iv.di_raw_json,
  iv.di_page_map,
  iv.di_ocr_invoice_id,
  iv.di_ocr_invoice_id_page,
  iv.di_ocr_invoice_id_polygon,
  iv.di_ocr_invoice_date,
  iv.di_ocr_invoice_date_page,
  iv.di_ocr_invoice_date_polygon,
  iv.di_ocr_vendor_name,
  iv.di_ocr_vendor_name_page,
  iv.di_ocr_vendor_name_polygon,
  iv.di_ocr_vendor_address,
  iv.di_ocr_vendor_address_page,
  iv.di_ocr_vendor_address_polygon,
  iv.di_ocr_customer_name,
  iv.di_ocr_customer_name_page,
  iv.di_ocr_customer_name_polygon,
  iv.di_ocr_customer_address,
  iv.di_ocr_customer_address_page,
  iv.di_ocr_customer_address_polygon,
  iv.di_ocr_customer_address_recipient,
  iv.di_ocr_customer_address_recipient_page,
  iv.di_ocr_customer_address_recipient_polygon,
  iv.di_ocr_service_address,
  iv.di_ocr_service_address_page,
  iv.di_ocr_service_address_polygon,
  iv.di_ocr_service_address_recipient,
  iv.di_ocr_service_address_recipient_page,
  iv.di_ocr_service_address_recipient_polygon,
  iv.di_ocr_billing_address,
  iv.di_ocr_billing_address_page,
  iv.di_ocr_billing_address_polygon,
  iv.di_ocr_billing_address_recipient,
  iv.di_ocr_billing_address_recipient_page,
  iv.di_ocr_billing_address_recipient_polygon,
  iv.di_ocr_sub_total,
  iv.di_ocr_sub_total_page,
  iv.di_ocr_sub_total_polygon,
  iv.di_ocr_total_tax,
  iv.di_ocr_total_tax_page,
  iv.di_ocr_total_tax_polygon,
  iv.di_ocr_invoice_total,
  iv.di_ocr_invoice_total_page,
  iv.di_ocr_invoice_total_polygon,
  iv.di_ocr_amount_due,
  iv.di_ocr_amount_due_page,
  iv.di_ocr_amount_due_polygon,
  iv.ahri_product_id,
  iv.created_at,
  iv.updated_at,
  iv.neea_product_id,
  iv.awhp_product_id,
  iv.ohpa_product_id,
  iv.users_eligibilitycode_id,
  iv.participant_user_id
FROM claims.invoices i
JOIN claims.invoice_versions iv
  ON iv.invoice_id = i.id
ORDER BY
  iv.invoice_id,
  iv.invoice_versionno DESC,
  iv.updated_at DESC,
  iv.id DESC;


CREATE OR REPLACE VIEW claims.v_current_ahri_products AS
SELECT
  hp.*,
  src.id AS ahri_source_id,
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
FROM claims.ahri_products hp
JOIN claims.ahri_import_runs run
  ON run.id = hp.import_run_id
JOIN claims.ahri_sources src
  ON src.id = run.ahri_source_id
JOIN (
  SELECT DISTINCT ON (ahri_source_id)
    id,
    ahri_source_id
  FROM claims.ahri_import_runs
  WHERE status = 'succeeded'
  ORDER BY ahri_source_id, completed_at DESC NULLS LAST, started_at DESC, id DESC
) latest
  ON latest.id = run.id;


CREATE OR REPLACE VIEW claims.v_current_neea_products AS
SELECT
  p.*,
  src.id AS neea_source_id,
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
FROM claims.neea_products p
JOIN claims.neea_import_runs run
  ON run.id = p.import_run_id
JOIN claims.neea_sources src
  ON src.id = run.neea_source_id
JOIN (
  SELECT DISTINCT ON (neea_source_id)
    id,
    neea_source_id
  FROM claims.neea_import_runs
  WHERE status = 'succeeded'
  ORDER BY neea_source_id, completed_at DESC NULLS LAST, started_at DESC, id DESC
) latest
  ON latest.id = run.id;


CREATE OR REPLACE VIEW claims.v_current_awhp_products AS
SELECT
  p.*,
  src.id AS awhp_source_id,
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
FROM claims.awhp_products p
JOIN claims.awhp_import_runs run
  ON run.id = p.import_run_id
JOIN claims.awhp_sources src
  ON src.id = run.awhp_source_id
JOIN (
  SELECT DISTINCT ON (awhp_source_id)
    id,
    awhp_source_id
  FROM claims.awhp_import_runs
  WHERE status = 'succeeded'
  ORDER BY awhp_source_id, completed_at DESC NULLS LAST, started_at DESC, id DESC
) latest
  ON latest.id = run.id;


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



-- View: sessions + contractor core fields
-- Naming: underscores (per your convention)

CREATE OR REPLACE VIEW claims.v_sessions_with_contractors AS
SELECT
  s.*,
  sc.contractor_ids,
  sc.submitter_ids,
  sc.representative_contractor_id AS contractor_id,
  sc.representative_submitter_id AS submitter_id,
  sc.representative_submitted_at AS submitted_at,

  c.business_name      AS contractor_business_name,
  c.number             AS contractor_number,
  c.email              AS contractor_email,
  c.phone_number       AS contractor_phone_number,
  c.cellphone_number   AS contractor_cellphone_number,
  c.city               AS contractor_city,
  c.postal_code        AS contractor_postal_code,
  c.onboarded          AS contractor_onboarded
FROM claims.sessions s
LEFT JOIN LATERAL (
  SELECT
    COALESCE(array_agg(DISTINCT i.contractor_id), ARRAY[]::uuid[]) AS contractor_ids,
    COALESCE(array_agg(DISTINCT i.submitter_id) FILTER (WHERE i.submitter_id IS NOT NULL), ARRAY[]::uuid[]) AS submitter_ids,
    (array_agg(i.contractor_id ORDER BY i.created_at, i.id))[1] AS representative_contractor_id,
    (array_agg(i.submitter_id ORDER BY i.created_at, i.id) FILTER (WHERE i.submitter_id IS NOT NULL))[1] AS representative_submitter_id,
    (array_agg(i.submitted_at ORDER BY i.created_at, i.id) FILTER (WHERE i.submitted_at IS NOT NULL))[1] AS representative_submitted_at
  FROM claims.invoices i
  WHERE i.session_id = s.id
) sc
  ON TRUE
LEFT JOIN public.contractors c
  ON c.id = sc.representative_contractor_id;

-- ============================================================
-- INVOICE GRID (admin read model)
-- one row per claims.invoices row
-- pulls "latest_*" triage fields from v_current_invoice_versions
-- includes contractor + submitter info for searching
-- ============================================================


CREATE OR REPLACE VIEW claims.v_invoice_grid AS
SELECT
  -- -------------------------
  -- invoice (base)
  -- -------------------------
  i.id                AS invoice_id,
  s.id                AS session_id,
  i.status            AS invoice_status,
  i.status_subtype    AS invoice_status_subtype,
  i.status_updated_at AS invoice_status_updated_at,
  i.system_help_notes AS system_help_notes,
  i.created_at        AS invoice_created_at,
  i.updated_at        AS invoice_updated_at,

  -- -------------------------
  -- session (base)
  -- -------------------------
  i.contractor_id     AS contractor_id,
  i.submitter_id      AS submitter_id,
  i.submitted_at      AS session_submitted_at, -- deprecated compatibility alias; use invoice_submitted_at
  s.created_at        AS session_created_at,
  s.updated_at        AS session_updated_at,

  -- -------------------------
  -- contractor (grid/search)
  -- -------------------------
  c.business_name     AS contractor_business_name,
  c.number            AS contractor_number,
  c.email             AS contractor_email,
  c.phone_number      AS contractor_phone_number,
  c.cellphone_number  AS contractor_cellphone_number,
  c.website           AS contractor_website,
  c.street_address    AS contractor_street_address,
  c.city              AS contractor_city,
  c.postal_code       AS contractor_postal_code,

  -- Optional: contractor primary contact (users.id = contractors.contact_id)
  cu.email            AS contractor_contact_email,
  NULLIF(TRIM(CONCAT_WS(' ', cu.first_name, cu.last_name)), '') AS contractor_contact_name,

  -- -------------------------
  -- submitter (grid/search)
  -- -------------------------
  u.email             AS submitter_email,
  NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), '') AS submitter_name,

  -- -------------------------
  -- latest invoice_version triage fields
  -- -------------------------
  civ.id                              AS latest_invoice_version_id,
  civ.invoice_versionno               AS latest_invoice_versionno,
  civ.updated_at                      AS latest_invoice_version_updated_at,

  civ.original_filename               AS latest_original_filename,

  civ.di_ocr_invoice_total            AS latest_di_ocr_invoice_total,
  civ.di_ocr_invoice_date             AS latest_di_ocr_invoice_date,
  civ.di_ocr_vendor_name              AS latest_di_ocr_vendor_name,
  civ.di_ocr_invoice_id               AS latest_di_ocr_invoice_id,

  civ.genai_result  AS latest_genai_result,
  civ.genai_overall_confidence        AS latest_genai_overall_confidence,

  civut.latest_detected_upgrade_type_keys AS latest_detected_upgrade_type_keys,
  civut.latest_detected_upgrade_types_json AS latest_detected_upgrade_types_json,

  i.submitted_at      AS invoice_submitted_at

FROM claims.invoices i
JOIN claims.sessions s
  ON s.id = i.session_id
JOIN public.contractors c
  ON c.id = i.contractor_id
LEFT JOIN public.users cu
  ON cu.id = c.contact_id
LEFT JOIN public.users u
  ON u.id = i.submitter_id
LEFT JOIN claims.v_current_invoice_versions civ
  ON civ.invoice_id = i.id
LEFT JOIN LATERAL (
  SELECT
    COALESCE(array_agg(x.upgrade_type_key ORDER BY x.upgrade_type_key), ARRAY[]::text[]) AS latest_detected_upgrade_type_keys,
    COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'upgrade_type_key', x.upgrade_type_key,
          'description', x.description,
          'confidence', x.confidence
        )
        ORDER BY x.upgrade_type_key
      ),
      '[]'::jsonb
    ) AS latest_detected_upgrade_types_json
  FROM (
    SELECT DISTINCT ON (iut.upgrade_type_key)
      iut.upgrade_type_key,
      iut.description,
      ivut.confidence
    FROM claims.invoice_version_upgrade_types ivut
    JOIN claims.invoice_upgrade_types iut
      ON iut.id = ivut.invoice_upgrade_type_id
    WHERE ivut.invoice_version_id = civ.id
      AND ivut.source_engine = 'classifier'
    ORDER BY iut.upgrade_type_key, ivut.created_at DESC, ivut.confidence DESC
  ) x
) civut
  ON TRUE;

DROP VIEW IF EXISTS claims.v_user_eligibilitycodes;

CREATE OR REPLACE VIEW claims.v_user_eligibilitycodes AS
SELECT
  -- ============================================================
  -- SECTION 01 — public.users
  -- ============================================================
  u.id                                   AS user_id,
  u.email                                AS email,
  u.organization                         AS organization,
  u.certified                            AS certified,
  u.encrypted_password                   AS encrypted_password,
  u.reset_password_token                 AS reset_password_token,
  u.reset_password_sent_at               AS reset_password_sent_at,
  u.remember_created_at                  AS remember_created_at,
  u.confirmation_token                   AS confirmation_token,
  u.confirmed_at                         AS confirmed_at,
  u.confirmation_sent_at                 AS confirmation_sent_at,
  u.created_at                           AS user_created_at,
  u.updated_at                           AS user_updated_at,
  u.role::text                           AS role,
  u.first_name                           AS first_name,
  u.last_name                            AS last_name,
  u.invitation_token                     AS invitation_token,
  u.invitation_created_at                AS invitation_created_at,
  u.invitation_sent_at                   AS invitation_sent_at,
  u.invitation_accepted_at               AS invitation_accepted_at,
  u.invitation_limit                     AS invitation_limit,
  u.invited_by_type                      AS invited_by_type,
  u.invited_by_id                        AS invited_by_id,
  u.invitations_count                    AS invitations_count,
  u.omniauth_provider                    AS omniauth_provider,
  u.omniauth_uid                         AS omniauth_uid,
  u.discarded_at                         AS discarded_at,
  u.sign_in_count                        AS sign_in_count,
  u.current_sign_in_at                   AS current_sign_in_at,
  u.last_sign_in_at                      AS last_sign_in_at,
  u.unconfirmed_email                    AS unconfirmed_email,
  u.omniauth_email                       AS omniauth_email,
  u.omniauth_username                    AS omniauth_username,
  u.reviewed                             AS reviewed,

  -- ============================================================
  -- SECTION 02 — claims.users_eligibilitycodes
  -- ============================================================
  uec.id                                 AS users_eligibilitycode_id,
  uec.user_id                            AS eligibilitycode_user_id,
  uec.eligibility_code                   AS eligibility_code,
  uec.applied_at                         AS applied_at,
  uec.approved_at                        AS approved_at,
  uec.expires_at                         AS expires_at,
  uec.created_at                         AS users_eligibilitycode_created_at,
  uec.updated_at                         AS users_eligibilitycode_updated_at,
  uec.income_level                       AS income_level

FROM public.users u
LEFT JOIN claims.users_eligibilitycodes uec
  ON uec.user_id = u.id;



CREATE OR REPLACE VIEW claims.v_revision_request_grid AS
SELECT
  -- =========================================================
  -- session
  -- =========================================================
  s.id            AS session_id,
  i.contractor_id AS session_contractor_id,
  i.submitter_id  AS session_submitter_id,
  NULL::text      AS session_status,       -- deprecated compatibility alias; sessions are grouping-only
  s.created_at    AS session_created_at,
  s.updated_at    AS session_updated_at,
  i.submitted_at  AS session_submitted_at, -- deprecated compatibility alias; use invoice_submitted_at

  -- =========================================================
  -- invoice
  -- =========================================================
  i.id                AS invoice_id,
  i.session_id        AS invoice_session_id,
  i.contractor_id     AS invoice_contractor_id,
  i.submitter_id      AS invoice_submitter_id,
  i.status            AS invoice_status,
  i.status_updated_at AS invoice_status_updated_at,
  i.system_help_notes AS invoice_system_help_notes,
  i.submitted_at      AS invoice_submitted_at,
  i.created_at        AS invoice_created_at,
  i.updated_at        AS invoice_updated_at,

  -- =========================================================
  -- invoice version
  -- =========================================================
  iv.id                           AS invoice_version_id,
  iv.invoice_id                   AS invoice_version_invoice_id,
  iv.invoice_versionno            AS invoice_versionno,
  iv.storage_provider             AS invoice_version_storage_provider,
  iv.storage_key                  AS invoice_version_storage_key,
  iv.original_filename            AS invoice_version_original_filename,
  iv.content_type                 AS invoice_version_content_type,
  iv.byte_size                    AS invoice_version_byte_size,
  iv.sha256                       AS invoice_version_sha256,
  iv.genai_raw_json               AS invoice_version_genai_raw_json,
  iv.genai_overall_confidence     AS invoice_version_genai_overall_confidence,
  iv.genai_result AS invoice_version_genai_result,
  iv.genai_admin_advice           AS invoice_version_genai_admin_advice,
  iv.di_raw_json                  AS invoice_version_di_raw_json,
  iv.di_page_map                  AS invoice_version_di_page_map,
  iv.di_ocr_invoice_id            AS di_ocr_invoice_id,
  iv.di_ocr_invoice_id_page       AS di_ocr_invoice_id_page,
  iv.di_ocr_invoice_id_polygon    AS di_ocr_invoice_id_polygon,
  iv.di_ocr_invoice_date          AS di_ocr_invoice_date,
  iv.di_ocr_invoice_date_page     AS di_ocr_invoice_date_page,
  iv.di_ocr_invoice_date_polygon  AS di_ocr_invoice_date_polygon,
  iv.di_ocr_vendor_name           AS di_ocr_vendor_name,
  iv.di_ocr_vendor_name_page      AS di_ocr_vendor_name_page,
  iv.di_ocr_vendor_name_polygon   AS di_ocr_vendor_name_polygon,
  iv.di_ocr_vendor_address        AS di_ocr_vendor_address,
  iv.di_ocr_vendor_address_page   AS di_ocr_vendor_address_page,
  iv.di_ocr_vendor_address_polygon AS di_ocr_vendor_address_polygon,
  iv.di_ocr_customer_name         AS di_ocr_customer_name,
  iv.di_ocr_customer_name_page    AS di_ocr_customer_name_page,
  iv.di_ocr_customer_name_polygon AS di_ocr_customer_name_polygon,
  iv.di_ocr_customer_address      AS di_ocr_customer_address,
  iv.di_ocr_customer_address_page AS di_ocr_customer_address_page,
  iv.di_ocr_customer_address_polygon AS di_ocr_customer_address_polygon,
  iv.di_ocr_customer_address_recipient AS di_ocr_customer_address_recipient,
  iv.di_ocr_customer_address_recipient_page AS di_ocr_customer_address_recipient_page,
  iv.di_ocr_customer_address_recipient_polygon AS di_ocr_customer_address_recipient_polygon,
  iv.di_ocr_service_address       AS di_ocr_service_address,
  iv.di_ocr_service_address_page  AS di_ocr_service_address_page,
  iv.di_ocr_service_address_polygon AS di_ocr_service_address_polygon,
  iv.di_ocr_service_address_recipient AS di_ocr_service_address_recipient,
  iv.di_ocr_service_address_recipient_page AS di_ocr_service_address_recipient_page,
  iv.di_ocr_service_address_recipient_polygon AS di_ocr_service_address_recipient_polygon,
  iv.di_ocr_billing_address       AS di_ocr_billing_address,
  iv.di_ocr_billing_address_page  AS di_ocr_billing_address_page,
  iv.di_ocr_billing_address_polygon AS di_ocr_billing_address_polygon,
  iv.di_ocr_billing_address_recipient AS di_ocr_billing_address_recipient,
  iv.di_ocr_billing_address_recipient_page AS di_ocr_billing_address_recipient_page,
  iv.di_ocr_billing_address_recipient_polygon AS di_ocr_billing_address_recipient_polygon,
  iv.di_ocr_sub_total             AS di_ocr_sub_total,
  iv.di_ocr_sub_total_page        AS di_ocr_sub_total_page,
  iv.di_ocr_sub_total_polygon     AS di_ocr_sub_total_polygon,
  iv.di_ocr_total_tax             AS di_ocr_total_tax,
  iv.di_ocr_total_tax_page        AS di_ocr_total_tax_page,
  iv.di_ocr_total_tax_polygon     AS di_ocr_total_tax_polygon,
  iv.di_ocr_invoice_total         AS di_ocr_invoice_total,
  iv.di_ocr_invoice_total_page    AS di_ocr_invoice_total_page,
  iv.di_ocr_invoice_total_polygon AS di_ocr_invoice_total_polygon,
  iv.di_ocr_amount_due            AS di_ocr_amount_due,
  iv.di_ocr_amount_due_page       AS di_ocr_amount_due_page,
  iv.di_ocr_amount_due_polygon    AS di_ocr_amount_due_polygon,
  iv.created_at                   AS invoice_version_created_at,
  iv.updated_at                   AS invoice_version_updated_at,

  -- =========================================================
  -- admin revision request (LEFT JOIN)
  -- =========================================================
  rr.id            AS revision_request_id,
  rr.invoice_id    AS revision_request_invoice_id,
  rr.invoice_version_id AS revision_request_invoice_version_id,
  rr.revreq_seqno  AS revision_request_seqno,
  rr.requester_id  AS revision_request_requester_id,
  rr.message_type  AS revision_request_message_type,
  rr.request_text  AS revision_request_text,
  rr.created_at    AS revision_request_created_at,
  rr.updated_at    AS revision_request_updated_at

FROM claims.admin_revision_requests rr
JOIN claims.invoices i
  ON i.id = rr.invoice_id
JOIN claims.sessions s
  ON s.id = i.session_id
LEFT JOIN claims.invoice_versions iv
  ON iv.id = rr.invoice_version_id;

-- Reporting read models and supporting indexes

-- Reporting read models for business-facing invoice analytics

DROP VIEW IF EXISTS claims.v_reporting_invoice_business;

CREATE OR REPLACE VIEW claims.v_reporting_invoice_business AS
SELECT
  ig.invoice_id,
  ig.session_id,
  ig.contractor_id,
  ig.contractor_business_name,
  ig.contractor_number,
  ig.invoice_status,
  ig.invoice_created_at,
  ig.invoice_updated_at,
  ig.latest_di_ocr_invoice_date AS ocr_invoice_date,
  ig.latest_di_ocr_invoice_id AS ocr_invoice_number,
  ig.latest_invoice_version_id,
  ig.latest_invoice_versionno,
  ig.latest_original_filename,
  ig.latest_di_ocr_invoice_total::numeric(12,2) AS invoice_total_cad,
  ig.latest_detected_upgrade_type_keys,
  ig.latest_detected_upgrade_types_json
FROM claims.v_invoice_grid ig
WHERE ig.invoice_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_invoices_on_created_at
  ON claims.invoices (created_at);

CREATE INDEX IF NOT EXISTS idx_invoices_on_status_created
  ON claims.invoices (status, created_at);
