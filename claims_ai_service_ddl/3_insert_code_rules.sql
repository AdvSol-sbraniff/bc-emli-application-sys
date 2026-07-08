BEGIN;

WITH obsolete_ashp_requirement_rule_keys (code_rule_key) AS (
  VALUES
  ('ashp_electric_rebate_math_within_cap'),
  ('ashp_electric_product_specs_meet_requirements'),
  ('ashp_electric_multisplit_minimum_two_indoor_heads'),
  ('ashp_wood_rebate_math_within_cap'),
  ('ashp_wood_product_specs_meet_requirements'),
  ('ashp_wood_multisplit_minimum_two_indoor_heads'),
  ('ashp_gas_propane_northern_top_up_within_cap')
),
obsolete_ashp_requirement_rule_mappings AS (
  SELECT cru.id
  FROM claims.code_rule_upgrade_types cru
  JOIN claims.code_rules cr
    ON cr.id = cru.code_rule_id
  JOIN obsolete_ashp_requirement_rule_keys old
    ON old.code_rule_key = cr.code_rule_key
)
DELETE FROM claims.code_rule_upgrade_types cru
USING obsolete_ashp_requirement_rule_mappings old
WHERE cru.id = old.id;

WITH obsolete_ashp_requirement_rule_keys (code_rule_key) AS (
  VALUES
  ('ashp_electric_rebate_math_within_cap'),
  ('ashp_electric_product_specs_meet_requirements'),
  ('ashp_electric_multisplit_minimum_two_indoor_heads'),
  ('ashp_wood_rebate_math_within_cap'),
  ('ashp_wood_product_specs_meet_requirements'),
  ('ashp_wood_multisplit_minimum_two_indoor_heads'),
  ('ashp_gas_propane_northern_top_up_within_cap')
)
DELETE FROM claims.code_rules cr
USING obsolete_ashp_requirement_rule_keys old
WHERE cr.code_rule_key = old.code_rule_key;

WITH retired_common_rule_keys (code_rule_key) AS (
  VALUES
  ('source_vintage_applies'),
  ('dfhp_northern_top_up_within_cap')
),
retired_common_rule_mappings AS (
  SELECT cru.id
  FROM claims.code_rule_upgrade_types cru
  JOIN claims.code_rules cr
    ON cr.id = cru.code_rule_id
  JOIN retired_common_rule_keys old
    ON old.code_rule_key = cr.code_rule_key
)
DELETE FROM claims.code_rule_upgrade_types cru
USING retired_common_rule_mappings old
WHERE cru.id = old.id;

