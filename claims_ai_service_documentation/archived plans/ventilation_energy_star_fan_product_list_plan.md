# Ventilation ENERGY STAR Fan Product List Implementation Plan

## Purpose

Implement the ventilation requirement:

```text
Fans must be ENERGY STAR certified and listed on the US Environmental Protection Agency and US Department of Energy's searchable product list.
```

This plan covers the ventilating fan product-list requirement only. It is separate from the HERV/ERV product-list work because the ENERGY STAR ventilating-fan catalogue is a different source, different data shape, and different rule.

## Decision

Create a sixth external-reference catalogue for ENERGY STAR certified ventilating fans.

This plan includes:

```text
1. A Downloads admin extension so staff can import and inspect the ENERGY STAR ventilating-fan product list.
2. A code-owned ventilation rule, vent_fan_energy_star_product_list_match, that checks fan product evidence against the imported ENERGY STAR ventilating-fan list.
3. End-to-end faux invoice/supporting-document test data so the full ingest path can be tested, not just a synthetic DB-only path.
```

Existing catalogue families after the HERV work:

| Family                                          | Source table          | Import run table          | Product table          | Current view                     | Invoice FK                         |
| ----------------------------------------------- | --------------------- | ------------------------- | ---------------------- | -------------------------------- | ---------------------------------- |
| AHRI / BC Hydro heat pump lists                 | `claims.ahri_sources` | `claims.ahri_import_runs` | `claims.ahri_products` | `claims.v_current_ahri_products` | `invoice_versions.ahri_product_id` |
| NEEA HPWH list                                  | `claims.neea_sources` | `claims.neea_import_runs` | `claims.neea_products` | `claims.v_current_neea_products` | `invoice_versions.neea_product_id` |
| Better Homes BC air-to-water / combined HP list | `claims.awhp_sources` | `claims.awhp_import_runs` | `claims.awhp_products` | `claims.v_current_awhp_products` | `invoice_versions.awhp_product_id` |
| NRCan OHPA BC ASHP list                         | `claims.ohpa_sources` | `claims.ohpa_import_runs` | `claims.ohpa_products` | `claims.v_current_ohpa_products` | `invoice_versions.ohpa_product_id` |
| NRCan ENERGY STAR HERV/ERV list                 | `claims.herv_sources` | `claims.herv_import_runs` | `claims.herv_products` | `claims.v_current_herv_products` | `invoice_versions.herv_product_id` |

New catalogue family:

| Family                                 | Source table              | Import run table              | Product table              | Current view                         | Invoice FK                             |
| -------------------------------------- | ------------------------- | ----------------------------- | -------------------------- | ------------------------------------ | -------------------------------------- |
| ENERGY STAR certified ventilating fans | `claims.vent_fan_sources` | `claims.vent_fan_import_runs` | `claims.vent_fan_products` | `claims.v_current_vent_fan_products` | `invoice_versions.vent_fan_product_id` |

## Confirmed Source Findings

Requirement URL:

```text
https://www.energystar.gov/productfinder/product/certified-ventilating-fans/results?SetLanguage=English&NRCAN=on
```

Confirmed download endpoint:

```text
https://www.energystar.gov/productfinder/download/certified-ventilating-fans/
```

Observed response headers:

```text
Content-Type: application/vnd.ms-excel;charset=ISO-8859-1
Content-Disposition: attachment; filename=certified-ventilating-fans-YYYY-MM-DD.csv
```

Observed Socrata/API dataset endpoint:

```text
https://data.energystar.gov/resource/8dv7-nngq.json
https://data.energystar.gov/resource/8dv7-nngq.csv
```

Observed CSV columns from the official download:

