# Gold Claims Schema Rebuild Runbook

## Purpose and scope

Use this runbook for a complete rebuild of the `claims` schema in Gold/dev (`ce8baa-dev`), followed by reloading all six external product-download families.

This is destructive: `2_create_schema.sql` starts with `DROP SCHEMA IF EXISTS claims CASCADE`. It deletes all Claims invoices, ingest history, rule configuration/history, test-harness data, product imports, and other data stored in `claims`. It leaves `public` users, contractors, programs, and legacy application data intact.

Before starting:

- Confirm the intended OpenShift context with `oc whoami` and `oc project`; the Gold/dev project is `ce8baa-dev`.
- Use a maintenance window and prevent Claims uploads during the rebuild.
- Back up any Claims data that must be retained. The rebuild scripts do not preserve it.
- Record the current replica count for `hesp-sidekiq-claims`, then scale that deployment to zero. Keep it stopped until the schema, views, and all six product-download families are healthy.
  - Record: `oc -n ce8baa-dev get deployment/hesp-sidekiq-claims -o jsonpath='{.spec.replicas}'`
  - Stop: `oc -n ce8baa-dev scale deployment/hesp-sidekiq-claims --replicas=0`
- Discover the current primary Crunchy Postgres pod rather than relying on an old pod name:
  - `oc -n ce8baa-dev get pods -l postgres-operator.crunchydata.com/role=master -o name`

## Active claims-only rebuild order

Run every file below, in this exact order, against the Gold `hesp-crunchydb` database:

1. `2_create_schema.sql`
2. `2_create_schema_for_testharness.sql`
3. `3_insert_ahri_sources.sql`
4. `3_insert_neea_sources.sql`
5. `3_insert_awhp_sources.sql`
6. `3_insert_ohpa_sources.sql`
7. `3_insert_herv_sources.sql`
8. `3_insert_vent_fan_sources.sql`
9. `3_insert_ingest_failure_subtypes.sql`
10. `3_insert_invoice_upgrade_types.sql`
11. `3_insert_personal_information_types.sql`
12. `3_insert_supporting_document_types.sql`
13. `3_insert_supporting_document_type_upgrade_types.sql`
14. `3_insert_supporting_document_type_located_fields.sql`
15. `3_insert_code_rules.sql`
16. `3_insert_code_located_fields.sql`
17. `3_insert_validationgenai_config.sql`
18. `3_insert_genai_normalized.sql`
19. `4_create_views.sql`

Do not include any SQL from a subdirectory in this sequence.

## SQL execution requirements

- Run every file with `psql -v ON_ERROR_STOP=1` so execution stops on the first SQL error.
- Copy and execute one file at a time against the current primary database pod. Known command shape:
  - `oc -n ce8baa-dev cp <local-sql-file> <primary-postgres-pod>:/tmp/<file>.sql -c database`
  - `oc -n ce8baa-dev exec <primary-postgres-pod> -c database -- psql -X -v ON_ERROR_STOP=1 -U postgres -d hesp-crunchydb -f /tmp/<file>.sql`
- Do not continue after a failure. Correct the cause and restart the ordered rebuild from `2_create_schema.sql`, because the database may contain only part of the expected schema.
- `4_create_views.sql` is not wrapped in a transaction. A failure can leave earlier views dropped and not recreated.

## Post-DDL recovery sequence

- After `4_create_views.sql`, verify at minimum:
  - `claims.v_ingest_runs` exists.
  - `claims.v_ingest_step_runs` exists.
  - `claims.ingest_step_runs.completed_at` exists.
  - The `claims` schema contains its expected admin, grid, reporting, and current-product views.
- Restart the Gold app deployment before using the UI. Rails caches table columns at boot; pods that stay up across a drop/recreate can continue using the old schema shape:
  - `oc -n ce8baa-dev rollout restart deployment/hesp-app`
  - `oc -n ce8baa-dev rollout status deployment/hesp-app`
- With `hesp-sidekiq-claims` still stopped, open `/downloads-admin` and repopulate all six product-download families:
  - AHRI / BC Hydro heat pump products.
  - NEEA heat pump water heater products.
  - Air-to-Water and Combined Heat Pump qualifying products.
  - OHPA products.
  - NRCan HERV/ERV products.
  - ENERGY STAR ventilating fan products.
- Verify the current product views after imports. A healthy rebuild should have non-zero counts in:
  - `claims.v_current_ahri_products`
  - `claims.v_current_neea_products`
  - `claims.v_current_awhp_products`
  - `claims.v_current_ohpa_products`
  - `claims.v_current_herv_products`
  - `claims.v_current_vent_fan_products`
- Verify each download's latest import run is `succeeded`, has `records_imported > 0`, and has no error text. Do not treat a merely present import-run row as success.
- OHPA is large and should insert rows in small batches. A single giant insert can destabilize the Gold database connection and leave a failed or running zero-record import.
- Restore `hesp-sidekiq-claims` to the replica count recorded before the rebuild, then wait for its rollout to become healthy:
  - `oc -n ce8baa-dev scale deployment/hesp-sidekiq-claims --replicas=<recorded-replicas>`
  - `oc -n ce8baa-dev rollout status deployment/hesp-sidekiq-claims`
- Perform a Claims UI/API smoke test and confirm app and worker logs contain no missing-table, missing-column, or missing-view errors.
- Any invoice submitted during the rebuild window must be uploaded again because the `claims` schema was dropped and recreated.

## Explicitly excluded from a Gold claims rebuild

- `public_legacy_seed/` contains old/public-schema bootstrap scripts.
- `archived_sql/` contains stale SQL, old existing-schema patch scripts, archived one-off local/admin/user repair scripts, historical local reference files, and scratch notes kept only for archaeology. Do not use these for gold rebuilds.
- `dev_tools/` contains local Rails runner/debug helper scripts. Do not use these for gold rebuilds.
- `out_of_scope_seed/` contains seed data outside the supported Gold claims rebuild.
- `db create/` contains database-creation SQL and is not part of a claims-schema rebuild.

Do not run public, legacy, local-test, archived, repair, or one-off scripts as part of this procedure.
