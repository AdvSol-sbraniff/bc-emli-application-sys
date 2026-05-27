# ESP Requirements Implementation Tracker 2026

This markdown file is now the hand-edited source of truth for the tracker.

- The old DOCX tracker is a legacy snapshot only.
- `build_esp_traceability_doc.py` is legacy source material, not the working tracker source anymore.
- The main cleanup in this markdown is that supplement references are split into:
  - supplement subtype / classification on `claims.supporting_documents`
  - true supplement-extracted fields that would justify `claims.supporting_document_located_fields`

## How To Maintain This File

Use this file as both:

- the audit ledger for current ESP requirement coverage
- the forward registry for future supplement-related keys

Editing rules:

- Prefer direct markdown edits here over generator changes.
- Keep real implemented keys under `Traceability keys in system`.
- Keep not-yet-implemented keys under `Proposed future registry keys`.
- When supporting documents are involved, always decide all three:
  - supplement subtype likely required
  - supplement extracted fields likely required
  - whether that actually justifies `claims.supporting_document_located_fields`
- Do not introduce pseudo-field names for supplement evidence-presence cases. If the need is only "this kind of document exists," put it under supplement subtype, not supplement field.
- Do not use `hybrid` as a check style. If code produces the final pass/warn/fail result, use `code`. If GenAI produces the final pass/warn/fail result, even when it consumes code facts or supplement-type facts, use `genai`.

## Supplement Table Shortlist

Current interpretation of the strongest `supporting_document_located_fields` candidates:

- `yes`
  - `Windows And Doors` item `3`
  - `Windows And Doors` item `6`
  - `Air-To-Water Heat Pump` item `2`
  - `Combined Space And Water Heat Pump` item `2`
  - `Heat Pump Water Heater` item `2`
  - `Ventilation` item `2`
  - `Ventilation` item `3`
- `maybe`
  - `Air Source Heat Pump (Convert From Natural Gas Or Propane)` item `6`
  - `Air Source Heat Pump (Convert From Oil)` item `6`
  - `Dual Fuel Ducted Heat Pump` item `2`
  - `Heat Pump Water Heater` item `3`
  - `Electrical Service Upgrade` item `2`

Working rule:

- `yes` means the current architecture should seriously assume a future supplement field table may be useful.
- `maybe` means only add the table path if we truly automate extraction of values from inside those documents.
- everything else should stay at supplement subtype / evidence-presence level for now.

## Supplement Interpretation Rule

When a requirement mentions supporting documents, photos, WETT reports, F280 documents, labels, permits, pre-approvals, or similar evidence, do not assume that means a supplement located-field row is required.

Use this split:

- `supplement subtype required`: the system mainly needs to know what kind of supporting document was uploaded or whether the evidence family is present. This belongs on `claims.supporting_documents` and does not by itself justify `claims.supporting_document_located_fields`.
- `supplement extracted fields required`: the system needs actual values from inside the supplement, such as U-factor, model number, NEEA reference, bathroom fan CFM, or permit/date details. These are the cases that justify `claims.supporting_document_located_fields`.

Decision labels used below:

- `no`: the current requirement should not need `claims.supporting_document_located_fields`
- `maybe`: only needed if we later automate extraction of real values from inside the supplement
- `yes`: the requirement is a good candidate for true supplement-extracted fields

## How To Read This Audit

### 1. Audit method (N/A) — key: `upgrade_type_evidence_present`

**Source quote:** This working document quotes the actual 2026 Energy Savings Program requirement text and then marks coverage in red.

**Evidence sources required:** documentation_only

**How this check should be done:** documentation_only

**Likely located fields required:** none

**Traceability keys in system:**

- Only real persisted keys are named here: `rule_key` from `claims.invoice_version_rulechecks` and `code_rule_key` from `claims.code_rules`.
- No made-up requirement labels are used in this document.
- GenAI `rule_key=upgrade_type_evidence_present` is a cross-cutting invoice-domain-evidence rule used to confirm that the invoice text supports the claimed upgrade domain. It is not tied neatly to one single PDF sentence, so it is documented here as a shared audit note rather than attached to just one requirement quote.

**Missing now:**

- If a source requirement has no clear implemented check, it is marked `Missing now` with a priority so we can sequence follow-up work.

## General Eligibility Requirements

### 1. Implemented now (Low) — key: `source_vintage_applies`

**Source quote:** Effective date: For invoices dated on or after April 1, 2026.

**Evidence sources required:** invoice_pdf

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Code `rule_key=source_vintage_applies`.

### 2. Missing now (High) — key: `income_verification_document_present`

**Source quote:** Participant must reside in an income qualified household... Income verification documentation must be submitted for each member of the household that is over the age of 18...

**Evidence sources required:** database

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** income_verification_document

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current intent is document-presence / admin-review support, not structured OCR facts persisted per supporting document.

**Proposed future registry keys:**

- `rule_key`: `income_verification_document_present`, `income_verification_documents_complete`
- `supporting_documents.supplement_type`: `income_verification_document`
- `supporting_document_located_fields.field_key`: none

**Missing now:**

- No persisted check currently verifies the underlying household income documents against the requirement text.
- Current implementation relies on the existence of an eligibility code elsewhere, not on validating the listed income-document rules here.

### 3. Missing now (High) — key: `not_yet_keyed`

**Source quote:** Home must be a year-round primary residence in British Columbia that is at least 12 months old... The following types of homes are not eligible...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Missing now:**

- No persisted `rule_key` currently enforces home-type, home-age, bulk-application, or ineligible-home exclusions from invoice/database evidence.

### 4. Partial (High) — key: `utility_account_supporting_document_present`

**Source quote:** The home must be connected to a residential account with one of the following utilities... The home must be primarily heated by one of the following...

**Evidence sources required:** database, supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** utility_bill_or_account_document

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** The tracker should treat this as possible supporting evidence, but not as a current supplement-located-field requirement.

**External source note:** No separate downloadable utility-eligibility feed is identified yet. Better Homes currently publishes the municipal-utility list as a webpage/FAQ, and the broader utility universe still reads as BC Hydro, FortisBC, and the named municipal utilities rather than a seeded product-style download. See:

- https://betterhomesbc.ca/faqs/municipal-utilities/
- https://betterhomesbc.ca/definitions/municipal-utilities/

**Proposed future registry keys:**

- `rule_key`: `utility_account_supporting_document_present`
- `supporting_documents.supplement_type`: `utility_bill_or_account_document`
- `supporting_document_located_fields.field_key`: none

**Traceability keys in system:**

- Upgrade-specific heat-pump `rule_key`s do check heating-context clues in several sections, for example `ashp_electric_existing_heat_context_present`, `ashp_wood_existing_heat_context_present`, `ashp_gas_propane_existing_heat_context_present`, and `ashp_oil_existing_heat_context_present`.

**Missing now:**

- No general persisted check currently validates the eligible-utility list itself.
- No general persisted check currently validates the broader primary-heating requirement across all claim types.

### 5. Missing now (High) — key: `not_yet_keyed`

**Source quote:** The property must have a total assessed value at or under the referenced BC Assessment listing...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**External source note:** BC Assessment looks more like a licensed lookup path than a periodic seeded download. The public site exposes Assessment Search, and BC Assessment points users to BC OnLine for database access. Treat this as a realtime/licensed data-source investigation, not a new CSV/PDF seed like AHRI or NEEA. See:

- https://info.bcassessment.ca/Services-products/look-up-property-assessment
- https://www.bconline.gov.bc.ca/bc_assessment.html

**Missing now:**

- No persisted `rule_key` or `code_rule_key` currently validates the BC Assessment cap logic.

### 6. Partial (High) — key: `eligibility_code_valid_for_invoice_date`

**Source quote:** Participants must pre-register and confirm eligibility prior to installing upgrades. Eligibility codes... are valid for upgrades completed within 6 months of the participants approval date.

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Code `rule_key=eligibility_code_valid_for_invoice_date`.

**Missing now:**

- No persisted check clearly proves pre-registration occurred before installation; current coverage is mainly date-validity logic tied to the eligibility code.

### 7. Partial (High) — key: `contractor_identity_matches_record`

**Source quote:** All upgrades must be installed by a Registered Contractor... Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.

**Evidence sources required:** database, invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** invoice_contractor_name, invoice_contractor_address

**Traceability keys in system:**

- GenAI `rule_key=contractor_identity_matches_record`.
- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces the upstream registered-contractor gate as its own explicit audit result.
- No persisted check currently enforces contractor terms/compliance status directly inside the claims rulecheck layer.

### 8. Missing now (High) — key: `not_yet_keyed`

**Source quote:** Participants may only receive one rebate payment... under any of the following programs...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Missing now:**

- No persisted duplicate-history or cross-program one-rebate-per-upgrade check currently enforces this requirement end to end.

### 9. Implemented now (Medium) — key: `overall_rebate_not_over_invoice_total`

**Source quote:** Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade. Upgrade costs covered by warranty or home insurance are not eligible for rebates.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** overall_rebate_line_amount, overall_rebate_line_description, amount_due_after_rebate, customer_deposit

**Traceability keys in system:**

- GenAI `rule_key=overall_rebate_not_over_invoice_total`.
- GenAI `rule_key=warranty_costs_flag`.
- GenAI `rule_key=overall_invoice_arithmetic_consistent`.
- Code `rule_key=first_class_invoice_fields_present` supports the invoice evidence path.

**Missing now:**

- Paid-cost versus financed/credited amounts still depends on visible invoice evidence and may need deeper payment-state integration later.

### 10. Missing now (High) — key: `homeowner_identity_matches_eligibility_record`

**Source quote:** Utility accounts must be in the name of the resident and/or homeowner... If you currently rent your home, the registered property owner must complete the Landlord Consent Form... Landlords and/or property owners are only eligible... with two eligible homes...

**Evidence sources required:** database, supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** invoice_homeowner_name

**Supplement subtype likely required:** utility_bill_or_account_document, landlord_consent_form

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** These are supporting-document classes rather than true extracted supplement fields in the current design.

**Proposed future registry keys:**

- `rule_key`: `utility_account_name_matches_resident`, `landlord_consent_document_present`
- `supporting_documents.supplement_type`: `utility_bill_or_account_document`, `landlord_consent_form`
- `supporting_document_located_fields.field_key`: none

**Traceability keys in system:**

- GenAI `rule_key=homeowner_identity_matches_eligibility_record` covers some identity comparison only.

**Missing now:**

- No persisted check currently validates utility-account ownership, landlord consent, or the two-home landlord cap.

## Insulation

### 1. Implemented now (Medium) — key: `income_level_allows_rebate`

**Source quote:** Insulation upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- GenAI `rule_key=income_level_allows_rebate`.

### 2. Partial (High) — key: `ins_material_and_location_present`

**Source quote:** New insulation must be batt, loose fill, board or spray foam... installed in an eligible location... installed between a conditioned and unconditioned space... result in an increased R-value.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** ins_material_type, ins_upgrade_location, ins_conditioned_boundary_evidence, ins_new_r_value, ins_existing_r_value, ins_r_value_added

**Traceability keys in system:**

- GenAI `rule_key=ins_material_and_location_present`.
- GenAI `rule_key=ins_minimum_r_value_and_boundary_present`.
- GenAI `rule_key=ins_description_sufficient_for_review`.

**Missing now:**

- No persisted check currently proves Best Practice Guide compliance.
- The conditioned/unconditioned-space and heat-loss intent portions still rely on review-oriented interpretation rather than a deterministic validator.

### 3. Partial (Medium) — key: `ins_r_value_and_area_present`

**Source quote:** Rebates are calculated based on R-value of the new insulation added... If pre-existing insulation was removed... the rebate is calculated on the difference in R-value...

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** ins_new_r_value, ins_existing_r_value, ins_r_value_added, ins_area_square_feet, ins_line_amount, upgrade_specific_rebate_line_amount, ins_location_specific_rebate_amount, ins_rebate_formula_or_rate_evidence

**Traceability keys in system:**

- GenAI `rule_key=ins_r_value_and_area_present`.
- GenAI `rule_key=ins_rebate_math_within_cap`.

**Missing now:**

