# Ventilation HERV NRCan Product List Implementation Plan

## Purpose

Implement the ventilation requirement:

> Heat/energy recovery ventilators must be ENERGY STAR certified and listed on Natural Resources Canada's searchable product list.

This plan covers only the HRV/ERV product-list requirement from the ventilation section. Bathroom fan ENERGY STAR/EPA product-list handling is a separate question and should not be bundled into this implementation.

## Decision

Create a fifth external-reference catalogue for ENERGY STAR heat/energy recovery ventilators.

This plan explicitly includes both:

```text
1. A Downloads admin extension so staff can import and inspect the HERV ENERGY STAR product list from the same downloads hub used for AHRI, NEEA, AWHP, and OHPA lists.
2. A code-owned ventilation rule, vent_herv_nrcan_energy_star_product_list_match, that checks HRV/ERV invoice and supporting-document product evidence against the imported HERV list.
```

The existing four external-reference catalogue families are:

| Family                                          | Existing source table | Import run table          | Product table          | Current view                     | Invoice FK                         |
| ----------------------------------------------- | --------------------- | ------------------------- | ---------------------- | -------------------------------- | ---------------------------------- |
| AHRI / BC Hydro heat pump lists                 | `claims.ahri_sources` | `claims.ahri_import_runs` | `claims.ahri_products` | `claims.v_current_ahri_products` | `invoice_versions.ahri_product_id` |
| NEEA HPWH list                                  | `claims.neea_sources` | `claims.neea_import_runs` | `claims.neea_products` | `claims.v_current_neea_products` | `invoice_versions.neea_product_id` |
| Better Homes BC air-to-water / combined HP list | `claims.awhp_sources` | `claims.awhp_import_runs` | `claims.awhp_products` | `claims.v_current_awhp_products` | `invoice_versions.awhp_product_id` |
| NRCan OHPA BC ASHP list                         | `claims.ohpa_sources` | `claims.ohpa_import_runs` | `claims.ohpa_products` | `claims.v_current_ohpa_products` | `invoice_versions.ohpa_product_id` |

The new family should follow that same pattern:

| Family                         | New source table      | New import run table      | New product table      | New current view                 | New invoice FK                     |
| ------------------------------ | --------------------- | ------------------------- | ---------------------- | -------------------------------- | ---------------------------------- |
| NRCan ENERGY STAR HRV/ERV list | `claims.herv_sources` | `claims.herv_import_runs` | `claims.herv_products` | `claims.v_current_herv_products` | `invoice_versions.herv_product_id` |

## Confirmed Testing

### Existing local catalogue count

Local DB query confirmed current source rows:

| Type   | Source rows |
| ------ | ----------: |
| `ahri` |           3 |
| `neea` |           1 |
| `awhp` |           1 |
| `ohpa` |           1 |

Existing source rows:

| Type   | Description                                                    | URL                                                                                        |
| ------ | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `ahri` | Ductless mini-split heat pump                                  | `https://app.bchydro.com/hero/HeatPumpLookup/DownloadMiniSplitSingleHeadListPDF`           |
| `ahri` | Ductless multi-split heat pump                                 | `https://app.bchydro.com/hero/HeatPumpLookup/DownloadMiniSplitMultiHeadListPDF`            |
| `ahri` | Central ducted heat pump (Tier 2)                              | `https://app.bchydro.com/hero/HeatPumpLookup/DownloadVariableSpeedCentralSystemListPDF`    |
| `neea` | Residential HPWH Qualified Products List                       | `https://neea.org/wp-content/uploads/2025/03/residential-HPWH-qualified-products-list.pdf` |
| `awhp` | Air-to-Water and Combination Heat Pump Qualifying Product List | `https://betterhomesbc.ca/qualified-product-list-air-to-water-heat-pumps-PDF`              |
| `ohpa` | NRCan OHPA BC Air Source Heat Pump Qualified Product List      | `https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ASHP3_OHPA`                      |

### Correct NRCan segment

Tested two NRCan HERV segments from inside the app container:

| Segment                             | Meaning                                            | Rows returned |
| ----------------------------------- | -------------------------------------------------- | ------------: |
| `ES.Ventilators.HeatEnergyRecovery` | ENERGY STAR heat/energy recovery ventilators       |           214 |
| `Ventilators.HeatEnergyRecovery`    | Broader regulated heat/energy recovery ventilators |           432 |

Conclusion: use `ES.Ventilators.HeatEnergyRecovery`. The broader `Ventilators.HeatEnergyRecovery` segment is not the correct source for the requirement because it includes non-ENERGY-STAR regulated models.

Recommended source URL:

```text
https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ES.Ventilators.HeatEnergyRecovery
```

### API mechanics

The NRCan page exposes the same Power Automate JSON API pattern already used by `Claims::ExternalReferences::ImportOhpaProducts`.

Request body tested:

```json
{
  "product": "ES.Ventilators.HeatEnergyRecovery",
  "lang": "en-US",
  "skip": 0,
  "take": 100000,
  "filters": {}
}
```

Response keys:

```text
data
fieldLabels
product
```

Observed product value:

```text
ES.Ventilators.HeatEnergyRecovery
```

Observed product row fields:

```text
ModelNumber
BrandName
SensibleHeatRecoveryEfficiencySREAt0C
IfNotMarkedForOutdoorMinus25CREG
ModelType
AssociatedNetSupplyAirflowAt0CCFM
IfNotMarkedForOutdoorMinus25CFM
AssociatedPowerConsumptionAt0CW
AssociatedPowerConsumptionAtMinus25CW
AssociatedNetSupplyAirflowAt0CLS
IfNotMarkedForOutdoorMinus25CLS
MarkedForOutdoorUseAtMinus10COrHigher
MaxRatedAirflowAt0CCFM
MaxRatedAirflowAt0CLS
PowerConsumptionAt0CW
```

Observed field-label shape:

```json
{
  "fieldname": "ModelNumber",
  "LabelEn": "Model number",
  "LabelFr": "Numero de modele"
}
```

### Matchability test

For the ENERGY STAR segment:

| Check                                 |   Result |
| ------------------------------------- | -------: |
| Rows returned                         |      214 |
| Missing `BrandName`                   |        0 |
| Missing `ModelNumber`                 |        0 |
| Unique normalized brand/model keys    |      211 |
| Duplicate normalized brand/model keys |        3 |
| Model types                           | `E`, `H` |

The three duplicate brand/model keys were identical duplicate rows in the sampled fields. Importer should dedupe before insert.

## Required Schema Changes

Update `claims_ai_service_ddl/2_create_schema.sql`.

The HERV DDL should intentionally mirror the existing product-list family pattern:

```text
source table: one stable source/catalogue row per source URL
import_runs table: child/history rows for each import attempt
products table: cached product rows from a successful import
current view: latest successful import rows
invoice_versions FK: one matched product row used by code/review UI
```

This is the same shape as OHPA/AWHP/NEEA/AHRI product-list storage. The HERV product table has HERV-specific metric columns because those columns exist in the NRCan HERV API response; it does not add a generic key/value table, extra source-document section table, or separate source-PDF tracking table.

### Exact HERV DDL

```sql
-- ============================================================
-- herv_sources
-- PURPOSE: Stable catalogue of NRCan ENERGY STAR heat/energy
-- recovery ventilator product-list source definitions. Import
-- runs are child/history records under these source rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.herv_sources (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  description text NOT NULL,
  source_url text NOT NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT herv_sources_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS idx_herv_sources_description
  ON claims.herv_sources (description);



-- ============================================================
-- herv_import_runs
-- PURPOSE: Track refresh attempts for NRCan ENERGY STAR heat/
-- energy recovery ventilator CSV data used by code-owned
-- ventilation checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.herv_import_runs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  herv_source_id uuid NOT NULL,
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

  CONSTRAINT herv_import_runs_pkey PRIMARY KEY (id),

  CONSTRAINT herv_import_runs_status_chk
    CHECK (status IN ('queued','running','succeeded','failed')),

  CONSTRAINT herv_import_runs_records_imported_chk
    CHECK (records_imported >= 0),

  CONSTRAINT fk_herv_import_runs_source
    FOREIGN KEY (herv_source_id)
    REFERENCES claims.herv_sources(id)
);

CREATE INDEX IF NOT EXISTS idx_herv_import_runs_source_started
  ON claims.herv_import_runs (herv_source_id, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_herv_import_runs_status
  ON claims.herv_import_runs (status);

CREATE INDEX IF NOT EXISTS idx_herv_import_runs_storage_key
  ON claims.herv_import_runs (storage_key);



-- ============================================================
-- herv_products
-- PURPOSE: Cached NRCan ENERGY STAR heat/energy recovery
-- ventilator product-list rows used by code-owned ventilation
-- HRV/ERV product-list checks.
-- ============================================================

CREATE TABLE IF NOT EXISTS claims.herv_products (
  id uuid NOT NULL DEFAULT gen_random_uuid(),

  import_run_id uuid NOT NULL,

  brand text NULL,
  brand_normalized text NULL,
  model_number text NOT NULL,
  model_number_normalized text NULL,
  model_number_regex text NULL,
  model_type text NULL,

  sensible_heat_recovery_efficiency_sre_at_0c numeric NULL,
  sensible_heat_recovery_efficiency_sre_at_minus_25c numeric NULL,
  associated_net_supply_airflow_at_0c_cfm numeric NULL,
  associated_net_supply_airflow_at_minus_25c_cfm numeric NULL,
  associated_power_consumption_at_0c_w numeric NULL,
  associated_power_consumption_at_minus_25c_w numeric NULL,
  associated_net_supply_airflow_at_0c_ls numeric NULL,
  associated_net_supply_airflow_at_minus_25c_ls numeric NULL,
  marked_for_outdoor_use_at_minus_10c_or_higher boolean NULL,
  max_rated_airflow_at_0c_cfm numeric NULL,
  max_rated_airflow_at_0c_ls numeric NULL,
  power_consumption_at_0c_w numeric NULL,

  eligibility_notes text NULL,
  raw_row_json jsonb NULL,

  created_at timestamp(6) without time zone NOT NULL DEFAULT now(),
  updated_at timestamp(6) without time zone NOT NULL DEFAULT now(),

  CONSTRAINT herv_products_pkey PRIMARY KEY (id),

  CONSTRAINT fk_herv_products_import_run
    FOREIGN KEY (import_run_id)
    REFERENCES claims.herv_import_runs(id)
);

CREATE INDEX IF NOT EXISTS idx_herv_products_import_run
  ON claims.herv_products (import_run_id);

CREATE INDEX IF NOT EXISTS idx_herv_products_brand_normalized
  ON claims.herv_products (brand_normalized);

CREATE INDEX IF NOT EXISTS idx_herv_products_model_number_normalized
  ON claims.herv_products (model_number_normalized);

CREATE UNIQUE INDEX IF NOT EXISTS idx_herv_products_source_row_unique
  ON claims.herv_products (
    import_run_id,
    COALESCE(brand_normalized, ''),
    model_number_normalized,
    COALESCE(model_type, ''),
    COALESCE(sensible_heat_recovery_efficiency_sre_at_0c, -1),
    COALESCE(associated_net_supply_airflow_at_0c_cfm, -1),
    COALESCE(power_consumption_at_0c_w, -1)
  );
```

