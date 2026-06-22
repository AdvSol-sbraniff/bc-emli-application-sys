# One Rebate Payment Per Participant Plan

## Requirement Source

The ESP requirements say:

> Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade.

## Goal

Add a code-owned advice check that detects whether the same participant already has a rebate payment, or a likely competing active claim, for the same detected upgrade type.

This should be a deterministic code rule, not a GenAI rule.

## Key Interpretation

V1 will intentionally use the simpler exact-upgrade-type interpretation.

The requirement text defines broader rebate-payment families, especially for "primary heating system." A fuller version could group these technical upgrade types together:

- `air_source_heat_pump_electric`
- `air_source_heat_pump_wood`
- `air_source_heat_pump_gas_propane`
- `air_source_heat_pump_oil`
- `dual_fuel_ducted_heat_pump`
- `air_to_water_heat_pump`
- `combined_space_water_heat_pump`

However, V1 will not implement that family grouping. V1 will compare exact `invoice_upgrade_type_id` / `upgrade_type_key` only.

Rationale:

- It is simpler and lower risk.
- It catches the obvious duplicate cases.
- It avoids creating a new family mapping before business confirms how strict the primary-heating-system grouping should be.
- It avoids pretending we fully implemented the broader legal wording when the system is intentionally doing a narrower first pass.

Suggested V1 rule name should reflect the narrower behavior, for example:

- `prior_same_upgrade_type_rebate_payment_found`

Future V2 can add a `rebate_payment_group_key` or normalized rebate-family table when we want to implement the broader primary-heating-system bucket.

## Prerequisite

This backlog item assumes the active `invoice_version_eligibility_uuid_enrichment_plan.md` has already been implemented.

Required existing fields before this rule is built:

- `claims.invoice_versions.participant_user_id`
- `claims.invoice_versions.users_eligibilitycode_id`

The duplicate-payment rule should rely on those normalized invoice-version fields. It should not re-resolve the participant by string-matching the eligibility code.

## Local DB Review Notes

Reviewed local DB on 2026-06-18 before implementation planning.

Confirmed schema support:

- `claims.invoice_versions.participant_user_id` exists and references `public.users`.
- `claims.invoice_versions.users_eligibilitycode_id` exists and references `claims.users_eligibilitycodes`.
- `claims.invoice_version_upgrade_types` is the detected-upgrade-type table to use for exact V1 matching.
- `claims.invoices.status` includes the states needed for this rule: `genai_complete`, `admin_review_inbox`, `contractor_revision_inbox`, `in_review`, `approved_pending`, `approved_paid`, `ineligible`, `package_needs_correction`, and `technical_failure`.
- `claims.invoices` does not have `current_invoice_version_id`; use latest version by `max(invoice_versionno)` per `invoice_id`.

Important data-shape finding:

- Local fixture data can have more than one `invoice_version_upgrade_types` row for the same upgrade type when different `source_engine` values exist. The rule must evaluate distinct `invoice_upgrade_type_id` values, not raw rows, or it can double-report the same upgrade type.

Code-runner finding:

- This rule belongs in `Claims::InvoiceVersionRulechecks::ApplyCodeRulechecks`.
- Add the new key to both `COMMON_RULE_KEYS` and `COMMON_RULE_BUILDERS`.
- Because `validate_common_rule_coverage!` raises when a common code rule is enabled but lacks an executor, the registry seed and Ruby implementation must ship together.

### No Rebate-Family Mapping In V1

Do not add `rebate_payment_group_key` in V1.

V1 will compare exact detected upgrade types using `claims.invoice_version_upgrade_types.invoice_upgrade_type_id`.

Documented limitation:

- This will not catch a prior paid `air_source_heat_pump_wood` claim when the new package is `dual_fuel_ducted_heat_pump`.
- That broader "primary heating system" grouping can be added later as V2.

## Pipeline Placement

After the prerequisite plan is complete, no special new pipeline phase is required.

This rule should run with the existing code-rule steps:

- `code_common` if implemented as one common rule that loops all detected upgrade types.
- `code_upgrade` only if we later decide it should produce one row per upgrade-type-specific code-rule invocation.

Recommended V1 placement: `code_common`, because the rule compares the current invoice version against other invoice parents and can loop all detected upgrade types in one deterministic pass.

## New Code Rule

Suggested key:

- `prior_same_upgrade_type_rebate_payment_found`

Suggested category:

- Common code rule, because it can evaluate all detected upgrade types for the invoice version.

Suggested result behavior:

- `pass`: no prior paid/approved-paid claim exists for the same participant and same detected upgrade type.
- `warn`: another non-closed active claim exists for the same participant and same detected upgrade type, but it is not yet a paid rebate.
- `fail`: another paid or payment-approved claim exists for the same participant and same detected upgrade type.
- `warn`: participant could not be resolved, so duplicate-payment history cannot be checked.

## Query Shape

For the current invoice version:

1. Load `invoice_versions.participant_user_id`.
2. Load detected upgrade types from `claims.invoice_version_upgrade_types`.
3. For each detected upgrade type:
   - Find other invoice parents for the same `participant_user_id`.
   - Join their current/latest invoice version.
   - Join their detected upgrade types.
   - Match the same `invoice_upgrade_type_id`.
   - Exclude the current invoice parent.

Fail statuses:

- `approved_paid`

Possible fail-or-warn business decision:

- `approved_pending`

Recommended default:

- Treat `approved_pending` as `warn`, not `fail`, unless business says a pending approval is already a payment commitment.

Warn statuses:

- `genai_complete`
- `admin_review_inbox`
- `contractor_revision_inbox`
- `in_review`
- `approved_pending`

Ignore statuses:

- upload/ocr/genai in-progress statuses
- `package_needs_correction`
- `technical_failure`
- `ineligible`

Those records are not evidence of a received rebate payment.

## Current Version Handling

The comparison should use only the latest/current invoice version for each invoice parent.

Current schema does not appear to have an explicit `current_invoice_version_id` on `claims.invoices`, so the initial implementation can use:

```sql
max(invoice_versionno) per invoice_id
```

Future improvement:

- Add `current_invoice_version_id` to `claims.invoices` once package-version work begins.

## Implementation Details

Use a latest-version CTE/subquery equivalent to:

```sql
SELECT DISTINCT ON (invoice_id)
  id,
  invoice_id,
  invoice_versionno,
  participant_user_id,
  users_eligibilitycode_id
FROM claims.invoice_versions
ORDER BY invoice_id, invoice_versionno DESC
```

Then compare the current invoice version against only those latest-version rows.

Current detected upgrade types should be loaded as distinct IDs:

```sql
SELECT DISTINCT invoice_upgrade_type_id
FROM claims.invoice_version_upgrade_types
WHERE invoice_version_id = :current_invoice_version_id
```

Result precedence:

- If `participant_user_id` is missing, return `warn`.
- If any same-participant, same-exact-upgrade latest prior invoice has status `approved_paid`, return `fail`.
- Else if any same-participant, same-exact-upgrade latest prior invoice has status in the warn list, return `warn`.
- Else return `pass`.

Recommended output shape:

- V1 can write one common rulecheck row whose detail lists each evaluated upgrade type and whether it passed/warned/failed.
- If any evaluated upgrade type fails, the overall row is `fail`.
- Else if any evaluated upgrade type warns, the overall row is `warn`.
- Else the overall row is `pass`.

The detail text should still include per-upgrade outcomes, because a multi-upgrade invoice can have one duplicate and one clean upgrade.

## Evidence Output

The code rule should write detailed `invoice_version_rulechecks` rows.

For each upgrade type evaluated, include:

- participant user ID
- matched eligibility code ID
- current invoice ID/version
- current upgrade type key
- matching prior invoice IDs/versions
- matching prior invoice statuses
- matching prior invoice upgrade type keys

The admin-facing detail should identify exactly why the result was pass/warn/fail.

## Rule Registry Seed

Add the new code rule to `3_insert_code_rules.sql`.

Suggested description:

Checks whether the matched participant already has a paid or active claim for the same detected upgrade type. This is a V1 exact-upgrade-type check and does not yet group all primary-heating-system upgrade types together.

Suggested fail message:

This participant appears to already have a paid rebate for the same upgrade type. Review the prior invoice before approving another payment.

Suggested warn message:

This participant has another active or pending claim for the same upgrade type. Confirm whether it is a duplicate before moving forward.

## UI Impact

Admin invoice review:

- Show the new code advice check under Advice Checks.
- Use the detail text to show the prior invoice(s) and family.

Rules/advice editor:

- New rule appears as a code-owned advice check.

Contractor review:

- If exposed to contractors, keep wording soft:
  - "This package may overlap with another rebate request for the same participant and upgrade type."
  - Avoid internal table names and IDs.

## Testing Plan

Create and use local test data only. Do not add a stored SQL patch or test-data insert script for this fixture set.

Local fixture marker:

- `claims.invoices.system_help_notes LIKE 'rebate-rule-fixture:%'`
- `claims.invoice_versions.original_filename LIKE 'rebate-rule-fixture-%'`

Local fixture participant A:

