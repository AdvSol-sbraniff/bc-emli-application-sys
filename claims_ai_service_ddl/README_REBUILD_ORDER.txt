# Claims AI DDL Folder Layout

## Active claims-only rebuild path

Run these when you want to drop and rebuild only the `claims` schema while leaving `public` users, contractors, programs, and legacy app data alone:

1. `2_create_schema.sql`
2. `3_insert_ahri_sources.sql`
3. `3_insert_neea_sources.sql`
4. `4_insert_invoice_upgrade_types.sql`
5. `4_insert_supporting_document_types.sql`
6. `5_insert_code_rules.sql`
7. `5_insert_code_located_fields.sql`
8. `5_insert_genai_normalized.sql`
9. `5_insert_validationgenai_rulesets.sql`
10. `6_views.sql`
11. `7_reporting_views.sql`

## Not part of normal claims rebuild

- `public_legacy_seed/` contains old/public-schema bootstrap scripts.
- `one_off_sql/` contains one-off local/admin/user repair scripts.
- `archived_sql/` contains stale SQL kept only for archaeology.
- `dev_tools/` contains Rails runner/debug helper scripts.
- `plans/` contains AI/ruleset implementation plans and analysis notes.
- `reference_data/` contains external files used by importers or historical local data loads.
  - `reference_data/silver_templates/` contains legacy Silver template JSON exports used only by the optional importer script.
- `test_notes/` contains scratch notes and API test snippets.

Do not run public/legacy/one-off scripts as part of a claims-schema rebuild unless you explicitly intend to change public schema data.
