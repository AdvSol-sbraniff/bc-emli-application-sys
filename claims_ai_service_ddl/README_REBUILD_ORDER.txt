# Claims AI DDL Folder Layout

## Active claims-only rebuild path

Run these when you want to drop and rebuild only the `claims` schema while leaving `public` users, contractors, programs, and legacy app data alone:

1. `2_create_schema.sql`
2. `3_insert_ahri_sources.sql`
3. `3_insert_neea_sources.sql`
4. `3_insert_awhp_sources.sql`
5. `3_insert_ohpa_sources.sql`
6. `3_insert_invoice_upgrade_types.sql`
7. `3_insert_supporting_document_types.sql`
8. `3_insert_supporting_document_type_upgrade_types.sql`
9. `3_insert_supporting_document_type_located_fields.sql`
10. `3_insert_code_rules.sql`
11. `3_insert_code_located_fields.sql`
12. `3_insert_validationgenai_config.sql`
13. `3_insert_genai_normalized.sql`
14. `4_create_views.sql`

## Optional local test data

- `testdata_20260616/`
  - Optional case/evidence fixtures for local end-to-end testing.
  - Run these after the active claims-only rebuild path only when you want repeatable local test records for real PDF/package smoke tests.
  - These scripts may insert/update `public.users`, `public.preferences`, and `public.contractors`, so they are deliberately not part of the default claims-only rebuild list.
  - `9_insert_testdata.sql` seeds the participant and eligibility-code record needed for `Invoice 2 - Insulation and Health & Safety.pdf`.
  - `9_insert_test014_multi_upgrade_testdata.sql` seeds the participant, contractor, and eligibility-code records needed for `Test Data/Heat Pump/test014`.

## Not part of normal claims rebuild

- `public_legacy_seed/` contains old/public-schema bootstrap scripts.
- `archived_sql/` contains stale SQL, old existing-schema patch scripts, archived one-off local/admin/user repair scripts, and scratch notes kept only for archaeology. Do not use these for gold rebuilds.
- `dev_tools/` contains Rails runner/debug helper scripts.
- `plans/` contains AI/ruleset implementation plans and analysis notes.
- `reference_data/` contains external files used by importers or historical local data loads.
  - `reference_data/silver_templates/` contains legacy Silver template JSON exports used only by the optional importer script.

Do not run public/legacy/one-off scripts as part of a claims-schema rebuild unless you explicitly intend to change public schema data.
