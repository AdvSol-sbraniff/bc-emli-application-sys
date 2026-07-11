# Product Download Rule Cleanup Plan

## Goal

Clean up product-list/download validation so product evidence is extracted as normal named located fields, product download lookups are owned by code rules, and each product-download family produces one coherent rule result with subcheck details.

This replaces the current split where the classifier extracts product references, `product_lookup_enrichment` precomputes match context for GenAI, and some product families are represented by several small code rules.

## Confirmed Direction

This cleanup is correct, with one wording correction:

- Do not describe the work as moving "six download keys" out of the classifier. AHRI is close to a single key, but the other families often require product identity evidence such as model number, manufacturer, ENERGY STAR reference, NEEA reference, NRCan reference, or product-list wording.
- The correct target is: move the six product-download families' invoice product identity extraction out of classifier and into normal GenAI located fields.
- Remove `download_product_enrichment` from the GenAI context window because no active GenAI rule currently depends on downloaded product-row facts.
- Make code rules perform the download lookup after GenAI invoice/supporting-document fields exist.
- Each product-download rule should emit one overall result plus explicit subcheck statuses so admin can see exactly which part failed.

## Product Families

The six product-download families are:

- AHRI heat pump products.
- OHPA BC oil-to-heat-pump products.
- NEEA heat pump water heater products.
- AWHP air-to-water / combined heat pump products.
- NRCan ENERGY STAR HERV/ERV products.
- ENERGY STAR ventilating fan products.

## Target Rule Shape

Each product-download family should have one primary code rule with this output pattern:

```text
rule_result="pass|warn|fail"

calculation:
invoice_product_identity:
  field_key=...
  value=...
supporting_document_product_identity:
  document_type=...
  field_key=...
  value=...
download_lookup:
  table_or_view=...
  matched_product_id=...

subchecks:
- invoice_product_identity_present: pass|warn|fail
- supporting_document_matches_invoice: pass|warn|fail
- product_found_in_download: pass|warn|fail
- product_attributes_meet_requirement: pass|warn|fail|not_applicable

failed_subchecks:
- subcheck_key: reason

warn_subchecks:
- subcheck_key: reason
```

The overall result should be:

- `fail` if any required subcheck clearly fails.
- `warn` if no required subcheck fails, but required evidence is missing, ambiguous, conflicting, or lookup is inconclusive.
- `pass` only when all required subchecks pass.

## Supporting-Document Subcheck Policy

The supporting-document match should be handled consistently across all six families.

Recommended policy:

- Treat invoice product identity as required for product-download validation.
- Treat supporting-document corroboration as required only when the configured supporting-document extraction has product identity fields for that family.
- If supporting docs are expected but no matching product identity is found, return `warn`, unless there is a clear conflicting product identity, which should return `fail`.
- If the requirement PDF does not explicitly require a supporting document match, the evidence wording should frame this as corroboration/review evidence, not as a standalone PDF eligibility condition.

## Classifier Cleanup

Remove product-download extraction from the classifier step.

Impacted classifier fields:

- `classifier.ahri_reference`
- `classifier.neea_reference`
- `classifier.awhp_reference`
- `classifier.ohpa_reference`
- `classifier.product_model_number`
- `classifier.product_manufacturer`

Implementation tasks:

1. Update classifier system/user prompt seed text in `claims_ai_service_ddl/3_insert_validationgenai_config.sql`.
2. Remove the classifier `product_references` schema/output expectations.
3. Update classifier result parsing in `app/jobs/claims/run_genai_job.rb` so it no longer persists those product-reference located fields.
4. Update `classifier_payload_from_evidence` so `product_references` is removed or replaced with an empty backwards-compatible object only if old rows must still be tolerated during transition.
5. Confirm classifier still emits upgrade type detection and eligibility code as before.

## Located Field Cleanup

Ensure invoice product identity fields exist as normal GenAI located fields for upgrade types that need them.

Expected invoice located-field ownership:

- AHRI/ASHP/DFHP: `hp_ahri_reference`, plus existing heat-pump model/manufacturer fields where useful.
- OHPA oil: `hp_ahri_reference` plus any oil-specific product-list/reference evidence if needed.
- NEEA HPWH: `hpwh_neea_reference`, `hpwh_manufacturer`, `hpwh_model_number`, `hpwh_make_model`, `hpwh_model_components`.
- AWHP hydronic: `atw_product_list_reference`, `cshp_product_list_reference`, `hp_make_model`, and any existing hydronic make/model fields.
- HERV/ERV: `vent_manufacturer`, `vent_model_number`, `vent_make_model`, `vent_energy_star_reference`, `vent_nrcan_or_product_list_reference`, `vent_system_type`.
- Vent fan: `vent_manufacturer`, `vent_model_number`, `vent_make_model`, `vent_energy_star_reference`, `vent_nrcan_or_product_list_reference`, `vent_system_type`.