WITH retired_common_rule_keys (code_rule_key) AS (
  VALUES
  ('source_vintage_applies'),
  ('dfhp_northern_top_up_within_cap')
)
DELETE FROM claims.code_rules cr
USING retired_common_rule_keys old
WHERE cr.code_rule_key = old.code_rule_key;

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
    'ashp_electric_wood_rebate_math_within_cap',
    'Checks ASHP convert-from-electric/wood rebate amount against the ASHP upgrade line amount and the Income Level 1/2 cap from the requirements table.',
    true,
    'No follow-up is required when the ASHP electric/wood rebate is within the named upgrade amount and income-level cap.',
    'Review the invoice ASHP line amount, rebate line, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice ASHP line amount, rebate line, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Requirement PDF: AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC), requirements table after item 9; AIR SOURCE HEAT PUMP (CONVERT FROM WOOD), requirements table after item 11. Uses ashp_upgrade_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53032'::uuid,
    'ashp_product_specs_meet_requirements',
    'Checks ASHP requirements table product specs: efficiency threshold, variable speed compressor, and minimum 12,000 BTU capacity.',
    true,
    'No follow-up is required when the matched product-list row and named field evidence satisfy the product specification checks.',
    'Review the matched product-list row and invoice/product evidence when a metric is missing or ambiguous.',
    'Confirm the product-list match before asking the contractor for corrected product evidence.',
    'Resolve the product-list match first, then rerun checks.',
    'Requirement PDF: ASHP requirements tables for electric, wood, gas/propane, and oil conversion sections. Uses the matched AHRI/OHPA product row plus hp_efficiency_and_capacity evidence for variable-speed wording.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53033'::uuid,
    'ashp_multisplit_minimum_two_indoor_heads',
    'Checks that an ASHP ductless multi-split installation has at least two indoor head units.',
    true,
    'No follow-up is required when the claim is not multi-split or the multi-split evidence supports at least two indoor heads.',
    'Review the invoice equipment section when a multi-split system is visible but the indoor-head count is not explicit.',
    'Ask the contractor for corrected invoice or product evidence if a ductless multi-split shows fewer than two indoor heads.',
    NULL,
    'Requirement PDF: ASHP requirements tables for electric, wood, gas/propane, and oil conversion sections. Uses hp_new_equipment_type and the matched AHRI/OHPA source/product evidence.',
    TIMESTAMP '2026-07-06 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53038'::uuid,
    'ashp_gas_propane_rebate_math_within_cap',
    'Checks ASHP natural-gas/propane base rebate amount against the ASHP upgrade line amount and the equipment-category cap for the matched income level. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read ashp_upgrade_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read hp_new_equipment_type. 5. Classify equipment as single-head mini-split, 2-head multi-split/2 single-head mini-split, central ducted/3-head multi-split, or unknown. 6. Apply base cap table: single-head ESP1 $7,500, ESP2 $5,500, ESP3 $4,000; 2-head/2-single-head ESP1 $14,000, ESP2 $10,500, ESP3 $8,000; central/3-head ESP1 $16,000, ESP2 $12,000, ESP3 $10,500. 7. If rebate amount, ASHP upgrade amount, income level, or equipment category is missing or ambiguous, warn. 8. If rebate amount exceeds the category/income cap, fail. 9. If rebate amount exceeds the ASHP upgrade amount, fail. 10. Pass only when all named values are clear and the rebate is less than or equal to both the ASHP upgrade amount and the applicable base cap. 11. Exclude separately claimed northern top-up from this base rebate comparison; ashp_fossil_northern_top_up_within_cap owns the separate northern top-up check. 12. In calculation, show upgrade_specific_rebate_line_amount, ashp_upgrade_line_amount, income level, equipment category, cap, and northern_top_up_excluded=true.',
    true,
    'No follow-up is required when the gas/propane ASHP base rebate is within the named ASHP upgrade amount and equipment-category cap.',
    'Review the invoice ASHP line amount, rebate line, equipment category, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice ASHP line amount, rebate line, equipment category, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Uses hp_new_equipment_type, ashp_upgrade_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level. Northern top-up is handled by ashp_fossil_northern_top_up_within_cap.',
    TIMESTAMP '2026-07-07 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53037'::uuid,
    'ashp_fossil_northern_top_up_within_cap',
    'Checks a separately claimed northern top-up for an ASHP fossil-fuel conversion from natural gas, propane, or oil. Pseudocode: 1. Read hp_northern_top_up_evidence. 2. If no separate northern top-up is visible, pass with calculation top_up_claimed=false. 3. Read income level from users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read hp_new_equipment_type and classify the equipment as single-head mini-split, central ducted/multi-split/2 single-head mini-split, or unknown. 5. Apply cap $1,500 for single-head mini-split, $3,000 for central ducted/multi-split/2 single-head mini-split, and no cap when category is unknown. 6. If income level is 3 and a positive top-up amount is visible, fail because ESP3 has no northern top-up. 7. If top-up amount, income level, or equipment category is missing or ambiguous, warn. 8. If top-up amount exceeds the category cap, fail. 9. Check hp_northern_top_up_evidence for location evidence north of and including the District of 100 Mile House. 10. Check hp_northern_top_up_evidence for BC Hydro electric service evidence. 11. If location or BC Hydro evidence is missing or ambiguous, warn even when the amount is within cap. 12. Pass only when the top-up amount is within cap, income level is 1 or 2, category is clear, northern-location evidence is clear, and BC Hydro-service evidence is clear. 13. In calculation, show top-up amount, income level, equipment category, cap, northern-location evidence, and BC Hydro-service evidence.',
    true,
    'No follow-up is required when the separate northern top-up is within cap and the named evidence supports location and BC Hydro service.',
    'Review the northern top-up amount, equipment category, income level, location evidence, and BC Hydro service evidence before moving the claim forward.',
    'Confirm the top-up amount, equipment category, and income level before asking the contractor for correction.',
    NULL,
    'Uses hp_northern_top_up_evidence, hp_new_equipment_type, and users_eligibilitycodes.income_level. This code rule intentionally treats missing top-up evidence as pass because no top-up was claimed.',
    TIMESTAMP '2026-07-07 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53039'::uuid,
    'ashp_oil_rebate_math_within_cap',
    'Checks ASHP oil-conversion base rebate amount against the ASHP upgrade line amount and the equipment-category cap for the matched income level. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read ashp_upgrade_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read hp_new_equipment_type. 5. Classify equipment as single-head mini-split, 2-head multi-split/2 single-head mini-split, central ducted/3-head multi-split, or unknown. 6. Apply base cap table: single-head ESP1 $10,000, ESP2 $10,000, ESP3 $10,000; 2-head/2-single-head ESP1 $14,000, ESP2 $10,500, ESP3 $10,000; central/3-head ESP1 $16,000, ESP2 $12,000, ESP3 $10,500. 7. If rebate amount, ASHP upgrade amount, income level, or equipment category is missing or ambiguous, warn. 8. If rebate amount exceeds the category/income cap, fail. 9. If rebate amount exceeds the ASHP upgrade amount, fail. 10. Pass only when all named values are clear and the rebate is less than or equal to both the ASHP upgrade amount and the applicable base cap. 11. Exclude separately claimed northern top-up from this base rebate comparison; ashp_fossil_northern_top_up_within_cap owns the separate northern top-up check. 12. In calculation, show upgrade_specific_rebate_line_amount, ashp_upgrade_line_amount, income level, equipment category, cap, and northern_top_up_excluded=true.',
    true,
    'No follow-up is required when the oil ASHP base rebate is within the named ASHP upgrade amount and equipment-category cap.',
    'Review the invoice ASHP line amount, rebate line, equipment category, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice ASHP line amount, rebate line, equipment category, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Uses hp_new_equipment_type, ashp_upgrade_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level. Northern top-up is handled by ashp_fossil_northern_top_up_within_cap.',
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53040'::uuid,
    'dfhp_rebate_math_within_cap',
    'Checks dual-fuel ducted heat pump base rebate amount against the DFHP upgrade line amount and the source-fuel-path cap for the matched income level. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read dfhp_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read dfhp_source_fuel_path. 5. Classify source fuel as PNG natural gas/PNG propane, tank propane, or unknown. 6. Apply base cap table: PNG natural gas/PNG propane ESP1 $11,500, ESP2 $6,500, ESP3 $6,500; tank propane ESP1 $15,000, ESP2 $10,000, ESP3 $10,000. 7. If rebate amount, DFHP upgrade amount, income level, or source-fuel path is missing or ambiguous, warn. 8. If rebate amount exceeds the source-fuel/income cap, fail. 9. If rebate amount exceeds the DFHP upgrade amount, fail. 10. Pass only when all named values are clear and the rebate is less than or equal to both the DFHP upgrade amount and the applicable base cap. 11. Exclude separately claimed northern top-up from this base rebate comparison; heat_pump_northern_top_up_3000_within_cap owns the separate northern top-up check. 12. In calculation, show upgrade_specific_rebate_line_amount, dfhp_line_amount, income level, source-fuel path, cap, and northern_top_up_excluded=true.',
    true,
    'No follow-up is required when the DFHP base rebate is within the named DFHP upgrade amount and source-fuel-path cap.',
    'Review the invoice DFHP line amount, rebate line, source-fuel path, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice DFHP line amount, rebate line, source-fuel path, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Uses dfhp_source_fuel_path, dfhp_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level. Northern top-up is handled by heat_pump_northern_top_up_3000_within_cap.',
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53042'::uuid,
    'dfhp_product_specs_meet_requirements',
    'Checks dual-fuel ducted heat pump product specifications from the matched AHRI product-list row. Pseudocode: 1. Resolve the matched AHRI product row from invoice_versions.ahri_product_id, falling back to classifier.ahri_reference searched against claims.v_current_ahri_products. 2. If no matched AHRI product row is available, return info because hp_ahri_reference_found_in_product_list owns the product-list match. 3. Read SEER, HSPF, SEER2, HSPF2, and rated_capacity_btu_at_minus_5c from the matched AHRI product row. 4. Pass the efficiency check when either SEER >= 16.0 and HSPF >= 10.0, or SEER2 >= 15.2 and HSPF2 >= 8.5. 5. Warn when neither complete efficiency pair is available. 6. Fail when complete values are available and neither efficiency path passes. 7. Pass the capacity check when the matched product row capacity is at least 12,000 BTU. 8. Warn when capacity is missing or not numeric. 9. Fail when capacity is present and below 12,000 BTU. 10. Do not check variable speed compressor because the dual-fuel ducted heat pump requirements table says variable speed compressor is not required. 11. Do not check multi-split indoor-head count because the dual-fuel ducted heat pump table has no multi-split indoor-head rule. 12. Combine the checks: fail if any check fails, warn if no check fails but any check is incomplete, otherwise pass. 13. In calculation, show the matched AHRI row values used.',
    true,
    'No follow-up is required when the matched AHRI row satisfies the DFHP efficiency and 12,000 BTU capacity checks.',
    'Review the matched AHRI product-list row when DFHP efficiency or capacity values are missing or incomplete.',
    'Confirm the AHRI match before asking the contractor for corrected DFHP product evidence.',
    'Resolve the AHRI product-list match first, then rerun checks.',
    'DFHP-specific replacement for the generic hp_product_minimum_capacity_at_minus_5c and hp_product_efficiency_threshold mappings. It intentionally does not check variable-speed compressor or multi-split indoor-head count.',
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53041'::uuid,
    'heat_pump_northern_top_up_3000_within_cap',
    'Checks a separately claimed northern top-up for heat-pump upgrade types whose requirement table has a $3,000 northern top-up cap. Pseudocode: 1. Read hp_northern_top_up_evidence. 2. If no separate northern top-up is visible, pass with calculation top_up_claimed=false. 3. Read income level from users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Apply top-up cap $3,000 for ESP1 or ESP2. 5. If income level is 3 and a positive top-up amount is visible, fail because ESP3 has no northern top-up. 6. If top-up amount or income level is missing or ambiguous, warn. 7. If top-up amount exceeds $3,000, fail. 8. Check hp_northern_top_up_evidence for location evidence north of and including the District of 100 Mile House. 9. Check hp_northern_top_up_evidence for BC Hydro electric service evidence. 10. If location or BC Hydro evidence is missing or ambiguous, warn even when the amount is within cap. 11. Pass only when the top-up amount is within $3,000, income level is 1 or 2, northern-location evidence is clear, and BC Hydro-service evidence is clear. 12. In calculation, show top-up amount, income level, cap, northern-location evidence, and BC Hydro-service evidence.',
    true,
    'No follow-up is required when the separate northern top-up is within the $3,000 cap and the named evidence supports location and BC Hydro service.',
    'Review the northern top-up amount, income level, location evidence, and BC Hydro service evidence before moving the claim forward.',
    'Confirm the top-up amount and income level before asking the contractor for correction.',
    NULL,
    'Uses hp_northern_top_up_evidence and users_eligibilitycodes.income_level. This code rule intentionally treats missing top-up evidence as pass because no top-up was claimed.',
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53152'::uuid,
    'atw_rebate_math_within_cap',
    'Checks air-to-water space-heating-only base rebate amount against the ATW upgrade line amount and the source-fuel-path cap for the matched income level. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read atw_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read hydronic_conversion_source_fuel_evidence. 5. Classify source fuel as fossil fuel, electricity/wood, or unknown. 6. Apply base cap table: fossil fuel ESP1 $16,000, ESP2 $12,000, ESP3 $10,500; electricity/wood ESP1 $5,000, ESP2 $5,000, ESP3 no rebate. 7. If rebate amount, ATW upgrade amount, income level, or source-fuel path is missing or ambiguous, warn. 8. If the source path has no rebate for the income level, fail. 9. If rebate amount exceeds the source-fuel/income cap, fail. 10. If rebate amount exceeds the ATW upgrade amount, fail. 11. Pass only when all named values are clear and the rebate is less than or equal to both the ATW upgrade amount and the applicable base cap. 12. Exclude separately claimed northern top-up from this base rebate comparison; heat_pump_northern_top_up_3000_within_cap owns the separate northern top-up check. 13. In calculation, show upgrade_specific_rebate_line_amount, atw_line_amount, income level, source-fuel path, cap, and northern_top_up_excluded=true.',
    true,
    'No follow-up is required when the ATW base rebate is within the named ATW upgrade amount and source-fuel-path cap.',
    'Review the invoice ATW line amount, rebate line, source-fuel path, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice ATW line amount, rebate line, source-fuel path, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Uses hydronic_conversion_source_fuel_evidence, atw_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level. Northern top-up is handled by heat_pump_northern_top_up_3000_within_cap.',
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53153'::uuid,
    'cshp_rebate_math_within_cap',
    'Checks combined space-and-water heat pump base rebate amount against the CSHP upgrade line amount and the source-fuel-path cap for the matched income level. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read cshp_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read hydronic_conversion_source_fuel_evidence. 5. Classify source fuel as fossil fuel, electricity/wood, or unknown. 6. Apply base cap table: fossil fuel ESP1 $19,500, ESP2 $16,500, ESP3 $14,000; electricity/wood ESP1 $8,500, ESP2 $8,500, ESP3 no rebate. 7. If rebate amount, CSHP upgrade amount, income level, or source-fuel path is missing or ambiguous, warn. 8. If the source path has no rebate for the income level, fail. 9. If rebate amount exceeds the source-fuel/income cap, fail. 10. If rebate amount exceeds the CSHP upgrade amount, fail. 11. Pass only when all named values are clear and the rebate is less than or equal to both the CSHP upgrade amount and the applicable base cap. 12. Exclude separately claimed northern top-up from this base rebate comparison; heat_pump_northern_top_up_3000_within_cap owns the separate northern top-up check. 13. In calculation, show upgrade_specific_rebate_line_amount, cshp_line_amount, income level, source-fuel path, cap, and northern_top_up_excluded=true.',
    true,
    'No follow-up is required when the CSHP base rebate is within the named CSHP upgrade amount and source-fuel-path cap.',
    'Review the invoice CSHP line amount, rebate line, source-fuel path, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice CSHP line amount, rebate line, source-fuel path, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Uses hydronic_conversion_source_fuel_evidence, cshp_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level. Northern top-up is handled by heat_pump_northern_top_up_3000_within_cap.',
    TIMESTAMP '2026-07-08 00:00:00',
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
    '590f2f3a-3e23-449a-a7d4-2f35c3d53104'::uuid,
    'hpwh_rebate_math_within_cap',
    'Checks heat pump water heater rebate amount against the HPWH upgrade line amount and the source-fuel-path cap for the matched income level. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read hpwh_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Read hpwh_existing_fuel_type. 5. Classify source fuel as fossil fuel, electricity/wood, or unknown. 6. Apply cap table: fossil fuel ESP1 $3,500, ESP2 $3,500, ESP3 $3,500; electricity/wood ESP1 $3,500, ESP2 $2,800, ESP3 no rebate. 7. If rebate amount, HPWH upgrade amount, income level, or source-fuel path is missing or ambiguous, warn. 8. If the source path has no rebate for the income level, fail. 9. If rebate amount exceeds the source-fuel/income cap, fail. 10. If rebate amount exceeds the HPWH upgrade amount, fail. 11. Pass only when all named values are clear and the rebate is less than or equal to both the HPWH upgrade amount and the applicable cap. 12. In calculation, show upgrade_specific_rebate_line_amount, hpwh_line_amount, income level, source-fuel path, and cap.',
    true,
    'No follow-up is required when the HPWH rebate is within the named HPWH upgrade amount and source-fuel-path cap.',
    'Review the invoice HPWH line amount, rebate line, source-fuel path, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice HPWH line amount, rebate line, source-fuel path, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Requirement PDF: HEAT PUMP WATER HEATER requirements table. Uses hpwh_existing_fuel_type, hpwh_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level.',
    TIMESTAMP '2026-07-08 00:00:00',
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
    'Checks whether the corroborated invoice/supporting-document AHRI reference exists in the current imported NRCan Oil to Heat Pump Affordability BC qualified product list.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched NRCan OHPA BC product-list row.',
    'Refresh the OHPA product-list import if invoice and supporting-document AHRI evidence agree but no current imported list rows are available.',
    'Ask the contractor for corrected product evidence when the agreed AHRI reference is not found in the imported OHPA BC product list.',
    NULL,
    'This rule owns only the NRCan OHPA BC product-list lookup. Invoice AHRI presence is handled by hp_invoice_ahri_reference_present, and invoice/supporting-document AHRI agreement is handled by hp_supporting_document_ahri_matches_invoice.',
    TIMESTAMP '2026-06-02 00:00:00',
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