- No persisted check currently models the pre-existing-insulation-difference calculation path explicitly.

### 4. Partial (High) — key: `ins_health_safety_issue_flag`

**Source quote:** Pest infestations and rodent tunnels... must be resolved prior to installation... Any existing health and safety concerns (vermiculite, asbestos, mould)... must be resolved prior to installation...

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** ins_removed_existing_insulation_evidence, ins_health_safety_resolution_evidence

**Traceability keys in system:**

- GenAI `rule_key=ins_health_safety_issue_flag`.

**Missing now:**

- No persisted check currently proves pest or rodent resolution.
- No persisted supplement workflow currently validates the remediation evidence itself.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install insulation...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this insulation contractor-registration requirement as its own explicit audit result.

### 6. Partial (High) — key: `ins_supporting_document_reference_present`

**Source quote:** Before and after photos of the insulation area... Floor plan drawing... may be requested. Invoice... must show the itemized CleanBC rebate and deduct the CleanBC rebate... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** ins_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** before_after_photo_set, floor_plan_document

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** The current requirement is evidence presence. A future floor-plan extraction path could change this, but it is not needed for the current architecture.

**Proposed future registry keys:**

- `rule_key`: `ins_before_after_photo_set_present`, `ins_floor_plan_document_present`
- `supporting_documents.supplement_type`: `before_after_photo_set`, `floor_plan_document`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `ins_before_after_photo_reference` should be read as `supplement subtype only: before_after_photo_set`
- `ins_floor_plan_reference` should be read as `supplement subtype only: floor_plan_document`

**Traceability keys in system:**

- GenAI `rule_key=ins_supporting_document_reference_present`.
- GenAI `rule_key=rebate_line_evidence_present`.
- Code `rule_key=first_class_invoice_fields_present`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The supplement path does not yet do structured OCR/table validation for the before/after photos or floor-plan evidence.

## Windows And Doors

### 1. Implemented now (Medium) — key: `wd_income_level_and_vancouver_review`

**Source quote:** Windows and doors upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- GenAI `rule_key=wd_income_level_and_vancouver_review`.

### 2. Partial (High) — key: `wd_quote_preapproval_reference_present`

**Source quote:** Pre-approval is required; a quote for windows and doors upgrades must be submitted and approved prior to installation.

**Evidence sources required:** database

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** preapproval_quote, preapproval_notice

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Treat this as supporting-document classification / presence unless later automation needs approval reference/date extraction.

**Proposed future registry keys:**

- `rule_key`: `wd_preapproval_document_present`, `wd_preapproval_approved_before_installation`
- `supporting_documents.supplement_type`: `preapproval_quote`, `preapproval_notice`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `quote_preapproval_reference` should be read as `supplement subtype only: preapproval_quote / preapproval_notice`

**Traceability keys in system:**

- GenAI `rule_key=wd_quote_preapproval_reference_present`.

**Missing now:**

- Current coverage looks for quote/pre-approval evidence, but there is no persisted system-level workflow validation proving the approval was actually granted.

### 3. Partial (High) — key: `wd_envelope_replacement_evidence_present`

**Source quote:** The new windows and/or doors must replace existing windows and doors in the building envelope... skylights are not eligible... be listed with one of the following certification bodies...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** envelope_replacement_evidence, skylight_detected

**Supplement subtype likely required:** certification_sheet, energy_performance_label, manufacturer_label_photo

**Supplement extracted fields likely required:** certification_body, nrcan_number, cpd_number, brand_and_model

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** This is one of the clearest cases where true supplement-extracted facts would be useful if we automate certification validation.

**External source note:** No single Better Homes-owned downloadable certification list has been identified for this requirement. This currently reads more like certification-body evidence plus possible certification-body lookup/registry work than a straightforward new seeded download.

**Proposed future registry keys:**

- `rule_key`: `wd_certification_document_present`, `wd_certification_body_valid`
- `supporting_documents.supplement_type`: `certification_sheet`, `energy_performance_label`, `manufacturer_label_photo`
- `supporting_document_located_fields.field_key`: `certification_body`, `nrcan_number`, `cpd_number`, `brand_and_model`

**Deprecated tracker wording to ignore:**

- `certification_body_reference` should be read as `use true extracted supplement fields such as certification_body / nrcan_number / cpd_number instead`

**Traceability keys in system:**

- GenAI `rule_key=wd_envelope_replacement_evidence_present`.
- GenAI `rule_key=wd_no_skylights`.
- GenAI `rule_key=wd_certification_reference_present`.

**Missing now:**

- No persisted check currently proves compliance with the Best Practices for Window and Door Replacement guide.
- Certification-body validation still relies on review-oriented evidence rather than a structured certification lookup.

### 4. Implemented now (Medium) — key: `wd_rough_opening_evidence_present`

**Source quote:** The number of windows and/or doors eligible for rebates is based on the number of Rough Openings...

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** rough_opening_count, window_or_door_quantity, pane_count

**Traceability keys in system:**

- GenAI `rule_key=wd_rough_opening_evidence_present`.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install windows and doors...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this windows-and-doors contractor-registration requirement as its own explicit audit result.

### 6. Implemented now (High) — key: `wd_income_level_and_vancouver_review`

**Source quote:** Install eligible window/doors with a U-factor of 1.22 (W/m2-K) or less... 95% or 60% of eligible upgrade costs... $950 per window or door... Homes within the City of Vancouver municipal boundary are not eligible...

**Evidence sources required:** invoice_pdf, supporting_document, database, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** window_or_door_line_amount, hardware_per_unit, labour_per_unit, upgrade_specific_rebate_line_amount, city_of_vancouver_evidence

**Supplement subtype likely required:** energy_performance_label, certification_sheet

**Supplement extracted fields likely required:** metric_u_factor

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** If U-factor is proven from the supplement rather than the invoice, the value itself is a true extracted supplement field.

**External source note:** Same as the certification requirement above: no single program-owned downloadable window/door qualifying list was identified in this pass. This likely remains supplement evidence first, with any external validation coming from certification-body references rather than a seed file.

**Proposed future registry keys:**

- `rule_key`: `wd_u_factor_from_supporting_document_valid`
- `supporting_documents.supplement_type`: `energy_performance_label`, `certification_sheet`
- `supporting_document_located_fields.field_key`: `metric_u_factor`

**Traceability keys in system:**

- GenAI `rule_key=wd_income_level_and_vancouver_review`.
- GenAI `rule_key=wd_per_unit_rebate_math_within_cap`.
- GenAI `rule_key=wd_per_home_rebate_math_within_cap`.
- GenAI `rule_key=wd_customer_portion_math_matches`.

**Missing now:**

- No persisted check currently validates the U-factor itself from a structured product source.

### 7. Partial (High) — key: `wd_label_photo_reference_present`

**Source quote:** A photo of a manufacturer label from each installed window/door... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** manufacturer_label_photo

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** This was one of the buggy tracker examples. The primary need is supplement subtype / evidence presence, not a supplement-located-field row.

**Proposed future registry keys:**

- `rule_key`: `wd_manufacturer_label_photo_present`
- `supporting_documents.supplement_type`: `manufacturer_label_photo`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `manufacturer_label_photo_reference` should be read as `supplement subtype only: manufacturer_label_photo`

**Traceability keys in system:**

- GenAI `rule_key=wd_label_photo_reference_present`.
- GenAI `rule_key=wd_description_sufficient_for_review`.
- GenAI `rule_key=rebate_line_evidence_present`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The supplement path does not yet do structured label-photo OCR/validation.

## Air Source Heat Pump (Convert From Electric)

### 1. Missing now (High) — key: `not_yet_keyed`

**Source quote:** Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Missing now:**

- No electric-to-heat-pump-specific persisted income-level validator currently enforces this source sentence.

### 2. Implemented now (Medium) — key: `ashp_electric_existing_heat_context_present`

**Source quote:** The home must primarily be heated by electricity... The new heat pump must replace an existing hard-wired electric heating system... be sized to function as the primary heating system... serve a main living area...

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hp_existing_electric_heat_evidence, hp_main_living_area_evidence, hp_new_equipment_type

**Traceability keys in system:**

- GenAI `rule_key=ashp_electric_existing_heat_context_present`.
- GenAI `rule_key=ashp_electric_primary_system_scope_present`.
- GenAI `rule_key=ashp_electric_main_living_area_or_primary_capacity_present`.

### 3. Partial (High) — key: `hp_product_reference_present`

**Source quote:** The new heat pump must have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List... SEER / HSPF thresholds... Minimum capacity of 12,000 BTU...

**Evidence sources required:** external_list

**How this check should be done:** code

**Likely located fields required:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity

**External source note:** Existing download path already in place. The current seeded examples are the AHRI source tables in `claims_ai_service_ddl/3_insert_ahri_sources.sql`, which back the implemented `hp_ahri_found_in_product_list` and related heat-pump code rules.

**Traceability keys in system:**

- GenAI `rule_key=hp_product_reference_present`.
- Code `code_rule_key=hp_ahri_found_in_product_list`.
- Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.
- Code `code_rule_key=hp_product_efficiency_threshold`.

**Missing now:**

- No persisted check currently proves installation-guide compliance.

### 4. Implemented now (Medium) — key: `ashp_electric_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hp_existing_heat_pump_flag

**Traceability keys in system:**

- GenAI `rule_key=ashp_electric_no_existing_heat_pump_flag`.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `ashp_electric_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hp_line_amount, upgrade_specific_rebate_line_amount, hp_new_equipment_type

**Supplement subtype likely required:** f280_heat_load_calculation

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current requirement reads more like supporting-document presence than structured F280 field extraction.

**Proposed future registry keys:**

- `rule_key`: `ashp_electric_f280_document_present`
- `supporting_documents.supplement_type`: `f280_heat_load_calculation`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_heat_load_calc_reference` should be read as `supplement subtype only: f280_heat_load_calculation unless future automation extracts real F280 values`

**Traceability keys in system:**

- GenAI `rule_key=ashp_electric_rebate_math_within_cap`.
- GenAI `rule_key=hp_description_sufficient_for_review`.
- GenAI `rule_key=rebate_line_evidence_present`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The F280 support-document path is still review-oriented rather than structured supplement validation.

## Air Source Heat Pump (Convert From Wood)

### 1. Missing now (High) — key: `not_yet_keyed`

**Source quote:** Wood to heat pump upgrade rebates are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Missing now:**

- No wood-to-heat-pump-specific persisted income-level validator currently enforces this source sentence.

### 2. Implemented now (Medium) — key: `ashp_wood_existing_heat_context_present`

**Source quote:** The home must primarily be heated by a wood or solid fuel heating system... The back-up heating system must be wood or electric. Fossil fuel back-up systems are not eligible...

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hp_existing_wood_heat_evidence, hp_backup_heat_evidence

**Traceability keys in system:**

- GenAI `rule_key=ashp_wood_existing_heat_context_present`.
- GenAI `rule_key=ashp_wood_backup_and_primary_capacity_review`.

### 3. Partial (High) — key: `hp_product_reference_present`

**Source quote:** The new heat pump must be sized... serve a main living area... have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List...

**Evidence sources required:** external_list

**How this check should be done:** code

**Likely located fields required:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity, hp_main_living_area_evidence

**Traceability keys in system:**

- GenAI `rule_key=hp_product_reference_present`.
- Code `code_rule_key=hp_ahri_found_in_product_list`.
- Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.
- Code `code_rule_key=hp_product_efficiency_threshold`.

**Missing now:**

- No persisted check currently proves installation-guide compliance.

### 4. Partial (High) — key: `ashp_wood_removal_or_wett_reference_present`

**Source quote:** The existing wood or solid fuel heating system may be retained in safe and working order or removed... Before and after photos... Copy of a WETT-certified inspection report...

**Evidence sources required:** supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** before_after_photo_set, wett_report

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current architecture only needs document classification / presence here.

**Proposed future registry keys:**

- `rule_key`: `ashp_wood_before_after_photo_set_present`, `ashp_wood_wett_report_present`
- `supporting_documents.supplement_type`: `before_after_photo_set`, `wett_report`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_wood_system_removal_or_wett_evidence` should be read as `supplement subtype only: before_after_photo_set / wett_report`

**Traceability keys in system:**

- GenAI `rule_key=ashp_wood_removal_or_wett_reference_present`.

**Missing now:**

- The supplement path does not yet do structured validation for the photo evidence or WETT report details.

### 5. Implemented now (Medium) — key: `ashp_wood_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hp_existing_heat_pump_flag

