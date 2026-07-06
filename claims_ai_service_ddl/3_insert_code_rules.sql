BEGIN;

WITH code_rules_seed (
  id,
  code_rule_key,
  description,
  enabled,
  pass_admin_message,
  warn_admin_message,
  fail_admin_message,
  info_admin_message,
  admin_notes,
  created_at,
  updated_at
) AS (
  VALUES
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53021'::uuid,
    'hp_invoice_ahri_reference_present',
    'Checks whether the classifier stored an invoice AHRI reference in claims.invoice_version_located_fields for AHRI-backed heat-pump upgrade types.',
    true,
    'No follow-up is required when the classifier stored an invoice AHRI reference for this heat-pump upgrade type.',
    'Review the invoice and rerun classifier extraction if the AHRI reference is visible but no classifier AHRI field was stored.',
    NULL,
    NULL,
    'Reads claims.invoice_version_located_fields where source_engine=classifier and field_key=classifier.ahri_reference. This rule only checks presence of the invoice classifier AHRI field.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53022'::uuid,
    'hp_supporting_document_ahri_matches_invoice',
    'Checks whether AHRI evidence extracted from supporting product documents matches the classifier AHRI reference found on the invoice.',
    true,
    'No follow-up is required when supporting-document AHRI evidence matches the invoice classifier AHRI reference.',
    'Review the supporting product evidence when no supporting-document AHRI reference was extracted or the invoice AHRI is missing.',
    'Ask the contractor for corrected product evidence when supporting-document AHRI evidence conflicts with the invoice AHRI reference.',
    NULL,
    'Compares claims.invoice_version_located_fields source_engine=classifier field_key=classifier.ahri_reference with claims.supporting_document_located_fields field_key=ahri_reference for supporting documents on the same invoice version.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53023'::uuid,
    'hp_ahri_reference_found_in_product_list',
    'Checks whether the classifier AHRI reference found on the invoice exists in the current imported BC Hydro heat-pump product list.',
    true,
    'No follow-up is required when the invoice AHRI reference is found in the imported product list.',
    'Review the invoice AHRI reference when it is missing or when no current imported AHRI product-list rows are available.',
    'Ask the contractor for corrected product evidence when the invoice AHRI reference is not found in the imported product list.',
    NULL,
    'Reads claims.invoice_version_located_fields source_engine=classifier field_key=classifier.ahri_reference and searches claims.v_current_ahri_products. Supporting-document AHRI corroboration is handled by hp_supporting_document_ahri_matches_invoice.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53031'::uuid,
    'ashp_electric_rebate_math_within_cap',
    'Checks ASHP convert-from-electric rebate amount against the ASHP upgrade line amount and the Income Level 1/2 cap from the requirements table.',
    true,
    'No follow-up is required when the ASHP electric rebate is within the named upgrade amount and income-level cap.',
    'Review the invoice ASHP line amount, rebate line, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice ASHP line amount, rebate line, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Requirement PDF: AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC), requirements table after item 9. Uses ashp_upgrade_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53032'::uuid,
    'ashp_electric_product_specs_meet_requirements',
    'Checks the ASHP convert-from-electric requirements table product specs: efficiency threshold, variable speed compressor, and minimum 12,000 BTU capacity.',
    true,
    'No follow-up is required when the matched AHRI product row and named field evidence satisfy the product specification checks.',
    'Review the matched AHRI row and invoice/product evidence when a metric is missing or ambiguous.',
    'Confirm the AHRI match before asking the contractor for corrected product evidence.',
    'Resolve the AHRI product-list match first, then rerun checks.',
    'Requirement PDF: AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC), requirements table after item 9. Uses the matched AHRI product row plus hp_efficiency_and_capacity evidence for variable-speed wording.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53033'::uuid,
    'ashp_electric_multisplit_minimum_two_indoor_heads',
    'Checks that an ASHP convert-from-electric ductless multi-split installation has at least two indoor head units.',
    true,
    'No follow-up is required when the claim is not multi-split or the multi-split evidence supports at least two indoor heads.',
    'Review the invoice equipment section when a multi-split system is visible but the indoor-head count is not explicit.',
    'Ask the contractor for corrected invoice or product evidence if a ductless multi-split shows fewer than two indoor heads.',
    NULL,
    'Requirement PDF: AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC), requirements table after item 9. Uses hp_new_equipment_type and the matched AHRI source/product evidence.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53002'::uuid,
    'hp_product_minimum_capacity_at_minus_5c',
    'Checks whether the matched BC Hydro heat-pump product-list row shows rated capacity at -5C of at least 12,000 BTU.',
    true,
    'No follow-up is required for the -5C capacity threshold if the AHRI match is correct.',
    'Review the product-list row and invoice evidence before moving the claim forward.',
    'Confirm the AHRI match before asking the contractor for corrected product evidence.',
    'Resolve the AHRI product-list match first, then rerun checks.',
    'The code supplies the detailed capacity math and source values; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-05-14 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53003'::uuid,
    'hp_product_efficiency_threshold',
    'Checks whether the matched BC Hydro heat-pump product-list row meets either SEER/HSPF or SEER2/HSPF2 threshold requirements.',
    true,
    'No follow-up is required for the efficiency threshold if the AHRI match is correct.',
    'Review the product-list row and invoice evidence before moving the claim forward.',
    'Confirm the AHRI match before asking the contractor for corrected product evidence.',
    'Resolve the AHRI product-list match first, then rerun checks.',
    'The code supplies the detailed efficiency threshold comparison; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-05-14 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53101'::uuid,
    'hpwh_neea_found_in_product_list',
    'Checks whether the heat pump water heater manufacturer/model found on the invoice exists in the current imported NEEA Residential HPWH Qualified Products List.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched NEEA product-list row.',
    'Ask the contractor to provide corrected manufacturer/model evidence if the invoice does not clearly identify a NEEA-listed heat pump water heater.',
    'Ask the contractor for corrected product evidence or an eligible NEEA-listed heat pump water heater model.',
    NULL,
    'The code supplies the detailed NEEA match explanation; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-05-15 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53102'::uuid,
    'hpwh_neea_tier_2_or_higher',
    'Checks whether the matched NEEA heat pump water heater product-list row is Tier 2 or higher.',
    true,
    'No follow-up is required for the NEEA Tier 2+ threshold if the product-list match is correct.',
    'Review the NEEA product-list row and invoice evidence before moving the claim forward.',
    'Ask the contractor for corrected product evidence or an eligible Tier 2+ heat pump water heater model.',
    'Resolve the NEEA product-list match first, then rerun checks.',
    'The code supplies the detailed NEEA tier comparison; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-05-15 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53151'::uuid,
    'hydronic_product_found_in_qualifying_list',
    'Checks whether invoice and supporting-document air-to-water or combined heat pump product evidence match each other and exist in the current imported Better Homes BC Air-to-Water and Combination Heat Pump Qualifying Product List.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched Better Homes BC qualifying-list row.',
    'Refresh the AWHP product-list import if invoice and supporting-document product evidence agree but no current imported list rows are available.',
    'Ask the contractor for corrected invoice/supporting product evidence when product evidence is missing, conflicting, or not found in the imported qualifying list.',
    NULL,
    'The code supplies the detailed invoice/supporting-document product comparison and Better Homes BC qualifying-list match explanation; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-06-01 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53181'::uuid,
    'ashp_oil_ohpa_bc_product_found_in_list',
    'Checks whether the invoice AHRI reference matches AHRI evidence from a product_spec_sheet or manufacturer_label_photo, and exists in the current imported NRCan Oil to Heat Pump Affordability BC qualified product list.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched NRCan OHPA BC product-list row.',
    'Refresh the OHPA product-list import if invoice and supporting-document AHRI evidence agree but no current imported list rows are available.',
    'Ask the contractor for corrected invoice/supporting product evidence when AHRI evidence is missing, conflicting, or not found in the imported OHPA BC product list.',
    NULL,
    'The code supplies the detailed invoice/supporting-document AHRI comparison and NRCan OHPA BC product-list match explanation; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-06-02 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53201'::uuid,
    'source_vintage_applies',
    'Checks whether the invoice date falls under the current 2026-04-01 Energy Savings Program requirements vintage or whether an earlier requirements version may apply.',
    true,
    'No follow-up is required if the invoice date clearly falls on or after April 1, 2026.',
    'Confirm the invoice date and whether an earlier requirements version should be used before treating this as a material issue.',
    'Use the earlier applicable requirements version or correct the invoice-date evidence before continuing this review.',
    'The invoice date does not clearly decide which requirements version applies, so keep this in view during review.',
    'This is a core date-version gate for the current requirements set. Admins may disable it only if this control is intentionally handled elsewhere.',
    TIMESTAMP '2026-05-25 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53202'::uuid,
    'first_class_invoice_fields_present',
    'Checks whether these tracked first-class invoice fields needed for core invoice review are populated in the stored OCR/DI result: invoice number, invoice date, vendor name, customer name, subtotal, total tax, invoice total, and amount due. Address fields are intentionally excluded because DI may classify visible invoice addresses as customer, billing, service, or shipping addresses depending on layout.',
    true,
    'All tracked first-class invoice fields were populated by OCR/DI.',
    'One or more tracked first-class invoice fields were blank. Check the PDF and re-run extraction if the value is visible but missing. Address evidence is reviewed separately.',
    'Not used by this rule.',
    'Not used by this rule.',
    'This is a data-completeness guardrail for downstream invoice review; it does not prove the field values are correct.',
    TIMESTAMP '2026-05-25 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53203'::uuid,
    'submission_within_six_months',
    'Pseudocode:
if rule submission_within_six_months is not enabled for common:
  do not run

invoice_date = invoice_versions.di_ocr_invoice_date
submitted_at = claims.invoices.submitted_at

if invoice_date is missing or submitted_at is missing:
  rule_result = warn
  expected = "invoices.submitted_at <= invoice_date + 6 months"
  reason = say exactly which date is missing

deadline = invoice_date + 6 months
submitted_date = submitted_at.to_date

if submitted_date <= deadline:
  rule_result = pass
else:
  rule_result = fail

calculation =
  invoice_date + 6 months = deadline;
  submitted_date <= deadline => true/false',
    true,
    'No follow-up is required when the submission date clearly falls within six months of the invoice date.',
    'Confirm the invoice date or submitted date before deciding whether the six-month deadline was met.',
    'The invoice appears to have been submitted after the six-month deadline and needs correction or program review.',
    'This timing check passed with context worth surfacing to the reviewer.',
    'This is a core program deadline check using stored invoice and submission dates.',
    TIMESTAMP '2026-05-25 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53204'::uuid,
    'eligibility_code_valid_for_invoice_date',
    'Checks whether the invoice date is within six months of the matched eligibility-code approval date. The invoice date is currently used as the system proxy for upgrade completed date.

Pseudo-code:
invoice_date = invoice_versions.di_ocr_invoice_date
approval_date = matched users_eligibilitycodes.approved_at

if invoice_date is missing:
  warn
else if approval_date is missing:
  warn
else:
  deadline = approval_date + 6 months
  if approval_date <= invoice_date <= deadline:
    pass
  else:
    fail',
    true,
    'No follow-up is required when the invoice date clearly falls within six months of the eligibility-code approval date.',
    'Verify the eligibility-code approval date and invoice date before deciding whether the claim falls inside the six-month completion window.',
    'The invoice date appears to fall outside the six-month eligibility-code completion window and needs correction or program review.',
    'This eligibility timing check passed with context worth surfacing to the reviewer.',
    'This rule compares claims.users_eligibilitycodes.approved_at against claims.invoice_versions.di_ocr_invoice_date and intentionally does not use users_eligibilitycodes.expires_at.',
    TIMESTAMP '2026-05-25 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53206'::uuid,
    'eligibility_code_found_in_database',
    'Checks whether the classifier-located eligibility code resolved to a populated claims.users_eligibilitycodes record in the code-located-field snapshot.',
    true,
    'No follow-up is required when the matched database eligibility code is populated.',
    'Review the invoice-visible eligibility code and eligibility table if the matched database eligibility field is missing.',
    'Create or correct the eligibility-code record before approving if the invoice-visible eligibility code cannot be resolved to a database record.',
    NULL,
    'Reads claims.invoice_version_located_fields where source_engine=code and field_key=users_eligibilitycodes.eligibility_code; pass when populated, fail when missing.',
    TIMESTAMP '2026-06-04 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53207'::uuid,
    'prior_same_upgrade_type_rebate_payment_found',
    'Checks whether the matched participant already has a non-ineligible current invoice for the same one-rebate-limited upgrade area.

Pseudo-code:
primary_space_heating_upgrade_types = [
  air_source_heat_pump_electric,
  air_source_heat_pump_wood,
  air_source_heat_pump_gas_propane,
  air_source_heat_pump_oil,
  dual_fuel_ducted_heat_pump,
  air_to_water_heat_pump,
  combined_space_water_heat_pump
]

current_upgrade_types = upgrade_type_keys on this invoice version
prior_current_upgrade_types = upgrade_type_keys on current invoice versions for the same participant, excluding this invoice, where invoice status is not ineligible

current_has_space_heating = current_upgrade_types has any key in primary_space_heating_upgrade_types
prior_has_space_heating = prior_current_upgrade_types has any key in primary_space_heating_upgrade_types

fail if current_has_space_heating and prior_has_space_heating
fail if current has heat_pump_water_heater and prior has heat_pump_water_heater
fail if current has insulation and prior has insulation
fail if current has windows_doors and prior has windows_doors
otherwise pass',
    true,
    'No prior non-ineligible current invoice was found for the same participant and same one-rebate-limited upgrade area.',
    NULL,
    'This participant appears to already have a non-ineligible current invoice for the same one-rebate-limited upgrade area. Review the prior invoice before approving another payment.',
    NULL,
    'Uses invoice_versions.participant_user_id, current invoice versions for other invoice parents, claims.invoice_version_upgrade_types, and claims.invoices.status. Primary space heating is checked as one grouped area; heat pump water heater, insulation, and windows/doors are exact upgrade-type checks. The rule returns pass or fail only.',
    TIMESTAMP '2026-06-18 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53208'::uuid,
    'current_invoice_cannot_contain_multiple_space_systems',
    'Checks whether the current invoice version contains more than one primary space heating system upgrade type. This is intentionally separate from prior-rebate history so the failed aspect is clear and the code remains simple.

Pseudo-code:
primary_space_heating_upgrade_types = [
  air_source_heat_pump_electric,
  air_source_heat_pump_wood,
  air_source_heat_pump_gas_propane,
  air_source_heat_pump_oil,
  dual_fuel_ducted_heat_pump,
  air_to_water_heat_pump,
  combined_space_water_heat_pump
]

current_space_heating_upgrade_types = current invoice version upgrade_type_keys that are in primary_space_heating_upgrade_types

fail if count(current_space_heating_upgrade_types) > 1
otherwise pass',
    true,
    'The current invoice contains zero or one primary space heating system upgrade type.',
    NULL,
    'The current invoice appears to contain multiple primary space heating system upgrade types. Review the detected upgrade types before approving.',
    NULL,
    'Uses claims.invoice_version_upgrade_types for the current invoice version only. The rule returns pass or fail only.',
    TIMESTAMP '2026-06-24 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53205'::uuid,
    'income_level_1_or_2_required',
    'Checks whether the matched participant eligibility-code record has stored income_level 1 or 2 for upgrade types that are explicitly limited to Income Level 1 or 2 in the ESP requirements.',
    true,
    'No follow-up is required when the participant is registered and approved as Income Level 1 or 2.',
    'Verify the matched eligibility-code record before deciding whether this income-level requirement is met.',
    'The participant appears to be Income Level 3, which is not eligible for this upgrade type under the current ESP requirements.',
    NULL,
    'Reads claims.users_eligibilitycodes.income_level from code located fields and returns pass for 1/2, fail for 3, warn when missing.',
    TIMESTAMP '2026-06-01 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53301'::uuid,
    'wd_u_factor_threshold',
    'Checks whether the structured metric U-factor values extracted for windows and doors are 1.22 W/m2-K or less.',
    true,
    'No follow-up is required for the U-factor threshold when all extracted metric U-factor values are at or below 1.22 W/m2-K.',
    'Review the visible product/certification evidence and confirm the U-factor value before moving the claim forward.',
    'Ask the contractor for corrected product or certification evidence if the installed window/door U-factor exceeds 1.22 W/m2-K.',
    'Resolve the extracted U-factor evidence first, then rerun validation if needed.',
    'This rule compares structured metric U-factor values after the windows/doors GenAI located-field pass. It is intended to remain admin-configurable like other code rules.',
    TIMESTAMP '2026-05-28 00:00:00',
    NOW()
  )
)
INSERT INTO claims.code_rules (
  id,
  code_rule_key,
  description,
  enabled,
  pass_admin_message,
  warn_admin_message,
  fail_admin_message,
  info_admin_message,
  admin_notes,
  created_at,
  updated_at
)
SELECT
  id,
  code_rule_key,
  description,
  enabled,
  pass_admin_message,
  warn_admin_message,
  fail_admin_message,
  info_admin_message,
  admin_notes,
  created_at,
  updated_at
