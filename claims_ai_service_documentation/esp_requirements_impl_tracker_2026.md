## common

### 1. Implemented now (Low) - key: `source_vintage_applies`

**Source quote:** Effective date: For invoices dated on or after April 1, 2026.

**Evidence:** invoice_pdf

**Check:** code

**Fields:** none

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - source-vintage-applies`: Invoice date is after the April 1, 2026 effective date. Expected output: `source_vintage_applies` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 001 - source-vintage-applies`.

### 2. Partial (High) - key: `income_verification_supporting_documents_present`

**Source quote:** Participant must reside in an income qualified household... Income verification documentation must be submitted for each member of the household that is over the age of 18...

**Evidence:** database

**Check:** genai

**Fields:** none

**Support docs:** yes - types: income_verification_document; extracted fields: document_holder_name, document_date_or_tax_year, income_or_benefit_evidence, redaction_or_legibility_concern; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - income-verification-supporting-documents-present`: Income verification document fields are supplied for adult household member review. Expected output: `income_verification_supporting_documents_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 002 - income-verification-supporting-documents-present`.

**Note:** The GenAI seed now checks whether extracted income-document facts appear usable for household-income review. Final income-level eligibility still requires DB/admin validation of household membership and thresholds.

**Missing now:**

- No deterministic income-threshold or household-member coverage validator currently exists.
- Current implementation still relies on the eligibility-code path for final income-level approval.

### 3. Missing now (High) - not keyed yet

**Source quote:** Home must be a year-round primary residence in British Columbia that is at least 12 months old... The following types of homes are not eligible...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted `rule_key` currently enforces home-type, home-age, bulk-application, or ineligible-home exclusions from invoice/database evidence.

### 4. Partial (High) - key: `utility_account_supporting_document_present`

**Source quote:** The home must be connected to a residential account with one of the following utilities... The home must be primarily heated by one of the following...

**Evidence:** database, supporting_document

**Check:** genai

**Fields:** none

**Support docs:** yes - types: utility_bill_or_account_document; extracted fields: utility_provider, account_holder_name, service_address, account_or_bill_date, residential_account_evidence, strata_or_landlord_account_evidence, utility_service_type_or_fuel_evidence, account_number_or_reference, fuel_consumption_quantity_or_period; located-field table: yes

**Tests:**

- Rule 4 / `test 003 - utility-account-supporting-document-present`: Utility bill is residential, in participant name, at the claim address. Expected output: `utility_account_supporting_document_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 003 - utility-account-supporting-document-present`.

**Note:** The GenAI seed now checks the extracted utility-account facts for residential account, account-holder, service-address, strata/landlord concern, and utility/service-type evidence. Final eligible-utility-list and primary-heating validation is still review-oriented until the app has a deterministic utility/reference path.

**External source note:** No separate downloadable utility-eligibility feed is identified yet. Better Homes currently publishes the municipal-utility list as a webpage/FAQ, and the broader utility universe still reads as BC Hydro, FortisBC, and the named municipal utilities rather than a seeded product-style download. See:

- https://betterhomesbc.ca/faqs/municipal-utilities/
- https://betterhomesbc.ca/definitions/municipal-utilities/

**Missing now:**

- No deterministic eligible-utility-list validator currently exists.
- No deterministic primary-heating validator currently exists across all claim types.

### 5. Missing now (High) - not keyed yet

**Source quote:** The property must have a total assessed value at or under the referenced BC Assessment listing...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**External source note:** BC Assessment looks more like a licensed lookup path than a periodic seeded download. The public site exposes Assessment Search, and BC Assessment points users to BC OnLine for database access. Treat this as a realtime/licensed data-source investigation, not a new CSV/PDF seed like AHRI or NEEA. See:

- https://info.bcassessment.ca/Services-products/look-up-property-assessment
- https://www.bconline.gov.bc.ca/bc_assessment.html

**Missing now:**

- No persisted `rule_key` or `code_rule_key` currently validates the BC Assessment cap logic.

### 6. Partial (High) - key: `eligibility_code_valid_for_invoice_date`

**Source quote:** Participants must pre-register and confirm eligibility prior to installing upgrades. Eligibility codes... are valid for upgrades completed within 6 months of the participants approval date.

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Tests:**

- Rule 6 / `test 004 - eligibility-code-valid-for-invoice-date`: Eligibility code is approved before installation and remains within six months. Expected output: `eligibility_code_valid_for_invoice_date` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 004 - eligibility-code-valid-for-invoice-date`.

**Missing now:**

- No persisted check clearly proves pre-registration occurred before installation; current coverage is mainly date-validity logic tied to the eligibility code.

### 7. Partial (High) - key: `contractor_identity_matches_record`

**Source quote:** All upgrades must be installed by a Registered Contractor... Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.

**Evidence:** database, invoice_pdf

**Check:** genai

**Fields:** invoice_contractor_name, invoice_contractor_address

**Support docs:** no

**Tests:**

- Rule 7 / `test 005 - contractor-identity-matches-record`: Invoice contractor name and address match the contractor record. Expected output: `contractor_identity_matches_record` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 005 - contractor-identity-matches-record`.

**Missing now:**

- No persisted claim-layer rulecheck currently traces the upstream registered-contractor gate as its own explicit audit result.
- No persisted check currently enforces contractor terms/compliance status directly inside the claims rulecheck layer.

### 8. Missing now (High) - not keyed yet

**Source quote:** Participants may only receive one rebate payment... under any of the following programs...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted duplicate-history or cross-program one-rebate-per-upgrade check currently enforces this requirement end to end.

### 9. Implemented now (Medium) - key: `overall_rebate_not_over_invoice_total`

**Source quote:** Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade. Upgrade costs covered by warranty or home insurance are not eligible for rebates.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** overall_rebate_line_amount, overall_rebate_line_description, amount_due_after_rebate, customer_deposit

**Support docs:** no

**Tests:**

- Rule 9 / `test 006 - overall-rebate-not-over-invoice-total`: Total rebate is less than invoice total and no warranty-paid cost is claimed. Expected output: `overall_rebate_not_over_invoice_total` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 006 - overall-rebate-not-over-invoice-total`.

**Missing now:**

- Paid-cost versus financed/credited amounts still depends on visible invoice evidence and may need deeper payment-state integration later.

### 10. Missing now (High) - key: `homeowner_identity_matches_eligibility_record`

**Source quote:** Utility accounts must be in the name of the resident and/or homeowner... If you currently rent your home, the registered property owner must complete the Landlord Consent Form... Landlords and/or property owners are only eligible... with two eligible homes...

**Evidence:** database, supporting_document

**Check:** code

**Fields:** invoice_homeowner_name

**Support docs:** yes - types: utility_bill_or_account_document, landlord_consent_form; extracted fields: utility_provider, account_holder_name, service_address, account_or_bill_date, residential_account_evidence, strata_or_landlord_account_evidence, utility_service_type_or_fuel_evidence, account_number_or_reference, fuel_consumption_quantity_or_period, tenant_or_resident_name, property_owner_name, property_address, consent_signature_date, owner_signature_evidence, consented_upgrade_scope; located-field table: yes

**Tests:**

