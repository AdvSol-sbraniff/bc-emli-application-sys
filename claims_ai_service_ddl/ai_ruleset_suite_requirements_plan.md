# AI Ruleset Suite Requirements Plan

Purpose: plan for turning the Better Homes BC Energy Savings Program requirements into a suite of AI rulesets by upgrade type.

Relationship to redesign:

- This work is Gate 0.
- Complete the website rules analysis before redesigning contractor/admin AI screens or changing workflow code.
- See `ai_rules_analysis_prerequisite_plan.md` for the standalone execution plan.

Source reviewed:

- Better Homes BC, `Energy Savings Program requirements`
- URL: https://betterhomesbc.ca/learn-about-programs/energy-savings-program/energy-savings-program-requirements/
- Page effective date: invoices dated on or after April 1, 2026
- Reviewed by Codex: May 2026

This is a planning/research artifact, not a final interpretation of program policy.

Important source anchors from the page:

- The requirements apply to invoices dated on or after April 1, 2026.
- The page explicitly points older installs to past requirements, so ruleset versions should be tied to program effective dates.
- The page has general eligibility requirements plus upgrade-specific sections.
- Invoice/supporting-document rules repeat across domains: the invoice must show the itemized CleanBC rebate, deduct the rebate from the participant total owed, and calculate the rebate according to income level / eligibility code / requirements.
- The deadline rule repeats across domains: rebate application and supporting documentation must be submitted by the Registered Contractor within six months of invoice date.
- The public page also links to sample invoice PDFs, product lists, contractor terms, participant terms, installation guides, and other external materials that are not all present in an uploaded invoice.

Key design conclusion:

- The public requirements are not a single "invoice validation" problem.
- They are a mixed evidence problem.
- The AI ruleset can pre-review the invoice and supporting documents, but the system still needs DB facts and human/admin judgment for full program eligibility.
- V1 direction update: use GenAI-only rulechecks for the first contractor-facing implementation. The prompt may use supplied DB facts and OCR evidence, but the runtime should not create code-based rulechecks in v1.

## Main Concern

The current AI approach is basically sound for an AI-assisted pre-review:

- Use OCR/Document Intelligence for first-class invoice fields.
- Use GenAI/rulesets for locating domain-specific evidence and doing rulechecks.
- Store located fields, rulechecks, confidence, and advice for admin/contractor review.

But the source requirements are too broad to treat the invoice PDF as the only truth.

Some requirements can be checked from the invoice.
Some require database facts.
Some require supporting documents.
Some require human/program judgment.
Some require external lists or pre-approval history.

Therefore, each ruleset must distinguish:

- `pass`: evidence supports the rule.
- `fail`: evidence contradicts the rule.
- `unknown`: required evidence is missing or ambiguous.
- Rules use boolean pass/fail only. If a rule is not supported by visible evidence, store `rule_pass_flag=false` and explain why.

The system should avoid pretending that all requirements can be proven from one invoice.

Recommended language for screens and reports:

- Use `Could not verify from the invoice` for missing external evidence.
- Use `Potential issue` when the invoice conflicts with a rule but the admin may need to confirm context.
- Use `Requires admin review` when the requirement depends on DB facts, prior approval, product-list lookup, photos, or professional judgment.
- Do not use `AI approved`, `AI eligible`, or similar wording.

## Source Requirement Themes

General eligibility themes found on the source page:

- Income level eligibility and income documentation.
- Eligible home type and ineligible home types.
- Utility account eligibility.
- Primary heating system eligibility.
- BC Assessment value thresholds.
- Pre-registration and eligibility code timing.
- Registered Contractor requirement.
- One rebate per upgrade type / no duplicate rebate rules.
- Rebate cannot exceed invoice/paid cost.
- Warranty-covered costs are not eligible.
- Financing/leasing must result in full ownership.
- No stacking with certain other programs.
- Utility accounts must be in resident/homeowner name.
- Landlord consent for renters.

These are mostly not invoice-only rules.

They should be represented as common rules with evidence sources such as:

- ESP database facts.
- Eligibility code records.
- Contractor records.
- Participant/application records.
- Prior rebate/payment history.
- Supporting documents.
- Admin review.

## Upgrade Types In Our App

Current upload variants in the app:

- Heat pump (space heating)
- Heat pump water heater (including combined)
- Insulation
- Windows and doors
- Ventilation
- Electrical service upgrade
- Health and safety remediation

