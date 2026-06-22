# Invoice Version Eligibility UUID Enrichment Plan

## Purpose

Normalize the matched participant and eligibility-code database identities onto `claims.invoice_versions` before existing code rules run.

This plan is intentionally narrow. It does not implement the duplicate prior-rebate/payment rule. That broader rule remains in backlog.

## Problem

Today the classifier locates an invoice-visible eligibility code, and the case-facts builder resolves that code against `claims.users_eligibilitycodes`. The resolved values are persisted into `claims.invoice_version_located_fields` as `source_engine='code'`.

That is useful evidence for the PDF viewer/context window, but it leaves code rules relying on located-field text values instead of normalized database identities.

Existing code rules affected:

- `eligibility_code_found_in_database`
- `eligibility_code_valid_for_invoice_date`
- `income_level_1_or_2_required`

The matching logic should happen once before code rules run. Code rules should then read normalized IDs/records from `claims.invoice_versions`.

## Pipeline Understanding

The intended pipeline ordering is:

1. Upload package.
2. OCR-read every file.
3. Classify PDFs.
4. Classify image files.
5. Supporting-document type extraction.
6. +1 fix path only when applicable.
7. Invoice OCR/DI extraction.
8. `case_facts`: builds DB facts and persists code-located evidence into `invoice_version_located_fields`.
9. `product_lookup_enrichment`: deterministic DB lookups/enrichment.
10. `genai_common`.
11. `genai_upgrade`.
12. `code_common`.
13. `code_upgrade`.
14. `aggregate_advice`.

This plan uses step 9 as the deterministic enrichment boundary. The UUID fields must be populated before steps 12 and 13.

## Schema Changes

Add two nullable columns to `claims.invoice_versions`:

- `participant_user_id uuid NULL`
- `users_eligibilitycode_id uuid NULL`

Add foreign keys:

- `participant_user_id` references `public.users(id)`
- `users_eligibilitycode_id` references `claims.users_eligibilitycodes(id)`

Add indexes:

- `index_invoice_versions_on_participant_user_id`
- `index_invoice_versions_on_users_eligibilitycode_id`

Rationale:

- `users_eligibilitycode_id` identifies the matched eligibility-code DB row.
- `participant_user_id` identifies the participant/homeowner through that eligibility-code row.
- Both are version-level evidence because the match comes from the eligibility code found on that invoice version.

## Enrichment Changes

Update deterministic enrichment so `product_lookup_enrichment` also performs eligibility-code identity enrichment.

Recommended behavior:

1. Read the classifier-located eligibility code from `claims.invoice_version_located_fields`, likely `field_key='classifier.eligibility_code'`.
2. Normalize the token consistently with existing case-facts logic.
3. Find `claims.users_eligibilitycodes` case-insensitively by `eligibility_code`.
4. If found:
   - set `invoice_versions.users_eligibilitycode_id`
   - set `invoice_versions.participant_user_id` from `users_eligibilitycodes.user_id`
5. If not found:
   - set both fields to null
   - leave existing located-field evidence behavior unchanged
6. Continue existing product-list enrichment updates unchanged.

Keep `case_facts` code-located fields in place. They remain useful for:

- context window display
- PDF viewer accordion evidence
- admin explanation
- backward compatibility during transition

## Existing Code Rule Refactor

### `eligibility_code_found_in_database`

Before:

- Reads `invoice_version_located_fields` for `source_engine='code'` and `field_key='users_eligibilitycodes.eligibility_code'`.

After:

- Passes when `invoice_version.users_eligibilitycode_id` is present.
- Fails when it is null.
- Detail text should still include:
  - classifier-located eligibility code when available
  - code-located eligibility-code value when available
  - `users_eligibilitycode_id` when present

### `eligibility_code_valid_for_invoice_date`

Before:

- Reads approval/expiry dates from code-located fields.

After:

- Prefer loading `Claims::UsersEligibilitycode` through `invoice_version.users_eligibilitycode_id`.
- Use that row's `approved_at`, `expires_at`, `eligibility_code`.
- Fall back to code-located fields only if needed during transition.

### `income_level_1_or_2_required`

Before:

- Reads income level and eligibility code from code-located fields.

After:

- Prefer loading `Claims::UsersEligibilitycode` through `invoice_version.users_eligibilitycode_id`.
- Use that row's `income_level` and `eligibility_code`.
- Fall back to code-located fields only if needed during transition.

## Case Facts Impact

No major behavioral change is required in step 8 for this plan.

Optionally, after step 9 exists and is trusted, `case_facts` can be simplified later to read `invoice_versions.users_eligibilitycode_id` instead of resolving the eligibility code itself. That is not part of this narrow plan.

## DDL And Local DB Policy

For source-controlled schema:

- Update `claims_ai_service_ddl/2_create_schema.sql`.

For local development:

- Apply realtime `ALTER TABLE` statements directly to local DB.
- Do not store alter scripts in the repo.

For Gold:

- Gold should be rebuilt from `2_create_schema.sql` when appropriate, not patched from stored alter files.

