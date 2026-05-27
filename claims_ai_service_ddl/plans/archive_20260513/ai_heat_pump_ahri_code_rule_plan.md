# AI Heat Pump AHRI / Product List Code-Rule Plan

## Purpose

Add the first code-owned validation rule to the AI invoice review flow.

The target rule is heat pump product-list validation:

- GenAI locates the AHRI reference number and equipment evidence in the invoice.
- Code checks the AHRI number against an official cached BC Hydro qualified heat pump product list.
- The structured lookup result is stored on the invoice version.
- A normal `invoice_version_rulechecks` row is written so the admin/contractor PDF viewers and advice flow still see one unified rule result list.

This is intentionally not a pure GenAI rule. The AHRI/product-list match is objective external reference data, so code should own the final lookup.

## Source References

Better Homes BC requirement concept:

- Heat pump sections repeatedly require an AHRI certified reference number that references the applicable heat pump components.
- Heat pump sections repeatedly require the system to be listed on the applicable qualified heat pump product list.
- Heat pump sections also refer to installation in accordance with the Heat Pump Best Practices Installation Guide for Existing Homes.

BC Hydro lookup source:

- Search page: `https://app.bchydro.com/hero/HeatPumpLookup`
- Downloadable list endpoints observed:
  - `https://app.bchydro.com/hero/HeatPumpLookup/DownloadMiniSplitSingleHeadListPDF`
  - `https://app.bchydro.com/hero/HeatPumpLookup/DownloadMiniSplitMultiHeadListPDF`
  - `https://app.bchydro.com/hero/HeatPumpLookup/DownloadVariableSpeedCentralSystemListPDF`

Known manual test:

- AHRI `213617706` appears in the BC Hydro ductless mini-split heat pump list published `2026-04-12`.
- Matched values observed:
  - Make: `Mitsubishi Electric`
  - Outdoor model: `PUZ-HA30NKA1***`
  - Indoor model / air handler: `PVA-A30AA*`
  - Rated capacity @ -5C: `32900`
  - SEER2: `18.00`
  - HSPF2: `8.70`
  - COP: `2.10`
  - Capacity maintenance: `94%`
  - Cold climate rated: `Yes`

Local PDF parsing discovery:

- The downloaded file `claims_ai_service_ddl/reference_data/Ductless mini-split heat pump List.pdf` is text-backed, not image-only OCR.
- The AHRI value `213617706` was found directly in a decompressed PDF text stream.
- The nearby PDF text stream included the expected structured row values:
  - AHRI: `213617706`
  - Type: `Ductless mini-split heat pump`
  - Make: `Mitsubishi Electric`
  - Outdoor model: `PUZ-HA30NKA1***`
  - Indoor model / air handler: `PVA-A30AA*`
  - Rated capacity @ -5C: `32900`
  - SEER2: `18.00`
  - HSPF2: `8.70`
  - COP: `2.10`
  - Capacity maintenance: `94%`
  - Cold climate rated: `Yes`
- This means the importer should parse embedded PDF text directly.
- Do not use Azure Document Intelligence, OCR, or an LLM for these BC Hydro source PDFs unless a future PDF source is image-only or the deterministic parser proves unreliable.

## Design Principles

- Keep the raw source file, not just parsed rows.
- Do not scrape live websites during invoice review.
- Import external reference data ahead of time, then review invoices against the cached table.
- Store import health in the database so failures are visible.
- Store the raw downloaded source PDF in the same Azure blob container pattern used by invoice PDFs.
- Store the matched external product row UUID directly on `claims.invoice_versions` for v1.
- Store the admin-visible pass/info/warn/fail outcome in the existing `claims.invoice_version_rulechecks` table.
- Keep the implementation specific rather than over-generalized. Future external checks can get their own specific tables if their fields differ.

V1 implementation decision:

- AHRI remains a normal GenAI located field using static `field_key='hp_ahri_reference'`.
- `claims.invoice_versions.ahri_external_heat_pump_product_id` stores the point-in-time matched external product row.
- No separate invoice-version AHRI child table is used in v1.
- No AHRI reference number is duplicated on `claims.invoice_versions`; the number remains in `claims.invoice_version_located_fields`.
- No-match, missing-AHRI, and stale-source explanations live in `claims.invoice_version_rulechecks`, not in a separate match table.