- Rule 10 / `test 007 - homeowner-identity-matches-eligibility-record`: Invoice homeowner/customer matches the eligibility participant name. Expected output: `homeowner_identity_matches_eligibility_record` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/common/test 007 - homeowner-identity-matches-eligibility-record`.

**Note:** The seed now extracts utility-account and landlord-consent facts; the missing work is final validation against participant/home/address rules.

**Missing now:**

- No persisted check currently validates utility-account ownership, landlord consent, or the two-home landlord cap.

## insulation

### 1. Implemented now (Medium) - key: `income_level_allows_rebate`

**Source quote:** Insulation upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - income-level-allows-rebate`: Insulation upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2. Expected output: `income_level_allows_rebate` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/insulation/test 001 - income-level-allows-rebate`.

### 2. Partial (High) - key: `ins_material_and_location_present`

**Source quote:** New insulation must be batt, loose fill, board or spray foam... installed in an eligible location... installed between a conditioned and unconditioned space... result in an increased R-value.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** ins_material_type, ins_upgrade_location, ins_conditioned_boundary_evidence, ins_new_r_value, ins_existing_r_value, ins_r_value_added

**Support docs:** no

**Tests:**

- Rule 2 / `test 002 - ins-material-and-location-present`: New insulation must be batt, loose fill, board or spray foam... installed in an eligible location... installed between a conditioned and unconditioned space... result in. Expected output: `ins_material_and_location_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/insulation/test 002 - ins-material-and-location-present`.

**Missing now:**

- No persisted check currently proves Best Practice Guide compliance.
- The conditioned/unconditioned-space and heat-loss intent portions still rely on review-oriented interpretation rather than a deterministic validator.

### 3. Partial (Medium) - key: `ins_r_value_and_area_present`

**Source quote:** Rebates are calculated based on R-value of the new insulation added... If pre-existing insulation was removed... the rebate is calculated on the difference in R-value...

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** ins_new_r_value, ins_existing_r_value, ins_r_value_added, ins_area_square_feet, ins_line_amount, upgrade_specific_rebate_line_amount, ins_location_specific_rebate_amount, ins_rebate_formula_or_rate_evidence

**Support docs:** no

**Tests:**

- Rule 3 / `test 003 - ins-r-value-and-area-present`: Rebates are calculated based on R-value of the new insulation added... If pre-existing insulation was removed... the rebate is calculated on the difference in R-value. Expected output: `ins_r_value_and_area_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/insulation/test 003 - ins-r-value-and-area-present`.

**Missing now:**

- No persisted check currently models the pre-existing-insulation-difference calculation path explicitly.

### 4. Partial (High) - key: `ins_health_safety_issue_flag`

**Source quote:** Pest infestations and rodent tunnels... must be resolved prior to installation... Any existing health and safety concerns (vermiculite, asbestos, mould)... must be resolved prior to installation...

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** ins_removed_existing_insulation_evidence, ins_health_safety_resolution_evidence

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - ins-health-safety-issue-flag`: Pest infestations and rodent tunnels... must be resolved prior to installation... Any existing health and safety concerns (vermiculite, asbestos, mould)... must be resolv. Expected output: `ins_health_safety_issue_flag` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/insulation/test 004 - ins-health-safety-issue-flag`.

**Missing now:**

- No persisted check currently proves pest or rodent resolution.
- No persisted supplement workflow currently validates the remediation evidence itself.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install insulation...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this insulation contractor-registration requirement as its own explicit audit result.

### 6. Partial (High) - key: `ins_supporting_document_reference_present`

**Source quote:** Before and after photos of the insulation area... Floor plan drawing... may be requested. Invoice... must show the itemized CleanBC rebate and deduct the CleanBC rebate... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** ins_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: before_after_photo_set, floor_plan_document; extracted fields: before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence, floor_plan_area_reference, floor_plan_location_or_scope, floor_plan_dimensions_or_square_feet, floor_plan_address_or_project_reference, floor_plan_legibility_concern; located-field table: yes

**Tests:**

- Rule 6 / `test 005 - ins-supporting-document-reference-present`: Before and after photos of the insulation area... Floor plan drawing... may be requested. Invoice... must show the itemized CleanBC rebate and deduct the CleanBC rebate. Expected output: `ins_supporting_document_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/insulation/test 005 - ins-supporting-document-reference-present`.

**Note:** The seed extracts before/after photo fields and floor-plan area/location/legibility fields; final sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final validation of photo/floor-plan sufficiency is still review-oriented.

## windows_doors

### 1. Implemented now (Medium) - key: `wd_income_level_and_vancouver_review`

**Source quote:** Windows and doors upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2... Homes within the City of Vancouver municipal boundary are not eligible...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** city_of_vancouver_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - wd-income-level-and-vancouver-review`: Windows and doors upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2... Homes within the City of Vancouver municipal bound. Expected output: `wd_income_level_and_vancouver_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 001 - wd-income-level-and-vancouver-review`.

### 2. Partial (High) - key: `wd_quote_preapproval_reference_present`

**Source quote:** Pre-approval is required; a quote for windows and doors upgrades must be submitted and approved prior to installation.

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** yes - types: preapproval_quote, preapproval_notice; extracted fields: quote_date, quote_reference, quoted_upgrade_scope, property_or_participant_reference, approval_submission_evidence, quoted_cost_or_amount, preapproval_date, approval_reference, approved_upgrade_scope, preapproval_condition_or_expiry, approval_status_or_decision; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - wd-quote-preapproval-reference-present`: Pre-approval is required; a quote for windows and doors upgrades must be submitted and approved prior to installation. Expected output: `wd_quote_preapproval_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 002 - wd-quote-preapproval-reference-present`.

**Note:** Treat this as supporting-document classification / presence unless later automation needs approval reference/date extraction.

**Missing now:**

- Current coverage looks for quote/pre-approval evidence, but there is no persisted system-level workflow validation proving the approval was actually granted.

### 3. Partial (High) - key: `wd_envelope_replacement_evidence_present`

**Source quote:** The new windows and/or doors must replace existing windows and doors in the building envelope... skylights are not eligible... be listed with one of the following certification bodies...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** envelope_replacement_evidence, skylight_detected

**Support docs:** yes - types: certification_sheet, energy_performance_label, manufacturer_label_photo; extracted fields: certification_body_reference, brand_and_model, model_number, metric_u_factor, cpd_number, nrcan_number, energy_star_reference, product_category_or_system_type, label_legibility_concern, serial_number, equipment_type_or_product_category, certification_or_listing_reference, installed_unit_location_or_count_evidence; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - wd-envelope-replacement-evidence-present`: The new windows and/or doors must replace existing windows and doors in the building envelope... skylights are not eligible... be listed with one of the following certifi. Expected output: `wd_envelope_replacement_evidence_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 003 - wd-envelope-replacement-evidence-present`.

**Note:** This is one of the clearest cases where true supplement-extracted facts would be useful if we automate certification validation.

**External source note:** No single Better Homes-owned downloadable certification list has been identified for this requirement. This currently reads more like certification-body evidence plus possible certification-body lookup/registry work than a straightforward new seeded download.

**Missing now:**

- No persisted check currently proves compliance with the Best Practices for Window and Door Replacement guide.
- Certification-body validation still relies on review-oriented evidence rather than a structured certification lookup.

### 4. Implemented now (Medium) - key: `wd_rough_opening_evidence_present`

**Source quote:** The number of windows and/or doors eligible for rebates is based on the number of Rough Openings...

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** rough_opening_count, window_or_door_quantity, pane_count

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - wd-rough-opening-evidence-present`: Two replacement rough openings are listed. Expected output: `wd_rough_opening_evidence_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 004 - wd-rough-opening-evidence-present`.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install windows and doors...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this windows-and-doors contractor-registration requirement as its own explicit audit result.

### 6. Implemented now (High) - key: `wd_u_factor_threshold`

**Source quote:** Install eligible window/doors with a U-factor of 1.22 (W/m2-K) or less...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** code

**Fields:** metric_u_factor

**Support docs:** yes - types: energy_performance_label, certification_sheet; extracted fields: brand_and_model, model_number, metric_u_factor, nrcan_number, energy_star_reference, product_category_or_system_type, label_legibility_concern, certification_body_reference, cpd_number; located-field table: yes

**Tests:**

- Rule 6 / `test 005 - wd-u-factor-threshold`: U-factor shown as 1.10 W/m2-K, below 1.22. Expected output: `wd_u_factor_threshold` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 005 - wd-u-factor-threshold`.

**Note:** If U-factor is proven from the supplement rather than the invoice, the value itself is a true extracted supplement field.

**External source note:** Same as the certification requirement above: no single program-owned downloadable window/door qualifying list was identified in this pass. This likely remains supplement evidence first, with any external validation coming from certification-body references rather than a seed file.

### 7. Implemented now (Medium) - key: `wd_per_unit_rebate_math_within_cap`

**Source quote:** 95% or 60% of eligible upgrade costs... $950 per window or door...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** window_or_door_line_amount, hardware_per_unit, labour_per_unit, upgrade_specific_rebate_line_amount

**Support docs:** no

**Tests:**

- Rule 7 / `test 006 - wd-per-unit-rebate-math-within-cap`: Per-unit rebate is at or below $950 and total is within the home cap. Expected output: `wd_per_unit_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 006 - wd-per-unit-rebate-math-within-cap`.

