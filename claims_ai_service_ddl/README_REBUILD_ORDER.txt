# Claims AI DDL Folder Layout

## Active claims-only rebuild path

Run these when you want to drop and rebuild only the `claims` schema while leaving `public` users, contractors, programs, and legacy app data alone:

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

## Operational notes for Gold/dev rebuilds

- Stop `hesp-sidekiq-claims` before running the rebuild and keep it stopped until the six product downloads are repopulated. This prevents uploads or background validation jobs from running against a half-built `claims` schema or empty product-list views.
- Run every SQL file with `ON_ERROR_STOP=1`. A failed `4_create_views.sql` can leave earlier views dropped and not recreated; for example, the admin ingest-run screen requires `claims.v_ingest_runs`.
- After `4_create_views.sql`, verify at least:
  - `claims.v_ingest_runs` exists.
  - `claims.v_ingest_step_runs` exists.
  - `claims.ingest_step_runs.completed_at` exists.
  - The total `claims` view count is non-zero and includes the admin/grid views.
- Repopulate all six product download families after the schema rebuild:
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
- OHPA is large. The importer should insert rows in small batches; a single giant insert can destabilize the Gold database connection and leave a failed/running zero-record OHPA import run.
- Restart `hesp-app` after the claims schema rebuild. Rails caches table columns at boot; if web pods stay up across a drop/recreate, upload endpoints can keep trying to write columns from the old schema.
- Restore or restart `hesp-sidekiq-claims` after the schema, views, and six downloads are complete.
- Any invoice uploaded during a claims-schema rebuild window should be uploaded again after the rebuild, because the `claims` schema is intentionally dropped and recreated.

## Optional local test data

- `testdata_20260616/`
  - Optional case/evidence fixtures for local end-to-end testing.
  - Run these after the active claims-only rebuild path only when you want repeatable local test records for real PDF/package smoke tests.
  - These scripts may insert/update `public.users`, `public.preferences`, and `public.contractors`, so they are deliberately not part of the default claims-only rebuild list.
  - `9_insert_testdata.sql` seeds the participant and eligibility-code record needed for `Invoice 2 - Insulation and Health & Safety.pdf`.
  - `9_insert_test014_multi_upgrade_testdata.sql` seeds the participant, contractor, and eligibility-code records needed for `Test Data/Heat Pump/test014`.

## Not part of normal claims rebuild

- `public_legacy_seed/` contains old/public-schema bootstrap scripts.
- `archived_sql/` contains stale SQL, old existing-schema patch scripts, archived one-off local/admin/user repair scripts, historical local reference files, and scratch notes kept only for archaeology. Do not use these for gold rebuilds.
- `dev_tools/` contains local Rails runner/debug helper scripts. Do not use these for gold rebuilds.

Do not run public/legacy/one-off scripts as part of a claims-schema rebuild unless you explicitly intend to change public schema data.