## Gate 1: DDL Shape

Purpose:

Create the persistent structures without changing runtime behavior.

Add table `claims.external_reference_import_runs`.

Suggested fields:

- `id uuid primary key default gen_random_uuid()`
- `source_key text not null`
- `source_url text not null`
- `source_description text null`
- `storage_provider text null`
- `storage_key text null`
- `original_filename text null`
- `content_type text null`
- `byte_size bigint null`
- `status text not null`
- `started_at timestamp not null default now()`
- `completed_at timestamp null`
- `records_imported integer not null default 0`
- `source_published_date date null`
- `storage_key text null`
- `file_sha256 text null`
- `error_text text null`
- `metadata_json jsonb null`
- `created_at timestamp not null default now()`
- `updated_at timestamp not null default now()`

Suggested status values:

- `queued`
- `running`
- `succeeded`
- `failed`

Add table `claims.external_heat_pump_products`.

Suggested fields:

- `id uuid primary key default gen_random_uuid()`
- `import_run_id uuid not null references claims.external_reference_import_runs(id)`
- `ahri_reference_number text not null`
- `heat_pump_type text null`
- `make text null`
- `outdoor_model text null`
- `indoor_model_or_air_handler text null`
- `furnace_model text null`
- `rated_capacity_btu_at_minus_5c numeric null`
- `seer numeric null`
- `seer2 numeric null`
- `hspf numeric null`
- `hspf2 numeric null`
- `cop numeric null`
- `capacity_maintenance_percent numeric null`
- `cold_climate_rated boolean null`
- `eligibility_notes text null`
- `raw_row_json jsonb null`
- `created_at timestamp not null default now()`
- `updated_at timestamp not null default now()`

Suggested indexes:

- Unique enough for cache lookup:
  - `(import_run_id, ahri_reference_number, heat_pump_type, outdoor_model, indoor_model_or_air_handler, coalesce(furnace_model,''))`
- Lookup index:
  - `(ahri_reference_number)`

Add table `claims.invoice_version_heat_pump_product_checks`.

Suggested fields:

- `id uuid primary key default gen_random_uuid()`
- `invoice_version_id uuid not null references claims.invoice_versions(id) on delete cascade`
- `status text not null`
- `ahri_reference_number text null`
- `external_heat_pump_product_id uuid null references claims.external_heat_pump_products(id)`
- `source_key text null`
- `source_url text null`
- `source_published_date date null`
- `heat_pump_type text null`
- `make text null`
- `outdoor_model text null`
- `indoor_model_or_air_handler text null`
- `furnace_model text null`
- `rated_capacity_btu_at_minus_5c numeric null`
- `seer numeric null`
- `seer2 numeric null`
- `hspf numeric null`
- `hspf2 numeric null`
- `cop numeric null`
- `capacity_maintenance_percent numeric null`
- `cold_climate_rated boolean null`
- `eligibility_notes text null`
- `checked_at timestamp not null default now()`
- `error_text text null`
- `result_json jsonb null`
- `created_at timestamp not null default now()`
- `updated_at timestamp not null default now()`

Suggested status values:

- `matched`
- `not_found`
- `missing_ahri`
- `source_unavailable`
- `not_applicable`
- `error`

Suggested uniqueness:

- `unique(invoice_version_id)`

Human test:

- Run schema locally.
- Confirm the three new tables exist.
- Confirm no runtime behavior changed.

## Gate 2: External List Importer

Purpose:

Build a service that downloads official BC Hydro list PDFs, stores the raw files, parses rows, and loads `claims.external_heat_pump_products`.

First implemented slice:

- Added DDL for:
  - `claims.external_reference_import_runs`
  - `claims.external_heat_pump_products`
- Added ActiveRecord models:
  - `Claims::ExternalReferenceImportRun`
  - `Claims::ExternalHeatPumpProduct`
- Added importer service:
  - `app/services/claims/external_references/import_bc_hydro_heat_pump_products.rb`
- Added manual rake task:
  - `claims:external_references:import_heat_pump_products`