### 8. Partial (High) - key: `wd_label_photo_reference_present`

**Source quote:** A photo of a manufacturer label from each installed window/door... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** upgrade_specific_rebate_line_amount

**Support docs:** yes - types: manufacturer_label_photo; extracted fields: brand_and_model, model_number, serial_number, label_legibility_concern, equipment_type_or_product_category, certification_or_listing_reference, metric_u_factor, nrcan_number, cpd_number, installed_unit_location_or_count_evidence; located-field table: yes

**Tests:**

- Rule 8 / `test 007 - wd-label-photo-reference-present`: A photo of a manufacturer label from each installed window/door... The rebate application... must be submitted... within six (6) months of the invoice date. Expected output: `wd_label_photo_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/windows_doors/test 007 - wd-label-photo-reference-present`.

**Note:** The seed now extracts manufacturer-label facts and label quality concerns from this support-document type.

**Missing now:**

- The support-document extraction path exists, but final label-photo sufficiency validation is still review-oriented.

## air_source_heat_pump_electric

### 1. Missing now (High) - not keyed yet

**Source quote:** Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No electric-to-heat-pump-specific persisted income-level validator currently enforces this source sentence.

### 2. Implemented now (Medium) - key: `ashp_electric_existing_heat_context_present`

**Source quote:** The home must primarily be heated by electricity... The new heat pump must replace an existing hard-wired electric heating system... be sized to function as the primary heating system... serve a main living area...

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hp_existing_electric_heat_evidence, hp_main_living_area_evidence, hp_new_equipment_type

**Support docs:** no

**Tests:**

- Rule 2 / `test 001 - ashp-electric-existing-heat-context-present`: The home must primarily be heated by electricity... The new heat pump must replace an existing hard-wired electric heating system... be sized to function as the primary h. Expected output: `ashp_electric_existing_heat_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_electric/test 001 - ashp-electric-existing-heat-context-present`.

### 3. Partial (High) - key: `hp_product_reference_present`

**Source quote:** The new heat pump must have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List... SEER / HSPF thresholds... Minimum capacity of 12,000 BTU...

**Evidence:** external_list

**Check:** code

**Fields:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity

**Support docs:** no

**Tests:**

- Rule 3 / `test 002 - hp-product-reference-present`: The new heat pump must have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List... SEER / HSPF thresholds... Mi. Expected output: `hp_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_electric/test 002 - hp-product-reference-present`.

**External source note:** Existing download path already in place. The current seeded examples are the AHRI source tables in `claims_ai_service_ddl/3_insert_ahri_sources.sql`, which back the implemented `hp_ahri_found_in_product_list` and related heat-pump code rules.

**Missing now:**

- No persisted check currently proves installation-guide compliance.

### 4. Implemented now (Medium) - key: `ashp_electric_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hp_existing_heat_pump_flag

**Support docs:** no

**Tests:**

- Rule 4 / `test 003 - ashp-electric-no-existing-heat-pump-flag`: Invoice states no existing heat pump is being replaced or added to. Expected output: `ashp_electric_no_existing_heat_pump_flag` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_electric/test 003 - ashp-electric-no-existing-heat-pump-flag`.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) - key: `ashp_electric_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** hp_line_amount, upgrade_specific_rebate_line_amount, hp_new_equipment_type

**Support docs:** yes - types: f280_heat_load_calculation; extracted fields: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference; located-field table: yes

**Tests:**

- Rule 6 / `test 004 - ashp-electric-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... The rebate application... must be submitted... within six (6). Expected output: `ashp_electric_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_electric/test 004 - ashp-electric-rebate-math-within-cap`.

**Note:** The seed now extracts F280 calculation facts; final heat-load sufficiency validation is still review-oriented.

**Missing now:**

- The F280 support-document path is still review-oriented rather than structured supplement validation.

## air_source_heat_pump_wood

### 1. Missing now (High) - not keyed yet

**Source quote:** Wood to heat pump upgrade rebates are only eligible for participants who are registered and approved as Income Level 1 or 2...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No wood-to-heat-pump-specific persisted income-level validator currently enforces this source sentence.

### 2. Implemented now (Medium) - key: `ashp_wood_existing_heat_context_present`

**Source quote:** The home must primarily be heated by a wood or solid fuel heating system... The back-up heating system must be wood or electric. Fossil fuel back-up systems are not eligible...

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hp_existing_wood_heat_evidence, hp_backup_heat_evidence

**Support docs:** no

**Tests:**

- Rule 2 / `test 001 - ashp-wood-existing-heat-context-present`: The home must primarily be heated by a wood or solid fuel heating system... The back-up heating system must be wood or electric. Fossil fuel back-up systems are not eligi. Expected output: `ashp_wood_existing_heat_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_wood/test 001 - ashp-wood-existing-heat-context-present`.

### 3. Partial (High) - key: `hp_product_reference_present`

**Source quote:** The new heat pump must be sized... serve a main living area... have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List...

**Evidence:** external_list

**Check:** code

**Fields:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity, hp_main_living_area_evidence

**Support docs:** no

**Tests:**

- Rule 3 / `test 002 - hp-product-reference-present`: The new heat pump must be sized... serve a main living area... have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Prod. Expected output: `hp_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_wood/test 002 - hp-product-reference-present`.

**Missing now:**

- No persisted check currently proves installation-guide compliance.

### 4. Partial (High) - key: `ashp_wood_removal_or_wett_reference_present`

**Source quote:** The existing wood or solid fuel heating system may be retained in safe and working order or removed... Before and after photos... Copy of a WETT-certified inspection report...

**Evidence:** supporting_document

**Check:** code

**Fields:** none

**Support docs:** yes - types: before_after_photo_set, wett_report; extracted fields: before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence, wett_inspection_date, wett_inspector_certification_number, site_address, compliance_or_removal_conclusion, wett_inspector_or_company_name, wett_appliance_or_system_reference; located-field table: yes

**Tests:**

- Rule 4 / `test 003 - ashp-wood-removal-or-wett-reference-present`: The existing wood or solid fuel heating system may be retained in safe and working order or removed... Before and after photos... Copy of a WETT-certified inspection repo. Expected output: `ashp_wood_removal_or_wett_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_wood/test 003 - ashp-wood-removal-or-wett-reference-present`.

**Note:** The seed now extracts photo/WETT facts; final removal or WETT sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final photo/WETT sufficiency validation is still review-oriented.

### 5. Implemented now (Medium) - key: `ashp_wood_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hp_existing_heat_pump_flag

**Support docs:** no

**Tests:**

- Rule 5 / `test 004 - ashp-wood-no-existing-heat-pump-flag`: Invoice states no existing heat pump is being replaced or added to. Expected output: `ashp_wood_no_existing_heat_pump_flag` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_wood/test 004 - ashp-wood-no-existing-heat-pump-flag`.

### 6. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 7. Partial (High) - key: `ashp_wood_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... The rebate application... must be submitted... within six (6) months of the invoice date.

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** hp_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: f280_heat_load_calculation; extracted fields: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference; located-field table: yes

**Tests:**

- Rule 7 / `test 005 - ashp-wood-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... The rebate application... must be submitted... within six (6). Expected output: `ashp_wood_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_wood/test 005 - ashp-wood-rebate-math-within-cap`.

**Note:** The seed now extracts F280 calculation facts; final heat-load sufficiency validation is still review-oriented.

**Missing now:**

- The F280 support-document path remains review-oriented rather than structured supplement validation.

## air_source_heat_pump_gas_propane

### 1. Implemented now (Medium) - key: `ashp_gas_propane_existing_heat_context_present`

**Source quote:** The home must be primarily heated by fossil fuel (natural gas or propane)...

**Evidence:** database

**Check:** code

**Fields:** hp_existing_gas_propane_heat_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - ashp-gas-propane-existing-heat-context-present`: The home must be primarily heated by fossil fuel (natural gas or propane). Expected output: `ashp_gas_propane_existing_heat_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_gas_propane/test 001 - ashp-gas-propane-existing-heat-context-present`.

### 2. Partial (High) - key: `hp_product_reference_present`

**Source quote:** The new heat pump must be capable of distributing heat throughout all the conditioned space... replace the existing fossil fuel heating system... have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity

**Support docs:** yes - types: fossil_fuel_removal_proof; extracted fields: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - hp-product-reference-present`: The new heat pump must be capable of distributing heat throughout all the conditioned space... replace the existing fossil fuel heating system... have an AHRI certified r. Expected output: `hp_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_gas_propane/test 002 - hp-product-reference-present`.

**Note:** The seed now extracts fossil-fuel removal facts; final removal-proof sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists; final removal-proof/date/address/scope sufficiency is still review-oriented.

### 3. Partial (High) - key: `ashp_gas_propane_non_integrated_area_review`

**Source quote:** Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation.

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** yes - types: non_integrated_area_preapproval_notice; extracted fields: preapproval_date, approval_reference, non_integrated_area_evidence, approved_upgrade_scope, property_or_participant_reference; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - ashp-gas-propane-non-integrated-area-review`: Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation. Expected output: `ashp_gas_propane_non_integrated_area_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_gas_propane/test 003 - ashp-gas-propane-non-integrated-area-review`.

**Note:** Preapproval is currently best modeled as supporting-document subtype/presence plus DB context.

**Missing now:**

- Current coverage is review-only; no persisted system integration proves pre-approval happened.

### 4. Implemented now (Medium) - key: `hp_fossil_backup_not_fossil_primary`

**Source quote:** The back-up heating system must be electric or wood... Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hp_backup_heat_evidence, hp_existing_heat_pump_flag

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - hp-fossil-backup-not-fossil-primary`: Visible backup heat evidence is electric/wood, not fossil primary. Expected output: `hp_fossil_backup_not_fossil_primary` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_gas_propane/test 004 - hp-fossil-backup-not-fossil-primary`.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) - key: `ashp_gas_propane_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... The rebate application... must be submitted... within six (6) months...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** hp_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: f280_heat_load_calculation, fossil_fuel_removal_proof; extracted fields: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference, removed_equipment_type, removal_date_or_permit_reference, contractor_or_authority_name, removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 6 / `test 005 - ashp-gas-propane-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... The rebate application. Expected output: `ashp_gas_propane_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_gas_propane/test 005 - ashp-gas-propane-rebate-math-within-cap`.

**Note:** The seed now extracts F280 and fossil-fuel removal facts; final permit/date sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final F280/removal-proof validation is still review-oriented.

## air_source_heat_pump_oil

### 1. Implemented now (Medium) - key: `ashp_oil_existing_heat_context_present`

**Source quote:** The home must be primarily heated by oil... The home must meet a minimum oil consumption baseline of 500 Ltrs. annually...

**Evidence:** database

**Check:** code

**Fields:** hp_existing_oil_heat_evidence, hp_oil_consumption_baseline_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - ashp-oil-existing-heat-context-present`: The home must be primarily heated by oil... The home must meet a minimum oil consumption baseline of 500 Ltrs. annually. Expected output: `ashp_oil_existing_heat_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_oil/test 001 - ashp-oil-existing-heat-context-present`.

### 2. Partial (High) - key: `hp_product_reference_present`

**Source quote:** The new heat pump must... replace the existing fossil fuel heating system... have an AHRI certified reference number... be listed as a qualifying system on the Natural Resources Canada Oil to Heat Pump Affordability Qualified Heat Pump Product List...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** hp_make_model, hp_ahri_reference, hp_product_list_reference, hp_efficiency_and_capacity

**Support docs:** yes - types: oil_removal_proof; extracted fields: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - hp-product-reference-present`: The new heat pump must... replace the existing fossil fuel heating system... have an AHRI certified reference number... be listed as a qualifying system on the Natural Re. Expected output: `hp_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_oil/test 002 - hp-product-reference-present`.

**Note:** The seed now extracts oil-removal facts; final removal-proof sufficiency validation is still review-oriented.

**External source note:** This row is the one place where the source text explicitly names the Natural Resources Canada Oil to Heat Pump Affordability qualified list. Current implementation still rides the existing AHRI-based download path. If the client wants strict source fidelity here, this may justify a distinct download/source investigation beyond the current AHRI seed.

**Missing now:**

- The support-document extraction path exists; final oil-removal/date/address/scope sufficiency is still review-oriented.
- The code layer does not currently use a distinct Oil-to-Heat-Pump product list validator separate from the current AHRI path.

### 3. Partial (High) - key: `ashp_oil_non_integrated_area_review`

**Source quote:** Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation.

**Evidence:** supporting_document, database

**Check:** genai

**Fields:** hp_non_integrated_area_preapproval_reference

**Support docs:** yes - types: non_integrated_area_preapproval_notice; extracted fields: preapproval_date, approval_reference, non_integrated_area_evidence, approved_upgrade_scope, property_or_participant_reference; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - ashp-oil-non-integrated-area-review`: Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation. Expected output: `ashp_oil_non_integrated_area_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_oil/test 003 - ashp-oil-non-integrated-area-review`.

**Note:** Same interpretation as the gas/propane path; the new rule consumes the extracted Non-Integrated Area preapproval notice fields but final approval sufficiency remains review-oriented.

**Missing now:**

- Final approval/date/scope sufficiency is still review-oriented.

### 4. Implemented now (Medium) - key: `hp_fossil_backup_not_fossil_primary`

**Source quote:** The back-up heating system must be electric or wood... Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hp_backup_heat_evidence, hp_existing_heat_pump_flag

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - hp-fossil-backup-not-fossil-primary`: Visible backup heat evidence is electric/wood, not fossil primary. Expected output: `hp_fossil_backup_not_fossil_primary` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_oil/test 004 - hp-fossil-backup-not-fossil-primary`.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) - key: `ashp_oil_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel (oil) system removal... The rebate application... within six (6) months...

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** hp_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: f280_heat_load_calculation, oil_removal_proof; extracted fields: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference, removed_equipment_type, removal_date_or_permit_reference, contractor_or_authority_name, removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 6 / `test 005 - ashp-oil-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel (oil) system removal... The rebate applic. Expected output: `ashp_oil_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_source_heat_pump_oil/test 005 - ashp-oil-rebate-math-within-cap`.

**Note:** The seed now extracts F280 and oil-removal facts; final date/permit sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final F280/oil-removal validation is still review-oriented.

## dual_fuel_ducted_heat_pump

### 1. Implemented now (Medium) - key: `dfhp_png_or_tank_propane_path_present`

**Source quote:** The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG)...

**Evidence:** database

**Check:** code

**Fields:** dfhp_existing_png_or_tank_propane_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - dfhp-png-or-tank-propane-path-present`: The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG). Expected output: `dfhp_png_or_tank_propane_path_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/dual_fuel_ducted_heat_pump/test 001 - dfhp-png-or-tank-propane-path-present`.

### 2. Partial (High) - key: `dfhp_dual_fuel_scope_present`

**Source quote:** The new heat pump must be integrated with a propane or natural gas heating system... have the thermostat / outdoor temperature switch-over control set to the following region-specific temperatures... be sized to ensure it has the capacity to meet the home's heat demand...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** dfhp_equipment_type, hp_ahri_reference

**Support docs:** yes - types: commissioning_or_control_document, fossil_modification_or_removal_proof; extracted fields: commissioning_date, equipment_reference, switchover_setpoint, backup_fuel_or_integration_evidence, region_or_temperature_threshold_evidence, modified_or_removed_equipment_type, modification_or_removal_date_or_permit_reference, site_address, contractor_or_authority_name, modification_or_removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - dfhp-dual-fuel-scope-present`: The new heat pump must be integrated with a propane or natural gas heating system... have the thermostat / outdoor temperature switch-over control set to the following re. Expected output: `dfhp_dual_fuel_scope_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/dual_fuel_ducted_heat_pump/test 002 - dfhp-dual-fuel-scope-present`.

**Note:** The seed now extracts commissioning/control facts including switchover setpoint.

**Missing now:**

- The support-document extraction path exists, but final fossil-modification/removal validation is still review-oriented.

### 3. Partial (High) - key: `dfhp_heat_load_calc_reference_present`

**Source quote:** A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted.

**Evidence:** supporting_document

**Check:** code

**Fields:** none

**Support docs:** yes - types: approved_heat_load_calculation; extracted fields: calculation_date, site_address, design_heat_load_value, approval_or_professional_reference, calculation_standard_reference, approval_status_or_condition; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - dfhp-heat-load-calc-reference-present`: A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted. Expected output: `dfhp_heat_load_calc_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/dual_fuel_ducted_heat_pump/test 003 - dfhp-heat-load-calc-reference-present`.