```text
ENERGY STAR Unique ID
ENERGY STAR Partner
Brand Name
Model Name
Model Number
Additional Model Information
UPC
Type
MERV of In-line Fan Filter
Number of Speeds
Duct Size
Sound Level (sones)
Bathroom and Utility Room Sound Level (sones) at 0.25 in. w.g.
Bathroom and Utility Room Airflow at 0.25 in. w.g.
Shipped with ENERGY STAR Lamp(s)
ENERGY STAR Lamp ESUID
Alternate ENERGY STAR Lamps ESUIDs
ENERGY STAR Lamp Partner
Lamp Model Number
Lighting Technology
Total Light Output (lumens)
Total Input Power (Watts)
Energy Efficiency - Measured Outside the Fixture (lm/W)
Power Factor
Light Color Appearance (CCT)
Light Color Quality (CRI)
Light Source Life (Hours)
Special Features (Dimming, Motion Sensing, etc.)
Notes
Lighting
Airflow 1 (cfm)
Airflow 2 (cfm)
Airflow 3 (cfm)
Efficacy 1 (cfm/Watt)
Efficacy 2 (cfm/Watt)
Efficacy 3 (cfm/Watt)
Ventilating Fan Features
Date Available On Market
Date Qualified
Markets
CB Model Identifier
Meets ENERGY STAR Most Efficient 2025 Criteria
```

Observed sample row:

```text
Brand Name: ACIQ
Model Name: AEP
Model Number: AEP110
Type: Bathroom/Utility Room
Airflow 1 (cfm): 110
Efficacy 1 (cfm/Watt): 4.2
Markets: United States
CB Model Identifier: ES_1151218_AEP110_09272024000000_1008147
```

Important source nuance:

```text
The requirement link includes NRCAN=on, but the direct downloadable CSV endpoint returns a full ENERGY STAR ventilating-fan catalogue that includes rows with Markets values such as United States and United States, Canada.

Recommendation: import all rows and preserve Markets. Do not silently hard-filter rows to Canada during import unless the program owner explicitly confirms that the rule should require Canada-market rows only. The code rule can include Markets in calculation/admin evidence.
```

## Required Schema Changes

Update `claims_ai_service_ddl/2_create_schema.sql`.

The fan DDL should intentionally mirror the existing product-list family pattern:

```text
source table: one stable source/catalogue row per source URL
import_runs table: child/history rows for each import attempt
products table: cached product rows from a successful import
current view: latest successful import rows
invoice_versions FK: one matched product row used by code/review UI
```

Do not create a generic key/value product table. Keep this as a plain typed product table, same style as HERV/OHPA/AWHP/NEEA/AHRI.

### Exact Fan DDL