The source page is more granular than this, especially for heat pumps.

The ruleset suite needs a two-level model:

- App-level upgrade type: one of the 7 variants.
- Detected subcategory: more granular category inside the ruleset.

Examples:

- Heat pump (space heating)
- Air source heat pump - convert from electric
- Air source heat pump - convert from wood
- Air source heat pump - convert from fossil fuel
- Dual fuel ducted heat pump
- Air-to-water heat pump
- Combined space and water heat pump

This does not need a new DB table immediately, but rulesets should be written as if subcategory detection is part of GenAI's job inside a broader upgrade type.

## Requirement Matrix Artifact

Before writing SQL seed prompts, create a requirements matrix. This can start as markdown or CSV in this folder, then become seed data later if useful.

Suggested filename:

- `claims_ai_service_ddl/ai_ruleset_requirements_matrix.md`

Suggested columns:

- `source_requirement_id`: stable local ID, such as `ESP-2026-WD-001`.
- `source_url`: public source URL.
- `source_effective_date`: `2026-04-01`.
- `source_section`: source heading, such as `Windows and doors`.
- `app_upgrade_type`: one of the seven app variants.
- `detected_subtype`: optional subtype, especially for heat pumps.
- `requirement_summary`: short paraphrase, not a long quote.
- `evidence_source`: `invoice_pdf`, `supporting_document`, `database`, `external_list`, `admin_review`.
- `automatable_level`: `invoice_only`, `invoice_plus_db`, `support_doc_required`, `external_validation_required`, `manual_review`.
- `v1_rule_action`: `enforce`, `warn`, `show_unknown`, `manual_only`, `out_of_scope`.
- `output_rule_key`: stable key for GenAI output.
- `notes`: implementation or policy caveats.

Example rows:

| source_requirement_id | source_section           | app_upgrade_type          | requirement_summary                                                   | evidence_source            | automatable_level                    | v1_rule_action                                       |
| --------------------- | ------------------------ | ------------------------- | --------------------------------------------------------------------- | -------------------------- | ------------------------------------ | ---------------------------------------------------- |
| ESP-2026-COM-001      | General/deadlines        | All                       | Submit within six months of invoice date                              | invoice_pdf + database     | invoice_plus_db                      | enforce if submitted date exists                     |
| ESP-2026-COM-002      | Supporting documentation | All                       | Invoice shows itemized CleanBC rebate and deducts it from amount owed | invoice_pdf                | invoice_only                         | enforce                                              |
| ESP-2026-WD-001       | Windows and doors        | Windows and doors         | U-factor is 1.22 W/m2-K or less                                       | invoice_pdf/supporting_doc | invoice_only or support_doc_required | enforce if visible, otherwise unknown                |
| ESP-2026-WD-002       | Windows and doors        | Windows and doors         | Manufacturer label photo for each installed window/door               | supporting_document        | support_doc_required                 | show_unknown in v1 unless supplements are classified |
| ESP-2026-HP-001       | Heat pump space heating  | Heat pump (space heating) | Equipment appears on qualified product list                           | external_list              | external_validation_required         | manual_only until product-list lookup exists         |

## Ruleset Suite Shape

Create a suite, not one giant forever prompt.

Recommended ruleset families:

- `esp_common_invoice_2026_04_v1`
- Shared invoice/contractor/eligibility/deadline/rebate-deduction checks.
- Maintained centrally.
- Composed with each upgrade-specific ruleset at GenAI run time or when publishing a ruleset version.

- `esp_windows_doors_v1`
- Windows and doors rules.

- `esp_insulation_v1`
- Insulation rules.

- `esp_heat_pump_space_heating_v1`
- Space-heating heat pump rules with subtype detection.

- `esp_heat_pump_water_heater_v1`
- Heat pump water heater and combined water/space-water logic as appropriate.

- `esp_electrical_service_upgrade_v1`
- Electrical service upgrade rules.

- `esp_health_safety_v1`
- Health and safety remediation rules.

- `esp_ventilation_v1`
- Ventilation rules.

Preferred production shortnames should include the source effective date:

- `esp_windows_doors_2026_04_v1`
- `esp_insulation_2026_04_v1`
- `esp_heat_pump_space_heating_2026_04_v1`
- `esp_heat_pump_water_heater_2026_04_v1`
- `esp_electrical_service_upgrade_2026_04_v1`
- `esp_health_safety_2026_04_v1`
- `esp_ventilation_2026_04_v1`

