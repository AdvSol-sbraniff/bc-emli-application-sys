# Remove Rulecheck Traceability Fields Plan

## 1. Decision

Remove `source_requirement_id`, `evidence_source`, and `rule_name` from the claims AI rulecheck model.

These fields are not governed by a real source-of-truth table, are partly hardcoded in Ruby, partly requested from GenAI output, and create confusing UI output. The durable rule identity and display label should be `rule_key`.

This plan is local-only until manual testing is complete. Do not update gold as part of this work.

## 2. Target Model

Keep these fields on `claims.invoice_version_rulechecks`:

- `rule_key`
- `rule_number`
- `source_engine`
- `rule_result`
- `confidence`
- `expected_text`
- `calculation`
- `evidence_text`
- `reason_and_likely_causes`

Remove these fields everywhere:

- `source_requirement_id`
- `evidence_source`
- `rule_name`

For audit/readability, use the rule explanation fields (`expected_text`, `calculation`, `evidence_text`, `reason_and_likely_causes`) instead of fake source taxonomy.

## 3. Schema Changes

Update `claims_ai_service_ddl/2_create_schema.sql`:

- Remove `source_requirement_id text NULL` from `claims.invoice_version_rulechecks`.
- Remove `evidence_source text NULL` from `claims.invoice_version_rulechecks`.
- Remove `rule_name text NOT NULL` from `claims.invoice_version_rulechecks`.
- Remove `index_invoice_version_rulechecks_on_source_requirement_id`.

Apply operational local DB changes with `ALTER TABLE`:

- Drop `source_requirement_id` from `claims.invoice_version_rulechecks`.
- Drop `evidence_source` from `claims.invoice_version_rulechecks`.
- Drop `rule_name` from `claims.invoice_version_rulechecks`.
- Drop the source requirement index if it exists.

## 4. Code Rule Cleanup

Remove hardcoded `source_requirement_id` values and `evidence_source` assignments from code-owned rule builders:

- `app/services/claims/invoice_version_rulechecks/apply_code_rulechecks.rb`
- `app/services/claims/code_rules/heat_pump_ahri/apply_product_list_match.rb`
- `app/services/claims/code_rules/heat_pump_water_heater_neea/apply_product_list_match.rb`
- `app/services/claims/code_rules/oil_heat_pump_ohpa/apply_product_list_match.rb`
- `app/services/claims/code_rules/air_water_heat_pump_product_list/apply_product_list_match.rb`
- `app/services/claims/code_rules/windows_doors_u_factor/apply_threshold_check.rb`
- `app/services/claims/code_rules/income_level/apply_level_one_or_two_required.rb`

After this, code rule rows should persist only the real rule identity and result details.

Also remove friendly-name constants used only to populate `rule_name`. Code-owned rulechecks should use `rule_key` directly.

## 5. GenAI Cleanup

Update `claims_ai_service_ddl/5_insert_validationgenai_config.sql`:

- Remove `evidence_source` from the required JSON output shape.
- Remove instructions telling GenAI to set `evidence_source`.

Update GenAI rulecheck persistence:

- In `app/services/claims/invoice_version_rulechecks/apply_genai_rulechecks.rb`, stop reading/persisting `source_requirement_id`.
- In the same file, stop reading/persisting `evidence_source`.
- In the same file, stop reading/persisting `rule_name`.

## 6. API Cleanup

Remove all three fields from rulecheck serializers:

- `app/controllers/api/claims/invoice_versions_admin_controller.rb`
- `app/controllers/api/claims/invoice_versions_controller.rb`

The API should still return `rule_key`, `rule_number`, `source_engine`, result fields, and explanation fields.

## 7. Frontend Cleanup

Remove display/types for `source_requirement_id`, `evidence_source`, and `rule_name`:

- `app/frontend/components/domains/invoice-versions/index.tsx`
- `app/frontend/components/domains/invoice-version-viewer-by-version/index.tsx`
- `app/frontend/components/domains/contractor-invoice-review/index.tsx`

In the admin PDF viewer, show `rule_key` where the system key is useful. Do not show `source_requirement_id`.
The rule card header should be the raw `rule_key`; do not render a secondary rule-key row.

## 8. Testing

Run static checks:

- `rg "rule_name|source_requirement_id|evidence_source" app claims_ai_service_ddl`
- Expected: no active runtime/schema references remain.
- Archived historical plans may still contain old references unless we intentionally scrub archives too.

Run local DB verification:

- Confirm `claims.invoice_version_rulechecks` no longer has any removed columns.
- Run the local schema rebuild path.
- Run at least one GenAI rulecheck flow and one code-rule flow.
- Confirm rulechecks persist successfully.
- Confirm the admin PDF viewer renders rule keys, results, confidence, and explanation text.

## 9. Acceptance Criteria

- `claims.invoice_version_rulechecks` contains no `source_requirement_id` column.
- `claims.invoice_version_rulechecks` contains no `evidence_source` column.
- `claims.invoice_version_rulechecks` contains no `rule_name` column.
- Runtime code does not hardcode `ESP-2026-*` identifiers for persisted rulechecks.
- GenAI is not asked to output `evidence_source`.
- API payloads do not include any removed field.
- UI does not render any removed field.
- Admin PDF viewer shows `rule_key` as the rule header.
- Gold DB is not touched.
