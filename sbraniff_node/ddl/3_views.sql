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