Rationale:

- Program rules change over time.
- Invoice eligibility depends on invoice/install dates.
- A future invoice dated before April 1, 2026 may need an older ruleset.
- The ruleset name should make the source vintage obvious to admins and developers.

Expected rule count:

- Most upgrade types will likely have a modest number of domain-specific rule groups.
- A rough expectation of about 4 upgrade-specific rule groups per upgrade type is plausible.
- However, those groups may expand into multiple concrete checks once evidence sources, rebate math, product-list checks, photos, and subtypes are separated.
- Common cross-upgrade rules will probably be the larger shared block.

Design implication:

- Do not force admins to edit common rules seven times.
- The ruleset editor should eventually expose separate edit areas:
- Common/cross-upgrade rules.
- Upgrade-specific rules.
- Output schema / shared instructions.
- Domain-specific located fields.

Implementation options:

- V1 simplest: keep one final prompt per upgrade type, but generate/copy it from a central common block plus a domain block.
- Better v1.5: add DB structure for reusable ruleset fragments and compose the final prompt at runtime.
- Avoid permanent manual duplication because common policy changes would become error-prone.

Do not build all at once.

Build order:

1. Common requirements extraction and rule taxonomy.
2. Windows and doors, because that is v1 contractor UI scope.
3. Ruleset test harness.
4. Remaining upgrade types one at a time.

## Common Versus Upgrade-Specific Rules

The current local `esp_default_v1` ruleset is a prototype where common and Windows/doors rules are mixed together as numbered prose.

Current mixed examples:

- Common/cross-upgrade:
- Vendor on invoice matches registered contractor.
- Customer on invoice matches program/customer record.
- Submission is within six months of invoice date.
- Eligibility code is valid for the invoice/upgrade date.
- Description is sufficiently detailed.
- Invoice/rebate math does not exceed allowed costs.

- Windows and doors specific:
- Metric U-factor threshold.
- Window/door per-unit cap.
- Per-home cap.
- Rough opening / unit logic.
- NRCan/CPD/brand/model/label evidence.

Target architecture:

- Common rules are maintained once.
- Upgrade-specific rules are maintained once per upgrade type.
- The final GenAI prompt is composed from:
- Shared output schema and execution instructions.
- Common rules.
- Selected upgrade-type rules.
- Runtime context from OCR/database/session/invoice.

This keeps the admin ruleset editor understandable:

- Admins should see and edit common rules in one central place.
- Admins should see and edit Windows/doors rules only on the Windows/doors ruleset.
- The UI should warn that changing common rules affects every upgrade type that references that common block.

Open design choice for later implementation:

- Physical composition model: separate DB rows/tables for fragments.
- Materialized model: compose and save a full prompt snapshot whenever an upgrade ruleset is published.

Recommended direction:

- Use fragments for editing.
- Store the composed final prompt/ruleset ID on `invoice_versions` for historical explainability.
- This gives admins central editing without losing auditability.

## Multi-Upgrade Single Invoice Scenario

Possible future requirement: one uploaded invoice PDF may contain more than one upgrade type.

Examples:

- One contractor invoice includes windows/doors plus insulation.
- One invoice includes a heat pump plus electrical service upgrade.
- One invoice includes a heat pump plus ventilation.

This is a serious architecture change.

Do not model this as just one `claims.invoices.upgrade_type_id` forever if the business confirms this requirement.

Recommended future model:

- `claims.invoices` remains the uploaded commercial invoice/document.
- Add child claim rows, such as `claims.invoice_upgrade_claims`.
- Each child claim has one upgrade type, one status/review outcome, one ruleset result set, and one rebate decision.
- Common invoice OCR runs once per invoice PDF.
- Domain rule review runs once per detected/claimed upgrade type.

Why child claim rows matter:

- One invoice can have one invoice number/date/vendor/customer total.
- But each upgrade type may have different eligibility rules, supporting documents, caps, rebate math, admin outcomes, and revision requests.
- One claim might be approved while another is ineligible or needs revision.

GenAI execution options:

- OCR once for the whole PDF.
- Classification/segmentation pass identifies candidate upgrade types and relevant line/evidence regions.
- Then run each upgrade-type ruleset against the same OCR payload plus the segmented evidence.

Preferred future execution:

- Use a small classification/segmentation step first.
- Then run one GenAI validation call per detected upgrade type.
- Reuse the same OCR result; do not OCR multiple times.

