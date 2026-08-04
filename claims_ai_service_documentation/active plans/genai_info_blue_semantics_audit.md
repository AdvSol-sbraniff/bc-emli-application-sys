# GenAI `info` / Blue Result Semantics Audit

Date: 2026-08-04

## Scope

Audited enabled GenAI rule prompts from the local database, which should reflect `claims_ai_service_ddl/3_insert_genai_normalized.sql`.

Only five enabled GenAI rule prompts explicitly instruct the model to return `rule_result="info"`:

- `contractor_identity_matches_record`
- `esu_contractor_utility_billed_work_on_one_invoice`
- `homeowner_identity_matches_eligibility_record`
- `overall_invoice_arithmetic_consistent`
- `rebate_line_evidence_present`

All other enabled GenAI rule prompts do not explicitly define an `info` path. If they return `info`, that is likely model drift or caused by higher-level schema freedom rather than rule-specific prompt text.

## Recommended Meaning Of `info`

`info` should mean:

- The policy-backed requirement is satisfied or no correction is requested.
- There is a useful caveat, oddity, or non-blocking context that makes the result not a plain green `pass`.
- Admin does not need to verify the item before moving forward unless they independently choose to.
- Contractor does not need to upload a correction.

`info` should not mean:

- A clean pass with a nice detail to mention.
- A hidden warning.
- Missing evidence for a requirement that the rule is supposed to confirm.
- A not-applicable rule firing merely because it was mapped broadly.
- The LLM explaining its reasoning when the conclusion is simply green.

Practical shorthand:

- `pass`: requirement satisfied; nothing noteworthy.
- `info`: requirement effectively satisfied, but there is a harmless caveat/context note.
- `warn`: not enough confidence to confirm the requirement, or admin should verify before relying on it.
- `fail`: visible evidence contradicts the requirement or required evidence is clearly absent.

## Problematic Or Probably Problematic GenAI Blue Paths

### `overall_invoice_arithmetic_consistent`

Current `info` behavior:

> Set rule_result="info" when the invoice reconciles, but the model is worth explaining to admins, such as a payment-history/customer-deposit/program-receivable structure.

Assessment:

This is mostly old-style `info`: "it passed, but here is useful explanation." On the current demo invoice it produced blue even though the arithmetic reconciled exactly:

`18,375.00 - 5,300.00 - 0.00 = 13,075.00`

That should be `pass`, not `info`.

Recommended change:

Remove or sharply narrow the `info` path.

Suggested semantics:

- `pass` when the invoice reconciles under an accepted model, including split rebates, deposits, payments, or customer-balance models, as long as the model is clear.
- `info` only if there is a harmless but unusual structure that is not ambiguous and could affect display/explanation, such as both a customer-balance model and a separate program-receivable model shown clearly.
- `warn` when the model is ambiguous or values cannot be confidently reconciled.

Likely prompt direction:

Do not return `info` merely because the arithmetic model is worth explaining. If the math is clear and reconciles, return `pass` and include the explanation in calculation.

### `rebate_line_evidence_present`

Current `info` behavior:

> Set rule_result="info" when multiple upgrade-specific CleanBC / Better Homes / ESP rebate amounts are clearly labelled, summable, and useful to call out as context.

Assessment:

This is old-style `info`. A split rebate presentation is not a caveat if the amounts are clear and summable. On the current demo invoice, the rule returned blue even though the invoice had:

- `CleanBC heat pump rebate credit - Income Level 1 -$5,000.00`
- `CleanBC ventilation rebate credit - Income Level 1, bathroom fan maximum -$300.00`
- `Total CleanBC rebate credits -$5,300.00`

That is a strong `pass`.

Recommended change:

Delete the `info` path or make it extremely narrow.

Suggested semantics:

- `pass` when one overall rebate line is clear, or multiple upgrade-specific rebate lines are clearly labelled and summable.
- `warn` when label, amount, or allocation is unclear.
- `fail` when no program rebate evidence is visible or visible text contradicts the rebate.

Likely prompt direction:

Do not return `info` merely because rebates are split by upgrade type. A clear split presentation is a pass.

### `esu_contractor_utility_billed_work_on_one_invoice`

Current `info` behavior:

> Set rule_result="info" when utility involvement is visible but the supplied evidence does not show who was billed by the utility, and there is no contradiction of contractor/electrician management.

Assessment:

This one is probably problematic because it overlaps with the current `warn` language:

> Set rule_result="warn" when contractor/electrician utility-management evidence is missing or ambiguous; when BC Hydro/FortisBC utility involvement is visible but billing path is unclear...

The same condition, "billing path unclear," is partly `info` and partly `warn`. That will produce inconsistent blues/yellows.

Policy/common-sense read:

If contractor/electrician management of the utility line upgrade is clear, and nothing indicates the contractor was billed by the utility, lack of bill-recipient detail may be harmless. But if the rule is specifically checking the "one invoice if contractor billed" clause, unknown billing path can be real ambiguity.

Recommended change:

Split the condition more cleanly:

- `pass` when contractor/electrician utility-management is clear and either the participant appears utility-billed, or billing recipient is not material because no contractor-billed utility charge is visible.
- `info` only when utility involvement and contractor/electrician management are clear, no contradiction exists, but the bill-recipient detail is not visible. This is a caveat, not a correction.
- `warn` when utility-management evidence itself is incomplete, or contractor-billed utility work may be present but the one-invoice relationship cannot be confirmed.
- `fail` when the evidence clearly contradicts contractor/electrician management or clearly shows contractor-billed utility work split across invoices.

Likely prompt direction:

Keep `info`, but remove the contradiction with `warn`. Do not let "billing path unclear" by itself decide both statuses.

## Probably Acceptable GenAI Blue Paths

### `contractor_identity_matches_record`

Current `info` behavior:

> Set rule_result="info" when the contractor appears to match but there is a harmless variation worth explaining, such as abbreviated legal suffix, DBA wording, missing unit number, or invoice address omitted while the name clearly matches.

Assessment:

This is a reasonable use of `info`.

Why:

The requirement is effectively satisfied, but identity matching can have harmless naming/address variations that are worth surfacing without implying a correction is needed.

Potential tweak:

Add a guard that `info` should not be used for ordinary exact matches. Exact matches should be `pass`.

### `homeowner_identity_matches_eligibility_record`

Current `info` behavior:

> Set rule_result="info" when the name likely matches but the invoice uses a harmless alternate format worth surfacing, such as first initial plus last name, spouse/household wording, or a minor OCR typo.

Assessment:

This is a reasonable use of `info`.

Why:

The rule is satisfied enough to avoid warning, but a harmless alternate name format is useful context for admins.

Potential tweak:

Add a guard that `info` should not be used for ordinary exact matches. Exact matches should be `pass`.

## Cross-Cutting Recommendation

Add a shared result rubric to the GenAI rule compiler prompt so every GenAI call receives the same status semantics:

```text
Use rule_result="pass" when the requirement is satisfied and no correction or meaningful caveat is needed.
Use rule_result="info" only when the requirement is satisfied or no correction is requested, but there is harmless context worth preserving. Do not use info for a clean pass.
Use rule_result="warn" when evidence is missing, ambiguous, incomplete, low-confidence, or requires admin verification before the requirement can be relied on.
Use rule_result="fail" when visible evidence clearly contradicts the requirement or required evidence is clearly absent.
```

Then update the three problematic prompts above. This should reduce unnecessary blue results while preserving useful "not quite green but not yellow" cases.

## Current Invoice Confirmation

Latest local invoice version at audit time:

`730d8a24-960c-48f7-8de5-bccda113dd10`

Blue/info rows on that invoice:

- `hp_ahri_product_validation`: code rule; acceptable info after the recent change.
- `overall_invoice_arithmetic_consistent`: GenAI; likely should be pass.
- `rebate_line_evidence_present`: GenAI; likely should be pass.
- `vent_herv_nrcan_product_validation`: code rule; not part of this GenAI seed audit, but likely a separate not-applicable/noise cleanup.
