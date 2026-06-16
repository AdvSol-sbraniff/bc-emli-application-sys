# Windows And Doors V1 Ruleset Refactor Plan

Purpose: convert the current prototype `esp_default_v1` prompt into a source-traced Windows and doors hybrid validation package.

Status: planning only. No SQL/code changes yet.

## Current Prototype

Current seed file:

- `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql`

Current shortname:

- `esp_default_v1`

Problem:

- It mixes common rules and Windows/doors rules in one prompt.
- It asks GenAI to do deterministic math/date checks.
- It uses rule numbers without stable source requirement IDs or rule keys.
- It is a prototype, not a source-traced ruleset.

Target shortname:

- `esp_windows_doors_2026_04_v1`

## Refactor Principles

- GenAI locates evidence.
- Code evaluates deterministic rules.
- DB queries supply program facts.
- Missing evidence becomes `unknown`, not false.
- Every rule maps back to a source requirement ID from `ai_ruleset_requirements_matrix.md`.
- The final ruleset is explicitly Windows and doors; no generic fallback.

## Located Fields

Keep and refine current located fields:

| Current field               | Keep? | Source engine | Notes                                                              |
| --------------------------- | ----- | ------------- | ------------------------------------------------------------------ |
| `contractor_gst_number`     | yes   | genai         | Useful admin evidence, not core public requirement.                |
| `eligibility_code`          | yes   | genai/code    | Regex/code should also extract; GenAI can locate evidence/polygon. |
| `labour_cost_invoice_total` | yes   | genai         | Needed for rebate math if line items split labour/materials.       |
| `customer_deposit`          | yes   | genai         | Useful for amount-due/customer-portion math.                       |
| `nrcan_number`              | yes   | genai         | Evidence for certification/product references.                     |
| `cpd_number`                | yes   | genai         | Evidence for NFRC/CPD references.                                  |
| `brand_and_model`           | yes   | genai         | Needed for admin/product traceability.                             |
| `metric_u_factor`           | yes   | genai         | Code should evaluate threshold.                                    |
| `labour_per_unit`           | yes   | genai         | Code should evaluate math if found.                                |

Add likely Windows/doors located fields:

| New field                            | Source engine | Why                                                  |
| ------------------------------------ | ------------- | ---------------------------------------------------- |
| `window_or_door_quantity`            | genai         | Needed for unit/per-home cap math.                   |
| `rough_opening_count`                | genai         | Public requirement counts rough openings, not panes. |
| `skylight_detected`                  | genai         | Skylights are not eligible.                          |
| `rebate_line_amount`                 | genai         | Needed for itemization/deduction and cap math.       |
| `rebate_line_description`            | genai         | Evidence for CleanBC itemization.                    |
| `hardware_per_unit`                  | genai         | Needed for per-unit rebate math if visible.          |
| `eligible_cost_total`                | genai/code    | Code may calculate from located amounts.             |
| `amount_due_after_rebate`            | genai/code    | Code can compare against DI amount due.              |
| `manufacturer_label_photo_reference` | genai/manual  | Might appear in docs or invoice notes.               |
| `certification_body_reference`       | genai         | CSA/Intertek/NFRC/Keystone/NAMI/etc.                 |

## Current Rule Mapping