**Traceability keys in system:**

- GenAI `rule_key=ashp_wood_no_existing_heat_pump_flag`.

### 6. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 7. Partial (High) — key: `ashp_wood_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hp_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** f280_heat_load_calculation

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Same as the electric path: current need is supporting-document presence, not extracted supplement fields.

**Proposed future registry keys:**

- `rule_key`: `ashp_wood_f280_document_present`
- `supporting_documents.supplement_type`: `f280_heat_load_calculation`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_heat_load_calc_reference` should be read as `supplement subtype only: f280_heat_load_calculation unless future automation extracts real F280 values`

**Traceability keys in system:**

- GenAI `rule_key=ashp_wood_rebate_math_within_cap`.
- GenAI `rule_key=hp_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The F280 support-document path remains review-oriented rather than structured supplement validation.

## Air Source Heat Pump (Convert From Natural Gas Or Propane)

### 1. Implemented now (Medium) — key: `ashp_gas_propane_existing_heat_context_present`

**Source quote:** The home must be primarily heated by fossil fuel (natural gas or propane)...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** hp_existing_gas_propane_heat_evidence

**Traceability keys in system:**

- GenAI `rule_key=ashp_gas_propane_existing_heat_context_present`.

### 2. Partial (High) — key: `hp_product_reference_present`

**Source quote:** The new heat pump must be capable of distributing heat throughout all the conditioned space... replace the existing fossil fuel heating system... have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity

**Supplement subtype likely required:** fossil_fuel_removal_proof

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** The removal-proof part is supplement-driven, but this requirement does not yet force a true extracted supplement field.

**Proposed future registry keys:**

- `rule_key`: `ashp_gas_propane_fossil_removal_proof_present`
- `supporting_documents.supplement_type`: `fossil_fuel_removal_proof`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_fossil_fuel_removal_evidence` should be read as `supplement subtype or extracted field; see interpretation above`

**Traceability keys in system:**

- GenAI `rule_key=hp_product_reference_present`.
- GenAI `rule_key=ashp_gas_propane_removal_reference_present`.
- Code `code_rule_key=hp_ahri_found_in_product_list`.
- Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.
- Code `code_rule_key=hp_product_efficiency_threshold`.

**Missing now:**

- The removal-proof supplement path is not yet structured or deterministic.

### 3. Partial (High) — key: `ashp_gas_propane_non_integrated_area_review`

**Source quote:** Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation.

**Evidence sources required:** database

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** non_integrated_area_preapproval_notice

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Preapproval is currently best modeled as supporting-document subtype/presence plus DB context.

**Proposed future registry keys:**

- `rule_key`: `ashp_gas_propane_non_integrated_area_preapproval_present`
- `supporting_documents.supplement_type`: `non_integrated_area_preapproval_notice`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_non_integrated_area_preapproval_reference` should be read as `supplement subtype only: non_integrated_area_preapproval_notice`

**Traceability keys in system:**

- GenAI `rule_key=ashp_gas_propane_non_integrated_area_review`.

**Missing now:**

- Current coverage is review-only; no persisted system integration proves pre-approval happened.

### 4. Implemented now (Medium) — key: `hp_fossil_backup_not_fossil_primary`

**Source quote:** The back-up heating system must be electric or wood... Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hp_backup_heat_evidence, hp_existing_heat_pump_flag

**Traceability keys in system:**

- GenAI `rule_key=hp_fossil_backup_not_fossil_primary`.
- GenAI `rule_key=hp_fossil_no_existing_heat_pump_flag`.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `ashp_gas_propane_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... The rebate application... must be submitted... within six (6) months...

**Evidence sources required:** invoice_pdf, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hp_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** f280_heat_load_calculation, fossil_fuel_removal_proof

**Supplement extracted fields likely required:** removal_date_or_permit_reference

**Would this justify `claims.supporting_document_located_fields`?** maybe

**Supplement interpretation note:** A table is only justified here if we decide to automate permit/date extraction rather than just document presence.

**Proposed future registry keys:**

- `rule_key`: `ashp_gas_propane_f280_document_present`, `ashp_gas_propane_removal_proof_present`, `ashp_gas_propane_removal_date_or_permit_present`
- `supporting_documents.supplement_type`: `f280_heat_load_calculation`, `fossil_fuel_removal_proof`
- `supporting_document_located_fields.field_key`: `removal_date_or_permit_reference`

**Deprecated tracker wording to ignore:**

- `hp_heat_load_calc_reference` should be read as `supplement subtype only: f280_heat_load_calculation unless future automation extracts real F280 values`
- `hp_fossil_fuel_removal_evidence` should be read as `supplement subtype or extracted field; see interpretation above`

**Traceability keys in system:**

- GenAI `rule_key=ashp_gas_propane_rebate_math_within_cap`.
- GenAI `rule_key=hp_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The F280 and removal-proof supplement path is still not structured enough for deterministic validation.

## Air Source Heat Pump (Convert From Oil)

### 1. Implemented now (Medium) — key: `ashp_oil_existing_heat_context_present`

**Source quote:** The home must be primarily heated by oil... The home must meet a minimum oil consumption baseline of 500 Ltrs. annually...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** hp_existing_oil_heat_evidence, hp_oil_consumption_baseline_evidence

**Traceability keys in system:**

- GenAI `rule_key=ashp_oil_existing_heat_context_present`.
- GenAI `rule_key=ashp_oil_consumption_baseline_reference_present`.

### 2. Partial (High) — key: `hp_product_reference_present`

**Source quote:** The new heat pump must... replace the existing fossil fuel heating system... have an AHRI certified reference number... be listed as a qualifying system on the Natural Resources Canada Oil to Heat Pump Affordability Qualified Heat Pump Product List...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity

**Supplement subtype likely required:** oil_removal_proof

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Removal-proof is supplement evidence, but not yet a true extracted-field requirement.

**External source note:** This row is the one place where the source text explicitly names the Natural Resources Canada Oil to Heat Pump Affordability qualified list. Current implementation still rides the existing AHRI-based download path. If the client wants strict source fidelity here, this may justify a distinct download/source investigation beyond the current AHRI seed.

**Proposed future registry keys:**

- `rule_key`: `ashp_oil_removal_proof_present`
- `supporting_documents.supplement_type`: `oil_removal_proof`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_oil_system_removal_evidence` should be read as `supplement subtype or extracted field; see interpretation above`

**Traceability keys in system:**

- GenAI `rule_key=hp_product_reference_present`.
- GenAI `rule_key=ashp_oil_removal_reference_present`.
- Code `code_rule_key=hp_ahri_found_in_product_list`.
- Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.
- Code `code_rule_key=hp_product_efficiency_threshold`.

**Missing now:**

- The oil-removal supplement path is not yet structured or deterministic.
- The code layer does not currently use a distinct Oil-to-Heat-Pump product list validator separate from the current AHRI path.

### 3. Missing now (High) — key: `ashp_oil_non_integrated_area_preapproval_present`

**Source quote:** Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation.

**Evidence sources required:** database

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** non_integrated_area_preapproval_notice

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Same interpretation as the gas/propane path.

**Proposed future registry keys:**

- `rule_key`: `ashp_oil_non_integrated_area_preapproval_present`
- `supporting_documents.supplement_type`: `non_integrated_area_preapproval_notice`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hp_non_integrated_area_preapproval_reference` should be read as `supplement subtype only: non_integrated_area_preapproval_notice`

**Missing now:**

- No oil-specific persisted non-integrated-area pre-approval validator currently enforces this sentence.

### 4. Implemented now (Medium) — key: `hp_fossil_backup_not_fossil_primary`

**Source quote:** The back-up heating system must be electric or wood... Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hp_backup_heat_evidence, hp_existing_heat_pump_flag

**Traceability keys in system:**

- GenAI `rule_key=hp_fossil_backup_not_fossil_primary`.
- GenAI `rule_key=hp_fossil_no_existing_heat_pump_flag`.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `ashp_oil_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel (oil) system removal... The rebate application... within six (6) months...

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hp_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** f280_heat_load_calculation, oil_removal_proof

**Supplement extracted fields likely required:** removal_date_or_permit_reference

**Would this justify `claims.supporting_document_located_fields`?** maybe

**Supplement interpretation note:** Only needs a supplement field table if we automate date/permit extraction.

**Proposed future registry keys:**

- `rule_key`: `ashp_oil_f280_document_present`, `ashp_oil_removal_proof_present`, `ashp_oil_removal_date_or_permit_present`
- `supporting_documents.supplement_type`: `f280_heat_load_calculation`, `oil_removal_proof`
- `supporting_document_located_fields.field_key`: `removal_date_or_permit_reference`

**Deprecated tracker wording to ignore:**

- `hp_heat_load_calc_reference` should be read as `supplement subtype only: f280_heat_load_calculation unless future automation extracts real F280 values`
- `hp_oil_system_removal_evidence` should be read as `supplement subtype or extracted field; see interpretation above`

**Traceability keys in system:**

- GenAI `rule_key=ashp_oil_rebate_math_within_cap`.
- GenAI `rule_key=hp_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The F280 and oil-removal supplement path is still not structured enough for deterministic validation.

## Dual Fuel Ducted Heat Pump

### 1. Implemented now (Medium) — key: `dfhp_png_or_tank_propane_path_present`

**Source quote:** The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG)...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** dfhp_existing_png_or_tank_propane_evidence

**Traceability keys in system:**

- GenAI `rule_key=dfhp_png_or_tank_propane_path_present`.

### 2. Partial (High) — key: `dfhp_dual_fuel_scope_present`

**Source quote:** The new heat pump must be integrated with a propane or natural gas heating system... have the thermostat / outdoor temperature switch-over control set to the following region-specific temperatures... be sized to ensure it has the capacity to meet the home's heat demand...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** dfhp_equipment_type, hp_ahri_reference

**Supplement subtype likely required:** commissioning_or_control_document, fossil_modification_or_removal_proof

**Supplement extracted fields likely required:** switchover_setpoint

**Would this justify `claims.supporting_document_located_fields`?** maybe

**Supplement interpretation note:** This becomes a true supplement field only if we automate reading the switchover setpoint from supporting material.

**Proposed future registry keys:**

- `rule_key`: `dfhp_control_document_present`, `dfhp_switchover_setpoint_valid`, `dfhp_fossil_modification_proof_present`
- `supporting_documents.supplement_type`: `commissioning_or_control_document`, `fossil_modification_or_removal_proof`
- `supporting_document_located_fields.field_key`: `switchover_setpoint`

**Deprecated tracker wording to ignore:**

- `dfhp_switchover_setpoint_evidence` should be read as `future candidate extracted supplement field: switchover_setpoint`
- `dfhp_fossil_modification_evidence` should be read as `supplement subtype only: fossil_modification_or_removal_proof`

**Traceability keys in system:**

- GenAI `rule_key=dfhp_dual_fuel_scope_present`.
- GenAI `rule_key=dfhp_controls_reference_present`.
- GenAI `rule_key=dfhp_switchover_setpoint_specific`.
- Code `code_rule_key=hp_ahri_found_in_product_list`.
- Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.
- Code `code_rule_key=hp_product_efficiency_threshold`.

**Missing now:**

- The fossil-fuel modification/removal proof is still supplement-driven and not structured end to end.

### 3. Partial (High) — key: `dfhp_heat_load_calc_reference_present`

**Source quote:** A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted.

**Evidence sources required:** supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** approved_heat_load_calculation

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Presence of the approved heat-load document is the current need.

**Proposed future registry keys:**

- `rule_key`: `dfhp_heat_load_document_present`
- `supporting_documents.supplement_type`: `approved_heat_load_calculation`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `dfhp_heat_load_calc_reference` should be read as `supplement subtype only: approved_heat_load_calculation unless future automation extracts real heat-load values`

**Traceability keys in system:**

- GenAI `rule_key=dfhp_heat_load_calc_reference_present`.