Why not one giant LLM call:

- A single mega-prompt can work for demos, but it is more likely to mix rules, miss edge cases, and become hard to test.
- Separate domain calls produce cleaner rulecheck outputs and easier regression tests.
- Cost is higher, but only for the GenAI step; OCR remains shared.

V1 decision:

- Do not support multi-upgrade single invoices in the contractor flow unless business explicitly requires it immediately.
- Keep the v1 UI honest: "one invoice upload is reviewed for Windows and doors only."
- Keep the data model/design notes future-ready so the future child-claim model is not a shock.

## Common Rule Categories

Common rules likely needed for every invoice ruleset:

- Invoice has required first-class fields: invoice number, date, vendor name/address, customer name/address, subtotal, tax, total, amount due.
- Invoice date exists and supports deadline calculation.
- Submission is within six months of invoice date.
- Eligibility code exists in system and was valid at the time of upgrade/invoice.
- Contractor on invoice matches registered contractor in ESP database.
- Customer/homeowner on invoice matches participant/application record.
- Address on invoice matches participant/application/property address.
- Invoice shows itemized CleanBC rebate.
- Invoice deducts CleanBC rebate from total owed.
- Rebate amount does not exceed invoice/paid upgrade cost.
- Warranty-covered costs are not being claimed, if visible.
- Upgrade appears to be supplied/installed by an approved registered contractor.

Some of these are invoice-evidence rules.
Some are DB-comparison rules.
Some are likely `unknown` unless supporting documents are present.

## Windows And Doors Rule Sketch

Source themes:

- Income level 1 or 2 only.
- Quote pre-approval required before installation.
- Replaces existing windows/doors in building envelope between unheated and heated space.
- Skylights are not eligible.
- Product must be listed/certified by one of the accepted certification bodies.
- Count rebates by rough openings, not individual panes.
- Installed by registered Windows and doors contractor.
- Maximum rebate: 95% or 60% of eligible cost depending on income level, up to maximum per home and per window/door.
- Homes in City of Vancouver are not eligible for windows/doors rebates.
- Supporting docs include invoice and manufacturer label photo for each installed window/door.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate window/door line items.
- Locate U-factor or similar efficiency information if present.
- Locate number/count of windows/doors or rough openings if present.
- Locate rebate line and deduction.
- Locate invoice date/vendor/customer/totals.
- Detect if invoice mentions skylights.
- Detect manufacturer/certification references if present.

Non-invoice checks:

- Income level.
- Quote pre-approval.
- City of Vancouver property exclusion.
- Registered contractor approval for domain.
- Manufacturer label photos.
- Prior rebate history / duplicate claim.

## Insulation Rule Sketch

Source themes:

- Income level 1 or 2 only.
- New insulation type and eligible location.
- Installed between conditioned and unconditioned space.
- Increased R-value.
- Rebate based on R-value added and square feet, with location-specific rates and caps.
- Existing health/safety issues must be resolved before installation.
- Contractor-installed only.
- Supporting docs include before/after photos and possibly floor plan drawing.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate insulation location.
- Locate insulation type.
- Locate R-value/new R-value.
- Locate area/square footage.
- Locate rebate calculation/deduction.

Non-invoice/supporting-doc checks:

- Before/after photos.
- Floor plan drawing if requested.
- Health/safety issues resolved.
- Approved insulation contractor.
- Income level.

## Heat Pump Space Heating Rule Sketch

The website has multiple subcategories under heat pump space heating.

Subcategories to detect:

- Convert from electric.
- Convert from wood/solid fuel.
- Convert from fossil fuel.
- Dual fuel ducted heat pump.
- Air-to-water heat pump.
- Combined space and water heat pump.

Common themes:

- Primary heating system/fuel matters.
- Equipment must be sized and serve appropriate living area.
- AHRI reference often required.
- Product must be on applicable qualified product list.
- Existing heat pump replacement/addition often not eligible.
- Fossil fuel/wood removal or retention requirements depend on subtype.
- Installation must follow applicable guides/bylaws.
- Heat load calculation may be required.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate equipment make/model.
- Locate AHRI reference.
- Locate heat pump type/head count/ducted vs ductless.
- Locate BTU/capacity, SEER/HSPF/SEER2/HSPF2 if present.
- Locate fuel conversion language/removal line items if present.
- Locate rebate line/deduction.