```sql
-- ============================================================
-- vent_fan_sources
-- PURPOSE: Stable catalogue of ENERGY STAR certified
-- ventilating-fan product-list source definitions. Import runs
-- are child/history records under these source rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.vent_fan_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT vent_fan_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_vent_fan_sources_description
  ON claims.vent_fan_sources (description);



-- ============================================================
-- vent_fan_import_runs
-- PURPOSE: Track refresh attempts for ENERGY STAR certified
-- ventilating-fan CSV data used by code-owned ventilation checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.vent_fan_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  vent_fan_source_id uuid NOT NULL,
  storage_provider character varying NULL,
  storage_key text NULL,
  content_type character varying NULL,
  byte_size bigint NULL,
  status text NOT NULL DEFAULT 'queued',

  started_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  completed_at timestamp(6) without time zone NULL,

  records_imported integer NOT NULL DEFAULT 0,
  publishing_notes text NULL,
  publishing_date date NULL,
  file_sha256 text NULL,
  error_text text NULL,
  metadata_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT vent_fan_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT vent_fan_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT vent_fan_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_vent_fan_import_runs_source
    FOREIGN KEY (vent_fan_source_id)
    REFERENCES claims.vent_fan_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_vent_fan_import_runs_source_started
  ON claims.vent_fan_import_runs (vent_fan_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_vent_fan_import_runs_status
  ON claims.vent_fan_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_vent_fan_import_runs_storage_key
  ON claims.vent_fan_import_runs (storage_key);



-- ============================================================
-- vent_fan_products
-- PURPOSE: Cached ENERGY STAR certified ventilating-fan
-- product-list rows used by code-owned ventilation fan checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.vent_fan_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  energy_star_unique_id text NULL,
  energy_star_partner text NULL,
  brand text NOT NULL,
  brand_normalized text NOT NULL,
  product_model_name text NULL,
  model_number text NOT NULL,
  model_number_normalized text NOT NULL,
  model_number_regex text NULL,
  additional_model_information text NULL,
  upc text NULL,

  fan_type text NULL,
  number_of_speeds text NULL,
  duct_size text NULL,
  sound_level_sones numeric NULL,
  bathroom_utility_sound_level_sones_at_0_25_in_wg numeric NULL,
  bathroom_utility_airflow_at_0_25_in_wg numeric NULL,

  lighting text NULL,
  shipped_with_energy_star_lamps text NULL,
  energy_star_lamp_esuid text NULL,
  alternate_energy_star_lamps_esuids text NULL,
  energy_star_lamp_partner text NULL,
  lamp_model_number text NULL,
  lighting_technology text NULL,
  total_light_output_lumens numeric NULL,
  total_input_power_watts numeric NULL,
  luminaire_efficacy numeric NULL,
  power_factor numeric NULL,
  cct_kelvin integer NULL,
  cri integer NULL,
  light_source_life_hours integer NULL,
  special_features text NULL,

  airflow_1_cfm numeric NULL,
  airflow_2_cfm numeric NULL,
  airflow_3_cfm numeric NULL,
  efficacy_1_cfm_watt numeric NULL,
  efficacy_2_cfm_watt numeric NULL,
  efficacy_3_cfm_watt numeric NULL,
  ventilating_fan_features text NULL,

  date_available_on_market date NULL,
  date_qualified date NULL,
  markets text NULL,
  cb_model_identifier text NULL,
  meets_most_efficient_criteria text NULL,
  notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT vent_fan_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_vent_fan_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.vent_fan_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_import_run
  ON claims.vent_fan_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_brand_model_norm
  ON claims.vent_fan_products (brand_normalized, model_number_normalized);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_model_norm
  ON claims.vent_fan_products (model_number_normalized);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_energy_star_unique_id
  ON claims.vent_fan_products (energy_star_unique_id);

CREATE INDEX IF NOT EXISTS idx_vent_fan_products_cb_model_identifier
  ON claims.vent_fan_products (cb_model_identifier);



ALTER TABLE claims.invoice_versions
  ADD COLUMN IF NOT EXISTS vent_fan_product_id uuid NULL;

ALTER TABLE claims.invoice_versions
  DROP CONSTRAINT IF EXISTS fk_invoice_versions_vent_fan_product;

ALTER TABLE claims.invoice_versions
  ADD CONSTRAINT fk_invoice_versions_vent_fan_product
  FOREIGN KEY (vent_fan_product_id)
  REFERENCES claims.vent_fan_products(id);

CREATE INDEX IF NOT EXISTS idx_invoice_versions_vent_fan_product_id
  ON claims.invoice_versions (vent_fan_product_id);
```

## Required View Changes

Update `claims_ai_service_ddl/4_create_views.sql`.

```sql
CREATE OR REPLACE VIEW claims.v_current_vent_fan_products AS
SELECT p.*
FROM claims.vent_fan_products p
JOIN claims.vent_fan_import_runs r
  ON r.id = p.import_run_id
WHERE r.status = 'succeeded'
  AND r.completed_at = (
    SELECT max(r2.completed_at)
    FROM claims.vent_fan_import_runs r2
    WHERE r2.vent_fan_source_id = r.vent_fan_source_id
      AND r2.status = 'succeeded'
  );
```

## Required Seed Changes

Create `claims_ai_service_ddl/3_insert_vent_fan_sources.sql`.

```sql
INSERT INTO claims.vent_fan_sources (id, description, source_url)
VALUES (
  'TBD-STABLE-UUID-HERE',
  'ENERGY STAR Certified Ventilating Fans Product List',
  'https://www.energystar.gov/productfinder/product/certified-ventilating-fans/results?SetLanguage=English&NRCAN=on'
)
ON CONFLICT (id) DO UPDATE
SET
  description = EXCLUDED.description,
  source_url = EXCLUDED.source_url,
  updated_at = now();
```

Update `claims_ai_service_ddl/README_REBUILD_ORDER.txt` so the fan source seed runs with the other product-list source seeds.

## Required Rails Models

Add:

```text
app/models/claims/vent_fan_source.rb
app/models/claims/vent_fan_import_run.rb
app/models/claims/vent_fan_product.rb
app/models/claims/current_vent_fan_product.rb
```

Update:

```text
app/models/claims/invoice_version.rb
```

Add:

```ruby
belongs_to :vent_fan_product,
           class_name: "Claims::VentFanProduct",
           optional: true
```

