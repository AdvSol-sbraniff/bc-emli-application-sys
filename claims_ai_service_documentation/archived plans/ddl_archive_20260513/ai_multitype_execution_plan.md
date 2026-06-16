# AI Multi-Type Execution Plan

## Purpose

This is the small-chunk implementation plan for the multi-upgrade invoice work.

The goal is to avoid a massive big-bang change. Each chunk should leave the app in a testable state, with a clear human test before moving on.

Primary architecture reference:

- `claims_ai_service_ddl/ai_multitype_classifier_pdfviewer_plan.md`

## Operating Rules

- Work local first. Do not push to Gold until the local path is stable.
- Keep old-school screens/code untouched unless the change is strictly needed for the new AI screens.
- Prefer additive DB changes first, then code that starts using them.
- Keep invoice status coarse. The detailed AI subcall state belongs in `claims.ingest_step_runs`, not `claims.invoices.status`.
- After each gate, Stephen should test only the narrow behavior for that gate.

## Gate 1: DDL Shape Only

Purpose:

Add the tables/columns needed for multi-type analysis without changing runtime behavior.

Codex changes:

- Add `claims.invoice_version_upgrade_types`.
- Add `claims.ingest_step_runs.invoice_upgrade_type_id`.
- Expand `claims.ingest_step_runs.step_type` to allow:
  - `upload`
  - `ocr`
  - `classifier`
  - `genai_common`
  - `genai_upgrade`
- Update ingest-step constraints so ruleset and upgrade type are required only for `genai_common` and `genai_upgrade`.
- Add indexes/FKs for the new columns.
- Do not change `Claims::RunGenaiJob` yet.

Human test:

Run the schema and seed scripts locally.

Suggested command from inside the Postgres container:

```sql
\i '/workspace/claims_ai_service_ddl/2_create_schema.sql'
\i '/workspace/claims_ai_service_ddl/4_insert_invoice_upgrade_types.sql'
\i '/workspace/claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql'
\i '/workspace/claims_ai_service_ddl/6_views.sql'
\i '/workspace/claims_ai_service_ddl/7_reporting_views.sql'
```

Verification SQL:

```sql
select upgrade_type_key, description
from claims.invoice_upgrade_types
order by upgrade_type_key;

select r.ruleset_shortname, t.upgrade_type_key
from claims.validationgenai_rulesets r
join claims.invoice_upgrade_types t on t.id = r.invoice_upgrade_type_id
order by t.upgrade_type_key;

select column_name, data_type
from information_schema.columns
where table_schema = 'claims'
  and table_name in ('invoice_version_upgrade_types', 'ingest_step_runs')
order by table_name, ordinal_position;
```

Expected result:

- 8 upgrade types exist, including `common`.
- 8 rulesets exist, including `common`.
- New manifest table exists.
- Existing app still loads.

Stop point:

If the old/current single-call AI still works exactly as before, Gate 1 is good.

## Gate 2: Admin Ruleset UI Shows Common As A Ruleset

Purpose:

Make the ruleset admin screens match the new model before changing runtime GenAI.

Codex changes:

- Move common prompt/rule text into a `common` ruleset row. This was pulled into Gate 1 after first UI testing because the ruleset screen looked incomplete without it.
- Keep `validationgenai_config.system_record` as the true singleton system record.
- Keep `validationgenai_config.admin_advice_intro` and `admin_advice_closing` as singleton wrapper text for the combined contractor-facing advice.
- Remove `common_user_record1` from the active config model; common field/rule tasks live in the `common` ruleset row.
- Ruleset grid should show 8 rows.
- Ruleset editor should edit `common` the same way as any upgrade type.

Human test:

Log in as admin and open the ruleset screen.

Check:

- You can see `common`.
- You can see `windows_doors`.
- You can see `heat_pump`.
- Editing/saving one ruleset does not break the list.
- The AI config screen still shows the true system record.

Optional SQL check:

```sql
select t.upgrade_type_key, count(*) as ruleset_count
from claims.invoice_upgrade_types t
left join claims.validationgenai_rulesets r on r.invoice_upgrade_type_id = t.id
group by t.upgrade_type_key
order by t.upgrade_type_key;
```

Expected result:

- Each of the 8 upgrade types has one current ruleset row in local.

Stop point:

Do not start classifier/runtime work until this UI makes sense.