Non-invoice/supporting-doc/external checks:

- Qualified product list validation.
- Heat load calculation document.
- Prior heating fuel from application/database.
- Fossil fuel/wood removal proof.
- Non-Integrated Area pre-approval.
- AHJ/bylaw compliance.

## Heat Pump Water Heater Rule Sketch

Source themes:

- Existing water heater replaced must be primary water heater.
- Eligible systems are Tier 2 or higher on qualified product list.
- Fossil fuel water heating removal/decommissioning if applicable.
- Existing heat pump water heater additions/replacements not eligible.
- Emergency replacement eligible.
- Installed by approved heat pump contractor.
- Supporting docs include invoice and proof of gas water heater removal if applicable.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate heat pump water heater line item.
- Locate make/model.
- Locate conversion/fuel references.
- Locate rebate line/deduction.

Non-invoice/external checks:

- Qualified product list.
- Existing primary water heater status.
- Removal/decommission proof.
- Approved contractor.

## Electrical Service Upgrade Rule Sketch

Source themes:

- Only homes converting from fossil fuel primary space and/or water heating to heat pump are eligible.
- Utility must upgrade service/new wire.
- Upgrade to 100, 200, or 400 amp service.
- Must be installed within six months of heat pump installation.
- Eligible expenses include utility connection fees, panel/sub-panel, service mast, conduit, meter base, weather head, labour.
- Panel-only upgrades without utility service upgrade are not eligible.
- If contractor is billed by utility, all work by contractor and utility must be on one invoice.
- Installed by approved contractor/electrician.
- Supporting docs include utility bill or invoice.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate service amp level.
- Locate utility service upgrade/new wire language.
- Locate eligible expense line items.
- Detect panel-only language.
- Locate rebate line/deduction.

Non-invoice checks:

- Linked heat pump installation date/type.
- Fossil fuel conversion.
- Utility relationship.
- Contractor approval.

## Health And Safety Rule Sketch

Source themes:

- Remediation must address existing health/safety issues.
- Must enable safe installation/operation of eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
- Not paid on its own.
- Must be completed in association with eligible upgrade.
- Must be confirmed rebate-eligible before beginning.
- Contractor-installed only.
- Supporting docs include invoice and before/after photos.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate remediation type: pest, asbestos, structural, mould.
- Locate association to eligible upgrade if described.
- Locate rebate line/deduction.

Non-invoice/supporting-doc checks:

- Before/after photos.
- Pre-confirmation.
- Linked eligible upgrade.
- Contractor approval.

## Ventilation Rule Sketch

Source themes:

- Must be installed in association with eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
- Must improve air circulation.
- HRV/ERV must be ENERGY STAR and installed to guide.
- Bathroom fans must be ENERGY STAR, ducted outside, capacity at least 85 cfm / 40 L/s at 50 Pa, continuous duty, self-closing damper, sealed/insulated ducts, screened duct hoods.
- Installed by approved contractor, with HRV/ERV by licensed HVAC contractor.
- Supporting docs include invoice.
- Submission deadline is six months from invoice date.

AI invoice-only checks likely possible:

- Locate HRV/ERV or bathroom fan line items.
- Locate ENERGY STAR reference.
- Locate CFM/capacity.
- Locate ducting/outside exhaust language if present.
- Locate rebate line/deduction.

Non-invoice checks:

- Associated eligible upgrade.
- Contractor/licensed HVAC approval.
- Product list validation.

## Ruleset Output Schema Enhancements

The current output schema has:

- `overall`
- `located_fields`
- `rulechecks`

For a ruleset suite, enhance rulechecks with source traceability:

- `rule_number`
- `rule_key`
- `rule_name`
- `upgrade_type`
- `requirement_source`
- `requirement_reference`
- `evidence_source`: `invoice`, `database`, `supporting_document`, `external_list`, `admin_review`
- `automatable_level`: `invoice_only`, `database_compare`, `supporting_doc_required`, `external_validation_required`, `human_review_required`
- `rule_pass_flag`: true/false/null
- `confidence`
- `expected`
- `observed`
- `calculation`
- `evidence_text`
- Use `evidence_text` only for evidence snippets/context.
- `reason_and_likely_causes`

This will keep the AI honest about what it actually checked.

## Parked Code Engine Plan

Stephen's current v1 decision is GenAI-only rulechecks. The existing data model still anticipates a possible future code engine:

- `claims.invoice_version_located_fields.source_engine` allows `code` or `genai`.
- `claims.invoice_version_rulechecks.source_engine` allows `code` or `genai`.
- `Claims::GenaiCaseFacts::Build` already persists DB-derived located fields as `source_engine = 'code'`.

For v1, keep this as future scaffolding instead of forcing a hybrid split too early.

V1 rule routing:

- GenAI performs the visible rulechecks using the OCR/DI JSON and database facts supplied in the context window.
- Missing or ambiguous evidence should be `unknown`, not fake pass/fail.
- Human/admin review remains the true eligibility decision.

Possible future rule routing:

- GenAI should locate and interpret fuzzy invoice evidence:
- invoice line descriptions
- rebate line descriptions
- skylight/window/door language
- brand/model/certification text
- rough opening versus pane-count hints
- free-text notes and unusual contractor wording

- Code engine could eventually evaluate deterministic rules:
- invoice date plus six months
- eligibility code approval date plus six months
- numeric thresholds such as U-factor <= 1.22
- per-unit caps
- per-home caps
- rebate percentage by income level
- tax/total/amount-due arithmetic
- exact/fuzzy-string comparisons after normalization
- missing first-class OCR fields

- DB query layer should supply facts:
- contractor registration and upgrade-type approval
- participant/user record
- eligibility code/income level/approval and expiry dates
- property address and municipality
- prior rebate history
- submitted date

- External lookup layer should eventually validate:
- NRCan/CPD/product list entries
- AHRI references
- ENERGY STAR / qualified product list requirements
- certification body references

- Manual/admin review remains necessary where evidence is incomplete or policy judgment is required.

V1 pipeline:

1. OCR extracts first-class fields and raw text.
2. Code extracts obvious regex/DB facts and persists `source_engine = 'code'` located fields.
3. GenAI receives OCR/DI JSON and DB/code facts in the context window.
4. GenAI locates fuzzy/domain evidence and persists `source_engine = 'genai'` located fields.
5. GenAI emits rulechecks.
6. UI displays GenAI located fields and rulechecks.

Important current design correction:

- For v1, a ruleset can mean "the prompt package GenAI uses for fields and rulechecks."
- Do not call `ApplyCodeRulechecks` in the normal v1 invoice flow.
- Later DDL/code can formalize deterministic rule definitions if the project revives the code engine.

Practical examples:

- Good v1 use of GenAI: "Using only the supplied OCR/DI JSON and DB facts, decide whether the submission appears within six months; if a date is missing or ambiguous, return unknown."
- Good v1 use of GenAI: "Using visible invoice values only, flag whether rebate evidence appears itemized/deducted; if arithmetic is unclear, return unknown and explain what is missing."
- Good v1 use of GenAI: "Find all places where the invoice describes windows, doors, skylights, rough openings, U-factor, CPD/NRCan identifiers, brand/model, and rebate lines."

Recommended `rule_pass_flag` meaning:

- `true`: the available evidence supports the rule.
- `false`: the available evidence contradicts the rule.
- `null`: the rule cannot be verified from available evidence.

Recommended extra status field:

- Use `rule_pass_flag=true|false`; unclear/missing evidence is `false` with explanation.

Rationale:

- `rule_pass_flag = null` is technically useful, but hard for users/admins to read.
- A named status makes it easier to display rules in the UI without implying that missing evidence is the same as failure.

Recommended `located_fields` enhancement:

- Include `source_requirement_id` where a located field exists only to support a specific rule.
- Include `field_group_key` for repeated groups, such as each rough opening/window/door line.
- Include `display_label` for contractor/admin UI.

## Source Traceability Plan

Every rule should be traceable to:

- Source URL.
- Page effective date.
- Section heading.
- Requirement phrase summary.
- Ruleset version.

Do not paste large copyrighted chunks of the page into the database.

Use short summaries and links.

Practical storage options:

- Store source summary fields in the ruleset JSON prompt text for v1.
- Store richer traceability in the requirements matrix doc while rules are still evolving.
- Later, add DB columns or a companion table only if the UI needs to show source traceability directly.

Minimum v1 requirement:

- Every rule in `rulechecks[]` should have a stable `rule_key`.
- Every rule should map back to a source requirement ID in the planning matrix.
- The ruleset seed file should include a header comment naming the public source URL and source effective date.

## Implementation Plan