- Local proof run imported `7,394` product rows from `claims_ai_service_ddl/reference_data/Ductless mini-split heat pump List.pdf`.
- Local proof lookup for AHRI `213617706` returned Mitsubishi Electric / `PUZ-HA30NKA1***` / `PVA-A30AA*` with SEER2 `18.0`, HSPF2 `8.7`, COP `2.1`, capacity maintenance `94%`, and cold-climate rated `true`.
- This first slice reads the locally downloaded PDF. Downloading fresh source PDFs and object-storage retention are still future work.
- Added admin UI route `/heat-pump-product-list-admin`, linked from `/rulesets-admin` as `Heat pump product list config`.
- Added admin API endpoints for import status, searchable latest-success product rows, and manual import of the downloaded PDF.

Suggested service:

- `app/services/claims/external_references/import_bc_hydro_heat_pump_products.rb`

Suggested behavior:

1. Create `external_reference_import_runs` row with `status='running'`.
2. Download each configured BC Hydro PDF endpoint.
3. Store each raw PDF in object storage.
   - Suggested key shape:
     - `reference-data/bc-hydro-heat-pump-qpl/<published-date>/<list-key>.pdf`
4. Calculate and store SHA-256 hash.
5. Parse rows from each PDF.
6. Validate minimum row quality:
   - AHRI number present.
   - Make or model present.
   - Non-zero parsed row count.
7. Insert product rows in a transaction.
8. Mark import run `succeeded`.
9. On failure, mark import run `failed` with `error_text`.

Implementation note:

- Use deterministic embedded-text PDF parsing for the first implementation.
- In Rails/Ruby, prefer a library such as `pdf-reader` so the importer can run inside the app/Sidekiq image.
- Parse rows by locating AHRI-number-led table rows and reconstructing columns from nearby text positions.
- Expect some long notes columns to wrap awkwardly; prioritize reliable structured columns first:
  - AHRI reference number.
  - Heat pump type.
  - Make.
  - Outdoor model.
  - Indoor model / air handler.
  - Furnace model, when applicable.
  - Rated capacity @ -5C.
  - SEER/SEER2/HSPF/HSPF2/COP.
  - Capacity maintenance percent.
  - Cold climate rated.
  - Eligibility notes, best effort.
- Avoid LLM parsing for this source unless deterministic parsing fails badly.

Human test:

- Run importer locally.
- Confirm AHRI `213617706` imports.
- Confirm imported row values match the known manual lookup.
- Confirm a failed URL produces a failed import-run row.

## Gate 3: Admin Refresh / Import Health

Purpose:

Make the importer visible and manually testable before any scheduler is added.

Suggested UI/API:

- Admin endpoint to trigger refresh:
  - `POST /api/claims/admin/external_references/bc_hydro_heat_pump_products/refresh`
- Admin endpoint to view latest import state:
  - `GET /api/claims/admin/external_references/bc_hydro_heat_pump_products/status`

Suggested admin display:

- Last successful refresh time.
- Last source published date.
- Records imported.
- Last failure time/error, if any.
- Warning if last success is older than a configurable threshold.

Human test:

- Trigger refresh from admin screen or API.
- Confirm import run row changes from running to succeeded.
- Confirm failure state is visible when the importer is forced to fail.

## Gate 4: Code Rule Service

Purpose:

Run the AHRI/product-list lookup after heat-pump GenAI has persisted located fields.

Suggested service:

- `app/services/claims/code_rules/heat_pump_product_list_check.rb`

Inputs:

- `invoice_version_id`

Behavior:

1. Determine whether the current upgrade type is an AHRI-relevant heat-pump upgrade type.
2. Read `hp_ahri_reference` located field from `claims.invoice_version_located_fields` for that upgrade type.
3. If no AHRI:
   - Leave `invoice_versions.ahri_external_heat_pump_product_id` null.
   - Upsert `invoice_version_rulechecks.rule_result='warn'`.
4. If AHRI exists:
   - Search latest imported `claims.external_heat_pump_products` rows for exact AHRI match.
5. If match:
   - Store the matched row id in `invoice_versions.ahri_external_heat_pump_product_id`.
   - Upsert `invoice_version_rulechecks.rule_result='pass'`.