- `claims.users_eligibilitycodes.eligibility_code = 'ESP1-REBATE-A'`
- `claims.users_eligibilitycodes.id = 33333333-3333-4333-8333-333333333333`
- `participant_user_id = 11111111-1111-4111-8111-111111111111`
- This is a dedicated local-only fixture participant to avoid accidental matches against older local package-test data.

Local fixture participant B:

- `claims.users_eligibilitycodes.eligibility_code = 'ESP1-REBATE-B'`
- `claims.users_eligibilitycodes.id = 44444444-4444-4444-8444-444444444444`
- `participant_user_id = 22222222-2222-4222-8222-222222222222`
- This is a dedicated local-only fixture participant used to prove same upgrade type does not match across different participants.

Local fixture rows created on 2026-06-18:

| Fixture                                                     |                     Invoice version ID | Status             | Participant | Upgrade type rows                                                                         | Purpose                                                                                    |
| ----------------------------------------------------------- | -------------------------------------: | ------------------ | ----------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `prior_paid_windows`                                        | `21f6a6db-9160-467e-a4e7-42b0590d55d8` | `approved_paid`    | A           | `windows_doors`                                                                           | Paid prior same exact upgrade should cause fail.                                           |
| `prior_pending_insulation`                                  | `fb55b4cb-7cba-4a19-bd9c-cf28fe0b7354` | `approved_pending` | A           | `insulation`                                                                              | Pending prior same exact upgrade should cause warn.                                        |
| `prior_in_review_insulation`                                | `5f489bc5-082f-43ec-a8b4-52a83f5e20b8` | `in_review`        | A           | `insulation`                                                                              | Active prior same exact upgrade should cause warn.                                         |
| `prior_ineligible_hpwh`                                     | `73dec121-80bc-4175-86a3-43ae04f301b8` | `ineligible`       | A           | `heat_pump_water_heater`                                                                  | Closed ineligible prior should be ignored.                                                 |
| `prior_paid_heat_pump_wood`                                 | `047c0d21-edf5-41a7-8de8-bcfb6e113a2b` | `approved_paid`    | A           | `air_source_heat_pump_wood`                                                               | Different exact upgrade should not affect V1 exact matching.                               |
| `prior_paid_multiversion_latest_ventilation` old version    | `a8e74b25-e895-42c5-ae5d-1ce14ce22e90` | `approved_paid`    | A           | `heat_pump_water_heater`                                                                  | Old version should be ignored.                                                             |
| `prior_paid_multiversion_latest_ventilation` latest version | `ddc79b2b-02f7-4874-8617-814b461a657d` | `approved_paid`    | A           | `ventilation`                                                                             | Latest version participates; old HPWH version must not.                                    |
| `current_multi_a`                                           | `a3badc11-3ea5-4639-8fac-f02c40c438e6` | `genai_complete`   | A           | `windows_doors` classifier, `windows_doors` genai, `insulation`, `heat_pump_water_heater` | Multi-upgrade current test; also tests de-duping same upgrade type across source engines.  |
| `current_exact_family_a`                                    | `08e5dfbb-d083-4fe8-b3f3-162a76091f18` | `genai_complete`   | A           | `air_source_heat_pump_electric`                                                           | Should pass V1 despite paid `air_source_heat_pump_wood`, because V1 is exact-upgrade only. |
| `current_missing_participant`                               | `fd8375bb-c52a-4624-ada2-42503633ed60` | `genai_complete`   | missing     | `windows_doors`                                                                           | Missing participant should warn.                                                           |
| `current_other_participant_b`                               | `59cd9a7b-0ea1-4ca6-a9f3-b8bcd9da9b69` | `genai_complete`   | B           | `windows_doors`                                                                           | Same exact upgrade paid by participant A should not affect participant B.                  |

Expected rule outcomes:

| Current fixture               | Expected overall result | Required detail assertions                                                                                                                                                                                                                                                          |
| ----------------------------- | ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `current_multi_a`             | `fail`                  | `windows_doors` fails due to `prior_paid_windows`; `insulation` warns due to `prior_pending_insulation` and `prior_in_review_insulation`; `heat_pump_water_heater` passes because `prior_ineligible_hpwh` is ignored and the old HPWH row in the multi-version prior is not latest. |
| `current_exact_family_a`      | `pass`                  | Does not fail due to `prior_paid_heat_pump_wood`; V1 exact matching intentionally does not group primary-heating-system families.                                                                                                                                                   |
| `current_missing_participant` | `warn`                  | Detail says `participant_user_id` is missing and duplicate-payment history cannot be checked.                                                                                                                                                                                       |
| `current_other_participant_b` | `pass`                  | Does not match participant A's paid `windows_doors` prior.                                                                                                                                                                                                                          |

