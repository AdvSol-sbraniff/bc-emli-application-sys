CREATE OR REPLACE VIEW claims.v_current_invoice_versions AS
SELECT DISTINCT ON (iv.invoice_id)
  i.session_id,
  i.status AS invoice_status,
  iv.*,
  i.upgrade_type_id
FROM claims.invoices i
JOIN claims.invoice_versions iv
  ON iv.invoice_id = i.id
ORDER BY
  iv.invoice_id,
  iv.invoice_versionno DESC,
  iv.updated_at DESC,
  iv.id DESC;



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
  i.status_updated_at AS invoice_status_updated_at,
  i.system_help_notes AS system_help_notes,
  i.created_at        AS invoice_created_at,
  i.updated_at        AS invoice_updated_at,

  -- -------------------------
  -- session (base)
  -- -------------------------
  i.contractor_id     AS contractor_id,
  i.submitter_id      AS submitter_id,
  i.submitted_at      AS session_submitted_at,
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

  -- -------------------------
  -- upgrade type / domain
  -- -------------------------
  i.upgrade_type_id   AS upgrade_type_id,
  ut.code             AS upgrade_type_code,
  ut.name             AS upgrade_type_name,

  civut.latest_detected_upgrade_type_keys AS latest_detected_upgrade_type_keys,
  civut.latest_detected_upgrade_types_json AS latest_detected_upgrade_types_json,

  i.submitted_at      AS invoice_submitted_at

FROM claims.invoices i
JOIN claims.sessions s
  ON s.id = i.session_id
JOIN public.contractors c
  ON c.id = i.contractor_id
LEFT JOIN public.permit_classifications ut
  ON ut.id = i.upgrade_type_id
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

/***********

old view def will keep for reference while testing, but will be deleted before merging to main

CREATE OR REPLACE VIEW claims.v_invoice_grid AS
SELECT
  -- -------------------------
  -- invoice (base)
  -- -------------------------
  i.id                AS invoice_id,
  i.session_id        AS session_id,
  i.status            AS invoice_status,
  i.status_updated_at AS invoice_status_updated_at,
  i.system_help_notes AS system_help_notes,
  i.created_at        AS invoice_created_at,
  i.updated_at        AS invoice_updated_at,

  -- -------------------------
  -- session (base)
  -- -------------------------
  s.contractor_id     AS contractor_id,
  s.submitter_id      AS submitter_id,
  s.status            AS session_status,
  s.submitted_at      AS session_submitted_at,
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
  civ.genai_overall_confidence        AS latest_genai_overall_confidence

FROM claims.invoices i
JOIN claims.sessions s
  ON s.id = i.session_id
JOIN public.contractors c
  ON c.id = s.contractor_id
LEFT JOIN public.users cu
  ON cu.id = c.contact_id
LEFT JOIN public.users u
  ON u.id = s.submitter_id
LEFT JOIN claims.v_current_invoice_versions civ
  ON civ.invoice_id = i.id;

*************************/


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
  u.role                                 AS role,
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
  uec.updated_at                         AS users_eligibilitycode_updated_at

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
  NULL::text      AS session_status,
  s.created_at    AS session_created_at,
  s.updated_at    AS session_updated_at,
  i.submitted_at  AS session_submitted_at,

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
  iv.di_ocr_billing_address       AS di_ocr_billing_address,
  iv.di_ocr_billing_address_page  AS di_ocr_billing_address_page,
  iv.di_ocr_billing_address_polygon AS di_ocr_billing_address_polygon,
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
  rr.invoice_version_id AS revision_request_invoice_version_id,
  rr.revreq_seqno  AS revision_request_seqno,
  rr.requester_id  AS revision_request_requester_id,
  rr.status        AS revision_request_status,
  rr.request_text  AS revision_request_text,
  rr.response_text AS revision_request_response_text,
  rr.created_at    AS revision_request_created_at,
  rr.updated_at    AS revision_request_updated_at,
  rr.closed_at     AS revision_request_closed_at

FROM claims.invoice_versions iv
JOIN claims.invoices i
  ON i.id = iv.invoice_id
JOIN claims.sessions s
  ON s.id = i.session_id
LEFT JOIN claims.admin_revision_requests rr
  ON rr.invoice_version_id = iv.id;  


  
