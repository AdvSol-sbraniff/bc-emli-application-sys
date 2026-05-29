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
    'Checks whether the AHRI reference found on the invoice exists in the current imported BC Hydro heat-pump product lists.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched AHRI product-list row.',
    'Ask the contractor to provide the AHRI reference or corrected product evidence if the invoice does not clearly identify it.',
    NULL,
    NULL,
    'The code supplies the detailed evidence and match explanation; these messages are short admin guidance additions only.',
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
    'Checks whether the tracked first-class invoice fields needed for core invoice review are present in the stored OCR/DI result.',
    true,
    'No follow-up is required when all tracked first-class invoice fields are present.',
    'Verify the missing invoice fields in the PDF before relying on downstream review results that depend on them.',
    'Correct or re-extract the invoice because required first-class fields are missing from the stored OCR/DI result.',
    'Some first-class invoice fields may need a quick manual confirmation even if the rest of the invoice looks usable.',
    'This rule supports baseline invoice evidence completeness for downstream checks.',
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
    'Checks whether the invoice date falls within the approval and expiry window of the participant eligibility code.',
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

WITH code_rule_upgrade_type_seed (
  code_rule_key,
  upgrade_type_key
) AS (
  VALUES
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_electric'),
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_wood'),
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_gas_propane'),
  ('hp_ahri_found_in_product_list', 'air_source_heat_pump_oil'),
  ('hp_ahri_found_in_product_list', 'dual_fuel_ducted_heat_pump'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_electric'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_wood'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_gas_propane'),
  ('hp_product_minimum_capacity_at_minus_5c', 'air_source_heat_pump_oil'),
  ('hp_product_minimum_capacity_at_minus_5c', 'dual_fuel_ducted_heat_pump'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_electric'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_wood'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_gas_propane'),
  ('hp_product_efficiency_threshold', 'air_source_heat_pump_oil'),
  ('hp_product_efficiency_threshold', 'dual_fuel_ducted_heat_pump'),
  ('source_vintage_applies', 'common'),
  ('first_class_invoice_fields_present', 'common'),
  ('submission_within_six_months', 'common'),
  ('eligibility_code_valid_for_invoice_date', 'common'),
  ('wd_u_factor_threshold', 'windows_doors'),
  ('hpwh_neea_found_in_product_list', 'heat_pump_water_heater'),
  ('hpwh_neea_tier_2_or_higher', 'heat_pump_water_heater')
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