**Note:** The seed now extracts approved heat-load calculation facts; final approval/sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists; final approved heat-load document sufficiency is still review-oriented.

### 4. Partial (High) - key: `dfhp_non_integrated_area_review`

**Source quote:** Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation.

**Evidence:** supporting_document, database

**Check:** genai

**Fields:** dfhp_source_fuel_path

**Support docs:** yes - types: non_integrated_area_preapproval_notice; extracted fields: preapproval_date, approval_reference, non_integrated_area_evidence, approved_upgrade_scope, property_or_participant_reference; located-field table: yes

**Tests:**

- Rule 4 / `test 004 - dfhp-non-integrated-area-review`: Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation. Expected output: `dfhp_non_integrated_area_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/dual_fuel_ducted_heat_pump/test 004 - dfhp-non-integrated-area-review`.

**Note:** The seed now extracts preapproval date/reference, Non-Integrated Area evidence, approved scope, and property/participant references; final approval sufficiency remains review-oriented.

**Missing now:**

- Final approval/date/scope sufficiency is still review-oriented.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) - key: `dfhp_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... Proof of fossil fuel system removal or modification... A copy of CSA-F280-12 Heat Load Calculation is required... within six (6) months...

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** dfhp_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: approved_heat_load_calculation, fossil_modification_or_removal_proof; extracted fields: calculation_date, site_address, design_heat_load_value, approval_or_professional_reference, calculation_standard_reference, approval_status_or_condition, modified_or_removed_equipment_type, modification_or_removal_date_or_permit_reference, contractor_or_authority_name, modification_or_removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 6 / `test 005 - dfhp-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... Proof of fossil fuel system removal or modification... A copy of CSA-F280-12 Heat Load Calculation is required... with. Expected output: `dfhp_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/dual_fuel_ducted_heat_pump/test 005 - dfhp-rebate-math-within-cap`.

**Note:** The seed now extracts approved heat-load calculation facts; final rebate-rule validation remains review-oriented.

**Missing now:**

- The support-document extraction path exists; final removal/modification-proof and heat-load sufficiency is still review-oriented.

## air_to_water_heat_pump

### 1. Implemented now (Medium) - key: `atw_scope_present`

**Source quote:** The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood...

**Evidence:** database

**Check:** code

**Fields:** atw_conversion_source_fuel_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - atw-scope-present`: The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood. Expected output: `atw_scope_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_to_water_heat_pump/test 001 - atw-scope-present`.

### 2. Partial (High) - key: `hydronic_product_reference_present`

**Source quote:** The new air-to-water heat pump must... be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** atw_product_list_reference

**Support docs:** yes - types: product_spec_sheet, manufacturer_label_photo; extracted fields: brand_and_model, model_number, efficiency_or_capacity_rating, product_list_reference, energy_star_reference, nrcan_reference, neea_reference, tier_reference, bathroom_fan_cfm, static_pressure, continuous_duty_motor_evidence, backdraft_damper_evidence, direct_exterior_ducting_evidence, main_bathroom_evidence, product_spec_legibility_concern, ahri_reference, capacity_btu_or_kw, seer_or_seer2_rating, hspf_or_hspf2_rating, duct_sealing_evidence, duct_insulation_r_value, installation_standard_or_guide_reference, serial_number, label_legibility_concern, equipment_type_or_product_category, certification_or_listing_reference, metric_u_factor, nrcan_number, cpd_number, installed_unit_location_or_count_evidence; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - hydronic-product-reference-present`: The new air-to-water heat pump must... be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List. Expected output: `hydronic_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_to_water_heat_pump/test 002 - hydronic-product-reference-present`.

**Note:** If the make/model is proved from supplement material rather than invoice text, it is a true extracted supplement field.

**External source note:** This looks like a real new downloadable-list candidate. Better Homes publishes the Air-to-Water and Combination Heat Pump qualified list directly, including a dedicated page and a PDF list. If we expand beyond AHRI/NEEA, this is one of the strongest next seeded-download candidates. See:

- https://www.betterhomesbc.ca/qualifyingairtowaterhp/
- https://betterhomesbc.ca/wp-content/uploads/2026/02/Air-to-Water-Eligibility-List-V10.pdf

**Missing now:**

- No persisted `code_rule_key` currently validates the air-to-water qualifying product list.
- No persisted check currently proves installation-guide compliance.

### 3. Partial (High) - key: `hydronic_conversion_context_present`

**Source quote:** If the new air-to-water heat pump replaces a fossil fuel heating system, all the fossil fuel heating equipment... must be removed... If it replaces a wood or solid fuel heating system, the existing wood or solid fuel heating system may be retained... or removed...

**Evidence:** supporting_document

**Check:** code

**Fields:** none

**Support docs:** yes - types: fossil_removal_proof, before_after_photo_set, wett_report; extracted fields: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, removal_scope_or_description, before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence, wett_inspection_date, wett_inspector_certification_number, compliance_or_removal_conclusion, wett_inspector_or_company_name, wett_appliance_or_system_reference; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - hydronic-conversion-context-present`: If the new air-to-water heat pump replaces a fossil fuel heating system, all the fossil fuel heating equipment... must be removed... If it replaces a wood or solid fuel h. Expected output: `hydronic_conversion_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_to_water_heat_pump/test 003 - hydronic-conversion-context-present`.

**Note:** The seed now extracts fossil-removal, photo, and WETT facts; final sufficiency validation is still review-oriented.

**Missing now:**

- No persisted check currently validates the fossil-fuel removal proof, wood-removal photos, or WETT-retention evidence.

### 4. Implemented now (Medium) - key: `hydronic_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** atw_existing_heat_pump_flag

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - hydronic-no-existing-heat-pump-flag`: Invoice states this is not a replacement/add-on/secondary heat pump. Expected output: `hydronic_no_existing_heat_pump_flag` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_to_water_heat_pump/test 004 - hydronic-no-existing-heat-pump-flag`.

### 5. Partial (High) - key: `hydronic_non_integrated_area_review`

**Source quote:** Homes in Non-Integrated Areas... must contact... for pre-approval...

**Evidence:** supporting_document, database

**Check:** genai

**Fields:** atw_non_integrated_area_preapproval_reference

**Support docs:** yes - types: non_integrated_area_preapproval_notice; extracted fields: preapproval_date, approval_reference, non_integrated_area_evidence, approved_upgrade_scope, property_or_participant_reference; located-field table: yes

**Tests:**

- Rule 5 / `test 005 - hydronic-non-integrated-area-review`: Homes in Non-Integrated Areas... must contact... for pre-approval. Expected output: `hydronic_non_integrated_area_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_to_water_heat_pump/test 005 - hydronic-non-integrated-area-review`.

**Note:** The new hydronic preapproval rule consumes the extracted Non-Integrated Area preapproval notice fields, but final approval/date/scope sufficiency remains review-oriented.

**Missing now:**

- Final approval/date/scope sufficiency is still review-oriented.

### 6. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 7. Partial (High) - key: `atw_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... Before and after photos of the wood or solid fuel heating system... WETT-certified inspection report...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** atw_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: f280_heat_load_calculation, fossil_removal_proof, before_after_photo_set, wett_report; extracted fields: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference, removed_equipment_type, removal_date_or_permit_reference, contractor_or_authority_name, removal_scope_or_description, before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence, wett_inspection_date, wett_inspector_certification_number, compliance_or_removal_conclusion, wett_inspector_or_company_name, wett_appliance_or_system_reference; located-field table: yes

**Tests:**

- Rule 7 / `test 006 - atw-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... Before and after photos. Expected output: `atw_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/air_to_water_heat_pump/test 006 - atw-rebate-math-within-cap`.

**Note:** Current path is still evidence-presence oriented.

**Missing now:**

- The support-document extraction path exists, but final F280/removal/photo/WETT validation is still review-oriented.

## combined_space_water_heat_pump

### 1. Implemented now (Medium) - key: `cshp_scope_present`

**Source quote:** The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood...

**Evidence:** database

**Check:** code

**Fields:** cshp_conversion_source_fuel_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - cshp-scope-present`: The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood. Expected output: `cshp_scope_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/combined_space_water_heat_pump/test 001 - cshp-scope-present`.