## Testing Plan

Local only.

### Local Baseline Observed 2026-06-18

Local DB: `app_development`.

Current shape before this plan:

- `claims.invoice_versions` does not yet have `participant_user_id`.
- `claims.invoice_versions` does not yet have `users_eligibilitycode_id`.
- `claims.invoice_versions` has 6 rows.
- `claims.users_eligibilitycodes` has 2 rows.
- `claims.invoice_version_located_fields` has 4 classifier eligibility-code rows.
- `claims.invoice_version_located_fields` has 4 code eligibility-code rows.
- `case_facts`, `product_lookup_enrichment`, `code_common`, and `code_upgrade` all have succeeded local step rows.
- For sampled invoice versions, `product_lookup_enrichment` is completed before `code_common` and `code_upgrade`, which is the ordering this plan relies on.

Useful local eligibility-code rows:

- `ESP1-Wood5cbd76ab`
  - `claims.users_eligibilitycodes.id = ad52c2e3-7697-4448-8ba1-17b660fa3659`
  - `user_id = fd8cee16-52de-41ec-aa89-60ea4fb39fd4`
  - participant display name observed as `Lucy Hemphill`
  - income level `1`
  - approved `2025-01-10`
  - expires `2026-08-11`
- `ESP1-7f6f0647`
  - `claims.users_eligibilitycodes.id = 69188f30-694d-4fe0-b0b5-6dba9df304a2`
  - `user_id = 1a20334f-36bc-4f64-b2a9-4f1562fef7e4`
  - participant display name observed as `rick Hoogendoorn`
  - income level `1`
  - approved `2026-06-04`
  - expires `2027-01-04`

Useful local invoice-version evidence:

- Matched positive case:
  - invoice version `c250a3c7-4c0c-43eb-a2d8-76f55618322f`
  - classifier code `ESP1-Wood5cbd76ab`
  - code-located DB code `ESP1-Wood5cbd76ab`
  - participant name `Lucy Hemphill`
  - current eligibility rules pass.
- Unmatched negative cases:
  - invoice versions `fcbf3d3f-aac7-4c81-973d-b76a83b3a8d1` and `f99bbbd3-4091-4cc2-893c-320008aae9d5`
  - classifier code `ESPI - 7a1899b2`
  - code-located DB code null.
  - current eligibility-code-found rule fails.
  - current eligibility-date and income-level rules warn.
  - invoice version `f02770b3-b8a4-48d8-a262-fb731ac8a4e9`
  - classifier code `ESP3-NatGas2b533c59`
  - code-located DB code null.
  - current eligibility-code-found rule fails.

### Pre-Implementation DB Checks

Run these checks before implementation to confirm the local baseline still matches:

```sql
select column_name
from information_schema.columns
where table_schema = 'claims'
  and table_name = 'invoice_versions'
  and column_name in ('participant_user_id', 'users_eligibilitycode_id')
order by column_name;

select count(*) as invoice_versions_count
from claims.invoice_versions;

select count(*) as users_eligibilitycodes_count
from claims.users_eligibilitycodes;

select source_engine, field_key, count(*)
from claims.invoice_version_located_fields
where field_key ilike '%eligibility%'
   or field_key ilike '%participant%'
group by source_engine, field_key
order by source_engine, field_key;
```

Expected before implementation:

- no rows returned for the two new columns;
- classifier eligibility-code rows exist;
- code-located eligibility-code/participant rows exist.

### Schema Test

After the local realtime `ALTER TABLE` and `2_create_schema.sql` edit:

```sql
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'claims'
  and table_name = 'invoice_versions'
  and column_name in ('participant_user_id', 'users_eligibilitycode_id')
order by column_name;
```

Expected:

- both columns exist;
- both are nullable UUID columns.

Also verify indexes/FKs:

```sql
select indexname
from pg_indexes
where schemaname = 'claims'
  and tablename = 'invoice_versions'
  and indexname in (
    'index_invoice_versions_on_participant_user_id',
    'index_invoice_versions_on_users_eligibilitycode_id'
  )
order by indexname;

select conname
from pg_constraint
where conrelid = 'claims.invoice_versions'::regclass
  and conname in (
    'fk_invoice_versions_participant_user',
    'fk_invoice_versions_users_eligibilitycode'
  )
order by conname;
```

### Positive Enrichment Test

Use an invoice version with a matched eligibility code.

Initial local candidate:

- `invoice_version_id = c250a3c7-4c0c-43eb-a2d8-76f55618322f`
- classifier/code evidence points to `ESP1-Wood5cbd76ab`

After rerunning the deterministic enrichment path for that invoice version, verify:

```sql
select
  iv.id,
  iv.users_eligibilitycode_id,
  iv.participant_user_id,
  uec.eligibility_code,
  uec.user_id
from claims.invoice_versions iv
left join claims.users_eligibilitycodes uec
  on uec.id = iv.users_eligibilitycode_id
where iv.id = 'c250a3c7-4c0c-43eb-a2d8-76f55618322f';
```

