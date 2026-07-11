# Rule Source Quote and Contractor Advice Plan

## Goal

Add rule-level traceability back to the requirement PDF, and make the contractor-facing advice cleaner and safer.

Each GenAI rule and code rule will have:

- `source_quote`: the exact requirement PDF quote that backs the rule.
- `contractor_visible_flag`: whether this rule is allowed to contribute to contractor-facing advice.

The admin PDF viewer will show the source quote beside each rulecheck. The existing overall/admin advice concept will become contractor advice, and it will only include contractor-visible failed requirements.

## Data Model Changes

Add these columns to both registry tables:

```sql
ALTER TABLE claims.genai_rules
  ADD COLUMN source_quote text NOT NULL,
  ADD COLUMN contractor_visible_flag boolean NOT NULL DEFAULT true;

ALTER TABLE claims.code_rules
  ADD COLUMN source_quote text NOT NULL,
  ADD COLUMN contractor_visible_flag boolean NOT NULL DEFAULT true;
```

Add non-empty quote constraints:

```sql
ALTER TABLE claims.genai_rules
  ADD CONSTRAINT genai_rules_source_quote_present_chk
  CHECK (btrim(source_quote) <> '');

ALTER TABLE claims.code_rules
  ADD CONSTRAINT code_rules_source_quote_present_chk
  CHECK (btrim(source_quote) <> '');
```

Also add the same fields to the history tables so admin edits snapshot the complete rule record:

```sql
ALTER TABLE claims.genai_rule_history
  ADD COLUMN source_quote text NULL,
  ADD COLUMN contractor_visible_flag boolean NULL;

ALTER TABLE claims.code_rule_history
  ADD COLUMN source_quote text NULL,
  ADD COLUMN contractor_visible_flag boolean NULL;
```

Update the full rebuild DDL in `claims_ai_service_ddl/2_create_schema.sql`.

Update local DB with equivalent `ALTER TABLE` statements.

## Seed Changes

Update the full rebuild seeds:

- `claims_ai_service_ddl/3_insert_genai_normalized.sql`
- `claims_ai_service_ddl/3_insert_code_rules.sql`

Default every seeded rule to:

```sql
contractor_visible_flag = true
```

Every seeded rule must also include a non-empty exact `source_quote`, because the DB constraint will reject a rule without one. This avoids any runtime fallback or skipped contractor advice caused by missing rule-source text.

The upsert logic should include both new fields so a nightly blowaway/rebuild preserves them.

## Admin Editors

Update the validation rule editor APIs:

- `app/controllers/api/claims/validation_rules_admin_controller.rb`
- `app/controllers/api/claims/code_rules_admin_controller.rb`

Permit, serialize, create, and update:

- `source_quote`
- `contractor_visible_flag`

Update the rule editor UI:

- `app/frontend/components/domains/validation-rules-admin/index.tsx`
- `app/frontend/components/domains/validation-rules-alphabetic-admin/index.tsx`
- `app/frontend/components/domains/code-rulesets-admin/index.tsx`, if still used for direct code-rule editing

UI fields:

- Add a textarea labelled `Source quote from requirement PDF`.
- Add a checkbox labelled `Visible to contractor advice`.
- Show both values in detail/read-only panels.

## Rulecheck Serialization

Rulecheck rows currently store the rule result, but not the registry metadata. The API should attach registry metadata when serializing rulechecks.

Update rulecheck serialization in:

- `app/controllers/api/claims/invoice_versions_admin_controller.rb`
- `app/controllers/api/claims/invoice_versions_controller.rb`

For each rulecheck:

- If `source_engine = "genai"`, join/read `claims.genai_rules` by `rule_key = genai_rule_key`.
- If `source_engine = "code"`, join/read `claims.code_rules` by `rule_key = code_rule_key`.
- Add `source_quote` to the serialized rulecheck JSON.
- Add `contractor_visible_flag` to the serialized rulecheck JSON.

Recommendation: do not duplicate `source_quote` into `claims.invoice_version_rulechecks` for now. The registry is the source of truth, and the user asked for these fields on the two registry tables.

## Admin PDF Viewer

Update:

- `app/frontend/components/domains/invoice-versions/index.tsx`
- `app/frontend/components/domains/contractor-invoice-review/index.tsx`, if it displays rule details/advice

For each rulecheck detail panel, display:

- `Source quote`: italicized quote text when present.
- `Contractor visible`: small yes/no badge or text.

Rename the existing advice accordion/label:

- From `Overall advice`, `Admin advice`, or similar wording.
- To `Contractor Advice`.

## Contractor Advice Generation

Current storage appears to use `claims.invoice_versions.genai_admin_advice`. Rename the concept to contractor advice.

Preferred implementation:

```sql
ALTER TABLE claims.invoice_versions
  RENAME COLUMN genai_admin_advice TO contractor_advice;
```

Then update all model/controller/frontend/job references from `genai_admin_advice` to `contractor_advice`.

Files likely touched:

- `claims_ai_service_ddl/2_create_schema.sql`
- `app/jobs/claims/run_genai_job.rb`
- `app/services/claims/invoice_versions/apply_genai_overall.rb`
- `app/services/claims/invoice_versions/reset_ai_outputs.rb`
- `app/services/claims/ingest/create_rule_change_run.rb`
- `app/services/claims/ingest/upload_fix_package.rb`
- `app/controllers/api/claims/invoice_versions_admin_controller.rb`
- `app/controllers/api/claims/invoice_versions_controller.rb`
- `app/frontend/components/domains/invoice-versions/index.tsx`
- `app/frontend/components/domains/contractor-invoice-review/index.tsx`
- `app/frontend/components/domains/invoice-versions-admin/index.tsx`

Contractor advice generation rules:

- Include only rulechecks with `rule_result = "fail"`.
- Include only rules where `contractor_visible_flag = true`.
- Use only `source_quote` as the bullet content.
- De-duplicate repeated source quotes.
- Do not include rule keys, expected text, calculation, reason, confidence, or evidence in contractor advice.
- Do not include warnings, infos, or passes.

Use the existing configurable advice wrapper fields from `claims.validation_genai_config`:

- `admin_advice_intro`: opening text.
- `admin_advice_closing`: closing text.

The contractor advice builder should assemble:

```text
{admin_advice_intro}
- _Exact source quote one._
- _Exact source quote two._
{admin_advice_closing}
```

For the current desired contractor wording, update the seed/default config so `admin_advice_intro` is:

```text
Please check for potential issues with the following program requirement(s):
```

The closing can remain whatever admin-configured value is desired, including blank.

If there are no contractor-visible failed source quotes, store `NULL` or blank contractor advice.

## Advice Builder Refactor

There are at least two advice builders:

- `app/jobs/claims/run_genai_job.rb`
- `app/services/claims/invoice_versions/apply_genai_overall.rb`

Avoid letting these drift. Create one shared helper/service for contractor advice generation, then call it from both places.

Suggested service:

- `app/services/claims/invoice_versions/build_contractor_advice.rb`

Inputs:

- Rulecheck hashes or relation rows.

Output:

- Contractor advice string or `nil`.

This keeps the exact wording and filtering rules in one place.

## Local DB Update

Apply live local DB changes after script edits:

- Add columns to registry tables.
- Add columns to history tables.
- Rename `genai_admin_advice` to `contractor_advice`, if we choose the physical rename.
- Backfill `contractor_visible_flag = true` for existing rules.
- Backfill every existing rule with a non-empty exact `source_quote` before applying the non-empty constraints.

Example:

```sql
UPDATE claims.genai_rules
SET contractor_visible_flag = true
WHERE contractor_visible_flag IS NULL;

UPDATE claims.code_rules
SET contractor_visible_flag = true
WHERE contractor_visible_flag IS NULL;
```

## Testing

Database:

- Run DDL syntax checks or rebuild against local DB.
- Confirm both registry tables and history tables have the new columns.
- Confirm all existing rules default to `contractor_visible_flag = true`.

API:

- Fetch validation rules admin data and confirm `source_quote` and `contractor_visible_flag` serialize.
- Update a GenAI rule source quote and visibility flag.
- Update a code rule source quote and visibility flag.
- Fetch invoice version rulechecks and confirm each rulecheck includes source quote/visibility metadata.

Advice behavior:

- Failed visible rule with quote appears in contractor advice.
- Failed invisible rule does not appear.
- Warn/info/pass visible rules do not appear.
- Failed visible rule with duplicate quote appears once.
- Attempting to save a rule with blank `source_quote` fails validation and/or DB constraint.

Frontend:

- Run ESLint for touched React files.
- Admin PDF viewer shows source quote in rule details.
- Advice accordion is labelled `Contractor Advice`.
- Rule editors can edit source quote and contractor visibility.

Manual:

- Pick one local invoice version with at least one red rule.
- Set one red rule `contractor_visible_flag=false`.
- Re-run or rebuild advice.
- Confirm the rule still shows in admin review, but no longer contributes to contractor advice.

## Open Decisions

Recommended defaults unless you object:

- Physically rename `genai_admin_advice` to `contractor_advice`, not just relabel it in the UI. The old name is now misleading.
- Require non-empty `source_quote` for every rule at the DB level.
- Keep `source_quote` as the exact quote only. Put section references or interpretation notes in `admin_notes`, not in `source_quote`.