### 2. Partial (High) - key: `hydronic_product_reference_present`

**Source quote:** Combined space and water heat pump... Must be listed on the air-to-water and combined heat pump qualifying product list.

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** cshp_product_list_reference

**Support docs:** yes - types: product_spec_sheet, manufacturer_label_photo; extracted fields: brand_and_model, model_number, efficiency_or_capacity_rating, product_list_reference, energy_star_reference, nrcan_reference, neea_reference, tier_reference, bathroom_fan_cfm, static_pressure, continuous_duty_motor_evidence, backdraft_damper_evidence, direct_exterior_ducting_evidence, main_bathroom_evidence, product_spec_legibility_concern, ahri_reference, capacity_btu_or_kw, seer_or_seer2_rating, hspf_or_hspf2_rating, duct_sealing_evidence, duct_insulation_r_value, installation_standard_or_guide_reference, serial_number, label_legibility_concern, equipment_type_or_product_category, certification_or_listing_reference, metric_u_factor, nrcan_number, cpd_number, installed_unit_location_or_count_evidence; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - hydronic-product-reference-present`: Combined space and water heat pump... Must be listed on the air-to-water and combined heat pump qualifying product list. Expected output: `hydronic_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/combined_space_water_heat_pump/test 002 - hydronic-product-reference-present`.

**Note:** Make/model from supplement material is a genuine extracted fact if we automate it.

**External source note:** Same source path as the air-to-water row above. The Better Homes Air-to-Water and Combination Heat Pump qualified list appears to cover both air-to-water-only and combined systems, so this likely points to the same next seeded-download family rather than a separate one. See:

- https://www.betterhomesbc.ca/qualifyingairtowaterhp/
- https://betterhomesbc.ca/wp-content/uploads/2026/02/Air-to-Water-Eligibility-List-V10.pdf

**Missing now:**

- No persisted `code_rule_key` currently validates the combined-system qualifying product list.

### 3. Partial (High) - key: `hydronic_conversion_context_present`

**Source quote:** If the new air-to-water heat pump replaces a fossil fuel heating system... must be removed... If it replaces a wood or solid fuel heating system... may be retained in safe and working order or removed...

**Evidence:** supporting_document

**Check:** code

**Fields:** cshp_domestic_hot_water_evidence

**Support docs:** yes - types: fossil_removal_proof, before_after_photo_set, wett_report; extracted fields: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, removal_scope_or_description, before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence, wett_inspection_date, wett_inspector_certification_number, compliance_or_removal_conclusion, wett_inspector_or_company_name, wett_appliance_or_system_reference; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - hydronic-conversion-context-present`: If the new air-to-water heat pump replaces a fossil fuel heating system... must be removed... If it replaces a wood or solid fuel heating system... may be retained in saf. Expected output: `hydronic_conversion_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/combined_space_water_heat_pump/test 003 - hydronic-conversion-context-present`.

**Note:** The seed now extracts fossil-removal, photo, and WETT facts; final sufficiency validation is still review-oriented.

**Missing now:**

- No persisted check currently validates fossil-fuel removal proof, wood-removal photos, or WETT-retention evidence for this path.

### 4. Implemented now (Medium) - key: `hydronic_no_existing_heat_pump_flag`

**Source quote:** Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** cshp_existing_heat_pump_flag

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - hydronic-no-existing-heat-pump-flag`: Invoice states this is not a replacement/add-on/secondary heat pump. Expected output: `hydronic_no_existing_heat_pump_flag` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/combined_space_water_heat_pump/test 004 - hydronic-no-existing-heat-pump-flag`.

### 5. Partial (High) - key: `hydronic_non_integrated_area_review`

**Source quote:** Homes in Non-Integrated Areas... must contact... for pre-approval...

**Evidence:** supporting_document, database

**Check:** genai

**Fields:** cshp_non_integrated_area_preapproval_reference

**Support docs:** yes - types: non_integrated_area_preapproval_notice; extracted fields: preapproval_date, approval_reference, non_integrated_area_evidence, approved_upgrade_scope, property_or_participant_reference; located-field table: yes

**Tests:**

- Rule 5 / `test 005 - hydronic-non-integrated-area-review`: Homes in Non-Integrated Areas... must contact... for pre-approval. Expected output: `hydronic_non_integrated_area_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/combined_space_water_heat_pump/test 005 - hydronic-non-integrated-area-review`.

**Note:** The new hydronic preapproval rule consumes the extracted Non-Integrated Area preapproval notice fields, but final approval/date/scope sufficiency remains review-oriented.

**Missing now:**

- Final approval/date/scope sufficiency is still review-oriented.

### 6. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 7. Partial (High) - key: `cshp_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... Before and after photos... WETT-certified inspection report...

**Evidence:** invoice_pdf, supporting_document, database

**Check:** genai

**Fields:** cshp_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: f280_heat_load_calculation, fossil_removal_proof, before_after_photo_set, wett_report; extracted fields: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference, removed_equipment_type, removal_date_or_permit_reference, contractor_or_authority_name, removal_scope_or_description, before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence, wett_inspection_date, wett_inspector_certification_number, compliance_or_removal_conclusion, wett_inspector_or_company_name, wett_appliance_or_system_reference; located-field table: yes

**Tests:**

- Rule 7 / `test 006 - cshp-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... Proof of fossil fuel system removal... Before and after photos. Expected output: `cshp_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/combined_space_water_heat_pump/test 006 - cshp-rebate-math-within-cap`.

**Note:** The seed now extracts F280, fossil-removal, photo, and WETT facts; final sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final F280/removal/photo/WETT validation is still review-oriented.

## heat_pump_water_heater

### 1. Implemented now (Medium) - key: `hpwh_primary_replacement_context_present`

**Source quote:** The existing water heater being replaced must be the home's primary water heater.

**Evidence:** invoice_pdf

**Check:** code

**Fields:** hpwh_existing_water_heater_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - hpwh-primary-replacement-context-present`: The existing water heater being replaced must be the home's primary water heater. Expected output: `hpwh_primary_replacement_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/heat_pump_water_heater/test 001 - hpwh-primary-replacement-context-present`.

### 2. Implemented now (Low) - key: `hpwh_product_reference_present`

**Source quote:** Eligible systems are listed as Tier 2 or higher on NEEA's Advanced Water Heater Specification Qualified Products List...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** none

**Support docs:** yes - types: product_spec_sheet, manufacturer_label_photo; extracted fields: brand_and_model, model_number, efficiency_or_capacity_rating, product_list_reference, energy_star_reference, nrcan_reference, neea_reference, tier_reference, bathroom_fan_cfm, static_pressure, continuous_duty_motor_evidence, backdraft_damper_evidence, direct_exterior_ducting_evidence, main_bathroom_evidence, product_spec_legibility_concern, ahri_reference, capacity_btu_or_kw, seer_or_seer2_rating, hspf_or_hspf2_rating, duct_sealing_evidence, duct_insulation_r_value, installation_standard_or_guide_reference, serial_number, label_legibility_concern, equipment_type_or_product_category, certification_or_listing_reference, metric_u_factor, nrcan_number, cpd_number, installed_unit_location_or_count_evidence; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - hpwh-product-reference-present`: Eligible systems are listed as Tier 2 or higher on NEEA's Advanced Water Heater Specification Qualified Products List. Expected output: `hpwh_product_reference_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/heat_pump_water_heater/test 002 - hpwh-product-reference-present`.

**Note:** This is a strong supplement-field-table candidate because label/spec OCR can produce real persisted product facts.

**External source note:** Existing download path already in place. The current seeded example is the NEEA qualified-products source in `claims_ai_service_ddl/3_insert_neea_sources.sql`, backing `hpwh_neea_found_in_product_list` and `hpwh_neea_tier_2_or_higher`.

### 3. Partial (High) - key: `hpwh_fossil_removal_evidence_present`

**Source quote:** If the new heat pump water heater replaces a fossil fuel water heating system, all the fossil fuel heating equipment... must be removed or decommissioned... Homes in Non-Integrated Areas... must contact... for pre-approval...

**Evidence:** database

**Check:** code

**Fields:** hpwh_existing_fuel_type

**Support docs:** yes - types: fossil_fuel_removal_proof, non_integrated_area_preapproval_notice, permit_document; extracted fields: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, removal_scope_or_description, preapproval_date, approval_reference, non_integrated_area_evidence, approved_upgrade_scope, property_or_participant_reference, permit_number, permit_date, permit_address, authority_name, permit_scope_or_equipment_reference, permit_status_or_completion_evidence; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - hpwh-fossil-removal-evidence-present`: If the new heat pump water heater replaces a fossil fuel water heating system, all the fossil fuel heating equipment... must be removed or decommissioned... Homes in Non-. Expected output: `hpwh_fossil_removal_evidence_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/heat_pump_water_heater/test 003 - hpwh-fossil-removal-evidence-present`.

