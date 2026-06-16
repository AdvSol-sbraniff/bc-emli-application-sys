# AI External Code Rule Next Candidates Plan

Date: 2026-05-13

## Purpose

AHRI/product-list validation proved the pattern:

1. GenAI locates messy invoice evidence.
2. Code checks objective external reference data or simple deterministic thresholds.
3. Code writes `source_engine='code'` rulecheck rows.
4. Admin and contractor viewers display those code-owned checks alongside GenAI checks.

This plan resets the next external/code-rule work after the AHRI implementation.

## Current implemented pattern

Implemented:

- BC Hydro ductless/mini-split heat-pump product-list import.
- `claims.ahri_import_runs`.
- `claims.ahri_products`.
- `claims.invoice_versions.ahri_product_id`.
- Heat-pump AHRI code-rule file physically isolated at:
  - `app/services/claims/code_rules/heat_pump_ahri/apply_product_list_match.rb`
- Code rules currently created:
  - `hp_ahri_found_in_product_list`
  - `hp_product_minimum_capacity_at_minus_5c`
  - `hp_product_efficiency_threshold`

Current AHRI code-rule upgrade types:

- `air_source_heat_pump_electric`
- `air_source_heat_pump_wood`
- `air_source_heat_pump_gas_propane`
- `air_source_heat_pump_oil`
- `dual_fuel_ducted_heat_pump`

Currently excluded heat-pump-like upgrade types:

- `air_to_water_heat_pump`
- `combined_space_water_heat_pump`
- `heat_pump_water_heater`

## Current RER website findings

Source reviewed:

- `https://betterhomesbc.ca/learn-about-programs/energy-savings-program/energy-savings-program-requirements/`

The current requirements page still contains several areas where the system is effectively saying "admin should verify" but a future implementation could partially automate the check.

Important external-list or deterministic candidates:

- Air-to-water and combined heat pumps must be listed on the Air-to-Water and Combined Heat Pump Qualifying Product List.
- Heat pump water heaters must be listed as Tier 2 or higher on NEEA's Advanced Water Heater Specification Qualified Products List.
- HRV/ERV ventilation equipment must be ENERGY STAR certified and listed on NRCan's searchable product list.
- Bathroom fans must be ENERGY STAR certified and listed on the EPA/DOE ENERGY STAR searchable product list.
- Ventilation bathroom fan specs include deterministic values such as 85 cfm / 40 L/s at 50 Pa, continuous duty, damper, ducting, insulation, and screened hood evidence.
- Windows and doors have certification-body/product-rating references such as NRCan/ENERGY STAR fenestration numbers, NFRC/CPD, CSA, Intertek, Keystone, QAI, NAMI, and related identifiers.
- Electrical service upgrade includes deterministic service-size language: 100, 200, or 400 amp service, utility service upgrade, and exclusion of panel-only work.

## Recommended next target

### 1. Heat Pump Water Heater NEEA Product List

Recommendation: do this next.

Why:

- It is philosophically closest to AHRI.
- The rule is objective: product must be Tier 2 or higher on NEEA's qualified product list.
- It belongs to one clear upgrade type: `heat_pump_water_heater`.
- It likely creates a new isolated code-rule file and new lookup table without touching the AHRI code path.
- It gives the project a second proof that the external-reference pattern is reusable.

Likely implementation:

- GenAI continues locating make/model/product-list references in `heat_pump_water_heater` ruleset.
- Add importer service:
  - `app/services/claims/external_references/import_neea_hpwh_products.rb`
- Add code-rule service:
  - `app/services/claims/code_rules/heat_pump_water_heater_neea/apply_product_list_match.rb`
- Add specific lookup table:
  - `claims.external_hpwh_products`
- Add FK on `claims.invoice_versions` only if we want a stable point-in-time matched row:
  - candidate field: `hpwh_external_product_id`
- Write code rulechecks:
  - `hpwh_found_in_neea_product_list`
  - `hpwh_neea_tier_2_or_higher`

Open question:

- Confirm whether the NEEA product list is downloadable in a stable CSV/XLS/PDF format or only searchable HTML.

## Second target

### 2. Air-to-Water and Combined Heat Pump Product List

Recommendation: do after HPWH, unless a real test invoice appears first.

Why:

- These two upgrade types are currently excluded from AHRI code rules.
- The website points to a specific qualifying product list.
- The logic should be mostly external-list match, similar to AHRI.

Upgrade types:

- `air_to_water_heat_pump`
- `combined_space_water_heat_pump`

Likely implementation:

- Add importer:
  - `app/services/claims/external_references/import_air_to_water_heat_pump_products.rb`
- Add code-rule file:
  - `app/services/claims/code_rules/air_to_water_product_list/apply_product_list_match.rb`
- Add specific lookup table:
  - `claims.external_air_to_water_heat_pump_products`
- Write code rulechecks:
  - `atw_found_in_qualifying_product_list`
  - `cshp_found_in_qualifying_product_list`

Open question:

- Confirm product-list structure and whether one table can safely cover both air-to-water and combined space/water systems.

## Third target

### 3. Ventilation Product and Spec Checks

Recommendation: do in two phases.

Phase A:

- Use GenAI for invoice/spec extraction only.
- Add simple deterministic checks where fields are already found:
  - bathroom fan capacity >= 85 cfm or >= 40 L/s
  - static pressure evidence around 50 Pa / 0.2 in. w.c.
  - continuous-duty motor evidence
  - backdraft damper evidence
  - ducted directly outside evidence

Phase B:

- Add external product-list imports only if the searchable NRCan/Energy Star data can be downloaded cleanly.

Why:

- Ventilation has a lot of invoice/spec language that may be visible without external lookup.
- The product-list side may be fussier than AHRI/NEEA, so keep it incremental.

Likely code-rule file:

- `app/services/claims/code_rules/ventilation_specs/apply_ventilation_checks.rb`

Likely rulechecks:

- `vent_bathroom_fan_capacity_meets_minimum`
- `vent_bathroom_fan_static_pressure_evidence_present`
- `vent_bathroom_fan_continuous_duty_evidence_present`
- `vent_bathroom_fan_backdraft_damper_evidence_present`
- `vent_hrv_erv_energy_star_or_nrcan_reference_present`

## Fourth target

### 4. Electrical Service Upgrade Deterministic Checks

Recommendation: good early code-rule candidate, but not an external-list candidate.

Why:

- Several checks are simple and deterministic once GenAI locates the right text.
- It avoids external download complexity.

Likely code-rule file:

- `app/services/claims/code_rules/electrical_service_upgrade/apply_service_upgrade_checks.rb`

Likely rulechecks:

- `esu_service_size_is_allowed`
- `esu_utility_service_upgrade_evidence_present`
- `esu_panel_only_exclusion_check`
- `esu_six_month_heat_pump_timing_check`

Keep GenAI-owned:

- Whether the upgrade is truly associated with an eligible fossil-fuel-to-heat-pump conversion, unless the application DB already supplies that association cleanly.

## Fifth target

### 5. Windows and Doors Certification/Product Rating

Recommendation: do not do first.

Why:

- The invoice evidence is messy.
- There are many acceptable certification bodies and identifiers.
- External data sources may not line up cleanly with invoice text.
- This may be better as a GenAI-located "product identifier/certification evidence" rule first, then later code where a specific identifier is reliable.

Possible future code-rule areas:

- U-factor numeric threshold if GenAI reliably extracts it.
- Product-rating identifier present.
- External CPD/NRCan/NFRC lookup if a stable downloadable source exists.

## Things to keep as admin/manual for now

Do not rush these into code:

- Product installed in accordance with installation guides.
- AHJ/bylaw/Technical Safety BC compliance.
- Contractor approval status, unless the program has a clean contractor approval table.
- Prior rebate history and one-per-home history, unless the application database has reliable historical claims.
- Pre-approval requirements such as Non-Integrated Area cases and health/safety confirmation.
- Fossil-fuel removal proof when it depends on supporting documents/photos/permits rather than invoice text.
- Heat-load calculation correctness, beyond detecting whether a heat-load document/reference exists.

## Proposed immediate next step

1. Investigate the NEEA HPWH product list source format.
2. Determine whether it can be downloaded as CSV/XLS/PDF/HTML.
3. If stable, create a tiny importer proof that loads only enough columns to answer:
   - model/manufacturer
   - tier
   - active/listed status if available
4. Add a read-only admin config screen only after the importer proof works.
5. Then add the `heat_pump_water_heater` code-rule file.

## Design rules going forward

- Each external code-rule family gets its own physical file.
- Each external lookup family gets a specific table if the columns are materially different.
- Do not over-generalize external reference storage too early.
- Prefer GenAI for messy extraction from invoices.
- Prefer code for exact external-list lookup and simple numeric thresholds.
- Store code outcomes in `claims.invoice_version_rulechecks` with `source_engine='code'`.
- Keep old code-rule files historically available when legislation changes; stop calling the old one rather than rewriting history.
- Keep active plan files short and current; archive stale planning drafts.
