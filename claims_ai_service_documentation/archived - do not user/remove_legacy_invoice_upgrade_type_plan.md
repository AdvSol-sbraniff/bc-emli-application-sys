# Remove Legacy Invoice Upgrade Type Column Plan

Implementation status: completed in the active DDL/documentation pass. Keep this file as the cleanup audit trail.

## 1. Goal

Remove the legacy `claims.invoices.upgrade_type_id` column and its downstream view/API exposure.

This column points to `public.permit_classifications`. It is not the claims AI upgrade-type model. The claims AI model uses `claims.invoice_upgrade_types`, with actual invoice-PDF classification tracked per invoice version in `claims.invoice_version_upgrade_types`.

## 2. Current State Before Cleanup

### 2.1 Legacy invoice column

`claims.invoices.upgrade_type_id` is defined in `claims_ai_service_ddl/2_create_schema.sql`.

It has:

- A nullable `upgrade_type_id` column on `claims.invoices`.
- A foreign key to `public.permit_classifications(id)`.
- An index named `index_claims_invoices_on_upgrade_type_id`.

The schema comment identifies it as a legacy upgrade/domain choice.

### 2.2 Actual AI upgrade-type structure

The real claims AI upgrade structure is:

- `claims.invoice_upgrade_types`: lookup table for AI upgrade domains.
- `claims.invoice_version_upgrade_types`: runtime classifier/GenAI result table for upgrade types detected on a specific invoice PDF version.
- `claims.lineitems.invoice_upgrade_type_id`: optional line-item upgrade classification.
- `claims.invoice_version_located_fields.invoice_upgrade_type_id`: located fields scoped to common or upgrade-specific validation.
- `claims.invoice_version_rulechecks.invoice_upgrade_type_id`: rulecheck outputs scoped to common or upgrade-specific validation.
- `claims.ingest_step_runs.invoice_upgrade_type_id`: audit trail for common/upgrade GenAI and code subcalls.

This is the correct model because upgrade classification belongs to the processed invoice PDF version, not the durable claim-level invoice shell.

### 2.3 View/API exposure

Before cleanup, `claims.v_invoice_grid` exposed legacy fields:

- `upgrade_type_id`
- `upgrade_type_code`
- `upgrade_type_name`

It also exposes the correct AI-detected fields:

- `latest_detected_upgrade_type_keys`
- `latest_detected_upgrade_types_json`

`Api::Claims::InvoiceGridController#index` returns `rows.as_json`, so the legacy fields are included in the API payload even though the current React claims invoice admin screen does not display them.

The invoice grid controller also allows sorting by any column present in `claims.v_invoice_grid`, so external callers could technically sort by one of the legacy fields while they exist.

Before cleanup, `claims.v_reporting_invoice_business` selected the legacy fields from `claims.v_invoice_grid`.

### 2.4 React usage

The current React invoice admin UX displays detected upgrade types from:

- `latest_detected_upgrade_types_json`
- `latest_detected_upgrade_type_keys`

No current React claims invoice admin display was found using `upgrade_type_id`, `upgrade_type_code`, or `upgrade_type_name` from `claims.v_invoice_grid`.

## 3. Why Remove It

The legacy column creates naming confusion:

- `claims.invoices.upgrade_type_id` points to `public.permit_classifications`.
- Most other `invoice_upgrade_type_id` columns point to `claims.invoice_upgrade_types`.

Leaving both concepts in the claims AI schema makes the data model harder to explain and easier to misuse in future reporting or API work.

Removing the legacy column makes the model clearer:

- Claim-level invoice rows stay durable workflow shells.
- Invoice versions own the actual processed PDF output.
- `claims.invoice_version_upgrade_types` owns detected/evaluated AI upgrade types for each invoice PDF version.

## 4. Cleanup Sequence

### 4.1 Confirm no live writes

Before editing DDL, re-run a targeted search for writes to `claims.invoices.upgrade_type_id`.

Expected result: no active claims AI upload, ingest, OCR, GenAI, admin, or React flow writes this field.

Check for patterns such as:

- `upgrade_type_id:`
- `.upgrade_type_id`
- `claims.invoices.upgrade_type_id`
- `i.upgrade_type_id`

Exclude archived junk and old plan folders from the audit.

### 4.2 Update reporting view first

Updated `claims_ai_service_ddl/7_reporting_views.sql`.

Remove these fields from `claims.v_reporting_invoice_business`:

- `ig.upgrade_type_id`
- `ig.upgrade_type_code`
- `ig.upgrade_type_name`