**Note:** The seed now extracts fossil-removal and permit facts; final permit/date sufficiency validation is still review-oriented.

**Missing now:**

- Current coverage is still review-oriented; no persisted structured supplement/external validator proves the removal or the non-integrated-area approval.

### 4. Implemented now (Medium) - key: `hpwh_secondary_system_flag`

**Source quote:** Replacing or adding a secondary heat pump water heater to a home with an existing heat pump water heater is not eligible.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hpwh_secondary_system_flag, hpwh_existing_hpwh_flag

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - hpwh-secondary-system-flag`: Invoice states this is the primary water heater replacement, not secondary. Expected output: `hpwh_secondary_system_flag` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/heat_pump_water_heater/test 004 - hpwh-secondary-system-flag`.

### 5. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 6. Partial (High) - key: `hpwh_rebate_math_within_cap`

**Source quote:** Invoice... must show the itemized CleanBC rebate... Proof of gas water heater removal... The rebate application... must be submitted... within six (6) months...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** hpwh_existing_fuel_type, hpwh_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** yes - types: fossil_fuel_removal_proof; extracted fields: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, removal_scope_or_description; located-field table: yes

**Tests:**

- Rule 6 / `test 005 - hpwh-rebate-math-within-cap`: Invoice... must show the itemized CleanBC rebate... Proof of gas water heater removal... The rebate application... must be submitted... within six (6) months. Expected output: `hpwh_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/heat_pump_water_heater/test 005 - hpwh-rebate-math-within-cap`.

**Note:** The seed now extracts fossil-fuel removal facts; final removal-proof sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final fossil-fuel-removal validation is still review-oriented.

## electrical_service_upgrade

### 1. Implemented now (Medium) - key: `esu_heat_pump_conversion_context_present`

**Source quote:** Only homes that convert from a fossil fuel primary space and/or water heating system to a heat pump... are eligible.

**Evidence:** invoice_pdf

**Check:** code

**Fields:** esu_fossil_to_heat_pump_context

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - esu-heat-pump-conversion-context-present`: Only homes that convert from a fossil fuel primary space and/or water heating system to a heat pump... are eligible. Expected output: `esu_heat_pump_conversion_context_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/electrical_service_upgrade/test 001 - esu-heat-pump-conversion-context-present`.

### 2. Partial (High) - key: `esu_utility_upgrade_evidence_present`

**Source quote:** The electric service (new wire) must be upgraded by the participant's electrical utility... The service upgrade... must be installed within six months of the heat pump installation.

**Evidence:** invoice_pdf, supporting_document

**Check:** genai

**Fields:** esu_utility_reference

**Support docs:** yes - types: utility_bill_or_invoice, utility_upgrade_document; extracted fields: utility_provider, previous_service_size, new_service_size, service_address, service_completion_or_invoice_date, utility_upgrade_cost_or_reference; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - esu-utility-upgrade-evidence-present`: The electric service (new wire) must be upgraded by the participant's electrical utility... The service upgrade... must be installed within six months of the heat pump in. Expected output: `esu_utility_upgrade_evidence_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/electrical_service_upgrade/test 002 - esu-utility-upgrade-evidence-present`.

**Note:** The seed now extracts utility service-size and service-reference facts; final utility-side validation is still review-oriented.

**External source note:** This looks more like utility-issued document evidence than a reusable central download. No general public utility-upgrade master list was identified in this pass; if automation is pursued here it likely depends on uploaded utility documents or direct utility-specific integrations rather than a seeded reference file.

**Missing now:**

- There is no persisted external/system validator that proves the utility actually performed the qualifying service upgrade.

### 3. Partial (Medium) - key: `esu_description_sufficient_for_review`

**Source quote:** Eligible expenses include utility connection fees, electrical panel or sub-panel upgrade, service mast alterations... labour.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** esu_eligible_expense_lines, esu_line_amount

**Support docs:** no

**Tests:**

- Rule 3 / `test 003 - esu-description-sufficient-for-review`: Eligible expenses include utility connection fees, electrical panel or sub-panel upgrade, service mast alterations... labour. Expected output: `esu_description_sufficient_for_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/electrical_service_upgrade/test 003 - esu-description-sufficient-for-review`.

**Missing now:**

- No persisted line-item classifier currently enforces the eligible-expense list deterministically.

### 4. Implemented now (Medium) - key: `esu_not_panel_only_or_connection_only`

**Source quote:** Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible.

**Evidence:** invoice_pdf

**Check:** code

**Fields:** esu_ineligible_panel_only_evidence

**Support docs:** no

**Tests:**

- Rule 4 / `test 004 - esu-not-panel-only-or-connection-only`: Invoice includes utility service/new-wire upgrade, not panel-only work. Expected output: `esu_not_panel_only_or_connection_only` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/electrical_service_upgrade/test 004 - esu-not-panel-only-or-connection-only`.

### 5. Partial (High) - key: `esu_contractor_utility_billed_work_on_one_invoice`

**Source quote:** If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice.

**Evidence:** invoice_pdf, supporting_document

**Check:** genai

**Fields:** esu_contractor_utility_management_evidence

**Support docs:** yes - types: utility_invoice; extracted fields: utility_provider, previous_service_size, new_service_size, service_address, service_completion_or_invoice_date, utility_upgrade_cost_or_reference; located-field table: yes

**Tests:**

- Rule 5 / `test 005 - esu-contractor-utility-billed-work-on-one-invoice`: If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice. Expected output: `esu_contractor_utility_billed_work_on_one_invoice` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/electrical_service_upgrade/test 005 - esu-contractor-utility-billed-work-on-one-invoice`.

**Note:** The GenAI seed now checks whether contractor-managed utility billing evidence appears to be included in the same invoice package. This is still evidence-review logic, not a utility-system integration.

**Missing now:**

- No deterministic utility billing integration currently proves the contractor and utility work were combined on one invoice when required.

### 6. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor... All upgrades must be completed in accordance with applicable by-laws...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.
- No persisted AHJ/by-law validation currently enforces these sentences.

### 7. Partial (High) - key: `esu_rebate_math_within_cap`

**Source quote:** Electrical service upgrade... up to a maximum... Maximum of one electrical service upgrade per home... Invoice... must show the itemized CleanBC rebate... within six (6) months...

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** esu_line_amount, upgrade_specific_rebate_line_amount, esu_new_service_size

**Support docs:** no

**Tests:**

- Rule 7 / `test 006 - esu-rebate-math-within-cap`: Electrical service upgrade... up to a maximum... Maximum of one electrical service upgrade per home... Invoice... must show the itemized CleanBC rebate... within six (6). Expected output: `esu_rebate_math_within_cap` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/electrical_service_upgrade/test 006 - esu-rebate-math-within-cap`.

**Missing now:**

- The one-per-home restriction is still manual-review oriented rather than a deterministic historical validator.

## health_and_safety_remediation

### 1. Implemented now (High) - key: `hs_issue_type_present`

**Source quote:** Remediation must be for existing health and safety issues... required to enable the safe installation and operation of a rebate-eligible upgrade... completed in association with an eligible upgrade... Rebates will not be paid for health and safety remediation on its own... confirmed as rebate-eligible prior to beginning remediation.

**Evidence:** invoice_pdf

**Check:** genai

**Fields:** hs_issue_type, hs_associated_upgrade_evidence, hs_remediation_scope

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - hs-issue-type-present`: Remediation must be for existing health and safety issues... required to enable the safe installation and operation of a rebate-eligible upgrade... completed in associati. Expected output: `hs_issue_type_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/health_and_safety_remediation/test 001 - hs-issue-type-present`.