| Current rule                                  | New rule key                              | Preferred evaluator | Source requirement                | Action                                                   |
| --------------------------------------------- | ----------------------------------------- | ------------------- | --------------------------------- | -------------------------------------------------------- |
| rule 1: U-factor <= 1.22                      | `wd_u_factor_threshold`                   | hybrid/code         | ESP-2026-WD-008                   | GenAI locates U-factor; code compares numeric threshold. |
| rule 2: vendor matches contractor             | `registered_contractor_for_upgrade_type`  | hybrid/code/db      | ESP-2026-COM-009, ESP-2026-WD-007 | GenAI/OCR locates vendor; DB validates contractor.       |
| rule 3: customer matches participant          | `customer_matches_participant`            | hybrid/code/db      | common/program fact               | Keep as common rule; needs participant address model.    |
| rule 4: submit within six months              | `submission_within_six_months`            | code_engine         | ESP-2026-COM-017, ESP-2026-WD-014 | Code date math only.                                     |
| rule 5: eligibility code date                 | `eligibility_code_valid_for_invoice_date` | code_engine/db      | ESP-2026-COM-008                  | Code date math only.                                     |
| rule 6: sufficiently detailed description     | `wd_description_sufficient_for_review`    | genai/manual        | ESP-2026-WD-003/005/006/008       | GenAI can warn; admin final.                             |
| rule 7: per-unit rebate cap                   | `wd_per_unit_cap`                         | code_engine         | ESP-2026-WD-009/010               | Code math after GenAI locates unit costs/counts.         |
| rule 8: per-home rebate cap                   | `wd_per_home_cap`                         | code_engine         | ESP-2026-WD-009/010               | Code math.                                               |
| rule 9: customer portion after rebate/deposit | `customer_portion_math`                   | code_engine         | common invoice math               | Code math.                                               |

## New Windows/Doors Rule Set

### GenAI Evidence Instructions

GenAI should locate:

- U-factor values.
- window/door line items.
- rough openings/counts.
- panes/counts if invoice uses pane language.
- skylight language.
- manufacturer/brand/model.
- NRCan/CPD/NFRC/CSA/Intertek/Keystone/NAMI/certification references.
- CleanBC rebate line.
- labour/material splits.
- customer deposit.
- amount due or customer owing language.
- any note about City of Vancouver, quote/pre-approval, manufacturer label photos, or supporting docs.

### Code Rulechecks

Common:

- `source_vintage_applies`
- `first_class_invoice_fields_present`
- `submission_within_six_months`
- `eligibility_code_valid_for_invoice_date`
- `registered_contractor_for_upgrade_type`
- `rebate_itemized_and_deducted`
- `customer_portion_math`

Windows/doors:

- `wd_u_factor_threshold`
- `wd_no_skylights` if `skylight_detected` is structured bool; otherwise GenAI/manual.
- `wd_rough_opening_count`
- `wd_per_unit_cap`
- `wd_per_home_cap`
- `wd_rebate_percentage_by_income_level`
- `wd_not_city_of_vancouver`

### GenAI / Manual Rulechecks

- `wd_description_sufficient_for_review`
- `wd_certification_body_reference_present`
- `wd_label_photos_present`
- `wd_quote_preapproval_present`

These may be `unknown` if evidence is not available.

## Output Shape

Eventually add fields:

- `rule_key`
- `source_requirement_id`
- `verification_status`: `pass`, `fail`, `unknown`, `not_applicable`
- `preferred_evaluator`
- `evidence_source`

Until DDL changes exist:

- Encode `rule_key` and `source_requirement_id` in `rule_name` or `notes`.
- Keep `rule_pass_flag = nil` for unknown.

## V1 Build Sequence

1. Create/confirm matrix rows for Windows and doors.
2. Draft `esp_windows_doors_2026_04_v1` prompt text focused on evidence location, not math decisions.
3. Add code-engine service plan/tests for deterministic Windows and doors rules.
4. Update ruleset editor plan to show common, domain, code, and manual-review sections.
5. Only then update `5_insert_validationgenai_rulesets.sql`.

## Test Fixtures

Minimum local fixture set:

- good Windows/doors invoice
- missing U-factor
- U-factor above 1.22
- skylight present
- rebate line missing
- rebate not deducted from amount due
- per-unit cap exceeded
- per-home cap exceeded
- submitted after six months
- eligibility code expired before invoice date

Expected result style:

- Missing U-factor: `unknown`, request evidence.
- U-factor above 1.22: `fail`.
- Skylight present: `fail` or strong admin warning depending policy.
- Missing rebate line: `fail` if invoice truly lacks itemized rebate.
- Missing label photos: `unknown` / support-doc required.