Expected:

- `users_eligibilitycode_id = ad52c2e3-7697-4448-8ba1-17b660fa3659`
- `participant_user_id = fd8cee16-52de-41ec-aa89-60ea4fb39fd4`
- joined `eligibility_code = ESP1-Wood5cbd76ab`
- joined `user_id` equals `participant_user_id`

Also verify existing code-located evidence remains:

```sql
select field_key, value_text
from claims.invoice_version_located_fields
where invoice_version_id = 'c250a3c7-4c0c-43eb-a2d8-76f55618322f'
  and source_engine = 'code'
  and field_key in (
    'users_eligibilitycodes.eligibility_code',
    'users_eligibilitycodes.income_level',
    'users_eligibilitycodes.approved_at',
    'users_eligibilitycodes.expires_at',
    'users.participant_name'
  )
order by field_key;
```

Expected:

- existing code-located evidence is still present for viewer/context-window display.

### Negative Enrichment Tests

Use invoice versions with classifier-visible but unmatched eligibility codes.

Initial local candidates:

- `f99bbbd3-4091-4cc2-893c-320008aae9d5` with classifier code `ESPI - 7a1899b2`
- `f02770b3-b8a4-48d8-a262-fb731ac8a4e9` with classifier code `ESP3-NatGas2b533c59`

After rerunning deterministic enrichment for each candidate:

```sql
select
  iv.id,
  iv.users_eligibilitycode_id,
  iv.participant_user_id
from claims.invoice_versions iv
where iv.id in (
  'f99bbbd3-4091-4cc2-893c-320008aae9d5',
  'f02770b3-b8a4-48d8-a262-fb731ac8a4e9'
)
order by iv.id;
```

Expected:

- both UUID columns remain null for both rows.

### Existing Code Rule Regression Tests

After refactoring existing rules, rerun code rules for the positive and negative candidates.

Check positive candidate:

```sql
select rule_key, rule_result, evidence_text, reason_and_likely_causes
from claims.invoice_version_rulechecks
where invoice_version_id = 'c250a3c7-4c0c-43eb-a2d8-76f55618322f'
  and rule_key in (
    'eligibility_code_found_in_database',
    'eligibility_code_valid_for_invoice_date',
    'income_level_1_or_2_required'
  )
order by rule_key;
```

Expected:

- `eligibility_code_found_in_database` passes because `invoice_versions.users_eligibilitycode_id` is populated.
- `eligibility_code_valid_for_invoice_date` passes using the matched `claims.users_eligibilitycodes` row and invoice date.
- `income_level_1_or_2_required` passes using the matched `claims.users_eligibilitycodes` row.
- evidence/reason text should mention the normalized DB row or make clear the result came from the matched eligibility-code record.

Check negative candidates:

```sql
select invoice_version_id, rule_key, rule_result, evidence_text, reason_and_likely_causes
from claims.invoice_version_rulechecks
where invoice_version_id in (
  'f99bbbd3-4091-4cc2-893c-320008aae9d5',
  'f02770b3-b8a4-48d8-a262-fb731ac8a4e9'
)
  and rule_key in (
    'eligibility_code_found_in_database',
    'eligibility_code_valid_for_invoice_date',
    'income_level_1_or_2_required'
  )
order by invoice_version_id, rule_key;
```

Expected:

- `eligibility_code_found_in_database` fails when `users_eligibilitycode_id` is null.
- date/income-level rules warn when the matched DB row is unavailable.
- admin detail remains understandable and should include the classifier-visible code where possible.

### End-To-End Test

Run one normal local package load with a valid eligibility code after implementation.

Expected:

- `case_facts` succeeds.
- `product_lookup_enrichment` succeeds.
- `code_common` succeeds after product lookup.
- `code_upgrade` succeeds after product lookup.
- `invoice_versions.users_eligibilitycode_id` is populated before code rules run.
- `invoice_versions.participant_user_id` is populated before code rules run.
- existing PDF viewer/context-window evidence remains visible through code-located fields.

### Cleanup / Non-Regression Checks

Verify no rule or enrichment code performs a second direct eligibility-code string lookup except the intended deterministic enrichment point:

```bash
rg -n "UsersEligibilitycode|users_eligibilitycodes|eligibility_code" app/services/claims app/jobs/claims
```

Expected:

- deterministic enrichment owns the lookup;
- existing code rules use `invoice_version.users_eligibilitycode_id` or the associated DB row;
- located fields remain only for evidence/details and transitional fallback.

## Out Of Scope

- Duplicate prior-rebate/payment rule.
- Rebate-payment family grouping.
- Exact-upgrade-type duplicate claim detection.
- Package-version/supporting-document revision model.
- Pipeline job-class renaming/alignment.

## Open Questions

- Should step 8 eventually stop doing the eligibility-code DB lookup and rely completely on step 9?
- Should the PDF viewer expose the UUIDs directly to admins, or only show friendly matched participant/code details?
- Should `participant_user_id` eventually move to a future package-version table?