Manual SQL sanity query used to verify fixture candidates:

```sql
WITH latest_versions AS (
  SELECT DISTINCT ON (iv.invoice_id)
    iv.id,
    iv.invoice_id,
    iv.invoice_versionno,
    iv.participant_user_id,
    iv.users_eligibilitycode_id
  FROM claims.invoice_versions iv
  ORDER BY iv.invoice_id, iv.invoice_versionno DESC
),
current_versions AS (
  SELECT
    iv.id AS current_invoice_version_id,
    iv.invoice_id AS current_invoice_id,
    iv.participant_user_id,
    i.system_help_notes
  FROM claims.invoice_versions iv
  JOIN claims.invoices i ON i.id = iv.invoice_id
  WHERE i.system_help_notes LIKE 'rebate-rule-fixture: current%'
),
current_types AS (
  SELECT DISTINCT
    cv.current_invoice_version_id,
    cv.current_invoice_id,
    cv.participant_user_id,
    cv.system_help_notes,
    iut.id AS invoice_upgrade_type_id,
    iut.upgrade_type_key
  FROM current_versions cv
  JOIN claims.invoice_version_upgrade_types ivut
    ON ivut.invoice_version_id = cv.current_invoice_version_id
  JOIN claims.invoice_upgrade_types iut
    ON iut.id = ivut.invoice_upgrade_type_id
)
SELECT
  ct.system_help_notes AS current_fixture,
  ct.current_invoice_version_id,
  ct.upgrade_type_key,
  pi.status AS prior_status,
  pi.system_help_notes AS prior_fixture,
  lv.id AS prior_invoice_version_id,
  lv.invoice_versionno AS prior_versionno
FROM current_types ct
LEFT JOIN latest_versions lv
  ON lv.participant_user_id = ct.participant_user_id
 AND lv.invoice_id <> ct.current_invoice_id
LEFT JOIN claims.invoices pi
  ON pi.id = lv.invoice_id
LEFT JOIN claims.invoice_version_upgrade_types pivut
  ON pivut.invoice_version_id = lv.id
 AND pivut.invoice_upgrade_type_id = ct.invoice_upgrade_type_id
WHERE pi.system_help_notes LIKE 'rebate-rule-fixture:%'
  AND pivut.id IS NOT NULL
ORDER BY current_fixture, upgrade_type_key, prior_status, prior_fixture;
```

Expected rows from that sanity query:

- `current_multi_a` / `windows_doors` matches `prior_paid_windows` with `approved_paid`.
- `current_multi_a` / `insulation` matches `prior_pending_insulation` with `approved_pending`.
- `current_multi_a` / `insulation` matches `prior_in_review_insulation` with `in_review`.
- `current_multi_a` / `heat_pump_water_heater` matches `prior_ineligible_hpwh` with `ineligible`, which the rule must ignore for pass/fail purposes.
- No row should appear for the old HPWH row in `prior_paid_multiversion_latest_ventilation`, because only version 2 is latest.

After implementation, run:

1. Syntax check for the touched code-rule service files.
2. Rerun `claims_ai_service_ddl/3_insert_code_rules.sql` locally so the new rule is enabled for `common`.
3. Run the common code-rule service for the four current fixture invoice versions listed above.
4. Query `claims.invoice_version_rulechecks` for `rule_key = 'prior_same_upgrade_type_rebate_payment_found'`.
5. Confirm the expected result and detail assertions in the table above.
6. Run at least one normal local package load after the fixture checks to confirm the new common rule does not break the existing pipeline.

## Implementation Steps

1. Confirm `invoice_versions.participant_user_id` and `invoice_versions.users_eligibilitycode_id` exist and are populated by deterministic enrichment.
2. Add `prior_same_upgrade_type_rebate_payment_found` to the code rule registry seed.
3. Implement the V1 exact-upgrade-type code rule.
4. Keep existing `invoice_version_located_fields` code evidence intact for display/detail text.
5. Run the rerunnable seeds locally.
6. Create local test records covering the test plan.
7. Run code rule tests and at least one end-to-end local package load.

## Open Questions

- Should `approved_pending` be a fail or a warn?
- Should `admin_review_inbox` and `in_review` be warnings, or ignored until payment approval?
- Should this rule be hidden from contractors or shown in softened language?
- Should V2 add broader rebate-payment family grouping for primary heating system?
- Should `participant_user_id` eventually move from `invoice_versions` to the future `invoice_package_versions` table?
