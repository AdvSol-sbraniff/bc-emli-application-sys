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