### Add `claims.herv_sources`

Columns:

```text
id uuid primary key default gen_random_uuid()
description text not null
source_url text not null
created_at timestamp not null default now()
updated_at timestamp not null default now()
```

Indexes:

```text
idx_herv_sources_description on description
```

### Add `claims.herv_import_runs`

Mirror `ohpa_import_runs`, with FK to `herv_sources`.

Columns:

```text
id uuid primary key default gen_random_uuid()
herv_source_id uuid not null references claims.herv_sources(id)
storage_provider varchar null
storage_key text null
content_type varchar null
byte_size bigint null
status text not null default 'queued'
started_at timestamp not null default now()
completed_at timestamp null
records_imported integer not null default 0
publishing_notes text null
publishing_date date null
file_sha256 text null
error_text text null
metadata_json jsonb null
created_at timestamp not null default now()
updated_at timestamp not null default now()
```

Checks and indexes:

```text
status in queued/running/succeeded/failed
records_imported >= 0
idx_herv_import_runs_source_started
idx_herv_import_runs_status
idx_herv_import_runs_storage_key
```

### Add `claims.herv_products`

Recommended columns:

```text
id uuid primary key default gen_random_uuid()
import_run_id uuid not null references claims.herv_import_runs(id)

brand text null
brand_normalized text null
model_number text not null
model_number_normalized text null
model_number_regex text null
model_type text null

sensible_heat_recovery_efficiency_sre_at_0c numeric null
sensible_heat_recovery_efficiency_sre_at_minus_25c numeric null
associated_net_supply_airflow_at_0c_cfm numeric null
associated_net_supply_airflow_at_minus_25c_cfm numeric null
associated_power_consumption_at_0c_w numeric null
associated_power_consumption_at_minus_25c_w numeric null
associated_net_supply_airflow_at_0c_ls numeric null
associated_net_supply_airflow_at_minus_25c_ls numeric null
marked_for_outdoor_use_at_minus_10c_or_higher boolean null
max_rated_airflow_at_0c_cfm numeric null
max_rated_airflow_at_0c_ls numeric null
power_consumption_at_0c_w numeric null

eligibility_notes text null
raw_row_json jsonb null
created_at timestamp not null default now()
updated_at timestamp not null default now()
```

Indexes:

```text
idx_herv_products_import_run
idx_herv_products_brand_normalized
idx_herv_products_model_number_normalized
```

Unique index:

```text
import_run_id,
COALESCE(brand_normalized, ''),
model_number_normalized,
COALESCE(model_type, ''),
COALESCE(sensible_heat_recovery_efficiency_sre_at_0c, -1),
COALESCE(associated_net_supply_airflow_at_0c_cfm, -1),
COALESCE(power_consumption_at_0c_w, -1)
```

The importer should also dedupe exact duplicate rows before insert.

### Add `invoice_versions.herv_product_id`

Add nullable FK:

```text
herv_product_id uuid null references claims.herv_products(id)
```

Add index:

```text
idx_invoice_versions_herv_product
```

## Required View Changes

Update `claims_ai_service_ddl/4_create_views.sql`.

Add `claims.v_current_herv_products`.

Pattern:

```sql
CREATE OR REPLACE VIEW claims.v_current_herv_products AS
SELECT hp.*, hir.herv_source_id, hs.description AS source_description, hs.source_url,
       hir.completed_at AS source_import_completed_at
FROM claims.herv_products hp
JOIN claims.herv_import_runs hir ON hir.id = hp.import_run_id
JOIN claims.herv_sources hs ON hs.id = hir.herv_source_id
WHERE hir.status = 'succeeded'
  AND hir.completed_at = (
    SELECT MAX(hir2.completed_at)
    FROM claims.herv_import_runs hir2
    WHERE hir2.herv_source_id = hir.herv_source_id
      AND hir2.status = 'succeeded'
  );
```

Also add a model:

```text
app/models/claims/current_herv_product.rb
```

## Required Seed Changes

Add a source row to the full rebuild seed.

Suggested source row:

```text
description: NRCan ENERGY STAR Heat/Energy Recovery Ventilators Product List
source_url: https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ES.Ventilators.HeatEnergyRecovery
```

Use stable UUIDs in the seed if the other source seed files use stable UUIDs.

## Importer Plan

Add:

```text
app/services/claims/external_references/import_herv_products.rb
```

Base it on `ImportOhpaProducts`, not the PDF importers.

Pseudo-code:

```text
load herv_source by id
create herv_import_run status=running
resolve defaultCSVAPI from source_url page HTML
download all rows using product=ES.Ventilators.HeatEnergyRecovery, skip/take pagination, filters={}
write downloaded rows to a temp CSV for blob archival
upload temp CSV with Node upload endpoint under external-references/herv/<source_id>
build normalized product rows
dedupe exact duplicate normalized product rows
insert into claims.herv_products
update run status=succeeded with records_imported, storage fields, file_sha256, metadata_json
on error update run status=failed and error_text
```

Normalization:

```text
brand_normalized = uppercase brand with non-alphanumeric collapsed to spaces
model_number_normalized = uppercase model with whitespace removed
loose model matching should remove punctuation for matching, but store strict normalized model for index/search
boolean marked_for_outdoor_use_at_minus_10c_or_higher from "1"/"true"/"yes" as true, "0"/"false"/"no" as false
numeric fields parsed with BigDecimal
raw_row_json stores the original NRCan row
```

Add rake task:

```text
claims:external_references:import_herv_products
```

Optional env:

```text
HERV_SOURCE_ID
PUBLISHING_DATE
PUBLISHING_NOTES
CSV_PATH
```

## Product Lookup Enrichment Plan

Update:

```text
app/services/claims/product_lookup_enrichment/apply.rb
```

Add:

```text
VENTILATION_UPGRADE_TYPE_KEY = "ventilation"
```

Add lookup for `herv_product_id`.

Candidate named invoice fields:

```text
vent_manufacturer
vent_model_number
vent_make_model
vent_system_type
```

Candidate supporting-document fields:

```text
product_spec_sheet.brand_and_model
product_spec_sheet.model_number
energy_star_label.brand_and_model
energy_star_label.model_number
manufacturer_label_photo.brand_and_model
manufacturer_label_photo.model_number
```

Recommended matching behavior:

```text
if ventilation system type is clearly bathroom fan, skip HERV lookup
if ventilation system type is HRV/ERV/HERV or unclear-but-ventilation, collect model/manufacturer evidence
match model values against claims.v_current_herv_products
prefer candidates where brand also matches
if invoice and supporting-document evidence both exist and resolve to different rows, do not set herv_product_id
if a single best row is found, set invoice_versions.herv_product_id
```

## GenAI Field Changes

Current ventilation fields have product-list and ENERGY STAR references, but not clean model/manufacturer fields.

Add or upgrade GenAI located fields:

```text
vent_manufacturer
vent_model_number
vent_make_model
```

Suggested prompts:

```text
vent_manufacturer:
Locate the ventilation product manufacturer, brand, or vendor product brand as a standalone value for the HRV, ERV, heat recovery ventilator, energy recovery ventilator, bathroom fan, exhaust fan, or ventilation system. Use value=null when the manufacturer/brand is not visible. In evidence_text, cite the exact line item, product label, or specification wording used.

vent_model_number:
Locate the ventilation product model number exactly as shown for the HRV, ERV, heat recovery ventilator, energy recovery ventilator, bathroom fan, exhaust fan, or ventilation system. Do not include the manufacturer/brand unless the invoice only shows a combined phrase. Use value=null when no model number is visible. In evidence_text, cite the exact line item, product label, or specification wording used.

vent_make_model:
Locate combined ventilation make/model text for admin readability when present. This is a fallback/display field; prefer vent_manufacturer and vent_model_number for exact product-list matching. Use value=null when no combined make/model text is visible. In evidence_text, cite the exact wording used.
```

Keep existing fields:

```text
vent_energy_star_reference
vent_nrcan_or_product_list_reference
vent_system_type
```

These are still useful evidence, but they should not substitute for deterministic product-list matching when a model number is available.

## Code Rule Plan

Add code rule:

```text
vent_herv_nrcan_energy_star_product_list_match
```