FROM code_rules_seed
ON CONFLICT (code_rule_key) DO UPDATE SET
  description = EXCLUDED.description,
  pass_admin_message = EXCLUDED.pass_admin_message,
  warn_admin_message = EXCLUDED.warn_admin_message,
  fail_admin_message = EXCLUDED.fail_admin_message,
  info_admin_message = EXCLUDED.info_admin_message,
  admin_notes = COALESCE(claims.code_rules.admin_notes, EXCLUDED.admin_notes),
  updated_at = NOW();

WITH obsolete_oil_ahri_mappings AS (
  SELECT cru.id
  FROM claims.code_rule_upgrade_types cru
  JOIN claims.code_rules cr
    ON cr.id = cru.code_rule_id
  JOIN claims.invoice_upgrade_types iut
    ON iut.id = cru.invoice_upgrade_type_id
  WHERE iut.upgrade_type_key = 'air_source_heat_pump_oil'
    AND cr.code_rule_key IN (
      'hp_ahri_found_in_product_list',
      'hp_product_minimum_capacity_at_minus_5c',
      'hp_product_efficiency_threshold'
    )
)
DELETE FROM claims.code_rule_upgrade_types cru
USING obsolete_oil_ahri_mappings old
WHERE cru.id = old.id;

WITH obsolete_electric_ahri_metric_mappings AS (
  SELECT cru.id
  FROM claims.code_rule_upgrade_types cru
  JOIN claims.code_rules cr
    ON cr.id = cru.code_rule_id
  JOIN claims.invoice_upgrade_types iut
    ON iut.id = cru.invoice_upgrade_type_id
  WHERE iut.upgrade_type_key = 'air_source_heat_pump_electric'
    AND cr.code_rule_key IN (
      'hp_product_minimum_capacity_at_minus_5c',
      'hp_product_efficiency_threshold'
    )
)
DELETE FROM claims.code_rule_upgrade_types cru
USING obsolete_electric_ahri_metric_mappings old
WHERE cru.id = old.id;