Phase 1: Source extraction and taxonomy.

- Create a structured requirements matrix from the Better Homes BC page.
- One row per requirement.
- Columns: upgrade type, subcategory, requirement, evidence source, automatable level, supporting docs, status.

Phase 2: Common ruleset.

- Extract common invoice/database checks shared across all upgrade types.
- Rewrite current `esp_default_v1` into `esp_windows_doors_v1` plus common shared text.

Phase 3: Windows and doors v1.

- Build explicit Windows and doors ruleset first.
- Include traceability fields.
- Add tests using known local PDFs and expected rule outputs.

Phase 4: Test harness.

- Add ruleset regression tests.
- Test output JSON shape.
- Test missing evidence produces `unknown`, not fake failure.
- Test rebate math where enough fields exist.

Phase 5: Other upgrade types.

- Add one ruleset at a time.
- Suggested order:
- Insulation.
- Heat pump water heater.
- Electrical service upgrade.
- Health and safety.
- Ventilation.
- Heat pump space heating last because it has the most subtypes.

Phase 6: Gold migration gate.

- Do not seed all seven rulesets into Gold as active production logic until the Windows and doors path is proven locally.
- It is okay to seed draft/disabled rulesets for review if the admin UI supports disabled rulesets clearly.
- Gold rollout should include a one-page business note explaining that AI is doing pre-review, not final eligibility determination.

## V1 Recommendation

For contractor v1, keep the build focused:

- Enable only Windows and doors in the contractor AI flow.
- Build a source-traced Windows and doors ruleset first.
- Retire the generic `esp_default_v1` fallback.
- If the invoice type is not Windows and doors, do not attempt a generic review.
- Treat supporting documents as uploadable/viewable in v1, but only let rules depend on them if the supporting document evidence is actually available to OCR/GenAI.

This still validates the architecture:

- Upgrade-type-specific rulesets.
- First-class invoice fields.
- Located fields with evidence.
- Rulechecks with source IDs.
- Contractor review.
- Admin review.
- Revision/fix loop.

It avoids the dangerous version of the project:

- A single generic prompt that gives confident answers across domains it does not understand.

## Sanity Check On Current Approach

Current approach makes sense if framed correctly:

- Good: AI pre-review to find invoice evidence, calculate visible rebate math, and flag likely issues.
- Good: Store field-level evidence and polygons so humans can verify.
- Good: Use domain-specific rulesets by upgrade type.
- Risk: If we claim AI is determining full eligibility from invoice alone, that is too strong.
- Risk: Website requirements include external lists, prior approvals, photos, contractor approvals, income levels, prior rebates, and property facts.
- Fix: Rulesets must classify evidence source and allow `unknown`.

Recommended language:

- "AI-assisted pre-review"
- "Potential issue"
- "Could not verify from invoice"
- "Requires supporting document/admin review"

Avoid:

- "Approved by AI"
- "Eligible by AI"
- "Automatically determined full compliance"

## Open Verification Items

- Confirm which program facts are already available in local/Gold DB for each common rule.
- Confirm whether the AI invoice system should ingest/support-check supporting documents for rulechecks in v1 or only display them.
- Confirm whether sample invoices linked from the page can be used to create test fixtures.
- Confirm whether ruleset text should cite source section references in the generated admin explanation.
- Confirm whether business wants all seven app-level upgrade types, or whether heat pump subtypes should eventually be first-class in the UI.

## Current Local Seed Shape

The local seed now intentionally keeps only two working rulesets:

- `esp_windows_doors_2026_04_v1`
- `esp_heat_pump_space_heating_2026_04_v1`

`claims.validationgenai_rulesets` remains a single-table design for now.

Prompt fields:

- `system_record`: strict output schema and general execution rules.
- `common_user_record1`: common located fields and common fuzzy/manual-review rulechecks shared by upgrade types.
- `user_record1`: upgrade-type-specific located fields and fuzzy/manual-review rulechecks.
- `summary_system_record`: removed from the v1 design. The main system record owns `overall.admin_advice` because there are no post-GenAI codechecks and no second mini-call.

Runtime composition:

```text
system: system_record
user: common_user_record1 + user_record1
user: case facts + OCR raw JSON
user: actual ask
```

The heat pump ruleset is first-pass only. It is intentionally conservative because the public requirements split heat pumps into several subtypes and require facts that usually come from DB records, external lists, and supporting documents rather than invoice text alone.