Map to:

```text
ventilation
```

Recommended rule number:

```text
4
```

Implementation decision: keep `vent_product_or_capacity_evidence_present` as the general GenAI product/capacity evidence rule, but remove any implication that it owns deterministic HRV/ERV product-list matching. The code rule `vent_herv_nrcan_energy_star_product_list_match` owns the imported NRCan ENERGY STAR HERV lookup.

`vent_product_or_capacity_evidence_present` still covers general product/capacity evidence and bathroom fan evidence. If bathroom fan matching ever becomes list-based, that should be a separate future rule. The cleaner long-term model remains:

```text
vent_herv_nrcan_energy_star_product_list_match: code-owned HRV/ERV NRCan ENERGY STAR list match
vent_bathroom_fan_product_or_capacity_evidence_present: GenAI/numeric evidence for bathroom fan requirements
```

Rule behavior:

```text
if vent_system_type clearly indicates bathroom fan, return info or skip because this HRV/ERV rule is not triggered
if vent_system_type is missing or unclear, warn unless other named fields clearly show HRV/ERV
if no current imported HERV products exist, warn
if no usable model/manufacturer evidence exists, warn
if model evidence matches a current imported HERV ENERGY STAR product row, pass
if invoice and supporting document evidence both exist but resolve to different product rows, fail
if usable product evidence exists but no current HERV row matches, fail or warn depending on strictness chosen
```

Recommended strictness:

```text
fail when clear HRV/ERV model evidence is present and not found in the current imported ENERGY STAR HERV product list
warn when model evidence is missing, source list is unavailable, or system type is unclear
pass when a clear model match is found
```

Expected text:

```text
For heat/energy recovery ventilators, the installed HRV/ERV model should be found in the imported NRCan ENERGY STAR Heat/Energy Recovery Ventilators searchable product list.
```

Calculation should show:

```text
vent_system_type
invoice model/manufacturer evidence
supporting-document model/manufacturer evidence
matched herv_products.id
source description
source import completed timestamp
```

### Code rule implementation details

Add executor:

```text
app/services/claims/code_rules/ventilation_herv/apply_product_list_match.rb
```

Suggested module/class:

```ruby
Claims::CodeRules::VentilationHerv::ApplyProductListMatch
```

Wire into:

```text
app/services/claims/invoice_version_rulechecks/apply_upgrade_code_rulechecks.rb
```

Add to `SERVICE_CLASSES`:

```ruby
::Claims::CodeRules::VentilationHerv::ApplyProductListMatch
```

Add code-rule seed in:

```text
claims_ai_service_ddl/3_insert_code_rules.sql
```

Seed details:

```text
code_rule_key: vent_herv_nrcan_energy_star_product_list_match
upgrade_type_key: ventilation
enabled: true
rule_number: use the product-validation slot after final ventilation rule ordering is decided
```

Final rule number:

```text
4
```

Recommended description:

```text
Checks whether a ventilation HRV/ERV model found on the invoice and/or supporting product evidence is listed in the imported NRCan ENERGY STAR Heat/Energy Recovery Ventilators searchable product list. Pseudocode: 1. Read vent_system_type, vent_manufacturer, vent_model_number, and vent_make_model from GenAI located fields for the ventilation upgrade. 2. Read product_spec_sheet, energy_star_label, and manufacturer_label_photo supporting-document fields such as brand_and_model, model_number, product_category_or_system_type, energy_star_reference, and nrcan_reference. 3. If the visible ventilation system is clearly a bathroom fan, return info because this HRV/ERV product-list rule is not triggered. 4. If no current imported HERV rows exist, warn. 5. If no usable HRV/ERV model evidence exists, warn. 6. Match model evidence against claims.v_current_herv_products, preferring brand/manufacturer agreement when present. 7. If invoice and supporting-document evidence both exist and resolve to different HERV rows, fail. 8. If clear HRV/ERV model evidence is present and no current HERV row matches, fail. 9. If a single matching HERV ENERGY STAR row is found, pass. 10. In calculation, show vent_system_type, invoice model/manufacturer values, supporting-document model/manufacturer values, matched herv_products.id, source description, and source import completed timestamp.
```

Admin messages:

```text
pass_admin_message: No follow-up is required when the HRV/ERV model is found in the imported NRCan ENERGY STAR H/ERV product list and the visible evidence supports the matched model.
warn_admin_message: Verify the HRV/ERV model evidence and refresh the HERV product-list import if the model evidence or source data is missing.
fail_admin_message: Confirm the invoice/supporting-document model evidence before asking the contractor for corrected HRV/ERV ENERGY STAR product-list evidence.
```

Runtime row behavior:

```text
source_engine = code
rule_key = vent_herv_nrcan_energy_star_product_list_match
expected_text = For heat/energy recovery ventilators, the installed HRV/ERV model should be found in the imported NRCan ENERGY STAR Heat/Energy Recovery Ventilators searchable product list.
calculation = named model/manufacturer evidence + matched source row details
evidence_text = exact invoice/supporting-document located-field evidence used
```

