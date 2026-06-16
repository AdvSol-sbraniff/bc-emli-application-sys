# Plan 0: Move Compiled Prompt Background Into Normalized Rules

## Purpose

Before any `claims.validationgenai_rulesets` runtime cleanup, fix normalized GenAI rule prompts that currently rely on useful table/background text from the old compiled `user_record1` blob.

This is Plan 0 because it fixes an existing design bug even before the larger table-removal work begins.

## Problem

Some normalized rebate-math rules say things like:

- "Determine the applicable cap from the summary-table values above"
- "Apply the category-mapping notes above"
- "Use the source-fuel and eligibility-code cap above"
- "apply the location-specific formula/rate from the background section"

That only works today because `claims.validationgenai_rulesets.user_record1` contains manually compiled program background text above the rule. The Ruby compiler cannot currently reproduce that background text from normalized tables. After the runtime compiles directly from normalized rules, that "above" text will not exist unless the rule prompt itself includes it.

The current seeded compiled rows mask the problem locally because the active `esp_*_v1` rows contain the missing background. A normalized admin save/publish path can still create newer compiled rows that omit this background, so the issue is already a real design bug.

## Decision

Put the needed table values directly into the relevant normalized rule prompt.

Do not add a new table or new `invoice_upgrade_types` field for this pass. The values are used by the rebate-math rules themselves, so proximity is clearer and safer for the LLM.

Use the existing compiled seed file as the source for the missing context:

- source: `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql`
- destination: `claims_ai_service_ddl/5_insert_genai_normalized.sql`

In other words: move the business-critical table/background text currently embedded in the compiled `validationgenai_rulesets.user_record1` seed into the relevant `claims.genai_rules.prompt_text` seed rows.

When this plan is complete, no business-critical rule prompt should depend on a compiled `validationgenai_rulesets` background section. There should be no dangling "compiled temp table" seed artifact left behind as a hidden source of business rules.

## Scope

Update normalized GenAI rule prompt text in:

- `claims_ai_service_ddl/5_insert_genai_normalized.sql`
- local Postgres

Reference text should be copied/adapted from:

- `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql`

Rules that must be made self-contained:

- `ashp_electric_rebate_math_within_cap`
- `ashp_wood_rebate_math_within_cap`
- `ashp_gas_propane_rebate_math_within_cap`
- `ashp_oil_rebate_math_within_cap`
- `dfhp_rebate_math_within_cap`
- `atw_rebate_math_within_cap`
- `cshp_rebate_math_within_cap`
- `hpwh_rebate_math_within_cap`
- `ins_rebate_math_within_cap`

Rules that should receive small cleanup wording so they do not silently lose compiled-background meaning:

- `wd_per_unit_rebate_math_within_cap`
- `wd_per_home_rebate_math_within_cap`
- `hs_rebate_math_within_cap`
- `vent_rebate_math_within_cap`

`esu_rebate_math_within_cap` is already self-contained enough and does not need a Plan 0 prompt move unless review finds new evidence.

## Hidden Context To Move

Move only the useful business values/tables that rule prompts need. Do not copy every paragraph of program prose into every rule.

Required prompt-local context:

- Electric ASHP: ESP1/ESP2 cap table for central ducted / 3-head multi-split, 2-head / 2 single-head, and single-head; category mapping for low-static-pressure ducted mini-splits and three-or-more supply outlets/zones.
- Wood ASHP: same ESP1/ESP2 cap table and same category mapping as electric ASHP.
- Gas/propane ASHP: ESP1/ESP2/ESP3 cap table by equipment category; northern top-up caps of $3,000 for central/multi/2-head/air-to-water/combined and $1,500 for single-head, ESP1/ESP2 only; same category mapping.
- Oil ASHP: ESP1/ESP2/ESP3 cap table by equipment category; northern top-up caps of $3,000 for central/multi/2-head/air-to-water/combined and $1,500 for single-head, ESP1/ESP2 only; same category mapping.
- Dual-fuel ducted heat pump: PNG natural gas/propane cap table, tank propane cap table, and $3,000 ESP1/ESP2 northern top-up cap.
- Air-to-water heat pump: fossil-fuel source cap table, electric/wood source cap table, and $3,000 ESP1/ESP2 northern top-up cap.
- Combined space and water heat pump: fossil-fuel source cap table, electric/wood source cap table, and $3,000 ESP1/ESP2 northern top-up cap.
- Heat pump water heater: fossil-fuel source cap table, electric/wood source cap table, and explicit ESP3 no-rebate wording for electric/wood.
- Insulation: ESP1/ESP2-only rule, ESP3 no-rebate rule, location-specific R-value minimums, location-specific formula/rates, $2,000 location maximum, and $5,500 home maximum.
- Windows/doors: explicit ESP3 no-rebate wording alongside the existing ESP1/ESP2 percentages and $950/$9,500 caps.
- Health and safety remediation: explicit ESP3 no-rebate wording alongside the existing ESP1/ESP2 percentages and $800 cap.
- Ventilation: explicit ESP3 no-rebate wording alongside the existing ESP1/ESP2 percentages and $1,600 cap.

## Prompt Rules

For each affected prompt:

- Replace "summary-table values above" with explicit cap values.
- Replace "category-mapping notes above" with explicit category mapping notes.
- Include northern top-up caps directly when the rule evaluates top-up.
- Pull those cap/category/top-up values from the existing compiled `5_insert_validationgenai_rulesets.sql` seed content.
- Keep the prompt concise enough that the rule remains readable.
- Do not centralize these values unless later evidence shows the same table is useful to several unrelated rules.
- Remove any wording that assumes a prior/background section exists.

## Verification

Run a local SQL/search check:

```bash
rg -n "summary-table values above|category-mapping notes above|above using|cap above|background section" claims_ai_service_ddl/5_insert_genai_normalized.sql
```

Expected:

- no rebate-math rule depends on invisible "above" text
- each affected rule contains the cap/category/top-up values needed to evaluate the rule
- ESP3 no-rebate conditions are explicit where the compiled background previously carried that meaning

Then apply the seed update to local Postgres and verify the same text is present in `claims.genai_rules.prompt_text`.

Also verify that an admin save/publish path cannot produce a confusing prompt for these rules:

- if `validationgenai_rulesets` still exists during this interim period, newly compiled rows may still be created
- those rows should no longer be logically broken because the normalized rule prompt itself now contains the needed cap/category/top-up text

## Interim Publish And Seed Artifact Cleanup

After the normalized prompts are self-contained:

- publish fresh compiled rows from the normalized prompts while `claims.validationgenai_rulesets` is still the runtime source
- verify the latest compiled rows no longer depend on invisible cap/category/top-up/formula text
- do not remove `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql` from the rebuild flow if Plan 0 is run by itself, because current runtime still needs compiled ruleset rows until Plan 1 is complete

During Plan 1, after runtime no longer queries `claims.validationgenai_rulesets`:

- remove `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql` from the rebuild flow, or reduce/rename/split it so it no longer appears to be a source of business rule prompt content
- update `claims_ai_service_ddl/README_REBUILD_ORDER.txt` so rebuild does not rely on compiled prompt seed data
- keep this local-only until the larger runtime removal plan has been implemented and manually tested