WITH obsolete_section_specific_ahri_metric_mappings AS (
  SELECT cru.id
  FROM claims.code_rule_upgrade_types cru
  JOIN claims.code_rules cr
    ON cr.id = cru.code_rule_id
  JOIN claims.invoice_upgrade_types iut
    ON iut.id = cru.invoice_upgrade_type_id
  WHERE iut.upgrade_type_key IN (
      'air_source_heat_pump_electric',
      'air_source_heat_pump_wood',
      'air_source_heat_pump_gas_propane',
      'dual_fuel_ducted_heat_pump'
    )
    AND cr.code_rule_key IN (
      'hp_product_minimum_capacity_at_minus_5c',
      'hp_product_efficiency_threshold'
    )
)
DELETE FROM claims.code_rule_upgrade_types cru
USING obsolete_section_specific_ahri_metric_mappings old
WHERE cru.id = old.id;

WITH code_rule_upgrade_type_seed (
  code_rule_key,
  upgrade_type_key
) AS (
  VALUES
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_electric'),
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_wood'),
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_gas_propane'),
  ('hp_invoice_ahri_reference_present', 'air_source_heat_pump_oil'),
  ('hp_invoice_ahri_reference_present', 'dual_fuel_ducted_heat_pump'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_electric'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_wood'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_gas_propane'),
  ('hp_supporting_document_ahri_matches_invoice', 'air_source_heat_pump_oil'),
  ('hp_supporting_document_ahri_matches_invoice', 'dual_fuel_ducted_heat_pump'),
  ('hp_ahri_reference_found_in_product_list', 'air_source_heat_pump_electric'),
  ('hp_ahri_reference_found_in_product_list', 'air_source_heat_pump_wood'),
  ('hp_ahri_reference_found_in_product_list', 'air_source_heat_pump_gas_propane'),
  ('hp_ahri_reference_found_in_product_list', 'dual_fuel_ducted_heat_pump'),
  ('dfhp_product_specs_meet_requirements', 'dual_fuel_ducted_heat_pump'),
  ('ashp_electric_wood_rebate_math_within_cap', 'air_source_heat_pump_electric'),
  ('ashp_electric_wood_rebate_math_within_cap', 'air_source_heat_pump_wood'),
  ('ashp_product_specs_meet_requirements', 'air_source_heat_pump_electric'),
  ('ashp_product_specs_meet_requirements', 'air_source_heat_pump_wood'),
  ('ashp_product_specs_meet_requirements', 'air_source_heat_pump_gas_propane'),
  ('ashp_product_specs_meet_requirements', 'air_source_heat_pump_oil'),
  ('ashp_multisplit_minimum_two_indoor_heads', 'air_source_heat_pump_electric'),
  ('ashp_multisplit_minimum_two_indoor_heads', 'air_source_heat_pump_wood'),
  ('ashp_multisplit_minimum_two_indoor_heads', 'air_source_heat_pump_gas_propane'),
  ('ashp_multisplit_minimum_two_indoor_heads', 'air_source_heat_pump_oil'),
  ('ashp_gas_propane_rebate_math_within_cap', 'air_source_heat_pump_gas_propane'),
  ('ashp_oil_rebate_math_within_cap', 'air_source_heat_pump_oil'),
  ('ashp_fossil_northern_top_up_within_cap', 'air_source_heat_pump_gas_propane'),
  ('ashp_fossil_northern_top_up_within_cap', 'air_source_heat_pump_oil'),
  ('dfhp_rebate_math_within_cap', 'dual_fuel_ducted_heat_pump'),
  ('heat_pump_northern_top_up_3000_within_cap', 'dual_fuel_ducted_heat_pump'),
  ('atw_rebate_math_within_cap', 'air_to_water_heat_pump'),
  ('cshp_rebate_math_within_cap', 'combined_space_water_heat_pump'),
  ('heat_pump_northern_top_up_3000_within_cap', 'air_to_water_heat_pump'),
  ('heat_pump_northern_top_up_3000_within_cap', 'combined_space_water_heat_pump'),
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
  ('hpwh_rebate_math_within_cap', 'heat_pump_water_heater'),
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
