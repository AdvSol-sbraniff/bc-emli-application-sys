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
    '590f2f3a-3e23-449a-a7d4-2f35c3d53001'::uuid,
    'hp_ahri_found_in_product_list',
    'Checks whether the invoice AHRI reference exists in the current imported BC Hydro heat-pump product lists; supporting-document AHRI evidence corroborates the match when present and must not conflict.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched AHRI product-list row.',
    'Review the AHRI match when supporting-document AHRI evidence is missing, when invoice AHRI is missing, or when no current imported list rows are available.',
    'Ask the contractor for corrected product evidence when the invoice AHRI conflicts with supporting-document AHRI evidence or is not found in the imported product list.',
    NULL,
    'The code supplies the detailed invoice AHRI product-list lookup and any supporting-document AHRI corroboration/conflict explanation; these messages are short admin guidance additions only.',
    TIMESTAMP '2026-05-14 00:00:00',
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
    'Checks whether the contractor submitted the invoice within six months of the invoice date.',
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
    'Checks whether the invoice date is inside the eligibility-code completion window. The invoice date is currently used as the system proxy for upgrade completed date.

Pseudo-code:
if invoice_date is missing or approved_at is missing:
  warn
else:
  deadline = expires_at if present, otherwise approved_at + 6 months
  if approved_at <= invoice_date <= deadline:
    pass
  else:
    fail',
    true,
    'No follow-up is required when the invoice date clearly falls within the eligibility-code validity window.',
    'Verify the eligibility-code dates and invoice date before deciding whether the claim falls inside the valid approval window.',
    'The invoice date appears to fall outside the eligibility-code validity window and needs correction or program review.',
    'This eligibility timing check passed with context worth surfacing to the reviewer.',
    'This rule compares stored eligibility-code dates against the invoice date and is intended to remain admin-configurable like other code rules.',
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
    'Checks whether the matched participant already has a paid or active claim for the same exact detected upgrade type. This is a V1 exact-upgrade-type check and does not yet group all primary-heating-system upgrade types together.',
    true,
    'No prior paid or active claim was found for the same participant and same exact detected upgrade type.',
    'Review the duplicate-payment detail before moving forward. This may mean another active or payment-pending claim exists, or that participant identity could not be resolved.',
    'This participant appears to already have a paid rebate for the same exact detected upgrade type. Review the prior invoice before approving another payment.',
    NULL,
    'Uses invoice_versions.participant_user_id and the latest invoice_version per other invoice parent. V1 compares exact invoice_upgrade_type_id only and intentionally does not group primary-heating-system families.',
    TIMESTAMP '2026-06-18 00:00:00',
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

WITH code_rule_upgrade_type_seed (
  code_rule_key,
  upgrade_type_key
) AS (
  VALUES
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_electric'),
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_wood'),
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_gas_propane'),
  ('hp_ahri_found_in_product_list', 'dual_fuel_ducted_heat_pump'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_electric'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_wood'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_gas_propane'),
  ('hp_product_minimum_capacity_at_minus_5c', 'dual_fuel_ducted_heat_pump'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_electric'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_wood'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_gas_propane'),
  ('hp_product_efficiency_threshold', 'dual_fuel_ducted_heat_pump'),
  ('source_vintage_applies', 'common'),
  ('first_class_invoice_fields_present', 'common'),
  ('submission_within_six_months', 'common'),
  ('eligibility_code_valid_for_invoice_date', 'common'),
  ('eligibility_code_found_in_database', 'common'),
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
