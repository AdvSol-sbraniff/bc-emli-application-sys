# AI Rules Analysis Gate 0 Findings

Purpose: concise findings from the first source-analysis pass against Better Homes BC Energy Savings Program requirements.

Status: working findings, not final program policy.

Source:

- Better Homes BC, `Energy Savings Program requirements`
- URL: https://betterhomesbc.ca/learn-about-programs/energy-savings-program/energy-savings-program-requirements/
- Source vintage: invoices dated on or after April 1, 2026

## Executive Finding

The proposed AI invoice architecture is viable if it is positioned as **AI-assisted pre-review**.

It is not viable as "AI determines full eligibility from the invoice PDF."

The public requirements require a mixed evidence model:

- invoice PDF evidence
- supporting documents/photos
- participant eligibility/database facts
- contractor registration/domain approval
- prior rebate history
- external product/certification lists
- admin/program judgment

## Main Architecture Adjustment

The system should be a hybrid validator:

- OCR/Document Intelligence extracts first-class invoice fields.
- GenAI locates fuzzy text and domain evidence.
- Deterministic code evaluates math, date, threshold, cap, and DB-comparison rules.
- DB queries supply program facts.
- External lookup validates product/certification/list membership.
- Admin/manual review remains explicit for judgment-heavy rules.

This matches the schema Stephen already designed:

- `claims.invoice_version_located_fields.source_engine` supports `code` and `genai`.
- `claims.invoice_version_rulechecks.source_engine` supports `code` and `genai`.

## V1 Scope Recommendation

Keep v1 to **Windows and doors only**.

Reasons:

- Windows and doors has a relatively compact domain rule set.
- It has several invoice-visible fields that GenAI can locate well: window/door lines, U-factor, certification references, skylight language, rebate lines, unit counts.
- Deterministic code can handle the hard math: U-factor threshold, rebate percentage, per-unit cap, per-home cap, six-month deadline.
- Supporting docs still matter, especially manufacturer label photos, but this is manageable as `unknown` / admin-review in v1.

Do not enable heat pumps in v1 unless business forces it.

Reasons:

- The public heat pump requirements split into many subtypes.
- Subtypes depend on prior heating fuel, system removal/retention, heat load calculations, AHRI/product-list data, capacity, head count, region, and special top-ups.
- This is too rich for the current one-broad-variant model without a careful subtype strategy.

## Common Rules Should Be Centralized

Common rules appear across most upgrade types:

- invoice date/source vintage
- six-month submission deadline
- eligibility code validity
- contractor registration/domain approval
- invoice rebate itemization/deduction
- rebate does not exceed cost
- duplicate rebate checks
- warranty/financing/program-stacking exclusions

These should not be manually duplicated into seven independent prompt blobs.

Recommended direction:

- Maintain common rules centrally.
- Maintain upgrade-specific rules separately.
- Publish/compose a versioned snapshot for each active upgrade-type ruleset.
- Store the exact used ruleset/version on invoice versions for historical explainability.

## Code Engine Candidates

These should be deterministic code checks, not GenAI checks:

- invoice date is on/after source effective date
- submitted date <= invoice date + six months
- eligibility approval/expiry date comparisons
- U-factor <= 1.22
- rebate percentage by income level
- per-unit cap
- per-home cap
- amount due / total / rebate arithmetic
- threshold/cap comparisons
- normalized contractor/customer/address comparisons after evidence is extracted

GenAI can locate the input evidence. Code should do the math.

## GenAI Candidates

These are reasonable GenAI jobs:

- locating skylight language
- locating U-factor and certification references
- distinguishing rough openings versus panes when invoice wording is messy
- locating brand/model/NRCan/CPD/NFRC/CSA/Intertek/Keystone references
- classifying line items as windows/doors/labour/rebate/deposit/tax
- locating installation/removal/supporting-doc language
- producing contractor/admin-friendly explanation text

## DB / External / Manual Candidates

These are not safe invoice-only checks:

- income level eligibility
- eligibility code record validity
- contractor is registered/approved for the upgrade type
- City of Vancouver property exclusion
- prior rebate history
- quote pre-approval
- product list / qualified model list validation
- manufacturer label photo count
- AHJ/bylaw compliance
- warranty/financing/program-stacking exclusions

They can be shown as `unknown`, `requires admin review`, or later checked by DB/external integrations.

## Multi-Upgrade Invoice Finding

If business requires one uploaded commercial invoice to contain multiple upgrade types, the current "invoice owns one upgrade type" model is only a v1 simplification.

Future recommended model:

- `claims.invoices`: uploaded invoice document.
- `claims.invoice_upgrade_claims`: one child claim per upgrade type found/claimed on that invoice.
- OCR once per invoice PDF.
- Classification/segmentation pass identifies upgrade-type evidence regions.
- One validation run per child claim / upgrade type.

Do not build this into v1 unless business explicitly requires it before first release.

## V1 Gate Decision

Proceed with planning for Windows and doors v1 only if:

- The UI says AI is assisting pre-review, not approving eligibility.
- The ruleset supports `unknown` and source/evaluator traceability.
- Supporting documents can be uploaded and shown, even if not fully machine-classified in v1.
- Code-engine checks are planned for dates/math/caps.
- Common rules are not copied manually into every domain prompt.

Pause if:

- Business expects full auto-eligibility.
- Business requires multi-upgrade invoices in v1.
- Business expects heat pump support immediately.
- The team cannot access the DB facts needed for common eligibility checks.

## Next Recommended Work

1. Convert current `esp_default_v1` into an explicit `esp_windows_doors_2026_04_v1`.
2. Split Windows and doors into:
   - GenAI located-field instructions.
   - GenAI fuzzy interpretation checks.
   - Code-engine rule definitions.
   - DB/external/manual placeholders.
3. Design the code-engine rulecheck service before redesigning the contractor portal.
4. Update admin ruleset editor plan to distinguish common rules, upgrade-specific rules, and deterministic code rules.
5. Build local fixture tests for at least:
   - good Windows and doors invoice
   - missing U-factor
   - skylight present
   - rebate not itemized/deducted
   - rebate cap exceeded
   - invoice date outside six months