Implementation tasks:

1. Audit existing `claims.genai_located_fields` and `claims.genai_located_field_upgrade_types`.
2. Add or revise missing field prompts in `claims_ai_service_ddl/3_insert_genai_normalized.sql`.
3. Apply equivalent local DB updates.
4. Keep prompts named-field focused; do not ask GenAI to reason against hidden DB column names.

## Remove Product Enrichment Context

Remove the pre-GenAI product enrichment step and User Record 6 context.

Implementation tasks:

1. Remove `run_product_lookup_enrichment_step!` from `RunGenaiJob#perform`.
2. Remove `product_lookup_result_from_step!` dependency from `run_genai_ruleset_child!`.
3. Remove `product_enrichment_context` from GenAI prompt/context construction.
4. Remove the User Record 6 `download_product_enrichment` layer from `claims_ai_service_documentation/genai_context_window_spec.md`.
5. Remove or archive `app/services/claims/product_lookup_enrichment/apply.rb` only after all code rules have taken ownership of the lookup logic.
6. Remove `product_lookup_enrichment` step registration from ingest step orchestration if no other runtime path needs it.

Important: product-id columns such as `invoice_versions.ahri_product_id`, `neea_product_id`, `awhp_product_id`, `ohpa_product_id`, `herv_product_id`, and `vent_fan_product_id` should still be populated when a code rule finds a clean match. The code rule should own that write so the persisted product match and rule result come from the same evidence.

## Consolidated Code Rules

### AHRI

Replace:

- `hp_invoice_ahri_reference_present`
- `hp_supporting_document_ahri_matches_invoice`
- `hp_ahri_reference_found_in_product_list`

With:

- `hp_ahri_product_validation`

Subchecks:

- `invoice_ahri_reference_present`
- `supporting_document_ahri_matches_invoice`
- `ahri_product_found_in_download`

Mapped to:

- `air_source_heat_pump_electric`
- `air_source_heat_pump_wood`
- `air_source_heat_pump_gas_propane`
- `dual_fuel_ducted_heat_pump`
- `air_source_heat_pump_oil`, if we keep AHRI certification separate from OHPA listing for oil.

### OHPA

Revise:

- `ashp_oil_ohpa_bc_product_found_in_list`

Target:

- `ashp_oil_ohpa_product_validation`

Subchecks:

- `invoice_product_identity_present`
- `supporting_document_matches_invoice`
- `ohpa_product_found_in_download`
- `ohpa_product_is_bc_eligible`

Mapped to:

- `air_source_heat_pump_oil`

Oil nuance:

- The oil section appears to require both an AHRI certified reference number and listing on the OHPA BC qualified product list. During implementation, decide whether oil uses both `hp_ahri_product_validation` and `ashp_oil_ohpa_product_validation`, or whether the OHPA rule includes the AHRI-reference subcheck. Prefer whichever maps most clearly to the requirement PDF wording.

### NEEA HPWH

Replace or consolidate:

- `hpwh_neea_found_in_product_list`
- `hpwh_neea_tier_2_or_higher`

With:

- `hpwh_neea_product_validation`

Subchecks:

- `invoice_hpwh_product_identity_present`
- `supporting_document_matches_invoice`
- `neea_product_found_in_download`
- `neea_tier_2_or_higher`

Mapped to:

- `heat_pump_water_heater`

### AWHP Hydronic

Revise:

- `hydronic_product_found_in_qualifying_list`

Target:

- `hydronic_awhp_product_validation`

Subchecks:

- `invoice_hydronic_product_identity_present`
- `supporting_document_matches_invoice`
- `awhp_product_found_in_download`

Mapped to:

- `air_to_water_heat_pump`
- `combined_space_water_heat_pump`

### HERV/ERV

Revise:

- `vent_herv_nrcan_energy_star_product_list_match`

Target:

- `vent_herv_nrcan_product_validation`

Subchecks:

- `invoice_herv_product_identity_present`
- `supporting_document_matches_invoice`
- `herv_product_found_in_download`

Mapped to:

- `ventilation`

### Vent Fan

Revise:

- `vent_fan_energy_star_product_list_match`

Target:

- `vent_fan_energy_star_product_validation`

Subchecks:

- `invoice_fan_product_identity_present`
- `supporting_document_matches_invoice`
- `vent_fan_product_found_in_download`
- `vent_fan_capacity_meets_minimum`, if we choose to fold the existing 85 CFM / static pressure code rule into the product-validation rule.

Mapped to:

- `ventilation`

Recommendation:

- Keep `vent_fan_capacity_meets_minimum` separate if it maps to a distinct requirement sentence and not strictly to the product-list lookup.

## Code Reader Changes

Update code rules so they read normal located fields, not classifier located fields.

Known current references to remove:

- `classifier.ahri_reference`
- `classifier.neea_reference`
- `classifier.awhp_reference`
- `classifier.ohpa_reference`
- `classifier.product_model_number`
- `classifier.product_manufacturer`

Known code areas:

- `app/services/claims/code_rules/heat_pump_ahri/apply_product_list_match.rb`
- `app/services/claims/code_rules/oil_heat_pump_ohpa/apply_product_list_match.rb`
- `app/services/claims/code_rules/ashp_product_requirements/apply_product_requirements.rb`
- `app/services/claims/code_rules/dfhp/apply_product_specs.rb`
- `app/services/claims/code_rules/heat_pump_water_heater_neea/apply_product_list_match.rb`
- `app/services/claims/code_rules/air_water_heat_pump_product_list/apply_product_list_match.rb`
- `app/services/claims/code_rules/ventilation_herv/apply_product_list_match.rb`
- `app/services/claims/code_rules/ventilation_fan/apply_product_list_match.rb`

## Seed And Local DB Work

Seeds are the rebuild source of truth.

Implementation tasks:

1. Update `claims_ai_service_ddl/3_insert_validationgenai_config.sql`.
2. Update `claims_ai_service_ddl/3_insert_genai_normalized.sql`.
3. Update `claims_ai_service_ddl/3_insert_code_rules.sql`.
4. Apply equivalent local DB changes with `UPDATE`, `INSERT`, and `DELETE` statements.
5. Delete obsolete rules from seed and local DB rather than retiring them, because this is still early dev.

## Admin/API Output

Keep product match display support, but make it rule-owned.

Implementation tasks:

1. Continue serializing product match objects for invoice review where useful.
2. Ensure product-id columns are written by the relevant code rule when matched.
3. Ensure failed/warned subchecks appear in the rule calculation/evidence payload.
4. Avoid GenAI context references to product enrichment.

## Testing Plan

### Unit/Service Tests

Add or update tests for each consolidated product-validation code rule:

- Invoice identity missing -> `warn`.
- Invoice identity present, no supporting document corroboration -> `warn` unless the family has no configured supporting-doc product fields.
- Invoice identity and supporting document conflict -> `fail`.
- Invoice/supporting identity match but no downloaded product match -> `fail`.
- Downloaded product match with incomplete attributes -> `warn` where attributes are required.
- Downloaded product match with failing attributes -> `fail`.
- All required subchecks pass -> `pass`.

### Regression Tests

Confirm no code path still depends on:

- `classifier.ahri_reference`
- `classifier.neea_reference`
- `classifier.awhp_reference`
- `classifier.ohpa_reference`
- `classifier.product_model_number`
- `classifier.product_manufacturer`
- `download_product_enrichment`

### End-To-End Tests

Run faux or existing test invoices for:

- ASHP AHRI match.
- Oil OHPA match.
- HPWH NEEA Tier 2+ match.
- Hydronic AWHP match.
- Ventilation HERV/ERV match.
- Ventilation fan ENERGY STAR match.

For each run, confirm:

- Classifier does not emit product references.
- GenAI upgrade located fields capture product identity evidence.
- Supporting-document extraction captures corroborating product identity where available.
- Consolidated code rule writes the product-id column when matched.
- Consolidated code rule calculation lists all subchecks.
- No GenAI context window contains `download_product_enrichment`.

## Rollout Order

1. Add or verify normal GenAI located fields for all six product families.
2. Build consolidated code-rule helpers and output format.
3. Implement one family first, preferably AHRI, because it exposes the current over-splitting most clearly.
4. Convert the remaining five families.
5. Remove classifier product-reference extraction.
6. Remove `product_lookup_enrichment` from GenAI context and runtime.
7. Delete obsolete split rules from seed and local DB.
8. Run regression and E2E tests.

## Open Decision

For oil ASHP, decide whether the requirement PDF is best represented as:

- two rules: AHRI product validation plus OHPA BC product validation, or
- one oil product validation rule with both AHRI-certified-reference and OHPA-list subchecks.

I lean toward two rules if the PDF has two separately stated requirements, but one rule is acceptable if admin wants one product-validity decision for oil. (stephen agrees)