**Missing now:**

- The required F280 / approved heat-load document is not yet validated through a structured supplement path.

### 4. Missing now (High) — key: `dfhp_non_integrated_area_preapproval_present`

**Source quote:** Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation.

**Evidence sources required:** database

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** non_integrated_area_preapproval_notice

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Subtype/presence only for now.

**Proposed future registry keys:**

- `rule_key`: `dfhp_non_integrated_area_preapproval_present`
- `supporting_documents.supplement_type`: `non_integrated_area_preapproval_notice`
- `supporting_document_located_fields.field_key`: none

**Missing now:**

- No dual-fuel-specific persisted non-integrated-area pre-approval validator currently enforces this sentence.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `dfhp_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... Proof of fossil fuel system removal or modification... A copy of CSA-F280-12 Heat Load Calculation is required... within six (6) months...

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** dfhp_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** approved_heat_load_calculation, fossil_modification_or_removal_proof

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current requirement does not force supplement field extraction.

**Proposed future registry keys:**

- `rule_key`: `dfhp_heat_load_document_present`, `dfhp_fossil_modification_proof_present`
- `supporting_documents.supplement_type`: `approved_heat_load_calculation`, `fossil_modification_or_removal_proof`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `dfhp_heat_load_calc_reference` should be read as `supplement subtype only: approved_heat_load_calculation unless future automation extracts real heat-load values`
- `dfhp_fossil_modification_evidence` should be read as `supplement subtype only: fossil_modification_or_removal_proof`

**Traceability keys in system:**

- GenAI `rule_key=dfhp_rebate_math_within_cap`.
- GenAI `rule_key=dfhp_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The removal/modification proof and required heat-load document are still not validated through a structured supplement path.

## Air-To-Water Heat Pump

### 1. Implemented now (Medium) — key: `atw_scope_present`

**Source quote:** The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** atw_conversion_source_fuel_evidence

**Traceability keys in system:**

- GenAI `rule_key=atw_scope_present`.
- GenAI `rule_key=hydronic_conversion_context_present`.
- GenAI `rule_key=atw_not_combined_or_hpwh_scope`.

### 2. Partial (High) — key: `hydronic_product_reference_present`

**Source quote:** The new air-to-water heat pump must... be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** atw_product_list_reference

**Supplement subtype likely required:** product_spec_sheet, manufacturer_label_photo

**Supplement extracted fields likely required:** atw_make_model

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** If the make/model is proved from supplement material rather than invoice text, it is a true extracted supplement field.

**External source note:** This looks like a real new downloadable-list candidate. Better Homes publishes the Air-to-Water and Combination Heat Pump qualified list directly, including a dedicated page and a PDF list. If we expand beyond AHRI/NEEA, this is one of the strongest next seeded-download candidates. See:

- https://www.betterhomesbc.ca/qualifyingairtowaterhp/
- https://betterhomesbc.ca/wp-content/uploads/2026/02/Air-to-Water-Eligibility-List-V10.pdf

**Proposed future registry keys:**

- `rule_key`: `atw_product_spec_document_present`, `atw_make_model_from_supporting_document_present`
- `supporting_documents.supplement_type`: `product_spec_sheet`, `manufacturer_label_photo`
- `supporting_document_located_fields.field_key`: `atw_make_model`

**Traceability keys in system:**

- GenAI `rule_key=hydronic_product_reference_present`.

**Missing now:**

- No persisted `code_rule_key` currently validates the air-to-water qualifying product list.
- No persisted check currently proves installation-guide compliance.

### 3. Partial (High) — key: `hydronic_conversion_context_present`

**Source quote:** If the new air-to-water heat pump replaces a fossil fuel heating system, all the fossil fuel heating equipment... must be removed... If it replaces a wood or solid fuel heating system, the existing wood or solid fuel heating system may be retained... or removed...

**Evidence sources required:** supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** fossil_removal_proof, before_after_photo_set, wett_report

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current need is document classification/presence.

**Proposed future registry keys:**

- `rule_key`: `atw_fossil_removal_proof_present`, `atw_before_after_photo_set_present`, `atw_wett_report_present`
- `supporting_documents.supplement_type`: `fossil_removal_proof`, `before_after_photo_set`, `wett_report`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `atw_fossil_removal_evidence` should be read as `supplement subtype only: fossil_removal_proof`
- `atw_wood_removal_or_wett_evidence` should be read as `supplement subtype only: before_after_photo_set / wett_report`

**Traceability keys in system:**

- GenAI `rule_key=hydronic_conversion_context_present`.

**Missing now:**

- No persisted check currently validates the fossil-fuel removal proof, wood-removal photos, or WETT-retention evidence.

### 4. Partial (High) — key: `hydronic_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible. Homes in Non-Integrated Areas... must contact... for pre-approval...

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** atw_existing_heat_pump_flag

**Supplement subtype likely required:** non_integrated_area_preapproval_notice

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Preapproval is not yet a true supplement field requirement.

**Proposed future registry keys:**

- `rule_key`: `atw_non_integrated_area_preapproval_present`
- `supporting_documents.supplement_type`: `non_integrated_area_preapproval_notice`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `atw_non_integrated_area_preapproval_reference` should be read as `supplement subtype only: non_integrated_area_preapproval_notice`

**Traceability keys in system:**

- GenAI `rule_key=hydronic_no_existing_heat_pump_flag`.

**Missing now:**

- No persisted air-to-water-specific non-integrated-area pre-approval validator currently enforces this sentence.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `atw_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... Before and after photos of the wood or solid fuel heating system... WETT-certified inspection report...

**Evidence sources required:** invoice_pdf, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** atw_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** f280_heat_load_calculation, fossil_removal_proof, before_after_photo_set, wett_report

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current path is still evidence-presence oriented.

**Proposed future registry keys:**

- `rule_key`: `atw_heat_load_document_present`, `atw_fossil_removal_proof_present`
- `supporting_documents.supplement_type`: `f280_heat_load_calculation`, `fossil_removal_proof`, `before_after_photo_set`, `wett_report`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `atw_heat_load_calc_reference` should be read as `supplement subtype only: f280_heat_load_calculation unless future automation extracts real heat-load values`
- `atw_fossil_removal_evidence` should be read as `supplement subtype only: fossil_removal_proof`
- `atw_wood_removal_or_wett_evidence` should be read as `supplement subtype only: before_after_photo_set / wett_report`

**Traceability keys in system:**

- GenAI `rule_key=atw_rebate_math_within_cap`.
- GenAI `rule_key=hp_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The F280, removal-proof, photo, and WETT supplement path is still not structured enough for deterministic validation.

## Combined Space And Water Heat Pump

### 1. Implemented now (Medium) — key: `cshp_scope_present`

**Source quote:** The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** cshp_conversion_source_fuel_evidence

**Traceability keys in system:**

- GenAI `rule_key=cshp_scope_present`.
- GenAI `rule_key=hydronic_conversion_context_present`.

### 2. Partial (High) — key: `hydronic_product_reference_present`

**Source quote:** Combined space and water heat pump... Must be listed on the air-to-water and combined heat pump qualifying product list.

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** cshp_product_list_reference

**Supplement subtype likely required:** product_spec_sheet, manufacturer_label_photo

**Supplement extracted fields likely required:** cshp_make_model

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** Make/model from supplement material is a genuine extracted fact if we automate it.

**External source note:** Same source path as the air-to-water row above. The Better Homes Air-to-Water and Combination Heat Pump qualified list appears to cover both air-to-water-only and combined systems, so this likely points to the same next seeded-download family rather than a separate one. See:

- https://www.betterhomesbc.ca/qualifyingairtowaterhp/
- https://betterhomesbc.ca/wp-content/uploads/2026/02/Air-to-Water-Eligibility-List-V10.pdf

**Proposed future registry keys:**

- `rule_key`: `cshp_product_spec_document_present`, `cshp_make_model_from_supporting_document_present`
- `supporting_documents.supplement_type`: `product_spec_sheet`, `manufacturer_label_photo`
- `supporting_document_located_fields.field_key`: `cshp_make_model`

**Traceability keys in system:**

- GenAI `rule_key=hydronic_product_reference_present`.
- GenAI `rule_key=cshp_combined_space_and_water_scope_present`.

**Missing now:**

- No persisted `code_rule_key` currently validates the combined-system qualifying product list.

### 3. Partial (High) — key: `hydronic_conversion_context_present`

**Source quote:** If the new air-to-water heat pump replaces a fossil fuel heating system... must be removed... If it replaces a wood or solid fuel heating system... may be retained in safe and working order or removed...

**Evidence sources required:** supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** cshp_domestic_hot_water_evidence

**Supplement subtype likely required:** fossil_removal_proof, before_after_photo_set, wett_report

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** The current architecture only needs supporting-document subtype/presence here.

**Proposed future registry keys:**

- `rule_key`: `cshp_fossil_removal_proof_present`, `cshp_before_after_photo_set_present`, `cshp_wett_report_present`
- `supporting_documents.supplement_type`: `fossil_removal_proof`, `before_after_photo_set`, `wett_report`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `cshp_fossil_removal_evidence` should be read as `supplement subtype only: fossil_removal_proof`
- `cshp_wood_removal_or_wett_evidence` should be read as `supplement subtype only: before_after_photo_set / wett_report`

**Traceability keys in system:**

- GenAI `rule_key=hydronic_conversion_context_present`.

**Missing now:**

- No persisted check currently validates fossil-fuel removal proof, wood-removal photos, or WETT-retention evidence for this path.

### 4. Implemented now (Medium) — key: `hydronic_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** cshp_existing_heat_pump_flag

**Traceability keys in system:**

- GenAI `rule_key=hydronic_no_existing_heat_pump_flag`.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `cshp_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... Before and after photos... WETT-certified inspection report...

**Evidence sources required:** invoice_pdf, supporting_document, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** cshp_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** f280_heat_load_calculation, fossil_removal_proof, before_after_photo_set, wett_report

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** No supplement table is required unless we later automate detailed extraction from these docs.

**Proposed future registry keys:**

- `rule_key`: `cshp_heat_load_document_present`, `cshp_fossil_removal_proof_present`
- `supporting_documents.supplement_type`: `f280_heat_load_calculation`, `fossil_removal_proof`, `before_after_photo_set`, `wett_report`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `cshp_heat_load_calc_reference` should be read as `supplement subtype only: f280_heat_load_calculation unless future automation extracts real heat-load values`
- `cshp_fossil_removal_evidence` should be read as `supplement subtype only: fossil_removal_proof`
- `cshp_wood_removal_or_wett_evidence` should be read as `supplement subtype only: before_after_photo_set / wett_report`

**Traceability keys in system:**

- GenAI `rule_key=cshp_rebate_math_within_cap`.
- GenAI `rule_key=hp_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The F280, removal-proof, photo, and WETT supplement path is still not structured enough for deterministic validation.

## Heat Pump Water Heater

### 1. Implemented now (Medium) — key: `hpwh_primary_replacement_context_present`

**Source quote:** The existing water heater being replaced must be the home's primary water heater.

**Evidence sources required:** invoice_pdf

**How this check should be done:** code

**Likely located fields required:** hpwh_existing_water_heater_evidence

**Traceability keys in system:**

- GenAI `rule_key=hpwh_primary_replacement_context_present`.

### 2. Implemented now (Low) — key: `hpwh_product_reference_present`

**Source quote:** Eligible systems are listed as Tier 2 or higher on NEEA's Advanced Water Heater Specification Qualified Products List...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** product_spec_sheet, manufacturer_label_photo

**Supplement extracted fields likely required:** hpwh_manufacturer, hpwh_model_number, hpwh_neea_reference, hpwh_tier_reference

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** This is a strong supplement-field-table candidate because label/spec OCR can produce real persisted product facts.

**External source note:** Existing download path already in place. The current seeded example is the NEEA qualified-products source in `claims_ai_service_ddl/3_insert_neea_sources.sql`, backing `hpwh_neea_found_in_product_list` and `hpwh_neea_tier_2_or_higher`.

**Proposed future registry keys:**

