CREATE OR REPLACE VIEW claims.v_current_invoice_versions AS
SELECT DISTINCT ON (iv.invoice_id)
  i.session_id,
  i.status AS invoice_status,
  iv.*
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

DROP VIEW IF EXISTS claims.v_sessions_with_contractors;

CREATE VIEW claims.v_sessions_with_contractors AS
SELECT
  s.*,

  -- contractor “denormalized” fields for grids/search
  c.business_name      AS contractor_business_name,
  c.number             AS contractor_number,
  c.email              AS contractor_email,
  c.phone_number       AS contractor_phone_number,
  c.cellphone_number   AS contractor_cellphone_number,
  c.city               AS contractor_city,
  c.postal_code        AS contractor_postal_code,
  c.onboarded          AS contractor_onboarded
FROM claims.sessions s
JOIN public.contractors c
  ON c.id = s.contractor_id;

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

  civ.genai_all_rulechecks_pass_flag  AS latest_genai_all_rulechecks_pass_flag,
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