WITH code_rule_upgrade_type_seed (
  code_rule_key,
  upgrade_type_key
) AS (
  VALUES
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_electric'),
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_wood'),
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_gas_propane'),
  ('hp_invoice_ahri_reference_present', 'dual_fuel_ducted_heat_pump'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_electric'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_wood'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_gas_propane'),
  ('hp_supporting_document_ahri_matches_invoice', 'dual_fuel_ducted_heat_pump'),
  ('hp_ahri_reference_found_in_product_list', 'air_source_heat_pump_electric'),
  ('hp_ahri_reference_found_in_product_list', 'air_source_heat_pump_wood'),
  ('hp_ahri_reference_found_in_product_list', 'air_source_heat_pump_gas_propane'),
  ('hp_ahri_reference_found_in_product_list', 'dual_fuel_ducted_heat_pump'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_wood'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_gas_propane'),
  ('hp_product_minimum_capacity_at_minus_5c', 'dual_fuel_ducted_heat_pump'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_wood'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_gas_propane'),
  ('hp_product_efficiency_threshold', 'dual_fuel_ducted_heat_pump'),
  ('ashp_electric_rebate_math_within_cap', 'air_source_heat_pump_electric'),
  ('ashp_electric_product_specs_meet_requirements', 'air_source_heat_pump_electric'),
  ('ashp_electric_multisplit_minimum_two_indoor_heads', 'air_source_heat_pump_electric'),
  ('source_vintage_applies', 'common'),
  ('first_class_invoice_fields_present', 'common'),
  ('submission_within_six_months', 'common'),
  ('eligibility_code_valid_for_invoice_date', 'common'),
  ('eligibility_code_found_in_database', 'common'),
  ('current_invoice_cannot_contain_multiple_space_systems', 'common'),
  ('prior_same_upgrade_type_rebate_payment_found', 'common'),
  ('income_level_1_or_2_required', 'insulation'),
  ('income_level_1_or_2_required', 'windows_doors'),
  ('income_level_1_or_2_required', 'air_source_heat_pump_electric'),
  ('income_level_1_or_2_required', 'air_source_heat_pump_wood'),
  ('income_level_1_or_2_required', 'health_and_safety_remediation'),
  ('income_level_1_or_2_required', 'ventilation'),
  ('wd_u_factor_threshold', 'windows_doors'),
  ('hpwh_neea_found_in_product_list', 'heat_pump_water_heater'),
  ('hpwh_neea_tier_2_or_higher', 'heat_pump_water_heater'),
  ('hydronic_product_found_in_qualifying_list', 'air_to_water_heat_pump'),
  ('hydronic_product_found_in_qualifying_list', 'combined_space_water_heat_pump'),
  ('ashp_oil_ohpa_bc_product_found_in_list', 'air_source_heat_pump_oil')
)
INSERT INTO claims.code_rule_upgrade_types (
  code_rule_id,
  invoice_upgrade_type_id,
  created_at
)
SELECT
  cr.id,
  iut.id,
  NOW()
FROM code_rule_upgrade_type_seed seed
JOIN claims.code_rules cr
  ON cr.code_rule_key = seed.code_rule_key
JOIN claims.invoice_upgrade_types iut
  ON iut.upgrade_type_key = seed.upgrade_type_key
ON CONFLICT (code_rule_id, invoice_upgrade_type_id) DO NOTHING;

COMMIT;
