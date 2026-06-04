# Claims AI DDL Folder Layout

## Active claims-only rebuild path

Run these when you want to drop and rebuild only the `claims` schema while leaving `public` users, contractors, programs, and legacy app data alone:

1. `2_create_schema.sql`
2. `3_insert_ahri_sources.sql`
3. `3_insert_neea_sources.sql`
4. `3_insert_awhp_sources.sql`
5. `3_insert_ohpa_sources.sql`
6. `4_insert_invoice_upgrade_types.sql`
7. `4_insert_supporting_document_types.sql`
8. `4_insert_supporting_document_type_upgrade_types.sql`
9. `4_insert_supporting_document_type_located_fields.sql`
10. `5_insert_code_rules.sql`
11. `5_insert_code_located_fields.sql`
12. `5_insert_validationgenai_config.sql`
13. `5_insert_genai_normalized.sql`
14. `6_views.sql`
15. `7_reporting_views.sql`

## Optional local test data

- `9_insert_testdata.sql`
  - Run after the active claims-only rebuild path when you want repeatable local test records for real PDF smoke tests.
  - Currently seeds the participant and eligibility-code record needed for `Invoice 2 - Insulation and Health & Safety.pdf`.
  - This script may insert/update `public.users` and `public.preferences`, so it is deliberately not part of the default claims-only rebuild list.

## Active existing-database patches

- `8_add_supporting_document_routing_quality.sql`
  - Run once against an existing claims schema to add supplement routing-quality columns.
  - A clean rebuild from `2_create_schema.sql` already includes these columns.
- `8_create_supporting_document_located_fields.sql`
  - Run once against an existing claims schema to add supporting-document located-field definition/result tables.
  - A clean rebuild from `2_create_schema.sql` already includes these tables.
- `8_enforce_separate_supporting_document_extraction.sql`
  - Run once against an existing claims schema to collapse classifier config to one routing-only prompt and make supporting-document field extraction a separate pipeline step.
  - A clean rebuild from `2_create_schema.sql` already includes these columns and step-type constraints.
- `8_redo_invoice_package_ingest_documents.sql`
  - Run once against an existing claims schema to make `claims.ingest_documents` a child of `claims.invoices`, add promotion traceability, and add redo-package/case-facts/aggregate step types.
  - A clean rebuild from `2_create_schema.sql` already includes these columns and constraints.
- `8_create_awhp_product_list.sql`
  - Run once against an existing claims schema to add Better Homes BC air-to-water / combined heat pump product-list tables and `claims.invoice_versions.awhp_product_id`.
  - A clean rebuild from `2_create_schema.sql` already includes these tables and columns.
- `8_create_ohpa_product_list.sql`
  - Run once against an existing claims schema to add NRCan Oil to Heat Pump Affordability BC product-list tables and `claims.invoice_versions.ohpa_product_id`.
  - A clean rebuild from `2_create_schema.sql` already includes these tables and columns.

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