**Missing now:**

- The pre-confirmation step is still evidence/review oriented rather than a wired workflow integration.

### 2. Partial (Medium) - not keyed yet

**Source quote:** All upgrades must be completed by a Registered Contractor who is approved to complete health and safety remediation...

**Evidence:** database

**Check:** code

**Fields:** hs_registered_contractor_evidence

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this health-and-safety contractor-registration requirement as its own explicit audit result.

### 3. Implemented now (Medium) - key: `hs_description_sufficient_for_review`

**Source quote:** Must be used to remediate pest, asbestos, structural and/or mould issues... Invoice... must show the itemized CleanBC rebate...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** hs_issue_type, hs_remediation_scope, hs_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** no

**Tests:**

- Rule 3 / `test 002 - hs-description-sufficient-for-review`: Must be used to remediate pest, asbestos, structural and/or mould issues... Invoice... must show the itemized CleanBC rebate. Expected output: `hs_description_sufficient_for_review` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/health_and_safety_remediation/test 002 - hs-description-sufficient-for-review`.

### 4. Partial (High) - key: `hs_before_after_photos_present`

**Source quote:** Before and after photos of the health and safety issue that was remediated.

**Evidence:** supporting_document

**Check:** code

**Fields:** none

**Support docs:** yes - types: before_after_photo_set; extracted fields: before_photo_evidence, after_photo_evidence, subject_area_evidence, visual_review_limitation, photo_pair_completeness_evidence; located-field table: yes

**Tests:**

- Rule 4 / `test 003 - hs-before-after-photos-present`: Before and after photo support document is supplied. Expected output: `hs_before_after_photos_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/health_and_safety_remediation/test 003 - hs-before-after-photos-present`.

**Note:** The seed now extracts before/after photo evidence fields; final photo sufficiency validation is still review-oriented.

**Missing now:**

- The support-document extraction path exists, but final photo sufficiency validation is still review-oriented.

### 5. Implemented now (Low) - key: `submission_within_six_months`

**Source quote:** The rebate application and supporting documentation must be submitted by the Registered Contractor within six (6) months of the invoice date.

**Evidence:** invoice_pdf, database

**Check:** code

**Fields:** none

**Support docs:** no

**Tests:**

- Rule 5 / `test 004 - submission-within-six-months`: Submission date is within six months of the invoice date. Expected output: `submission_within_six_months` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/health_and_safety_remediation/test 004 - submission-within-six-months`.

## ventilation

### 1. Implemented now (Medium) - key: `vent_associated_upgrade_present`

**Source quote:** Ventilation upgrades must be installed in association with a rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for ventilation upgrades on their own.

**Evidence:** invoice_pdf

**Check:** code

**Fields:** vent_associated_upgrade_evidence

**Support docs:** no

**Tests:**

- Rule 1 / `test 001 - vent-associated-upgrade-present`: Ventilation is billed with an eligible heat pump upgrade. Expected output: `vent_associated_upgrade_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/ventilation/test 001 - vent-associated-upgrade-present`.

### 2. Partial (High) - key: `vent_system_type_present`

**Source quote:** Heat/energy recovery ventilators must be ENERGY STAR certified and listed on Natural Resources Canada's searchable product list... be installed in accordance with the BC Housing Heat Recovery Ventilation Guide...

**Evidence:** invoice_pdf, supporting_document, external_list

**Check:** genai

**Fields:** vent_system_type

**Support docs:** yes - types: product_spec_sheet, energy_star_label; extracted fields: brand_and_model, model_number, efficiency_or_capacity_rating, product_list_reference, energy_star_reference, nrcan_reference, neea_reference, tier_reference, bathroom_fan_cfm, static_pressure, continuous_duty_motor_evidence, backdraft_damper_evidence, direct_exterior_ducting_evidence, main_bathroom_evidence, product_spec_legibility_concern, ahri_reference, capacity_btu_or_kw, seer_or_seer2_rating, hspf_or_hspf2_rating, duct_sealing_evidence, duct_insulation_r_value, installation_standard_or_guide_reference, product_category_or_system_type, label_legibility_concern; located-field table: yes

**Tests:**

- Rule 2 / `test 002 - vent-system-type-present`: Heat/energy recovery ventilators must be ENERGY STAR certified and listed on Natural Resources Canada's searchable product list... be installed in accordance with the BC. Expected output: `vent_system_type_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/ventilation/test 002 - vent-system-type-present`.

**Note:** If the Energy Star / NRCan proof is coming from supplement docs, those are true extracted facts.

**External source note:** An official NRCan searchable product list exists for ENERGY STAR certified products, including HRVs/ERVs, but this pass did not identify a simple seeded CSV/PDF equivalent like AHRI/NEEA. Treat this as a likely lookup/search integration or future scraper/API research item unless NRCan exposes a cleaner export path. See:

- https://prod-natural-resources.azure.cloud.nrcan-rncan.gc.ca/energy-efficiency/energy-star/products/list-certified-products
- https://natural-resources.canada.ca/energy-efficiency/energy-efficiency-regulations/energy-heat-recovery-ventilators

**Missing now:**

- No persisted structured validator currently checks the HRV/ERV product list or ENERGY STAR status.
- No persisted check currently proves the ventilation-guide installation requirement.

### 3. Partial (High) - key: `vent_product_or_capacity_evidence_present`

**Source quote:** Bathroom fan systems must... be ENERGY STAR certified... be ducted directly to the outside... have a capacity of at least 85 cfm... be rated for continuous duty... be equipped with self-closing backdraft damper... ducts must be sealed... ducts must be insulated to minimum R4...

**Evidence:** invoice_pdf, supporting_document

**Check:** genai

**Fields:** vent_system_type

**Support docs:** yes - types: product_spec_sheet, energy_star_label; extracted fields: brand_and_model, model_number, efficiency_or_capacity_rating, product_list_reference, energy_star_reference, nrcan_reference, neea_reference, tier_reference, bathroom_fan_cfm, static_pressure, continuous_duty_motor_evidence, backdraft_damper_evidence, direct_exterior_ducting_evidence, main_bathroom_evidence, product_spec_legibility_concern, ahri_reference, capacity_btu_or_kw, seer_or_seer2_rating, hspf_or_hspf2_rating, duct_sealing_evidence, duct_insulation_r_value, installation_standard_or_guide_reference, product_category_or_system_type, label_legibility_concern; located-field table: yes

**Tests:**

- Rule 3 / `test 003 - vent-product-or-capacity-evidence-present`: Bathroom fan systems must... be ENERGY STAR certified... be ducted directly to the outside... have a capacity of at least 85 cfm... be rated for continuous duty... be equ. Expected output: `vent_product_or_capacity_evidence_present` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/ventilation/test 003 - vent-product-or-capacity-evidence-present`.

**Note:** This is one of the clearest supplement-field-table cases because the spec-sheet values themselves matter.

**Missing now:**

- Most bathroom-fan technical subrequirements are still review-oriented and not backed by a structured deterministic validator.

### 4. Partial (High) - not keyed yet

**Source quote:** All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install ventilation upgrades... Heat/energy recovery ventilators must be installed by a licensed HVAC contractor...

**Evidence:** database

**Check:** code

**Fields:** none

**Support docs:** no

**Missing now:**

- No persisted claim-layer rulecheck currently traces this ventilation contractor-registration requirement as its own explicit audit result.
- No persisted licensed-HVAC validator currently enforces these sentences.

### 5. Implemented now (Medium) - key: `income_level_allows_rebate`

**Source quote:** Ventilation... 95% or 60% of eligible upgrade costs... up to a maximum of $1,600 per home... Invoice... must show the itemized CleanBC rebate... within six (6) months...

**Evidence:** invoice_pdf, database

**Check:** genai

**Fields:** vent_line_amount, upgrade_specific_rebate_line_amount

**Support docs:** no

**Tests:**

- Rule 5 / `test 004 - income-level-allows-rebate`: Ventilation... 95% or 60% of eligible upgrade costs... up to a maximum of $1,600 per home... Invoice... must show the itemized CleanBC rebate... within six (6) months. Expected output: `income_level_allows_rebate` returns `pass`. Test folder: `claims_ai_service_documentation/pdf test files/ventilation/test 004 - income-level-allows-rebate`.
