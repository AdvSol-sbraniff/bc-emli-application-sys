# Air-To-Water / Combined Heat Pump Code Rule Plan

Date: 2026-05-15

## Purpose

We have now implemented two external-reference code-rule families:

- AHRI / BC Hydro heat pump product-list checks.
- NEEA heat pump water heater product-list checks.

This plan identifies the next best external-reference candidate from the Better Homes BC Energy Savings Program requirements page and lays out the implementation path.

## Source Review

Primary program page:

- `https://betterhomesbc.ca/learn-about-programs/energy-savings-program/energy-savings-program-requirements/`

Relevant product-list source:

- `https://betterhomesbc.ca/qualified-product-list-air-to-water-heat-pumps-PDF`

Other external-reference candidates noticed on the same program page:

- NEEA Residential HPWH Qualified Products List, already implemented.
- AHRI / BC Hydro heat pump product lists, already implemented.
- ENERGY STAR / NRCan ventilation product-list checks, likely valuable but messier.
- ENERGY STAR bathroom fan product-list checks, likely valuable but needs separate investigation.

## Recommendation

Build the Air-To-Water / Combined Heat Pump product-list code rules next.

Why this is the best next candidate:

- It is the closest sibling to AHRI and NEEA, so the mental model is already proven.
- It covers upgrade types that are currently excluded from the AHRI rule family.
- The Better Homes BC source PDF appears small and structured, with columns such as brand, model number, system type, and notes.
- The requirement is objective: the installed system should be listed on the qualifying product list.
- It should be cheaper and lower-risk than starting with ventilation, where the references split across ENERGY STAR/NRCan and product/spec evidence is more varied.

## Upgrade Types

Apply this rule family to:

- `air_to_water_heat_pump`
- `combined_space_water_heat_pump`

Do not apply this to:

- Regular air-source heat pumps already covered by AHRI.
- Heat pump water heaters already covered by NEEA.
- Ventilation, windows/doors, electrical service, insulation, or health/safety.

## Proposed User Journey

Admin setup:

- Admin opens `Downloads`.
- Admin opens a new `Air-to-water heat pump product list config` screen.
- Admin clicks a download/import button.
- Admin enters `publishing_date` and `publishing_notes`, same pattern as AHRI/NEEA.
- Screen shows the latest imported rows in a searchable grid.

Invoice processing:

- GenAI locates manufacturer/model/system evidence in the air-to-water or combined heat pump ruleset.
- After that upgrade-type LLM call completes, Sidekiq calls the new code-rule file.
- Code searches the current imported product-list rows.
- Code stores a point-in-time FK on `claims.invoice_versions`.
- Code writes one or more `source_engine='code'` rulechecks.

Admin review:

- PDF viewer shows the normal GenAI located fields and rulechecks.
- PDF viewer also shows a new `Air-to-water product-list match` section when there is a matched product row.
- The section shows brand, model, system type, source list, published date, import date, and source URL.

## Data Model

Use the same three-table pattern as AHRI and NEEA.

Recommended table names:

- `claims.awhp_sources`
- `claims.awhp_import_runs`
- `claims.awhp_products`

Reason for `awhp`:

- It is short enough for code.
- It means air-water heat pump.
- The product list covers both air-to-water and combined space/water heat pump systems, so `atw` alone is slightly too narrow.

Recommended `claims.awhp_sources` fields:

- `id uuid primary key`
- `description text not null`
- `source_url text not null`
- `created_at`
- `updated_at`

Recommended `claims.awhp_import_runs` fields:

- `id uuid primary key`
- `awhp_source_id uuid not null`
- `storage_provider varchar null`
- `storage_key text null`
- `content_type varchar null`
- `byte_size bigint null`
- `status text not null default 'queued'`
- `started_at timestamp not null default now()`
- `completed_at timestamp null`
- `records_imported integer not null default 0`
- `publishing_notes text null`
- `publishing_date date null`
- `file_sha256 text null`
- `error_text text null`
- `metadata_json jsonb null`
- `created_at`
- `updated_at`

Recommended `claims.awhp_products` fields:

- `id uuid primary key`
- `import_run_id uuid not null`
- `brand text null`
- `brand_normalized text null`
- `model_number text not null`
- `model_number_normalized text null`
- `model_number_regex text null`
- `system_type text null`
- `product_family text null`
- `eligibility_notes text null`
- `raw_row_json jsonb null`
- `created_at`
- `updated_at`

Recommended invoice version FK:

- `claims.invoice_versions.awhp_product_id uuid null`

Foreign key:

- `awhp_product_id` references `claims.awhp_products(id)`.

Recommended current view:

- `claims.v_current_awhp_products`