## Required Importer

Add:

```text
app/services/claims/external_references/import_vent_fan_products.rb
```

Recommended behaviour:

```text
1. Accept vent_fan_source_id, publishing_date, publishing_notes, and optional csv_path.
2. If csv_path is present, parse that CSV.
3. If csv_path is absent, download from https://www.energystar.gov/productfinder/download/certified-ventilating-fans/.
4. Parse using CSV headers from the official ENERGY STAR download.
5. Normalize brand and model number using the same normalization style as product_lookup_enrichment.
6. Build a safe model_number_regex for exact-ish model matching.
7. Insert typed rows into claims.vent_fan_products.
8. Dedupe rows by energy_star_unique_id when present, otherwise by brand_normalized + model_number_normalized + cb_model_identifier.
9. Upload the source CSV through the existing Node upload pattern used by the other importers.
10. Mark import run succeeded with records_imported, byte_size, file_sha256, storage_key, and metadata_json.
11. Mark import run failed with error_text when parsing/downloading/uploading fails.
```

Do not filter out non-Canada `Markets` rows inside the importer. Preserve `markets` and let the rule/admin display decide what to do with that evidence.

## Required Rake Task

Update:

```text
lib/tasks/claims_external_references.rake
```

Add:

```text
claims:external_references:import_vent_fan_products
```

The task should mirror the HERV task options:

```text
VENT_FAN_SOURCE_ID
CSV_PATH
PUBLISHING_DATE
PUBLISHING_NOTES
```

## Required Admin/API/UI

Add controller:

```text
app/controllers/api/claims/vent_fan_products_admin_controller.rb
```

Routes:

```ruby
get "admin/vent_fan_products", to: "vent_fan_products_admin#index"
get "admin/vent_fan_products/import_status", to: "vent_fan_products_admin#import_status"
post "admin/vent_fan_products/import_downloaded_csv", to: "vent_fan_products_admin#import_downloaded_csv"
```

Add frontend screen:

```text
app/frontend/components/domains/vent-fan-product-list-admin/index.tsx
```

Update:

```text
app/frontend/components/domains/downloads-admin/index.tsx
app/frontend/components/domains/navigation/index.tsx
app/frontend/components/domains/navigation/sub-nav-bar.tsx
```

Admin screen columns should include:

```text
Brand
Model number
Product model name
Type
Airflow 1 CFM
Efficacy 1 CFM/Watt
Sound level sones
Markets
ENERGY STAR Unique ID
CB Model Identifier
Import run
```

## Required Product Lookup Enrichment

Update:

```text
app/services/claims/product_lookup_enrichment/apply.rb
```

Ventilation matching should have two separate branches:

```text
1. HERV/ERV branch:
   Match HRV/ERV evidence against v_current_herv_products and write invoice_versions.herv_product_id.

2. Fan branch:
   Match bathroom/utility/ventilating fan evidence against v_current_vent_fan_products and write invoice_versions.vent_fan_product_id.
```

Fan matching evidence:

```text
Invoice fields:
- vent_manufacturer
- vent_model_number
- vent_make_model

Supporting-document fields:
- brand_and_model
- model_number
- energy_star_reference
- product_list_reference
- nrcan_reference, if present in older/generic prompts

DI fields:
- Do not invent unnamed DI concepts. Use named DI fields only if there is a clear named DI field in context. Otherwise rely on second-class GenAI fields.
```

Recommended match rules:

```text
1. Prefer exact normalized model_number match when model number is present.
2. Prefer brand_normalized + model_number_normalized when brand is available.
3. Allow model_number_regex only for safe model-number boundary matching.
4. Do not match on brand alone.
5. Do not match on ENERGY STAR wording alone.
6. Require invoice evidence and supporting-document evidence to resolve to the same current fan product before writing vent_fan_product_id.
7. If multiple current products match the same evidence ambiguously, leave vent_fan_product_id null and let the rule warn.
```

## Required Code Rule

Add:

```text
app/services/claims/code_rules/ventilation_fan/apply_product_list_match.rb
```

Register in:

```text
app/services/claims/invoice_version_rulechecks/apply_upgrade_code_rulechecks.rb
```

Seed in:

```text
claims_ai_service_ddl/3_insert_code_rules.sql
```

Rule key:

```text
vent_fan_energy_star_product_list_match
```

Upgrade type mapping:

```text
ventilation
```

Recommended rule description:

```text
Checks whether the visible ventilating fan product evidence from the invoice and supporting documents resolves to a current ENERGY STAR certified ventilating-fan product-list row.

Pseudo-code:
1. Run only for ventilation invoice versions.
2. Read invoice_versions.vent_fan_product_id, which is populated by product lookup enrichment only when invoice evidence and supporting-document evidence resolve to the same current ENERGY STAR ventilating-fan product row.
3. If vent_fan_product_id is present and the referenced product belongs to the latest successful ENERGY STAR ventilating-fan import, return pass.
4. Include the matched brand, model number, fan type, ENERGY STAR Unique ID, CB Model Identifier, Markets, and import_run_id in calculation.
5. If invoice or supporting-document product evidence is missing, ambiguous, or does not resolve to the same imported product row, return warn so admin can verify the ENERGY STAR fan listing manually.
6. Return fail only when the evidence clearly identifies a fan product and that identified fan product is not present in the imported current ENERGY STAR ventilating-fan list.
```

Recommended rule result logic:

```text
pass:
- vent_fan_product_id is present and points to claims.v_current_vent_fan_products.

warn:
- no fan model evidence is visible.
- invoice evidence exists but supporting-document evidence is missing.
- supporting-document evidence exists but invoice evidence is missing.
- evidence exists but matches multiple fan products.
- evidence exists but cannot be confidently matched to the imported list.

fail:
- visible invoice/supporting-document evidence identifies a specific fan model and the model is clearly absent from the current imported ENERGY STAR ventilating-fan list.
```

## GenAI Prompt/Field Impact

No new second-class GenAI fields are required at plan time if existing ventilation product fields are working:

```text
vent_manufacturer
vent_model_number
vent_make_model
```

Keep the existing supporting-document fields:

```text
brand_and_model
model_number
energy_star_reference
product_list_reference
```

If testing shows fan invoices regularly describe products differently than HERV/ERV invoices, consider a future dedicated field:

```text
vent_fan_make_model
```

Do not add that field now unless testing proves the generic `vent_make_model` is too ambiguous.

Update the existing GenAI rule prompt, if needed, so it does not try to decide product-list membership itself. It should say the deterministic ENERGY STAR list match is handled by code when product evidence is visible.

## Required Review Payload/UI

Update invoice-version serializers:

```text
app/controllers/api/claims/invoice_versions_controller.rb
app/controllers/api/claims/invoice_versions_admin_controller.rb
```

Expose:

```text
vent_fan_product_match
```

Include:

```text
brand
model_number
product_model_name
fan_type
airflow_1_cfm
efficacy_1_cfm_watt
sound_level_sones
markets
energy_star_unique_id
cb_model_identifier
import_run_id
```

Update review UI:

```text
app/frontend/components/domains/contractor-invoice-review/index.tsx
app/frontend/components/domains/invoice-versions/index.tsx
```

Display a compact "ENERGY STAR ventilating fan match" panel only when a match exists.

## Reset/Clone/Fix Package Impact

Update any reset/clone/fix-package code that clears product matches:

```text
app/services/claims/invoice_versions/reset_ai_outputs.rb
app/services/claims/ingest/create_rule_change_run.rb
app/services/claims/ingest/upload_fix_package.rb
```

Ensure `vent_fan_product_id` is cleared with the other product IDs.

## Test Data

Create a new folder:

```text
claims_ai_service_documentation/Test Data/Ventilation/test002 - ENERGY STAR fan product list match/
```

Recommended files:

```text
faux_invoice.txt
faux_invoice.pdf
faux_supporting_doc_product_spec_sheet.txt
faux_supporting_doc_product_spec_sheet.pdf
faux_supporting_doc_energy_star_label.txt
faux_supporting_doc_energy_star_label.pdf
expected_located_fields.md
README.md
```

Use a real imported ENERGY STAR fan row from the CSV, for example:

```text
Brand Name: ACIQ
Model Name: AEP
Model Number: AEP110
Type: Bathroom/Utility Room
Airflow 1 (cfm): 110
Efficacy 1 (cfm/Watt): 4.2
ENERGY STAR Unique ID: 3629726
CB Model Identifier: ES_1151218_AEP110_09272024000000_1008147
```

The faux invoice should clearly show:

```text
Ventilation upgrade
ENERGY STAR bathroom/utility fan
Brand: ACIQ
Model: AEP110
Installed quantity and line amount
CleanBC rebate line, if needed for existing ventilation rules
```

The supporting document should clearly show:

```text
ENERGY STAR certified ventilating fan
Brand: ACIQ
Model: AEP110
ENERGY STAR Unique ID or CB Model Identifier
Product type: Bathroom/Utility Room
Airflow and efficacy values
```

## Testing Plan

### Source/download tests

```text
1. Confirm ENERGY STAR download endpoint returns CSV.
2. Confirm parser handles ISO-8859-1 or UTF-8 compatible content.
3. Confirm required columns are present.
4. Confirm rows with blank brand/model are skipped or failed safely.
5. Confirm rows are deduped predictably.
6. Confirm import run stores file_sha256, byte_size, storage_key, records_imported, and metadata_json.
```

### DB tests

```text
1. Apply additive DDL locally.
2. Seed vent_fan_sources locally.
3. Run import task.
4. Confirm claims.v_current_vent_fan_products returns imported rows.
5. Confirm invoice_versions.vent_fan_product_id FK works.
```

### Runtime tests

```text
1. Rails autoload check for new models, importer, controller, and code rule.
2. Importer dry run from official CSV endpoint.
3. Importer run from local CSV_PATH.
4. Product lookup synthetic transaction:
   - create invoice_version
   - create invoice located fields for ACIQ AEP110
   - create supporting document located fields for ACIQ AEP110
   - run product_lookup_enrichment
   - confirm invoice_versions.vent_fan_product_id is set
5. Code rule synthetic transaction:
   - run vent_fan_energy_star_product_list_match
   - expect pass when product ID is set
   - expect warn when evidence is missing or ambiguous
```

### End-to-end ingest test

```text
1. Submit faux_invoice.pdf plus faux supporting documents through Claims::Ingest::CreateDraftBatch.
2. Confirm OCR succeeds for all files.
3. Confirm classifier marks invoice/supporting documents correctly.
4. Confirm GenAI extracts fan product evidence.
5. Confirm supporting-document extraction extracts fan product evidence.
6. Confirm product_lookup_enrichment sets invoice_versions.vent_fan_product_id.
7. Confirm vent_fan_energy_star_product_list_match returns pass.
8. Confirm review payload includes vent_fan_product_match.
```

### Frontend tests

```text
1. Run frontend lint/type checks used by the repo.
2. Open Downloads admin and confirm the fan product-list card is present.
3. Open fan product-list admin screen and confirm import status loads.
4. Confirm imported fan rows can be searched by brand/model.
5. Confirm invoice review shows the ENERGY STAR ventilating fan match panel when present.
```

## Implementation Order

```text
1. Add DDL and rebuild-order scripts.
2. Add seed file for vent_fan_sources.
3. Add Rails models.
4. Add importer and rake task.
5. Add admin API/controller and frontend admin screen.
6. Add invoice FK serialization and review UI match panel.
7. Add product_lookup_enrichment fan branch.
8. Add code rule and rule seed/mapping.
9. Add reset/clone cleanup for vent_fan_product_id.
10. Apply local DB changes and seed/import the catalogue.
11. Create faux ventilation fan invoice/supporting documents.
12. Run synthetic DB/runtime tests.
13. Run full ingest end-to-end test.
14. Run frontend checks.
```

## Open Decisions

```text
1. Should the rule require `Markets` to include Canada?
   Recommendation: no hard requirement yet. Preserve and display Markets. The requirement sentence says listed on the US EPA/DOE searchable product list, not explicitly Canada-market only.

2. Should the fan code rule fail when a visible fan model is absent from the list?
   Recommendation: yes, but only when the model evidence is specific and unambiguous. Otherwise warn.

3. Should HERV and fan matching share helper methods?
   Recommendation: only small private matching helpers are acceptable if they remain boring and transparent. Keep HERV and fan code-rule modules separate so each maps cleanly back to the requirement text.
```
