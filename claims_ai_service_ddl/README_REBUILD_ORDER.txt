# Claims AI DDL Folder Layout

## Active claims-only rebuild path

Run these when you want to drop and rebuild only the `claims` schema while leaving `public` users, contractors, programs, and legacy app data alone:

1. `2_create_schema.sql`
2. `3_insert_ahri_sources.sql`
3. `3_insert_neea_sources.sql`
4. `4_insert_invoice_upgrade_types.sql`
5. `4_insert_supporting_document_types.sql`
6. `4_insert_supporting_document_type_upgrade_types.sql`
7. `4_insert_supporting_document_type_located_fields.sql`
8. `5_insert_code_rules.sql`
9. `5_insert_code_located_fields.sql`
10. `5_insert_genai_normalized.sql`
11. `5_insert_validationgenai_rulesets.sql`
12. `6_views.sql`
13. `7_reporting_views.sql`

## Active existing-database patches

- `8_add_supporting_document_routing_quality.sql`
  - Run once against an existing claims schema to add supplement routing-quality columns.
  - A clean rebuild from `2_create_schema.sql` already includes these columns.
- `8_create_supporting_document_located_fields.sql`
  - Run once against an existing claims schema to add supporting-document located-field definition/result tables.
  - A clean rebuild from `2_create_schema.sql` already includes these tables.
- `8_split_supporting_document_extraction_mode.sql`
  - Run once against an existing claims schema to rename the classifier prompt column and add the separate supporting-document extraction mode/config columns.
  - A clean rebuild from `2_create_schema.sql` already includes these columns and step-type constraints.

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
