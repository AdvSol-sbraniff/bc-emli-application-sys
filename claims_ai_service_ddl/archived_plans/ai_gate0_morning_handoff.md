# AI Gate 0 Morning Handoff

Purpose: short handoff for Stephen/Codex after the autonomous Gate 0 documentation pass.

## Current Correction

Stephen has chosen a simpler v1 direction: no code-based rulechecks in the runtime path.

For v1:

- GenAI performs the rulechecks using the OCR/DI JSON and database values supplied in the context window.
- The app should not call `Claims::InvoiceVersionRulechecks::ApplyCodeRulechecks` from the GenAI job.
- Existing code-engine files and source-engine columns can stay as parked/future scaffolding.
- Do not add a second mini-call just to combine codecheck results into revision-request text.

Some older notes below describe a hybrid code-engine path. Treat those as superseded design history, not current v1 direction.

## What Changed

Gate 0 now has enough analysis to guide the next phase.

New/updated artifacts:

- `ai_ruleset_requirements_matrix.md`
- `ai_rules_analysis_gate0_findings.md`
- `ai_code_engine_plan.md`
- `ai_windows_doors_v1_ruleset_refactor_plan.md`
- `ai_ruleset_editor_refactor_plan.md`
- Existing contractor portal plans updated to point at Gate 0 findings.

Post-Gate-0 implementation slice also started, but the code-rulecheck runtime path has since been parked:

- Added the first deterministic code-rulecheck service.
- It is no longer wired into the GenAI job for v1.
- Exposed `code_rulechecks` in existing read endpoints.
- Updated AI invoice viewers to show code and GenAI rulechecks together with a source-engine badge.
- Added rulecheck metadata columns to the DDL and local Postgres: `rule_key`, `source_requirement_id`, `verification_status`, `preferred_evaluator`, and `evidence_source`.

## Main Decision From Gate 0

Proceed with Windows and doors v1 only.

Do not enable heat pumps or all upgrade types in v1.

Reason:

- Windows and doors is compact enough for a first production-ish AI assistant.
- Heat pumps are several subtypes hiding under one app variant and need DB facts, support docs, product lists, and removal/fuel context.

## Superseded Architecture Note

The earlier Gate 0 direction was: do not make GenAI do deterministic validation.

That is now superseded for v1. The current direction is GenAI-only rulechecks for the first contractor-facing implementation.

Longer-term, hybrid validation may still return:

- GenAI locates evidence.
- Code does math/date/threshold/cap checks.
- DB supplies program facts.
- External lookup validates products/certifications later.
- Admin review handles judgment and missing evidence.

This still fits the schema Stephen already designed with `source_engine = 'code' | 'genai'`, but v1 should only create GenAI rulechecks during normal invoice processing.

## Safe Assumptions Used

- AI is pre-review only.
- Missing evidence is `unknown`, not automatic failure.
- One invoice equals one upgrade type for v1.
- Multi-upgrade invoices are v2 unless forced.
- No Gold changes.
- No legacy screen/code changes.
- No implementation code changes during Gate 0.

## Recommended Next Work

1. Review `ai_rules_analysis_gate0_findings.md`.
2. Review the Windows and doors section of `ai_ruleset_requirements_matrix.md`.
3. Approve/refine the hybrid split in `ai_windows_doors_v1_ruleset_refactor_plan.md`.
4. Only then start DDL/code planning for:
   - `rule_key`
   - `source_requirement_id`
   - code-engine rulechecks
   - ruleset package/fragment model
5. After that, draft `esp_windows_doors_2026_04_v1`.

## Suggested Next Code Work

The first code-engine slice is parked. Do not extend it for v1.

Next implementation work:

- Refactor the current seed prompt into `esp_windows_doors_2026_04_v1`.

## Additional Autonomous Slice Completed

After the first Gate 0 implementation slice, Codex briefly continued the Windows and doors code-engine path. This is now parked/superseded for v1:

- Added `users_eligibilitycodes.income_level` as a derived code-located fact from the eligibility code prefix.
- Tightened `eligibility_code_valid_for_invoice_date` so the invoice date must be on/after approval and on/before expiry.
- Added deterministic code rulechecks:
  - `1006 rebate_not_over_invoice_total`
  - `1007 rebate_itemized_and_deducted_math`
  - `2003 wd_income_level_eligible`
  - `2004 wd_rebate_percentage_cap`
  - `2005 wd_per_unit_cap`
  - `2006 wd_per_home_cap`
- Added `claims_ai_service_ddl/run_local_code_rulechecks.rb` as a Rails-runner harness for local retesting.
- Updated AI invoice viewers so unknown rulechecks are visually neutral and rule metadata is visible.

Local harness command:

```bash
docker exec bc-emli-application-sys-app-1 bin/rails runner claims_ai_service_ddl/run_local_code_rulechecks.rb
```

Optional target:

```bash
docker exec -e INVOICE_VERSION_ID=<uuid> bc-emli-application-sys-app-1 bin/rails runner claims_ai_service_ddl/run_local_code_rulechecks.rb
```

Verification notes:

- Ruby syntax checks passed in the app container for the modified Ruby files and harness.
- The local harness ran successfully and replaced 13 `source_engine='code'` rulechecks on the latest local invoice version.
- Frontend TypeScript could not be checked cleanly because WSL resolves `npm` to Windows npm and the repo does not have local `typescript` installed for `npx tsc`.

## Things Not To Do Yet

- Do not redesign contractor portal screens yet.
- Do not redesign admin ruleset editor yet.
- Do not enable heat pump AI.
- Do not seed Gold.
- Do not build multi-upgrade invoice support.

Those are all follow-on phases after the Windows and doors hybrid path is stable.
