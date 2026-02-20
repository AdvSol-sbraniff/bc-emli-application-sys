BEGIN;

-- Lineitems (child of invoice_versions)
DELETE FROM claims.lineitems;
DELETE FROM claims.invoice_versions;
DELETE FROM claims.invoices;
DELETE FROM claims.sessions;
delete from claims.ingest_step_runs;

COMMIT;
