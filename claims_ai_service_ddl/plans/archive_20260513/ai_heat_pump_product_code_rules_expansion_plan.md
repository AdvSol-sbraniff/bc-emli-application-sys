# Heat Pump Product-List Code Rules Expansion Plan

## Purpose

Expand the first AHRI code rule into a small family of deterministic heat-pump product-list checks.

These rules should run after the heat-pump upgrade GenAI call because the code needs the GenAI-located `hp_ahri_reference` field. The code rules then use the locally imported BC Hydro qualified heat-pump product list as the information on record.

## Public Requirement Basis

The Better Homes BC Energy Savings Program requirements repeat the following concepts across air-source heat-pump upgrade paths:

- The invoice/equipment should have an AHRI certified reference number for the heat-pump components.
- The heat pump should be listed as a qualifying system on the applicable qualified heat-pump product list.
- Air-source heat-pump rows require either `SEER >= 16.0 and HSPF >= 10.0` or `SEER2 >= 15.2 and HSPF2 >= 8.5`.
- Air-source heat-pump rows require a minimum capacity of `12,000 BTU`.
- Installation guide compliance, backup heat, fossil-fuel removal, sizing/design, region, and supporting documents are still document/business checks, not product-list code checks.

Source reviewed:

- `https://betterhomesbc.ca/learn-about-programs/energy-savings-program/energy-savings-program-requirements/`

## V1 Code Rules

All V1 rules stay in:

- `app/services/claims/code_rules/heat_pump_ahri/apply_product_list_match.rb`

This keeps the AHRI/product-list rule family physically isolated and easy to debug or replace later.

### Code Rule 1 - AHRI Found In Product List

Rule key:

- `hp_ahri_found_in_product_list`

Result logic:

- `pass` when the located AHRI number matches a row in the latest successful imported BC Hydro heat-pump product list.
- `warn` when no AHRI was located, no source list is available, or the AHRI was not found.

Side effect:

- Set `claims.invoice_versions.ahri_external_heat_pump_product_id` to the matched product row id.
- Clear that FK when the current rerun does not match, so stale previous matches do not linger.

### Code Rule 2 - Minimum Capacity At -5C

Rule key:

- `hp_product_minimum_capacity_at_minus_5c`

Result logic:

- `pass` when the matched product row has `rated_capacity_btu_at_minus_5c >= 12000`.
- `fail` when the product row has a value below `12000`.
- `warn` when the product row exists but the capacity value is missing.
- `info` when there is no matched product row, because Code Rule 1 already explains the missing AHRI/product-list match.

### Code Rule 3 - Efficiency Threshold

Rule key:

- `hp_product_efficiency_threshold`

Result logic:

- `pass` when either legacy metrics pass:
  - `SEER >= 16.0 and HSPF >= 10.0`
- Or when current metrics pass:
  - `SEER2 >= 15.2 and HSPF2 >= 8.5`
- `fail` when complete metric pairs are present but neither pair meets the threshold.
- `warn` when the product row exists but does not have enough metrics to evaluate either pair.
- `info` when there is no matched product row, because Code Rule 1 already explains the missing AHRI/product-list match.

## Explicit Non-V1 Items

Do not implement these as product-list code rules yet:

- Heat Pump Best Practices Installation Guide compliance.
- Contractor installed / self-installation.
- Fossil-fuel removal or modification.
- Backup heat source.
- Number of heads / zones.
- Home heat-load sizing.
- Region-specific outdoor switch-over settings.
- Northern top-up eligibility.
- Air-to-water / combined heat-pump product list checks.
- Heat-pump water-heater NEEA list checks.

Those need either different source lists, supporting documents, invoice language, homeowner/location facts, or admin review. They should stay as LLM/human-assisted rulechecks until we add the right structured source data.

## Human Retest

Use the known local heat-pump invoice with AHRI `213617706`.

Expected after rerunning GenAI:

- Admin PDF viewer shows the AHRI product-list section.
- Rule list shows:
  - `Code Rule 1 - AHRI Found In Product List`
  - `Code Rule 2 - Heat Pump Capacity At -5C Meets Minimum`
  - `Code Rule 3 - Heat Pump Efficiency Meets ESP Threshold`
- All three should pass for AHRI `213617706`.

