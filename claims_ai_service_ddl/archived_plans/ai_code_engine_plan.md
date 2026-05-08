# AI Code Engine Plan

Purpose: plan the deterministic validation engine that complements GenAI evidence extraction.

Status: parked after design review. V1 will use GenAI-only rulechecks; the code engine remains a future option, not part of the v1 runtime path.

Implementation started:

- `app/services/claims/invoice_version_rulechecks/apply_code_rulechecks.rb`
- `Claims::RunGenaiJob` does not call the code rulecheck service for v1.
- Read endpoints now expose `code_rulechecks` beside GenAI `rulechecks`.
- AI invoice viewers now merge/display code and GenAI rulechecks with a source-engine badge.
- `claims.invoice_version_rulechecks` DDL now includes optional metadata columns: `rule_key`, `source_requirement_id`, `verification_status`, `preferred_evaluator`, and `evidence_source`.
- Local Postgres has been altered with those additive columns for testing.

## Why This Exists

This document is retained because a future deterministic code engine may still make sense for:

- date math
- DB fact comparisons
- first-class field presence

For v1, do not run code-based rulechecks. GenAI handles the rulecheck suite using the OCR/DI JSON and database facts passed into the context window.

Important v1 boundary:

- Do not implement code-based rulechecks in Ruby for the first contractor-facing version.
- Do not add a second mini-call just to summarize codecheck results.
- Keep the service/harness only as future scaffolding unless we deliberately revive it.

The existing schema already supports this:

- `claims.invoice_version_located_fields.source_engine = 'code'`
- `claims.invoice_version_located_fields.source_engine = 'genai'`
- `claims.invoice_version_rulechecks.source_engine = 'code'`
- `claims.invoice_version_rulechecks.source_engine = 'genai'`

## Target Pipeline

1. Upload PDF.
2. OCR runs and fills `claims.invoice_versions` first-class DI fields.
3. Code fact builder snapshots DB/regex facts into `claims.invoice_version_located_fields` as `source_engine = 'code'`.
4. GenAI locates fuzzy/domain evidence, writes `source_engine = 'genai'` located fields, and emits rulechecks.
5. UI displays GenAI located fields/rulechecks.
6. Future: if codechecks return, UI can merge and display both engines clearly because the schema already supports `source_engine`.

## Candidate Service Shape

Suggested Ruby service:

```text
app/services/claims/invoice_version_rulechecks/apply_code_rulechecks.rb
```

Possible call signature:

```ruby
Claims::InvoiceVersionRulechecks::ApplyCodeRulechecks.call(
  invoice_version_id: iv.id,
  ruleset_id: ruleset.id
)
```

Responsibilities:

- Load invoice version and invoice/session/contractor facts.
- Load code located fields.
- Load DB facts such as eligibility code, participant, contractor, submitted date, upgrade type.
- Evaluate deterministic rule functions.
- Replace existing `source_engine = 'code'` rulechecks for that invoice version.
- Return a count and any warnings/errors.

## Candidate Rule Function Contract

Each deterministic rule should return a normalized row:

```ruby
{
  rule_number: 1001,
  rule_key: "submission_within_six_months",
  rule_name: "Submission within six months",
  rule_pass_flag: true, # false or nil allowed
  confidence: 100,
  expected_text: "submitted_at <= invoice_date + 6 months",
  observed_text: "submitted_at=2026-05-04, invoice_date=2026-04-20",
  calculation: "2026-04-20 + 6 months = 2026-10-20; 2026-05-04 <= 2026-10-20",
  evidence_text: "invoice_versions.di_ocr_invoice_date + session/invoice submitted date",
  evidence_hint: nil,
  reason_and_likely_causes: nil,
  notes: "source_requirement_id=ESP-2026-COM-017"
}
```

Current table does not have `rule_key`; v1 can encode it in `rule_name` or `notes`, but DDL should eventually add it.

## Numbering Scheme

Use distinct number ranges so code and GenAI do not collide:

- `1000-1999`: common deterministic rules.
- `2000-2999`: Windows and doors deterministic rules.
- `3000-3999`: insulation deterministic rules.
- `4000-4999`: heat pump deterministic rules.
- `5000-5999`: heat pump water heater deterministic rules.
- `6000-6999`: electrical service upgrade deterministic rules.
- `7000-7999`: health and safety deterministic rules.
- `8000-8999`: ventilation deterministic rules.

GenAI rule numbers can remain lower/user-facing if needed, but long-term `rule_key` is safer than numeric meaning.

## Dormant Candidate Code Rules

If revived later, likely safe early code rules:

- `1001 source_vintage_applies`
- `1002 first_class_invoice_fields_present`
- `1003 submission_within_six_months`
- `1004 eligibility_code_valid_for_invoice_date`

Not suitable for near-term Ruby enforcement:

- `rebate_line_evidence_present`: GenAI/manual-review for now.
- `rebate_not_over_invoice_total`: defer until canonical rebate amount and invoice line model exists.
- `rebate_itemized_and_deducted_math`: defer until canonical line-item/claim model exists.
- `wd_u_factor_threshold`: GenAI/manual-review for now because U-factor can appear in many product/certification formats.
- `wd_no_skylights`: GenAI/manual-review for now.
- `wd_income_level_eligible`: DB/code fact can be exposed, but rule enforcement is deferred.
- `wd_rebate_percentage_cap`, `wd_per_unit_cap`, `wd_per_home_cap`: defer until rebate math model exists.

GenAI should locate inputs:

- U-factor values.
- unit/rough-opening counts.
- rebate line amount.
- window/door line amounts.
- customer deposit and amount due after rebate when visible.
- skylight language.
- certification identifiers.

If revived later, code could evaluate:

- submission date
- eligibility date
- first-class invoice field presence
- source-requirement vintage applicability
- eligibility-code-derived validity window

## Missing Evidence Behavior

If inputs are missing:

- `rule_pass_flag = nil`
- `confidence = 0` or lower confidence
- `observed_text` explains missing input
- `reason_and_likely_causes` says what evidence is needed

Do not convert missing evidence into failure unless the business rule is truly "required field must be present before submit."

## UI Implication

Rule display should show:

- status: pass/fail/unknown/not applicable
- evaluator: code/GenAI/DB/external/manual
- evidence source
- calculation when deterministic
- friendly contractor action if fixable

## Test Harness Implication

Code-engine tests should be fast and deterministic:

- no GenAI call
- no network
- fixture invoice versions and located fields
- assert exact rulecheck output

Recommended first fixtures:

- good Windows and doors invoice
- missing invoice date
- invoice submitted after six months
- eligibility approval/expiry missing
- eligibility code expired before invoice date