Product matching helper behavior:

```text
Use the same model-normalization style as NEEA/AWHP:
- strict model key removes whitespace
- loose model key removes non-alphanumeric characters
- brand/manufacturer match adds score but should not be mandatory when model is unique
- product model regex column can be reserved for future model-family patterns
```

Rule-order cleanup:

```text
Current ventilation GenAI rule 3 is vent_product_or_capacity_evidence_present.
Keep rule 3 for general product/capacity evidence.
Add rule 4 as vent_herv_nrcan_energy_star_product_list_match.
Update the rule 3 prompt so HRV/ERV NRCan product-list matching is not duplicated in GenAI.
Bathroom-fan product/capacity evidence remains covered by GenAI for now.
```

## Admin/UI Plan

Add admin route/controller similar to existing product-list admin pages:

```text
admin/herv_products
admin/herv_products/import_status
admin/herv_products/import_downloaded_csv
```

Add frontend admin page by parity with AHRI/NEEA/AWHP/OHPA. This is required so staff can refresh and inspect the HERV catalogue without SQL.

Add review UI display in contractor invoice review:

```text
HERV product match
Brand
Model number
Model type
SRE at 0C
SRE at -25C
Airflow
Power consumption
Source
Import completed at
```

### Download screen and product-list admin implementation details

The current downloads hub is:

```text
app/frontend/components/domains/downloads-admin/index.tsx
```

It currently exposes cards for:

```text
AHRI heat pump product list config
NEEA HPWH product list config
Air-to-water product list config
OHPA BC product list config
```

Add a fifth card:

```text
title: HERV ENERGY STAR product list config
description: Download, import, and inspect the NRCan ENERGY STAR heat/energy recovery ventilator product list used by ventilation code rules.
path: /herv-product-list-admin
```

Add a dedicated frontend screen:

```text
app/frontend/components/domains/herv-product-list-admin/index.tsx
```

Base it on:

```text
app/frontend/components/domains/ohpa-product-list-admin/index.tsx
```

Use CSV import semantics, not PDF import semantics.

Screen title:

```text
HERV ENERGY STAR Product List Config
```

Main explanation:

```text
This is the cached NRCan ENERGY STAR heat/energy recovery ventilator product list used by code-owned ventilation HRV/ERV product-list checks.
```

Grid columns:

```text
Brand
Model number
Model type
SRE at 0 C
SRE at -25 C
Airflow at 0 C CFM
Airflow at -25 C CFM
Power at 0 C W
Power at -25 C W
Source
```

Search should match:

```text
brand
brand_normalized
model_number
model_number_normalized
model_type
```

Import status panel should show:

```text
source description
source_url
latest status
latest success completed_at
records_imported
publishing_date
publishing_notes
error_text when failed
```

Import action:

```text
POST /api/claims/admin/herv_products/import_downloaded_csv
body:
{
  "herv_source_id": "<source id>",
  "publishing_notes": "NRCan ENERGY STAR HERV CSV import"
}
```

Add lazy import in:

```text
app/frontend/components/domains/navigation/index.tsx
```

Pattern:

```typescript
const HervProductListAdminScreen = lazy(() =>
  import('../herv-product-list-admin').then((module) => ({ default: module.default })),
);
```

Add title mapping:

```text
'/herv-product-list-admin': 'HERV ENERGY STAR Product List Admin'
```

Add protected route inside the claims admin block:

```text
<Route path="/herv-product-list-admin" element={<HervProductListAdminScreen />} />
```

Add subnav breadcrumb entry if needed in:

```text
app/frontend/components/domains/navigation/sub-nav-bar.tsx
```

Expected behavior from `/downloads-admin`:

```text
The Downloads page shows the HERV card beside the four existing product-list cards.
Clicking Open launches /herv-product-list-admin.
The HERV screen loads source/import status from the API.
The HERV screen loads the current product grid from the API.
Clicking Import runs the CSV importer and refreshes status/grid.
```

### Backend API implementation details

Add controller:

```text
app/controllers/api/claims/herv_products_admin_controller.rb
```

Base it on:

```text
app/controllers/api/claims/ohpa_products_admin_controller.rb
```

Routes in `config/routes.rb`:

```ruby
get "admin/herv_products", to: "herv_products_admin#index"
get "admin/herv_products/import_status", to: "herv_products_admin#import_status"
post "admin/herv_products/import_downloaded_csv",
     to: "herv_products_admin#import_downloaded_csv"
```

Controller actions:

```text
index:
  reads claims.v_current_herv_products
  supports q, page, per, sort
  optional herv_source_id filter
  serializes HERV product rows for the grid

import_status:
  returns each herv_source with latest import run and latest successful import run

import_downloaded_csv:
  calls Claims::ExternalReferences::ImportHervProducts.call(...)
```

Index search SQL should include:

```text
brand ILIKE :like
brand_normalized ILIKE :like
model_number ILIKE :like
model_number_normalized ILIKE :like
model_type ILIKE :like
```

Sortable columns:

```text
brand
model_number
model_type
source_import_completed_at
```

Serialized product row fields:

```text
id
brand
brand_normalized
model_number
model_number_normalized
model_type
sensible_heat_recovery_efficiency_sre_at_0c
sensible_heat_recovery_efficiency_sre_at_minus_25c
associated_net_supply_airflow_at_0c_cfm
associated_net_supply_airflow_at_minus_25c_cfm
associated_power_consumption_at_0c_w
associated_power_consumption_at_minus_25c_w
max_rated_airflow_at_0c_cfm
power_consumption_at_0c_w
herv_source_id
source_url
source_description
publishing_notes
publishing_date
source_import_completed_at
```

Import status serialization should mirror OHPA with `herv_source_id`.

### Review UI implementation details

Update contractor invoice review data serialization if needed so the frontend receives:

```text
herv_product_match
```

or add `herv_product` beside the existing AHRI/NEEA/OHPA/AWHP match payload.

Update:

```text
app/frontend/components/domains/contractor-invoice-review/index.tsx
```

Add a display block similar to the existing NEEA/OHPA product match panels.

Display fields:

```text
Brand
Model number
Model type
SRE at 0 C
SRE at -25 C
Airflow at 0 C
Airflow at -25 C
Power at 0 C
Power at -25 C
Source
Import completed at
```

Acceptance:

```text
When invoice_versions.herv_product_id is populated, the review screen shows the matched HERV product row.
When no match exists, no HERV panel is shown or the panel clearly says no HERV product match, following the current product-match UI pattern.
```

## Test Plan

### Faux document fixtures

Create and maintain faux ventilation test documents here:

```text
claims_ai_service_documentation/Test Data/Ventilation/test001 - HRV ENERGY STAR NRCan match/
```

Files:

```text
README.md
faux_invoice.txt
faux_supporting_doc_product_spec_sheet.txt
faux_supporting_doc_energy_star_label.txt
expected_located_fields.md
```

Purpose:

```text
Positive end-to-end HRV/ERV product-list match fixture.
Invoice shows ventilation installed with an eligible air-source heat pump upgrade.
Invoice and supporting documents identify Airflow AIR205-R.
Airflow AIR205-R was confirmed in the live NRCan ENERGY STAR H/ERV segment during investigation.
```

Expected future located-field values:

```text
vent_system_type = HRV / heat recovery ventilator
vent_manufacturer = Airflow
vent_model_number = AIR205-R
vent_make_model = Airflow AIR205-R
vent_associated_upgrade_evidence = same CleanBC project as air-source heat pump installation
vent_energy_star_reference = ENERGY STAR certified
vent_nrcan_or_product_list_reference = Natural Resources Canada searchable product list
vent_line_amount = $2,000.00
upgrade_specific_rebate_line_amount = $1,600.00
```

Expected future code-rule outcome:

```text
vent_associated_upgrade_present = pass
vent_herv_nrcan_energy_star_product_list_match = pass
invoice_versions.herv_product_id is populated with the imported HERV row for Airflow / AIR205-R
```

If PDF ingestion is needed later, convert the text fixtures to PDFs without changing the visible wording. The text fixtures are the source of truth for the intended OCR-visible content.

### Importer tests

Create fixture JSON/CSV with:

```text
normal HERV row
duplicate identical row
missing brand
missing model
numeric fields with decimals
boolean marked_for_outdoor_use_at_minus_10c_or_higher values 0 and 1
```

Assertions:

```text
successful run inserts deduped rows
failed download marks import run failed
missing model rows are skipped or fail import based on chosen policy
raw_row_json is stored
file_sha256 and storage metadata are updated
```

Live importer smoke test:

```text
Run importer against source_url=https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ES.Ventilators.HeatEnergyRecovery
Assert run succeeds.
Assert records_imported is approximately the current live count; during investigation the API returned 214 rows.
Assert v_current_herv_products contains Airflow / AIR205-R.
Assert v_current_herv_products does not include rows that exist only in the broader Ventilators.HeatEnergyRecovery segment.
```

Source-segment guard test:

```text
Load or mock both segments:
ES.Ventilators.HeatEnergyRecovery returns ENERGY STAR rows.
Ventilators.HeatEnergyRecovery returns broader regulated rows.
Assert default source seed uses ES.Ventilators.HeatEnergyRecovery.
Assert importer metadata_json records product_segment=ES.Ventilators.HeatEnergyRecovery.
```

### Product matching tests

Cases:

```text
invoice brand/model exact match passes
supporting document brand/model exact match passes
model matches without brand still finds candidate when unique
invoice/supporting models conflict fails or prevents FK update
no current HERV rows warns
bathroom fan system type skips/infos this HERV rule
unclear system type with HERV-like model evidence warns or evaluates according to named evidence
```