- `rule_key`: `hpwh_product_spec_document_present`, `hpwh_label_or_spec_product_identifiers_present`, `hpwh_neea_reference_present`
- `supporting_documents.supplement_type`: `product_spec_sheet`, `manufacturer_label_photo`
- `supporting_document_located_fields.field_key`: `hpwh_manufacturer`, `hpwh_model_number`, `hpwh_neea_reference`, `hpwh_tier_reference`

**Traceability keys in system:**

- GenAI `rule_key=hpwh_product_reference_present`.
- Code `code_rule_key=hpwh_neea_found_in_product_list`.
- Code `code_rule_key=hpwh_neea_tier_2_or_higher`.

### 3. Partial (High) — key: `hpwh_fossil_removal_evidence_present`

**Source quote:** If the new heat pump water heater replaces a fossil fuel water heating system, all the fossil fuel heating equipment... must be removed or decommissioned... Homes in Non-Integrated Areas... must contact... for pre-approval...

**Evidence sources required:** database

**How this check should be done:** code

**Invoice / runtime fields likely required:** hpwh_existing_fuel_type

**Supplement subtype likely required:** fossil_fuel_removal_proof, non_integrated_area_preapproval_notice, permit_document

**Supplement extracted fields likely required:** hpwh_fossil_removal_date_or_permit_reference

**Would this justify `claims.supporting_document_located_fields`?** maybe

**Supplement interpretation note:** A supplement field table is justified only if we automate permit/date extraction instead of pure document presence.

**Proposed future registry keys:**

- `rule_key`: `hpwh_fossil_removal_proof_present`, `hpwh_non_integrated_area_preapproval_present`, `hpwh_permit_or_removal_date_present`
- `supporting_documents.supplement_type`: `fossil_fuel_removal_proof`, `non_integrated_area_preapproval_notice`, `permit_document`
- `supporting_document_located_fields.field_key`: `hpwh_fossil_removal_date_or_permit_reference`

**Deprecated tracker wording to ignore:**

- `hpwh_fossil_fuel_removal_evidence` should be read as `supplement subtype only: fossil_fuel_removal_proof`
- `hpwh_non_integrated_area_preapproval_reference` should be read as `supplement subtype only: non_integrated_area_preapproval_notice`
- `hpwh_fossil_removal_date_or_permit` should be read as `supplement subtype or extracted field; see interpretation above`

**Traceability keys in system:**

- GenAI `rule_key=hpwh_fossil_removal_evidence_present`.
- GenAI `rule_key=hpwh_non_integrated_area_review`.

**Missing now:**

- Current coverage is still review-oriented; no persisted structured supplement/external validator proves the removal or the non-integrated-area approval.

### 4. Implemented now (Medium) — key: `hpwh_secondary_system_flag`

**Source quote:** Replacing or adding a secondary heat pump water heater to a home with an existing heat pump water heater is not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hpwh_secondary_system_flag, hpwh_existing_hpwh_flag

**Traceability keys in system:**

- GenAI `rule_key=hpwh_secondary_system_flag`.
- GenAI `rule_key=hpwh_no_existing_or_secondary_hpwh_flag`.

### 5. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) — key: `hpwh_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... Proof of gas water heater removal... The rebate application... must be submitted... within six (6) months...

**Evidence sources required:** invoice_pdf, database

**How this check should be done:** genai

**Invoice / runtime fields likely required:** hpwh_existing_fuel_type, hpwh_line_amount, upgrade_specific_rebate_line_amount

**Supplement subtype likely required:** fossil_fuel_removal_proof

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** Current need is supporting evidence presence, not extracted supplement values.

**Proposed future registry keys:**

- `rule_key`: `hpwh_fossil_removal_proof_present`
- `supporting_documents.supplement_type`: `fossil_fuel_removal_proof`
- `supporting_document_located_fields.field_key`: none

**Traceability keys in system:**