The current view should join products to the latest successful import run per source, exactly like `v_current_ahri_products` and `v_current_neea_products`.

## Code Rule Registry

Add registry rows:

- `awhp_found_in_qualifying_product_list`

Optional future rule rows if the product list exposes enough objective fields:

- `awhp_system_type_matches_upgrade_type`
- `awhp_product_notes_do_not_exclude_claim`

For v1, keep it simple:

- Only implement the product-list match.
- Treat notes/system type as display evidence unless the source list has clear deterministic status values.

## Physical Code Files

Importer:

- `app/services/claims/external_references/import_awhp_products.rb`

Code rule:

- `app/services/claims/code_rules/air_water_heat_pump_product_list/apply_product_list_match.rb`

Admin API:

- `app/controllers/api/claims/awhp_products_admin_controller.rb`

Models:

- `app/models/claims/awhp_source.rb`
- `app/models/claims/awhp_import_run.rb`
- `app/models/claims/awhp_product.rb`
- `app/models/claims/current_awhp_product.rb`

React:

- `app/frontend/components/domains/awhp-product-list-admin/index.tsx`
- Add a card on `app/frontend/components/domains/downloads-admin/index.tsx`.
- Add the admin PDF viewer section in `app/frontend/components/domains/invoice-versions/index.tsx`.

## GenAI Ruleset Changes

Update the air-to-water and combined heat pump rulesets to locate stable matching fields.

Recommended located field keys:

- `awhp_manufacturer`
- `awhp_model_number`
- `awhp_model_components`
- `awhp_make_model`
- `awhp_system_type_evidence`

Important instruction:

- Manufacturer and model number should be separate fields.
- `awhp_make_model` is display/fallback only.
- The code rule should primarily use manufacturer and model number.

## Matching Strategy

V1 matching should be forgiving but deterministic:

- Normalize manufacturer by uppercasing and removing punctuation.
- Normalize model by uppercasing and removing spaces.
- Support source-list wildcard patterns if the PDF uses them.
- Prefer exact model match.
- Add brand/manufacturer match as a score boost, not an absolute requirement.
- If multiple rows match, prefer exact brand plus exact model.
- If still tied, choose the first stable row ordered by brand/model/id and write enough evidence for admin review.

## Rulecheck Output

Rule: `awhp_found_in_qualifying_product_list`

Pass:

- Model/manufacturer evidence matched a current imported qualifying product-list row.

Warn:

- No model evidence was found by GenAI.
- No current product-list import exists.
- Model evidence was present but no current product-list row matched.

Avoid fail in v1:

- A non-match may be caused by invoice OCR quality, model aliasing, stale import data, or source-list parsing issues.
- Use `warn` until we have enough real invoices to know the matching is reliable.

## PDF Viewer Section

Add a section visible only when `invoice_versions.awhp_product_id` is present:

Title:

- `Air-to-water product-list match`

Fields:

- Brand
- Model number
- System type
- Product family
- Eligibility notes
- Source description
- Publishing date
- Import completed at
- Records imported
- Source URL

## Downloads Screen

Add a new card:

- Title: `Air-to-water heat pump product list config`
- Description: `Download, import, and inspect the qualifying product list used by air-to-water and combined heat-pump code rules.`
- Route: `/awhp-product-list-admin`

## Candidate Ranking After AWHP

Next after AWHP:

1. Ventilation HRV/ERV product-list check.
2. Bathroom fan ENERGY STAR product-list check.
3. Electrical service upgrade deterministic checks.
4. Windows/doors certification and U-factor checks.

Why ventilation is not first:

- It is valuable, but it has multiple product-list sources and several invoice/spec evidence checks.
- It may need both downloaded list data and GenAI-extracted spec fields.
- It is better tackled after one more product-list import proves the pattern is fully reusable.

## First Small Testable Step

The smallest useful test is the importer proof:

1. Download the AWHP PDF from the configured source URL.
2. Parse rows into a temporary in-memory structure.
3. Confirm row count and sample rows.
4. Only then add the DDL and admin screen.

Success condition:

- We can search the imported rows by manufacturer/model and find a known row from the PDF.

## Risks

- The PDF may use awkward text streams that require custom parsing.
- The source URL may redirect or block direct server downloads.
- Product rows may contain wildcard model numbers.
- The source list may cover both air-to-water and combined systems in one file, so the `system_type` mapping must be visible to admins.

## Open Questions

- Does the program expect the same qualifying list for both `air_to_water_heat_pump` and `combined_space_water_heat_pump`?
- Are there any known real invoices for these upgrade types we can use as matching test cases?
- Does the list include active/inactive/removed rows, or is every row in the latest PDF considered currently qualifying?