## Gate 3: Read API And Viewer Can Display Upgrade Groups

Purpose:

Teach the admin PDF viewer/read APIs about upgrade type grouping without changing GenAI execution yet.

Codex changes:

- Add upgrade type display fields to line item, located field, and rulecheck API payloads.
- Add manifest/result rows from `claims.invoice_version_upgrade_types` to the read payload.
- Group the PDF viewer text panel by upgrade type.
- Use `common` as fallback for unclassified rows.

Human test:

Open an existing AI invoice in the admin PDF viewer.

Check:

- The right/text side has sections like `Common`, `Windows and doors`, etc.
- Old rows with no type show under `Common`.
- The PDF itself still loads.
- Existing admin buttons still work.

Verification SQL:

```sql
select t.upgrade_type_key, count(*) lineitem_count
from claims.lineitems li
left join claims.invoice_upgrade_types t on t.id = li.invoice_upgrade_type_id
group by t.upgrade_type_key
order by t.upgrade_type_key;
```

Expected result:

- This may only show `common` before classifier exists. That is fine.

Stop point:

If the viewer grouping looks sane with old data, Gate 3 is good.

## Gate 4: Classifier Call Only

Purpose:

Add the classifier and line-item stamping, but do not run multiple validation rulesets yet.

Codex changes:

- Add classifier prompt/service.
- Call classifier inside `Claims::RunGenaiJob` after OCR/case facts and before GenAI validation.
- Create one `ingest_step_runs` row with `step_type='classifier'`.
- Persist detected upgrade types into `claims.invoice_version_upgrade_types`.
- Stamp `claims.lineitems.invoice_upgrade_type_id` from classifier output.
- Keep the existing single ruleset GenAI call temporarily, probably Windows/doors, so runtime risk stays small.

Human test:

Upload/run one invoice through OCR and GenAI locally.

Check UI:

- Invoice reaches `genai_complete` or gives a useful failure.
- Run tracker shows a `classifier` step.
- PDF viewer line items group by type.

Verification SQL:

```sql
select step_type, status, error_text, validationgenai_ruleset_id, invoice_upgrade_type_id
from claims.ingest_step_runs
order by created_at desc
limit 20;

select t.upgrade_type_key, vut.confidence, vut.call_status, left(vut.evidence_text, 120) evidence
from claims.invoice_version_upgrade_types vut
join claims.invoice_upgrade_types t on t.id = vut.invoice_upgrade_type_id
order by vut.created_at desc
limit 20;

select li.lineitem_seqno, t.upgrade_type_key, li.description
from claims.lineitems li
left join claims.invoice_upgrade_types t on t.id = li.invoice_upgrade_type_id
order by li.created_at desc
limit 30;
```

Expected result:

- Classifier step exists.
- At least one manifest row exists.
- Some line items are classified as `windows_doors`, `heat_pump`, etc., or safely left as `common`.

Stop point:

Do not start multi-ruleset calls until classifier output is stable enough.

## Gate 5: Common Ruleset Call

Purpose:

Run the `common` ruleset as a real call and persist its results.

Codex changes:

- In `Claims::RunGenaiJob`, run the `common` ruleset after classifier.
- Create `ingest_step_runs.step_type='genai_common'`.
- Store common call output in:
  - `ingest_step_runs.genai_results_json`
  - `claims.invoice_version_upgrade_types.genai_raw_json`
  - common located fields/rulechecks stamped with `common` upgrade type
- Do not yet run every detected upgrade-specific ruleset.

Human test:

Run one invoice.

Verification SQL:

```sql
select step_type, status, invoice_upgrade_type_id, validationgenai_ruleset_id, error_text
from claims.ingest_step_runs
order by created_at desc
limit 20;

select t.upgrade_type_key, vut.call_status, vut.genai_overall_confidence, vut.genai_all_rulechecks_pass_flag
from claims.invoice_version_upgrade_types vut
join claims.invoice_upgrade_types t on t.id = vut.invoice_upgrade_type_id
order by vut.created_at desc
limit 20;
```

Expected result:

- `genai_common` step succeeds.
- `common` result row has GenAI result fields populated.
- Viewer shows common located fields/rulechecks grouped under `Common`.

Stop point:

Confirm common rules are useful and not duplicative/noisy.

## Gate 6: One Real Upgrade Ruleset Call

Purpose:

Prove the multi-call structure with exactly one real upgrade type before enabling arbitrary multi-type invoices.

Codex changes:

- After common, run one detected real upgrade type.
- Prefer `windows_doors` first because it has the most known local testing history.
- Create `ingest_step_runs.step_type='genai_upgrade'`.
- Store per-type GenAI result on the manifest row.
- Stamp located fields/rulechecks with the real upgrade type.
- Aggregate parent `invoice_versions.genai_*` fields from common + windows/doors.

Human test:

Run a Windows/doors invoice.

Check:

- Run tracker shows `classifier`, `genai_common`, and `genai_upgrade`.
- Viewer shows `Common` and `Windows and doors`.
- Parent `genai_admin_advice` reads like one combined message, not two pasted emails fighting each other in a trench coat.

Verification SQL:

```sql
select step_type, status, t.upgrade_type_key, s.error_text
from claims.ingest_step_runs s
left join claims.invoice_upgrade_types t on t.id = s.invoice_upgrade_type_id
order by s.created_at desc
limit 30;

select t.upgrade_type_key, vut.call_status, vut.genai_overall_confidence,
       vut.genai_all_rulechecks_pass_flag, left(vut.genai_admin_advice, 200) advice
from claims.invoice_version_upgrade_types vut
join claims.invoice_upgrade_types t on t.id = vut.invoice_upgrade_type_id
order by vut.created_at desc
limit 20;
```

Expected result:

- Parent invoice version has combined `genai_admin_advice`.
- Per-upgrade manifest rows hold section-level advice.

Stop point:

If this works, the core architecture is validated.

## Gate 7: Multiple Real Upgrade Ruleset Calls

Purpose:

Enable true multi-upgrade invoices.

Codex changes:

- Loop over all classifier-detected real upgrade types with rulesets.
- Skip real upgrade types not detected.
- If no real type is detected, run common only and fail/flag gracefully.
- Keep each per-type call independently logged.
- Aggregate all results to the parent invoice version.

Human test:

Run a known mixed invoice, ideally one containing Windows/doors plus Heat pump.

Check:

- Run tracker shows one classifier, one common, and one `genai_upgrade` per detected upgrade type.
- Viewer shows separate groups.
- Admin advice has one intro, grouped upgrade sections, and one closing.

Stop point:

If a mixed invoice works locally, then we can start polishing UI and retry flows.

## Gate 8: Retry And Failure Handling

Purpose:

Make failures survivable for local testing and future contractor use.

Codex changes:

- If classifier fails, invoice status becomes `genai_failed`.
- If one upgrade call fails, invoice status becomes `genai_failed` or `genai_partial_failed` only if we add that status later.
- Add retry helpers/buttons only for the new AI admin/contractor screens.
- Retry should start at the failed step where feasible:
  - classifier
  - common
  - specific upgrade type

Human test:

Temporarily force/observe a failure.

Check:

- Failed step has `error_text`.
- No silent blank screen.
- Retry does not duplicate good rows endlessly.

Stop point:

This is the point where a contractor-facing upload flow becomes realistic.

## Gate 9: Contractor Flow

Purpose:

Wire the contractor AI upload path after the admin/runtime foundation is stable.

Codex changes:

- Add AI invoice submissions tab.
- Add contractor upload screen.
- Add contractor PDF viewer with submit/fix/supplement actions.
- Use grouped analysis display where appropriate.

Human test:

Log in as `MiniMe1`.

Check:

- Contractor can upload.
- Contractor can see processing status.
- Contractor can submit once AI processing is complete.

## Useful Local Commands

Start app stack:

```bash
docker compose up
```

App logs:

```bash
docker compose logs -f app
```

Run Rails console/runner:

```bash
docker compose exec app bin/rails console
docker compose exec app bin/rails runner 'puts Claims::Invoice.count'
```

Run SQL from local psql if available:

```bash
PGPASSWORD=password psql -h 127.0.0.1 -U postgres -d app_development
```

Run SQL from inside Postgres container:

```bash
psql -U postgres -d app_development
```

## Stop/Go Rule

After each gate:

- If SQL shape is wrong, stop and fix DDL/DML.
- If backend data is right but UI is confusing, fix UI before moving on.
- If AI output is poor but plumbing is right, adjust ruleset prompt text before changing the architecture.
- If a gate passes, commit mentally and move to the next small gate.