Fixture-backed matching tests:

```text
Using the faux test001 documents, located fields Airflow and AIR205-R should match the imported HERV row.
If invoice model is AIR205-R and supporting document model is AIR155R, do not populate herv_product_id and make the rule fail or warn according to the final conflict policy.
If invoice has Airflow AIR205-R but no supporting document product evidence, warn if the final rule requires supporting corroboration; otherwise pass product-list match and let separate supporting-document rules own missing document evidence.
If invoice says bathroom fan and model AIR205-R appears only in unrelated text, the HRV/ERV product-list rule should skip/info rather than pass.
If model is present but not found in v_current_herv_products, fail when system type is clearly HRV/ERV and current HERV rows are available.
```

### SQL smoke tests

After full rebuild:

```sql
SELECT COUNT(*) FROM claims.herv_sources;
SELECT COUNT(*) FROM claims.v_current_herv_products;
SELECT code_rule_key FROM claims.code_rules WHERE code_rule_key = 'vent_herv_nrcan_energy_star_product_list_match';
SELECT description, source_url FROM claims.herv_sources;
SELECT brand, model_number FROM claims.v_current_herv_products WHERE brand_normalized = 'AIRFLOW' AND model_number_normalized = 'AIR205-R';
```

### Runtime smoke test

Use a ventilation test invoice with:

```text
vent_system_type = HRV
vent_model_number = AIR205-R
vent_manufacturer = Airflow
```

Expected:

```text
product lookup sets invoice_versions.herv_product_id
code rule returns pass
calculation names the matched imported row
```

End-to-end smoke test using faux documents:

```text
1. Convert faux_invoice.txt to a PDF or inject equivalent located fields in a controlled test setup.
2. Convert faux_supporting_doc_product_spec_sheet.txt and faux_supporting_doc_energy_star_label.txt to PDFs or inject equivalent supporting_document_located_fields.
3. Run classification/extraction for the invoice version.
4. Confirm ventilation upgrade type is present.
5. Confirm GenAI located fields include vent_manufacturer=Airflow and vent_model_number=AIR205-R.
6. Run product lookup enrichment.
7. Confirm invoice_versions.herv_product_id points to Airflow / AIR205-R.
8. Run code rules.
9. Confirm vent_herv_nrcan_energy_star_product_list_match returns pass.
10. Confirm calculation names the source segment, source import run, matched product id, invoice evidence, and supporting-document evidence.
```

### Regression tests after conversion from existing GenAI rule

Current `vent_product_or_capacity_evidence_present` mixes HRV/ERV product-list evidence and bathroom fan requirements. When the HERV code rule is added:

```text
Ensure HRV/ERV ENERGY STAR/NRCan product-list judgment is not duplicated in GenAI.
Ensure bathroom fan ENERGY STAR/capacity/ducting/motor/damper evidence still has coverage.
Ensure existing ventilation rule order remains understandable to admin review.
```

## Implementation Order

1. Add schema tables, indexes, FK, and current view.
2. Add ActiveRecord models for source, import run, product, and current product.
3. Add source seed.
4. Add importer and rake task.
5. Run importer locally against `ES.Ventilators.HeatEnergyRecovery`.
6. Add GenAI fields for ventilation manufacturer/model/make-model.
7. Add product lookup enrichment for ventilation HERV products.
8. Add code rule and code-rule seed/mapping.
9. Keep `vent_product_or_capacity_evidence_present` for general ventilation product/capacity evidence and update its prompt to defer deterministic HERV lookup to the code rule.
10. Add admin/import UI parity, including the `/downloads-admin` card and `/herv-product-list-admin` screen.
11. Add review UI display for matched HERV products.
12. Run syntax, seeds, importer, and rule smoke tests.

## Non-Goals

Do not implement bathroom fan ENERGY STAR/EPA/DOE list matching in this plan.

Do not use the broader `Ventilators.HeatEnergyRecovery` product segment for this rule.

Do not treat `vent_energy_star_reference` or `vent_nrcan_or_product_list_reference` as a deterministic product-list match when a model number is available. They are supporting evidence, not the source-of-truth match.

Do not add generic product-list tables. Follow the existing explicit family pattern to keep rule-to-requirement mapping straightforward.

## Sources Checked

- NRCan ENERGY STAR HRV/ERV profile page: `https://natural-resources.canada.ca/energy-efficiency/energy-star/products/list-certified-products/heat-energy-recovery-ventilators`
- NRCan ENERGY STAR HERV product segment: `https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ES.Ventilators.HeatEnergyRecovery`
- NRCan broader regulated HERV product segment: `https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=Ventilators.HeatEnergyRecovery`
- Existing local schema: `claims_ai_service_ddl/2_create_schema.sql`
- Existing OHPA importer pattern: `app/services/claims/external_references/import_ohpa_products.rb`
- Existing product lookup enrichment: `app/services/claims/product_lookup_enrichment/apply.rb`