Replace them with AI-detected fields if business reporting still needs upgrade type information:

- `ig.latest_detected_upgrade_type_keys`
- `ig.latest_detected_upgrade_types_json`

If reporting consumers only need one display value, derive it from `latest_detected_upgrade_types_json` rather than reintroducing a single legacy upgrade type.

### 4.3 Update invoice grid view

Updated `claims_ai_service_ddl/6_views.sql`.

Remove from `claims.v_invoice_grid`:

- `i.upgrade_type_id AS upgrade_type_id`
- `ut.code AS upgrade_type_code`
- `ut.name AS upgrade_type_name`
- `LEFT JOIN public.permit_classifications ut ON ut.id = i.upgrade_type_id`

Keep:

- `latest_detected_upgrade_type_keys`
- `latest_detected_upgrade_types_json`

Also check the earlier current-version/grid views in the same file for any direct `i.upgrade_type_id` select list entries and remove those if they exist only for legacy display.

### 4.4 Update API expectations

The current React code does not type or display the legacy invoice-grid fields, but the API payload shape changed once the view changed.

Review:

- `Api::Claims::InvoiceGridController#index`
- Any API docs or tests around `/api/claims/admin/invoices`
- Any non-React consumers, exports, reporting notebooks, or ad hoc scripts if they exist

The controller can continue returning `rows.as_json`; the key change is that the view will no longer provide the legacy fields.

If sort requests are accepted from external callers, document that sorting by `upgrade_type_id`, `upgrade_type_code`, or `upgrade_type_name` is no longer supported.

### 4.5 Remove schema column

Updated `claims_ai_service_ddl/2_create_schema.sql`.

Remove:

- `upgrade_type_id uuid NULL`
- `fk_claims_invoices_upgrade_type`
- `index_claims_invoices_on_upgrade_type_id`
- legacy comments about `public.permit_classifications`

Do not remove `claims.invoice_upgrade_types` or any `invoice_upgrade_type_id` columns that reference it. Those are the active AI model.

### 4.6 Update documentation

Updated `claims_ai_service_documentation/claims_data_model.md`.

Remove or revise the section that says `claims.invoices.upgrade_type_id` is a live legacy column.

Recommended replacement language:

`claims.invoices` does not store the AI upgrade classification. Upgrade classification is version-specific and is stored in `claims.invoice_version_upgrade_types`.

Also ensure later sections consistently describe:

- `upgrade_type_id`: legacy term being removed.
- `invoice_upgrade_type_id`: claims AI FK to `claims.invoice_upgrade_types`.

## 5. Verification Checklist

Run after code/DDL edits:

- Search for `claims.invoices.upgrade_type_id`.
- Search for `upgrade_type_code`.
- Search for `upgrade_type_name`.
- Search for `public.permit_classifications` in claims-specific DDL and docs.
- Confirm `latest_detected_upgrade_type_keys` still appears in `claims.v_invoice_grid`.
- Confirm `latest_detected_upgrade_types_json` still appears in `claims.v_invoice_grid`.
- Confirm React invoice admin still renders detected upgrade tiles.
- Confirm invoice grid filtering still uses `latest_detected_upgrade_type_keys`.
- Confirm no stale `validationgenai_rulesets` or ruleset cleanup references were reintroduced.

Suggested commands:

```powershell
rg -n "claims\\.invoices\\.upgrade_type_id|upgrade_type_code|upgrade_type_name|public\\.permit_classifications" claims_ai_service_ddl app claims_ai_service_documentation -g "!claims_ai_service_documentation/archived - do not user/**"
rg -n "latest_detected_upgrade_type_keys|latest_detected_upgrade_types_json" claims_ai_service_ddl app/frontend app/controllers/api/claims
```

## 6. Risks

The main risk is not runtime AI processing. The main risk is breaking a reporting view or external consumer that still expects the legacy invoice-grid fields.

Specific risks:

- `claims.v_reporting_invoice_business` currently depends on the legacy columns.
- External API callers could receive fewer fields from `/api/claims/admin/invoices`.
- Any ad hoc report that sorted by `upgrade_type_name` would need to switch to detected AI upgrade type fields.

## 7. Recommendation

The cleanup has been completed as a small dedicated DDL/API/documentation pass.

The correct source of truth for upgrade classification is `claims.invoice_version_upgrade_types`. The legacy `claims.invoices.upgrade_type_id` column has been removed from the active claims AI schema and dependent active reporting views.