6. If not found:
   - Leave `invoice_versions.ahri_external_heat_pump_product_id` null.
   - Upsert rulecheck `warn`.
7. If no imported source list:
   - Leave `invoice_versions.ahri_external_heat_pump_product_id` null.
   - Upsert rulecheck `warn`.

Suggested rulecheck values:

- `rule_key='hp_ahri_found_in_product_list'`
- `rule_name='AHRI Found In Product List'`
- `source_requirement_id='ESP-2026-HP-AHRI-001'`
- `evidence_source='external_list'`
- `source_engine='code'`

Human test:

- With AHRI `213617706`, confirm `invoice_versions.ahri_external_heat_pump_product_id` and pass rulecheck row.
- With fake AHRI, confirm FK remains null and warn rulecheck.
- With no AHRI, confirm FK remains null and warn rulecheck.

## Gate 5: GenAI Job Integration

Purpose:

Call the code rule after relevant heat-pump LLM output has been persisted.

Integration point:

- After each heat-pump upgrade ruleset call persists located fields/rulechecks.
- Call code rule when upgrade type is one of:
  - `air_source_heat_pump_electric`
  - `air_source_heat_pump_wood`
  - `air_source_heat_pump_gas_propane`
  - `air_source_heat_pump_oil`
  - `dual_fuel_ducted_heat_pump`
  - `air_to_water_heat_pump`
  - `combined_space_water_heat_pump`

Important:

- Do not run before the LLM output is persisted, because the code rule needs the `hp_ahri_reference` found field.
- Ensure GenAI reruns clean stale code-rule results for that invoice version before recomputing.

Human test:

- Run OCR + full GenAI on a heat-pump invoice with AHRI.
- Confirm code-rule row appears after GenAI.
- Confirm rulecheck appears in the normal rule list.
- Confirm advice includes code-rule only if info/warn/fail.

## Gate 6: PDF Viewer Section

Purpose:

Expose the structured AHRI/product-list match details without forcing admins to read only the rule explanation.

Suggested section title:

- `Heat Pump Product List Check`

Show section when:

- `invoice_version_heat_pump_product_checks` has a row, or
- invoice has a heat-pump upgrade type.

Suggested display fields:

- Status dot.
- AHRI reference number.
- Matched list/source.
- Source published date.
- Make.
- Outdoor model.
- Indoor model / air handler.
- Furnace model, if applicable.
- Rated capacity @ -5C.
- SEER/SEER2/HSPF/HSPF2/COP.
- Capacity maintenance percent.
- Cold climate rated.
- Eligibility notes.
- Source link.

Important:

- The rulecheck remains in the normal rule list.
- This section is the structured lookup detail.

Human test:

- Admin PDF viewer shows the AHRI section for a matched heat-pump invoice.
- Contractor PDF viewer should likely show the section too, because contractors need to understand product-list issues before admin review.
- Non-heat-pump invoices do not show the section.

## Gate 7: Scheduler

Purpose:

Automate the external reference refresh only after manual refresh is proven.

Preferred options:

1. OpenShift `CronJob`.
2. Sidekiq scheduler / sidekiq-cron.

Recommendation:

- Start with manual refresh.
- Add scheduler later.
- The scheduler must call the same importer as the manual refresh.
- The DB import-run table is the source of operational truth, not the CronJob log.

Operational check:

- Admin UI should warn when latest successful import is stale.
- Consider an app health/admin alert when latest success is older than 7 days.

## Open Questions

- Does BC Hydro expose a stable JSON API behind the lookup page?
- Is PDF parsing reliable enough for the three observed list PDFs?
- Should `not_found` be warn or fail for v1?
- Should AHRI/product-list rule be duplicated across all heat-pump rulesets as a rule task, or only injected by code after matching heat-pump upgrade types?
- Should `source_engine='code'` be added to `claims.invoice_version_rulechecks` if not already present?
- Do we need separate import support for air-to-water / combined space-water lists hosted by Better Homes BC rather than BC Hydro?
- Should the raw source PDFs be stored in the same object storage bucket/prefix as invoice PDFs or in a separate reference-data prefix?