- GenAI `rule_key=hpwh_rebate_math_within_cap`.
- GenAI `rule_key=hpwh_description_sufficient_for_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The fossil-fuel-removal supplement path is still not structured enough for deterministic validation.

## Electrical Service Upgrade

### 1. Implemented now (Medium) — key: `esu_heat_pump_conversion_context_present`

**Source quote:** Only homes that convert from a fossil fuel primary space and/or water heating system to a heat pump... are eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** code

**Likely located fields required:** esu_fossil_to_heat_pump_context

**Traceability keys in system:**

- GenAI `rule_key=esu_heat_pump_conversion_context_present`.

### 2. Partial (High) — key: `esu_utility_upgrade_evidence_present`

**Source quote:** The electric service (new wire) must be upgraded by the participant's electrical utility... The service upgrade... must be installed within six months of the heat pump installation.

**Evidence sources required:** invoice_pdf, supporting_document

**How this check should be done:** genai

**Invoice / runtime fields likely required:** esu_utility_reference

**Supplement subtype likely required:** utility_bill_or_invoice, utility_upgrade_document

**Supplement extracted fields likely required:** previous_service_size, new_service_size

**Would this justify `claims.supporting_document_located_fields`?** maybe

**Supplement interpretation note:** This only needs a supplement field table if we automate service-size extraction from utility-side docs.

**External source note:** This looks more like utility-issued document evidence than a reusable central download. No general public utility-upgrade master list was identified in this pass; if automation is pursued here it likely depends on uploaded utility documents or direct utility-specific integrations rather than a seeded reference file.

**Proposed future registry keys:**

- `rule_key`: `esu_utility_upgrade_document_present`, `esu_service_size_values_present`
- `supporting_documents.supplement_type`: `utility_bill_or_invoice`, `utility_upgrade_document`
- `supporting_document_located_fields.field_key`: `previous_service_size`, `new_service_size`

**Deprecated tracker wording to ignore:**

- `esu_previous_service_size` should be read as `future candidate extracted supplement field: previous_service_size`
- `esu_new_service_size` should be read as `future candidate extracted supplement field: new_service_size`
- `esu_utility_bill_or_invoice_reference` should be read as `supplement subtype only: utility_bill_or_invoice / utility_upgrade_document`

**Traceability keys in system:**

- GenAI `rule_key=esu_utility_upgrade_evidence_present`.
- GenAI `rule_key=esu_service_size_present`.
- GenAI `rule_key=esu_timing_within_six_months_evidence`.

**Missing now:**

- There is no persisted external/system validator that proves the utility actually performed the qualifying service upgrade.

### 3. Partial (Medium) — key: `esu_description_sufficient_for_review`

**Source quote:** Eligible expenses include utility connection fees, electrical panel or sub-panel upgrade, service mast alterations... labour.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** esu_eligible_expense_lines, esu_line_amount

**Traceability keys in system:**

- GenAI `rule_key=esu_description_sufficient_for_review`.

**Missing now:**

- No persisted line-item classifier currently enforces the eligible-expense list deterministically.

### 4. Implemented now (Medium) — key: `esu_not_panel_only_or_connection_only`

**Source quote:** Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible.

**Evidence sources required:** invoice_pdf

**How this check should be done:** code

**Likely located fields required:** esu_ineligible_panel_only_evidence

**Traceability keys in system:**

- GenAI `rule_key=esu_not_panel_only_or_connection_only`.

### 5. Missing now (High) — key: `esu_utility_invoice_present`

**Source quote:** If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice.

**Evidence sources required:** invoice_pdf, supporting_document

**How this check should be done:** genai

**Invoice / runtime fields likely required:** esu_contractor_utility_management_evidence

**Supplement subtype likely required:** utility_invoice

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** The current requirement is mainly one-invoice / evidence-presence logic.

**Proposed future registry keys:**

- `rule_key`: `esu_utility_invoice_present`
- `supporting_documents.supplement_type`: `utility_invoice`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `esu_utility_bill_or_invoice_reference` should be read as `supplement subtype only: utility_bill_or_invoice / utility_upgrade_document`

**Missing now:**

- No persisted invoice-composition validator currently proves that contractor and utility work were combined on one invoice when required.

### 6. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 7. Partial (High) — key: `esu_rebate_math_within_cap`

**Source quote:** Electrical service upgrade... up to a maximum... Maximum of one electrical service upgrade per home... Invoice... must show the itemized CleanBC rebate... within six (6) months...

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** esu_line_amount, upgrade_specific_rebate_line_amount, esu_new_service_size

**Traceability keys in system:**

- GenAI `rule_key=esu_rebate_math_within_cap`.
- GenAI `rule_key=esu_one_per_home_manual_review`.
- Code `rule_key=submission_within_six_months`.

**Missing now:**

- The one-per-home restriction is still manual-review oriented rather than a deterministic historical validator.

## Health And Safety

### 1. Implemented now (High) — key: `hs_issue_type_present`

**Source quote:** Remediation must be for existing health and safety issues... required to enable the safe installation and operation of a rebate-eligible upgrade... completed in association with an eligible upgrade... Rebates will not be paid for health and safety remediation on its own... confirmed as rebate-eligible prior to beginning remediation.

**Evidence sources required:** invoice_pdf

**How this check should be done:** genai

**Likely located fields required:** hs_issue_type, hs_associated_upgrade_evidence, hs_remediation_scope

**Traceability keys in system:**

- GenAI `rule_key=hs_issue_type_present`.
- GenAI `rule_key=hs_associated_upgrade_present`.
- GenAI `rule_key=hs_not_standalone_flag`.
- GenAI `rule_key=hs_pre_confirmation_evidence_present`.

**Missing now:**

- The pre-confirmation step is still evidence/review oriented rather than a wired workflow integration.

### 2. Partial (Medium) — key: `not_yet_keyed`

**Source quote:** All upgrades must be completed by a Registered Contractor who is approved to complete health and safety remediation...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** hs_registered_contractor_evidence

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this health-and-safety contractor-registration requirement as its own explicit audit result.

### 3. Implemented now (Medium) — key: `hs_description_sufficient_for_review`

**Source quote:** Must be used to remediate pest, asbestos, structural and/or mould issues... Invoice... must show the itemized CleanBC rebate...

**Evidence sources required:** invoice_pdf, database

**How this check should be done:** genai

**Likely located fields required:** hs_issue_type, hs_remediation_scope, hs_line_amount, upgrade_specific_rebate_line_amount

**Traceability keys in system:**

- GenAI `rule_key=hs_description_sufficient_for_review`.
- GenAI `rule_key=hs_rebate_math_within_cap`.
- GenAI `rule_key=income_level_allows_rebate`.
- GenAI `rule_key=rebate_line_evidence_present`.

### 4. Partial (High) — key: `hs_before_after_photos_present`

**Source quote:** Before and after photos of the health and safety issue that was remediated.

**Evidence sources required:** supporting_document

**How this check should be done:** code

**Invoice / runtime fields likely required:** none

**Supplement subtype likely required:** before_after_photo_set

**Supplement extracted fields likely required:** none

**Would this justify `claims.supporting_document_located_fields`?** no

**Supplement interpretation note:** This is photo-evidence presence, not a structured supplement field.

**Proposed future registry keys:**

- `rule_key`: `hs_before_after_photo_set_present`
- `supporting_documents.supplement_type`: `before_after_photo_set`
- `supporting_document_located_fields.field_key`: none

**Deprecated tracker wording to ignore:**

- `hs_before_after_photo_reference` should be read as `supplement subtype only: before_after_photo_set`

**Traceability keys in system:**

- GenAI `rule_key=hs_before_after_photos_present`.

**Missing now:**

- The supplement path does not yet do structured photo validation.

### 5. Implemented now (Low) — key: `submission_within_six_months`

**Source quote:** The rebate application and supporting documentation must be submitted by the Registered Contractor within six (6) months of the invoice date.

**Evidence sources required:** invoice_pdf, database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Code `rule_key=submission_within_six_months`.

## Ventilation

### 1. Implemented now (Medium) — key: `vent_associated_upgrade_present`

**Source quote:** Ventilation upgrades must be installed in association with a rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for ventilation upgrades on their own.

**Evidence sources required:** invoice_pdf

**How this check should be done:** code

**Likely located fields required:** vent_associated_upgrade_evidence

**Traceability keys in system:**

- GenAI `rule_key=vent_associated_upgrade_present`.
- GenAI `rule_key=vent_standalone_flag`.

### 2. Partial (High) — key: `vent_system_type_present`

**Source quote:** Heat/energy recovery ventilators must be ENERGY STAR certified and listed on Natural Resources Canada's searchable product list... be installed in accordance with the BC Housing Heat Recovery Ventilation Guide...

**Evidence sources required:** invoice_pdf, supporting_document, external_list

**How this check should be done:** genai

**Invoice / runtime fields likely required:** vent_system_type

**Supplement subtype likely required:** product_spec_sheet, energy_star_label

**Supplement extracted fields likely required:** vent_energy_star_reference, vent_nrcan_or_product_list_reference

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** If the Energy Star / NRCan proof is coming from supplement docs, those are true extracted facts.

**External source note:** An official NRCan searchable product list exists for ENERGY STAR certified products, including HRVs/ERVs, but this pass did not identify a simple seeded CSV/PDF equivalent like AHRI/NEEA. Treat this as a likely lookup/search integration or future scraper/API research item unless NRCan exposes a cleaner export path. See:

- https://prod-natural-resources.azure.cloud.nrcan-rncan.gc.ca/energy-efficiency/energy-star/products/list-certified-products
- https://natural-resources.canada.ca/energy-efficiency/energy-efficiency-regulations/energy-heat-recovery-ventilators

**Proposed future registry keys:**

- `rule_key`: `vent_product_spec_document_present`, `vent_energy_star_supporting_document_present`
- `supporting_documents.supplement_type`: `product_spec_sheet`, `energy_star_label`
- `supporting_document_located_fields.field_key`: `vent_energy_star_reference`, `vent_nrcan_or_product_list_reference`

**Traceability keys in system:**

- GenAI `rule_key=vent_system_type_present`.
- GenAI `rule_key=vent_product_or_capacity_evidence_present`.

**Missing now:**

- No persisted structured validator currently checks the HRV/ERV product list or ENERGY STAR status.
- No persisted check currently proves the ventilation-guide installation requirement.

### 3. Partial (High) — key: `vent_product_or_capacity_evidence_present`

**Source quote:** Bathroom fan systems must... be ENERGY STAR certified... be ducted directly to the outside... have a capacity of at least 85 cfm... be rated for continuous duty... be equipped with self-closing backdraft damper... ducts must be sealed... ducts must be insulated to minimum R4...

**Evidence sources required:** invoice_pdf, supporting_document

**How this check should be done:** genai

**Invoice / runtime fields likely required:** vent_system_type

**Supplement subtype likely required:** product_spec_sheet, energy_star_label

**Supplement extracted fields likely required:** vent_bathroom_fan_cfm, vent_static_pressure, vent_continuous_duty_motor_evidence, vent_backdraft_damper_evidence, vent_ducting_evidence, vent_main_bathroom_evidence, vent_direct_exterior_ducting_evidence

**Would this justify `claims.supporting_document_located_fields`?** yes

**Supplement interpretation note:** This is one of the clearest supplement-field-table cases because the spec-sheet values themselves matter.

**Proposed future registry keys:**

- `rule_key`: `vent_product_spec_values_present`, `vent_bathroom_fan_spec_values_present`
- `supporting_documents.supplement_type`: `product_spec_sheet`, `energy_star_label`
- `supporting_document_located_fields.field_key`: `vent_bathroom_fan_cfm`, `vent_static_pressure`, `vent_continuous_duty_motor_evidence`, `vent_backdraft_damper_evidence`, `vent_ducting_evidence`, `vent_main_bathroom_evidence`, `vent_direct_exterior_ducting_evidence`

**Traceability keys in system:**

- GenAI `rule_key=vent_product_or_capacity_evidence_present`.
- GenAI `rule_key=vent_not_generic_ductwork_only`.

**Missing now:**

- Most bathroom-fan technical subrequirements are still review-oriented and not backed by a structured deterministic validator.

### 4. Partial (High) — key: `not_yet_keyed`

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install ventilation upgrades... Heat/energy recovery ventilators must be installed by a licensed HVAC contractor...

**Evidence sources required:** database

**How this check should be done:** code

**Likely located fields required:** none

**Traceability keys in system:**

- Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer.

**Missing now:**

- No persisted claim-layer rulecheck currently traces this ventilation contractor-registration requirement as its own explicit audit result.
- No persisted licensed-HVAC validator currently enforces these sentences.

### 5. Implemented now (Medium) — key: `income_level_allows_rebate`

**Source quote:** Ventilation... 95% or 60% of eligible upgrade costs... up to a maximum of $1,600 per home... Invoice... must show the itemized CleanBC rebate... within six (6) months...

**Evidence sources required:** invoice_pdf, database

**How this check should be done:** genai

**Likely located fields required:** vent_line_amount, upgrade_specific_rebate_line_amount

**Traceability keys in system:**

- GenAI `rule_key=income_level_allows_rebate`.
- GenAI `rule_key=vent_rebate_math_within_cap`.
- GenAI `rule_key=vent_description_sufficient_for_review`.
- GenAI `rule_key=rebate_line_evidence_present`.
- Code `rule_key=submission_within_six_months`.

## Appendix: Proposed Future Supplement Registry Keys

This appendix is the forward-looking registry for supplement-related keys that are not all implemented yet.

### Proposed `supporting_documents.supplement_type` keys

- `approved_heat_load_calculation`
- `before_after_photo_set`
- `certification_sheet`
- `commissioning_or_control_document`
- `energy_performance_label`
- `energy_star_label`
- `f280_heat_load_calculation`
- `floor_plan_document`
- `fossil_fuel_removal_proof`
- `fossil_modification_or_removal_proof`
- `fossil_removal_proof`
- `income_verification_document`
- `landlord_consent_form`
- `manufacturer_label_photo`
- `non_integrated_area_preapproval_notice`
- `oil_removal_proof`
- `permit_document`
- `preapproval_notice`
- `preapproval_quote`
- `product_spec_sheet`
- `utility_bill_or_account_document`
- `utility_bill_or_invoice`
- `utility_invoice`
- `utility_upgrade_document`
- `wett_report`

### Proposed future supplement `field_key` values

- `atw_make_model`
- `brand_and_model`
- `certification_body`
- `cpd_number`
- `cshp_make_model`
- `hpwh_fossil_removal_date_or_permit_reference`
- `hpwh_manufacturer`
- `hpwh_model_number`
- `hpwh_neea_reference`
- `hpwh_tier_reference`
- `metric_u_factor`
- `new_service_size`
- `nrcan_number`
- `previous_service_size`
- `removal_date_or_permit_reference`
- `switchover_setpoint`
- `vent_backdraft_damper_evidence`
- `vent_bathroom_fan_cfm`
- `vent_continuous_duty_motor_evidence`
- `vent_direct_exterior_ducting_evidence`
- `vent_ducting_evidence`
- `vent_energy_star_reference`
- `vent_main_bathroom_evidence`
- `vent_nrcan_or_product_list_reference`
- `vent_static_pressure`

### Proposed future supplement-related `rule_key` values

- `ashp_electric_f280_document_present`
- `ashp_gas_propane_f280_document_present`
- `ashp_gas_propane_fossil_removal_proof_present`
- `ashp_gas_propane_non_integrated_area_preapproval_present`
- `ashp_gas_propane_removal_date_or_permit_present`
- `ashp_gas_propane_removal_proof_present`
- `ashp_oil_f280_document_present`
- `ashp_oil_non_integrated_area_preapproval_present`
- `ashp_oil_removal_date_or_permit_present`
- `ashp_oil_removal_proof_present`
- `ashp_wood_before_after_photo_set_present`
- `ashp_wood_f280_document_present`
- `ashp_wood_wett_report_present`
- `atw_before_after_photo_set_present`
- `atw_fossil_removal_proof_present`
- `atw_heat_load_document_present`
- `atw_make_model_from_supporting_document_present`
- `atw_non_integrated_area_preapproval_present`
- `atw_product_spec_document_present`
- `atw_wett_report_present`
- `cshp_before_after_photo_set_present`
- `cshp_fossil_removal_proof_present`
- `cshp_heat_load_document_present`
- `cshp_make_model_from_supporting_document_present`
- `cshp_product_spec_document_present`
- `cshp_wett_report_present`
- `dfhp_control_document_present`
- `dfhp_fossil_modification_proof_present`
- `dfhp_heat_load_document_present`
- `dfhp_non_integrated_area_preapproval_present`
- `dfhp_switchover_setpoint_valid`
- `esu_service_size_values_present`
- `esu_utility_invoice_present`
- `esu_utility_upgrade_document_present`
- `hpwh_fossil_removal_proof_present`
- `hpwh_label_or_spec_product_identifiers_present`
- `hpwh_neea_reference_present`
- `hpwh_non_integrated_area_preapproval_present`
- `hpwh_permit_or_removal_date_present`
- `hpwh_product_spec_document_present`
- `hs_before_after_photo_set_present`
- `income_verification_document_present`
- `income_verification_documents_complete`
- `ins_before_after_photo_set_present`
- `ins_floor_plan_document_present`
- `landlord_consent_document_present`
- `utility_account_name_matches_resident`
- `utility_account_supporting_document_present`
- `vent_bathroom_fan_spec_values_present`
- `vent_energy_star_supporting_document_present`
- `vent_product_spec_document_present`
- `vent_product_spec_values_present`
- `wd_certification_body_valid`
- `wd_certification_document_present`
- `wd_manufacturer_label_photo_present`
- `wd_preapproval_approved_before_installation`
- `wd_preapproval_document_present`
- `wd_u_factor_from_supporting_document_valid`

## Appendix: Implemented Runtime Mapping By Upgrade Type

This appendix shows the normalized seeded runtime mapping in the direction admins usually think about it:

- one upgrade type at a time
- then the exact implemented keys relevant to that upgrade type

Interpretation rules:

- Every non-common upgrade-specific runtime call also inherits the `common` mapping below.
- Shared normalized keys are intentionally repeated under each relevant upgrade type so a search for one taxonomy gives a complete view.
- The eight `code_field_key` values are common runtime database facts and apply across all upgrade types.

### Common runtime `code_field_key` values shared across all upgrade types

- `contractors.address`
- `contractors.business_name`
- `invoices.submitted_at`
- `users.participant_name`
- `users_eligibilitycodes.approved_at`
- `users_eligibilitycodes.eligibility_code`
- `users_eligibilitycodes.expires_at`
- `users_eligibilitycodes.income_level`

### Common invoice evidence (`common`)

- Implemented `code_rule_key`: `eligibility_code_valid_for_invoice_date`, `first_class_invoice_fields_present`, `source_vintage_applies`, `submission_within_six_months`
- Implemented `genai_rule_key`: `contractor_identity_matches_record`, `homeowner_identity_matches_eligibility_record`, `overall_invoice_arithmetic_consistent`, `overall_rebate_not_over_invoice_total`, `rebate_line_evidence_present`, `upgrade_type_evidence_present`, `warranty_costs_flag`
- Implemented `genai_field_key`: `amount_due_after_rebate`, `contractor_gst_number`, `customer_deposit`, `eligibility_code`, `invoice_contractor_address`, `invoice_contractor_name`, `invoice_homeowner_name`, `invoice_upgrade_type_evidence`, `labour_cost_invoice_total`, `overall_rebate_line_amount`, `overall_rebate_line_description`

### Windows and doors (`windows_doors`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `wd_certification_reference_present`, `wd_customer_portion_math_matches`, `wd_description_sufficient_for_review`, `wd_envelope_replacement_evidence_present`, `wd_income_level_and_vancouver_review`, `wd_label_photo_reference_present`, `wd_no_skylights`, `wd_per_home_rebate_math_within_cap`, `wd_per_unit_rebate_math_within_cap`, `wd_quote_preapproval_reference_present`, `wd_rough_opening_evidence_present`
- Implemented `genai_field_key`: `brand_and_model`, `certification_body_reference`, `city_of_vancouver_evidence`, `cpd_number`, `envelope_replacement_evidence`, `hardware_per_unit`, `labour_per_unit`, `manufacturer_label_photo_reference`, `metric_u_factor`, `nrcan_number`, `pane_count`, `quote_preapproval_reference`, `rough_opening_count`, `skylight_detected`, `upgrade_specific_rebate_line_amount`, `wd_registered_contractor_evidence`, `window_or_door_line_amount`, `window_or_door_quantity`

### Air source heat pump - convert from electric (`air_source_heat_pump_electric`)

- Implemented `code_rule_key`: `hp_ahri_found_in_product_list`, `hp_product_efficiency_threshold`, `hp_product_minimum_capacity_at_minus_5c`
- Implemented `genai_rule_key`: `ashp_electric_existing_heat_context_present`, `ashp_electric_main_living_area_or_primary_capacity_present`, `ashp_electric_no_existing_heat_pump_flag`, `ashp_electric_primary_system_scope_present`, `ashp_electric_rebate_math_within_cap`, `hp_description_sufficient_for_review`, `hp_product_reference_present`
- Implemented `genai_field_key`: `hp_ahri_reference`, `hp_efficiency_and_capacity`, `hp_existing_electric_heat_evidence`, `hp_existing_heat_pump_flag`, `hp_heat_load_calc_reference`, `hp_installation_labour_amount`, `hp_line_amount`, `hp_main_living_area_evidence`, `hp_make_model`, `hp_new_equipment_type`, `hp_product_list_reference`, `hp_registered_contractor_or_permit_evidence`, `upgrade_specific_rebate_line_amount`

### Air source heat pump - convert from wood (`air_source_heat_pump_wood`)

- Implemented `code_rule_key`: `hp_ahri_found_in_product_list`, `hp_product_efficiency_threshold`, `hp_product_minimum_capacity_at_minus_5c`
- Implemented `genai_rule_key`: `ashp_wood_backup_and_primary_capacity_review`, `ashp_wood_existing_heat_context_present`, `ashp_wood_no_existing_heat_pump_flag`, `ashp_wood_rebate_math_within_cap`, `ashp_wood_removal_or_wett_reference_present`, `hp_description_sufficient_for_review`, `hp_product_reference_present`
- Implemented `genai_field_key`: `hp_ahri_reference`, `hp_backup_heat_evidence`, `hp_efficiency_and_capacity`, `hp_existing_heat_pump_flag`, `hp_existing_wood_heat_evidence`, `hp_heat_load_calc_reference`, `hp_line_amount`, `hp_main_living_area_evidence`, `hp_make_model`, `hp_new_equipment_type`, `hp_product_list_reference`, `hp_registered_contractor_or_permit_evidence`, `hp_wood_system_removal_or_wett_evidence`, `upgrade_specific_rebate_line_amount`

### Air source heat pump - convert from natural gas or propane (`air_source_heat_pump_gas_propane`)

- Implemented `code_rule_key`: `hp_ahri_found_in_product_list`, `hp_product_efficiency_threshold`, `hp_product_minimum_capacity_at_minus_5c`
- Implemented `genai_rule_key`: `ashp_gas_propane_existing_heat_context_present`, `ashp_gas_propane_non_integrated_area_review`, `ashp_gas_propane_rebate_math_within_cap`, `ashp_gas_propane_removal_reference_present`, `hp_description_sufficient_for_review`, `hp_fossil_backup_not_fossil_primary`, `hp_fossil_no_existing_heat_pump_flag`, `hp_product_reference_present`
- Implemented `genai_field_key`: `hp_ahri_reference`, `hp_backup_heat_evidence`, `hp_efficiency_and_capacity`, `hp_existing_gas_propane_heat_evidence`, `hp_existing_heat_pump_flag`, `hp_fossil_combination_boiler_evidence`, `hp_fossil_fuel_removal_evidence`, `hp_heat_load_calc_reference`, `hp_line_amount`, `hp_make_model`, `hp_new_equipment_type`, `hp_non_integrated_area_preapproval_reference`, `hp_northern_top_up_evidence`, `hp_product_list_reference`, `upgrade_specific_rebate_line_amount`

### Air source heat pump - convert from oil (`air_source_heat_pump_oil`)

- Implemented `code_rule_key`: `hp_ahri_found_in_product_list`, `hp_product_efficiency_threshold`, `hp_product_minimum_capacity_at_minus_5c`
- Implemented `genai_rule_key`: `ashp_oil_consumption_baseline_reference_present`, `ashp_oil_existing_heat_context_present`, `ashp_oil_rebate_math_within_cap`, `ashp_oil_removal_reference_present`, `hp_description_sufficient_for_review`, `hp_fossil_backup_not_fossil_primary`, `hp_fossil_no_existing_heat_pump_flag`, `hp_product_reference_present`
- Implemented `genai_field_key`: `hp_ahri_reference`, `hp_backup_heat_evidence`, `hp_efficiency_and_capacity`, `hp_existing_heat_pump_flag`, `hp_existing_oil_heat_evidence`, `hp_fossil_combination_boiler_evidence`, `hp_heat_load_calc_reference`, `hp_line_amount`, `hp_make_model`, `hp_new_equipment_type`, `hp_non_integrated_area_preapproval_reference`, `hp_northern_top_up_evidence`, `hp_oil_consumption_baseline_evidence`, `hp_oil_system_removal_evidence`, `hp_product_list_reference`, `upgrade_specific_rebate_line_amount`

### Dual fuel ducted heat pump (`dual_fuel_ducted_heat_pump`)

- Implemented `code_rule_key`: `hp_ahri_found_in_product_list`, `hp_product_efficiency_threshold`, `hp_product_minimum_capacity_at_minus_5c`
- Implemented `genai_rule_key`: `dfhp_controls_reference_present`, `dfhp_description_sufficient_for_review`, `dfhp_dual_fuel_scope_present`, `dfhp_heat_load_calc_reference_present`, `dfhp_png_or_tank_propane_path_present`, `dfhp_rebate_math_within_cap`, `dfhp_switchover_setpoint_specific`
- Implemented `genai_field_key`: `dfhp_equipment_type`, `dfhp_existing_png_or_tank_propane_evidence`, `dfhp_fossil_modification_evidence`, `dfhp_heat_load_calc_reference`, `dfhp_line_amount`, `dfhp_make_model`, `dfhp_source_fuel_path`, `dfhp_switchover_setpoint_evidence`, `hp_ahri_reference`, `hp_northern_top_up_evidence`, `hp_registered_contractor_or_permit_evidence`, `upgrade_specific_rebate_line_amount`

### Air-to-water heat pump (`air_to_water_heat_pump`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `atw_not_combined_or_hpwh_scope`, `atw_rebate_math_within_cap`, `atw_scope_present`, `hp_description_sufficient_for_review`, `hydronic_conversion_context_present`, `hydronic_no_existing_heat_pump_flag`, `hydronic_product_reference_present`
- Implemented `genai_field_key`: `atw_equipment_type`, `atw_line_amount`, `atw_product_list_reference`, `atw_space_heating_only_evidence`, `hp_existing_heat_pump_flag`, `hp_heat_load_calc_reference`, `hp_make_model`, `hp_non_integrated_area_preapproval_reference`, `hp_northern_top_up_evidence`, `hydronic_conversion_source_fuel_evidence`, `hydronic_fossil_removal_evidence`, `hydronic_wood_removal_or_wett_evidence`, `upgrade_specific_rebate_line_amount`

### Combined space and water heat pump (`combined_space_water_heat_pump`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `cshp_combined_space_and_water_scope_present`, `cshp_rebate_math_within_cap`, `cshp_scope_present`, `hp_description_sufficient_for_review`, `hydronic_conversion_context_present`, `hydronic_no_existing_heat_pump_flag`, `hydronic_product_reference_present`
- Implemented `genai_field_key`: `cshp_domestic_hot_water_evidence`, `cshp_equipment_type`, `cshp_line_amount`, `cshp_product_list_reference`, `hp_existing_heat_pump_flag`, `hp_heat_load_calc_reference`, `hp_make_model`, `hp_non_integrated_area_preapproval_reference`, `hp_northern_top_up_evidence`, `hydronic_conversion_source_fuel_evidence`, `hydronic_fossil_removal_evidence`, `hydronic_wood_removal_or_wett_evidence`, `upgrade_specific_rebate_line_amount`

### Heat pump water heater (`heat_pump_water_heater`)

- Implemented `code_rule_key`: `hpwh_neea_found_in_product_list`, `hpwh_neea_tier_2_or_higher`
- Implemented `genai_rule_key`: `hpwh_description_sufficient_for_review`, `hpwh_fossil_removal_evidence_present`, `hpwh_no_existing_or_secondary_hpwh_flag`, `hpwh_non_integrated_area_review`, `hpwh_primary_replacement_context_present`, `hpwh_product_reference_present`, `hpwh_rebate_math_within_cap`, `hpwh_secondary_system_flag`
- Implemented `genai_field_key`: `hp_registered_contractor_or_permit_evidence`, `hpwh_existing_fuel_type`, `hpwh_existing_hpwh_flag`, `hpwh_existing_water_heater_evidence`, `hpwh_fossil_fuel_removal_evidence`, `hpwh_fossil_removal_date_or_permit`, `hpwh_line_amount`, `hpwh_make_model`, `hpwh_manufacturer`, `hpwh_model_components`, `hpwh_model_number`, `hpwh_neea_reference`, `hpwh_new_equipment_type`, `hpwh_non_integrated_area_preapproval_reference`, `hpwh_secondary_system_flag`, `hpwh_tier_reference`, `upgrade_specific_rebate_line_amount`

### Electrical service upgrade (`electrical_service_upgrade`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `esu_description_sufficient_for_review`, `esu_heat_pump_conversion_context_present`, `esu_not_panel_only_or_connection_only`, `esu_one_per_home_manual_review`, `esu_rebate_math_within_cap`, `esu_service_size_present`, `esu_timing_within_six_months_evidence`, `esu_utility_upgrade_evidence_present`
- Implemented `genai_field_key`: `esu_associated_heat_pump_or_hpwh_reference`, `esu_contractor_utility_management_evidence`, `esu_eligible_expense_lines`, `esu_fossil_to_heat_pump_context`, `esu_heat_pump_installation_date_reference`, `esu_ineligible_panel_only_evidence`, `esu_line_amount`, `esu_new_service_size`, `esu_permit_or_ahj_reference`, `esu_previous_service_size`, `esu_service_size`, `esu_utility_bill_or_invoice_reference`, `esu_utility_reference`, `upgrade_specific_rebate_line_amount`

### Insulation (`insulation`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `income_level_allows_rebate`, `ins_description_sufficient_for_review`, `ins_health_safety_issue_flag`, `ins_material_and_location_present`, `ins_minimum_r_value_and_boundary_present`, `ins_r_value_and_area_present`, `ins_rebate_math_within_cap`, `ins_supporting_document_reference_present`
- Implemented `genai_field_key`: `before_after_photo_reference`, `ins_area_square_feet`, `ins_conditioned_boundary_evidence`, `ins_existing_r_value`, `ins_floor_plan_reference`, `ins_health_safety_resolution_evidence`, `ins_line_amount`, `ins_location_specific_rebate_amount`, `ins_material_type`, `ins_minimum_r_value_requirement_evidence`, `ins_new_r_value`, `ins_r_value_added`, `ins_rebate_formula_or_rate_evidence`, `ins_registered_contractor_evidence`, `ins_removed_existing_insulation_evidence`, `ins_upgrade_location`, `upgrade_specific_rebate_line_amount`

### Ventilation (`ventilation`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `income_level_allows_rebate`, `vent_associated_upgrade_present`, `vent_description_sufficient_for_review`, `vent_not_generic_ductwork_only`, `vent_product_or_capacity_evidence_present`, `vent_rebate_math_within_cap`, `vent_standalone_flag`, `vent_system_type_present`
- Implemented `genai_field_key`: `upgrade_specific_rebate_line_amount`, `vent_associated_upgrade_evidence`, `vent_backdraft_damper_evidence`, `vent_bathroom_fan_cfm`, `vent_continuous_duty_motor_evidence`, `vent_contractor_license_evidence`, `vent_direct_exterior_ducting_evidence`, `vent_ducting_evidence`, `vent_energy_star_reference`, `vent_generic_ductwork_only_flag`, `vent_improved_air_circulation_evidence`, `vent_line_amount`, `vent_main_bathroom_evidence`, `vent_nrcan_or_product_list_reference`, `vent_static_pressure`, `vent_system_type`

### Health and safety remediation (`health_and_safety_remediation`)

- Implemented `code_rule_key`: none
- Implemented `genai_rule_key`: `hs_associated_upgrade_present`, `hs_before_after_photos_present`, `hs_description_sufficient_for_review`, `hs_issue_type_present`, `hs_not_standalone_flag`, `hs_pre_confirmation_evidence_present`, `hs_rebate_math_within_cap`, `income_level_allows_rebate`
- Implemented `genai_field_key`: `before_after_photo_reference`, `hs_associated_upgrade_evidence`, `hs_confirmation_date_or_reference`, `hs_issue_type`, `hs_line_amount`, `hs_pre_confirmation_reference`, `hs_registered_contractor_evidence`, `hs_remediation_scope`, `hs_resolution_completion_date`, `hs_technical_safety_or_permit_reference`, `upgrade_specific_rebate_line_amount`

## Appendix: Implemented Seeded Runtime Registry Keys

This appendix is the current complete implemented key registry from the active seed files.

- `claims_ai_service_ddl/5_insert_code_rules.sql`
- `claims_ai_service_ddl/5_insert_code_located_fields.sql`
- `claims_ai_service_ddl/5_insert_genai_normalized.sql`

Notes:

- `claims_ai_service_ddl/5_insert_validationgenai_rulesets.sql` is the compiled legacy-shaped runtime blob artifact. It does not introduce a separate authoritative key family beyond the normalized GenAI seeds and code families listed here.
- The goal of this appendix is simple: every currently seeded implemented key should appear somewhere in this tracker, even if an earlier requirement row did not explicitly name it.

### Implemented `code_rule_key` values

- `eligibility_code_valid_for_invoice_date`
- `first_class_invoice_fields_present`
- `hp_ahri_found_in_product_list`
- `hp_product_efficiency_threshold`
- `hp_product_minimum_capacity_at_minus_5c`
- `hpwh_neea_found_in_product_list`
- `hpwh_neea_tier_2_or_higher`
- `source_vintage_applies`
- `submission_within_six_months`

### Implemented `code_field_key` values

- `contractors.address`
- `contractors.business_name`
- `invoices.submitted_at`
- `users.participant_name`
- `users_eligibilitycodes.approved_at`
- `users_eligibilitycodes.eligibility_code`
- `users_eligibilitycodes.expires_at`
- `users_eligibilitycodes.income_level`

### Implemented `genai_rule_key` values

- `ashp_electric_existing_heat_context_present`
- `ashp_electric_main_living_area_or_primary_capacity_present`
- `ashp_electric_no_existing_heat_pump_flag`
- `ashp_electric_primary_system_scope_present`
- `ashp_electric_rebate_math_within_cap`
- `ashp_gas_propane_existing_heat_context_present`
- `ashp_gas_propane_non_integrated_area_review`
- `ashp_gas_propane_rebate_math_within_cap`
- `ashp_gas_propane_removal_reference_present`
- `ashp_oil_consumption_baseline_reference_present`
- `ashp_oil_existing_heat_context_present`
- `ashp_oil_rebate_math_within_cap`
- `ashp_oil_removal_reference_present`
- `ashp_wood_backup_and_primary_capacity_review`
- `ashp_wood_existing_heat_context_present`
- `ashp_wood_no_existing_heat_pump_flag`
- `ashp_wood_rebate_math_within_cap`
- `ashp_wood_removal_or_wett_reference_present`
- `atw_not_combined_or_hpwh_scope`
- `atw_rebate_math_within_cap`
- `atw_scope_present`
- `contractor_identity_matches_record`
- `cshp_combined_space_and_water_scope_present`
- `cshp_rebate_math_within_cap`
- `cshp_scope_present`
- `dfhp_controls_reference_present`
- `dfhp_description_sufficient_for_review`
- `dfhp_dual_fuel_scope_present`
- `dfhp_heat_load_calc_reference_present`
- `dfhp_png_or_tank_propane_path_present`
- `dfhp_rebate_math_within_cap`
- `dfhp_switchover_setpoint_specific`
- `esu_description_sufficient_for_review`
- `esu_heat_pump_conversion_context_present`
- `esu_not_panel_only_or_connection_only`
- `esu_one_per_home_manual_review`
- `esu_rebate_math_within_cap`
- `esu_service_size_present`
- `esu_timing_within_six_months_evidence`
- `esu_utility_upgrade_evidence_present`
- `homeowner_identity_matches_eligibility_record`
- `hp_description_sufficient_for_review`
- `hp_fossil_backup_not_fossil_primary`
- `hp_fossil_no_existing_heat_pump_flag`
- `hp_product_reference_present`
- `hpwh_description_sufficient_for_review`
- `hpwh_fossil_removal_evidence_present`
- `hpwh_no_existing_or_secondary_hpwh_flag`
- `hpwh_non_integrated_area_review`
- `hpwh_primary_replacement_context_present`
- `hpwh_product_reference_present`
- `hpwh_rebate_math_within_cap`
- `hpwh_secondary_system_flag`
- `hs_associated_upgrade_present`
- `hs_before_after_photos_present`
- `hs_description_sufficient_for_review`
- `hs_issue_type_present`
- `hs_not_standalone_flag`
- `hs_pre_confirmation_evidence_present`
- `hs_rebate_math_within_cap`
- `hydronic_conversion_context_present`
- `hydronic_no_existing_heat_pump_flag`
- `hydronic_product_reference_present`
- `income_level_allows_rebate`
- `ins_description_sufficient_for_review`
- `ins_health_safety_issue_flag`
- `ins_material_and_location_present`
- `ins_minimum_r_value_and_boundary_present`
- `ins_r_value_and_area_present`
- `ins_rebate_math_within_cap`
- `ins_supporting_document_reference_present`
- `overall_invoice_arithmetic_consistent`
- `overall_rebate_not_over_invoice_total`
- `rebate_line_evidence_present`
- `upgrade_type_evidence_present`
- `vent_associated_upgrade_present`
- `vent_description_sufficient_for_review`
- `vent_not_generic_ductwork_only`
- `vent_product_or_capacity_evidence_present`
- `vent_rebate_math_within_cap`
- `vent_standalone_flag`
- `vent_system_type_present`
- `warranty_costs_flag`
- `wd_certification_reference_present`
- `wd_customer_portion_math_matches`
- `wd_description_sufficient_for_review`
- `wd_envelope_replacement_evidence_present`
- `wd_income_level_and_vancouver_review`
- `wd_label_photo_reference_present`
- `wd_no_skylights`
- `wd_per_home_rebate_math_within_cap`
- `wd_per_unit_rebate_math_within_cap`
- `wd_quote_preapproval_reference_present`
- `wd_rough_opening_evidence_present`

### Implemented `genai_field_key` values

- `amount_due_after_rebate`
- `atw_equipment_type`
- `atw_line_amount`
- `atw_product_list_reference`
- `atw_space_heating_only_evidence`
- `before_after_photo_reference`
- `brand_and_model`
- `certification_body_reference`
- `city_of_vancouver_evidence`
- `contractor_gst_number`
- `cpd_number`
- `cshp_domestic_hot_water_evidence`
- `cshp_equipment_type`
- `cshp_line_amount`
- `cshp_product_list_reference`
- `customer_deposit`
- `dfhp_equipment_type`
- `dfhp_existing_png_or_tank_propane_evidence`
- `dfhp_fossil_modification_evidence`
- `dfhp_heat_load_calc_reference`
- `dfhp_line_amount`
- `dfhp_make_model`
- `dfhp_source_fuel_path`
- `dfhp_switchover_setpoint_evidence`
- `eligibility_code`
- `envelope_replacement_evidence`
- `esu_associated_heat_pump_or_hpwh_reference`
- `esu_contractor_utility_management_evidence`
- `esu_eligible_expense_lines`
- `esu_fossil_to_heat_pump_context`
- `esu_heat_pump_installation_date_reference`
- `esu_ineligible_panel_only_evidence`
- `esu_line_amount`
- `esu_new_service_size`
- `esu_permit_or_ahj_reference`
- `esu_previous_service_size`
- `esu_service_size`
- `esu_utility_bill_or_invoice_reference`
- `esu_utility_reference`
- `hardware_per_unit`
- `hp_ahri_reference`
- `hp_backup_heat_evidence`
- `hp_efficiency_and_capacity`
- `hp_existing_electric_heat_evidence`
- `hp_existing_gas_propane_heat_evidence`
- `hp_existing_heat_pump_flag`
- `hp_existing_oil_heat_evidence`
- `hp_existing_wood_heat_evidence`
- `hp_fossil_combination_boiler_evidence`
- `hp_fossil_fuel_removal_evidence`
- `hp_heat_load_calc_reference`
- `hp_installation_labour_amount`
- `hp_line_amount`
- `hp_main_living_area_evidence`
- `hp_make_model`
- `hp_new_equipment_type`
- `hp_non_integrated_area_preapproval_reference`
- `hp_northern_top_up_evidence`
- `hp_oil_consumption_baseline_evidence`
- `hp_oil_system_removal_evidence`
- `hp_product_list_reference`
- `hp_registered_contractor_or_permit_evidence`
- `hp_wood_system_removal_or_wett_evidence`
- `hpwh_existing_fuel_type`
- `hpwh_existing_hpwh_flag`
- `hpwh_existing_water_heater_evidence`
- `hpwh_fossil_fuel_removal_evidence`
- `hpwh_fossil_removal_date_or_permit`
- `hpwh_line_amount`
- `hpwh_make_model`
- `hpwh_manufacturer`
- `hpwh_model_components`
- `hpwh_model_number`
- `hpwh_neea_reference`
- `hpwh_new_equipment_type`
- `hpwh_non_integrated_area_preapproval_reference`
- `hpwh_secondary_system_flag`
- `hpwh_tier_reference`
- `hs_associated_upgrade_evidence`
- `hs_confirmation_date_or_reference`
- `hs_issue_type`
- `hs_line_amount`
- `hs_pre_confirmation_reference`
- `hs_registered_contractor_evidence`
- `hs_remediation_scope`
- `hs_resolution_completion_date`
- `hs_technical_safety_or_permit_reference`
- `hydronic_conversion_source_fuel_evidence`
- `hydronic_fossil_removal_evidence`
- `hydronic_wood_removal_or_wett_evidence`
- `ins_area_square_feet`
- `ins_conditioned_boundary_evidence`
- `ins_existing_r_value`
- `ins_floor_plan_reference`
- `ins_health_safety_resolution_evidence`
- `ins_line_amount`
- `ins_location_specific_rebate_amount`
- `ins_material_type`
- `ins_minimum_r_value_requirement_evidence`
- `ins_new_r_value`
- `ins_r_value_added`
- `ins_rebate_formula_or_rate_evidence`
- `ins_registered_contractor_evidence`
- `ins_removed_existing_insulation_evidence`
- `ins_upgrade_location`
- `invoice_contractor_address`
- `invoice_contractor_name`
- `invoice_homeowner_name`
- `invoice_upgrade_type_evidence`
- `labour_cost_invoice_total`
- `labour_per_unit`
- `manufacturer_label_photo_reference`
- `metric_u_factor`
- `nrcan_number`
- `overall_rebate_line_amount`
- `overall_rebate_line_description`
- `pane_count`
- `quote_preapproval_reference`
- `rough_opening_count`
- `skylight_detected`
- `upgrade_specific_rebate_line_amount`
- `vent_associated_upgrade_evidence`
- `vent_backdraft_damper_evidence`
- `vent_bathroom_fan_cfm`
- `vent_continuous_duty_motor_evidence`
- `vent_contractor_license_evidence`
- `vent_direct_exterior_ducting_evidence`
- `vent_ducting_evidence`
- `vent_energy_star_reference`
- `vent_generic_ductwork_only_flag`
- `vent_improved_air_circulation_evidence`
- `vent_line_amount`
- `vent_main_bathroom_evidence`
- `vent_nrcan_or_product_list_reference`
- `vent_static_pressure`
- `vent_system_type`
- `wd_registered_contractor_evidence`
- `window_or_door_line_amount`
- `window_or_door_quantity`
