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
  source_quote,
  legacy_contractor_visible_flag,
  created_at,
  updated_at
) AS (
  VALUES
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53021'::uuid,
    'hp_ahri_product_validation',
    'Checks AHRI-backed heat pump product validation as one code-owned decision. Pseudocode: 1. Read hp_ahri_reference from GenAI invoice located fields. 2. Read ahri_reference from supporting product documents. 3. Search claims.v_current_ahri_products for the invoice AHRI reference. 4. Subcheck invoice_ahri_reference_present passes when hp_ahri_reference is present, otherwise warns. 5. Subcheck supporting_document_ahri_matches_invoice passes when supporting-document AHRI includes the invoice AHRI, warns when supporting AHRI is missing, and fails when supporting AHRI conflicts. 6. Subcheck ahri_product_found_in_download passes when the invoice AHRI is found in the current imported AHRI product list, warns when invoice AHRI or source rows are missing, and fails when the AHRI is searched and not found. 7. Overall result fails if any subcheck fails, warns if no subcheck fails but any subcheck warns, otherwise passes. 8. Write invoice_versions.ahri_product_id when a clean product-list match is found. 9. In calculation, list invoice product identity, supporting-document product identity, download lookup, subchecks, failed_subchecks, and warn_subchecks.',
    true,
    'No follow-up is required when the invoice AHRI, supporting-document AHRI, and imported AHRI product-list row agree.',
    'Review invoice/supporting product evidence or refresh the AHRI import when one AHRI validation subcheck is incomplete.',
    'Ask the contractor for corrected product evidence when AHRI evidence conflicts or the invoice AHRI is not found in the imported product list.',
    NULL,
    'Reads normal GenAI located field hp_ahri_reference, not classifier product references.',
    'have an AHRI certified reference number that references all components of the heat pump.',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $5,000 per home. 100% of eligible upgrade costs, up to a maximum of $4,000 per home.',
    true,
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
    'SEER >= 16.0, HSPF >= 10.0 or SEER2 >= 15.2, HSPF2 >= 8.5 (Region IV). Variable speed compressor. Minimum capacity of 12,000 BTU (1 ton).',
    true,
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
    'Must install a minimum of two indoor head units',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $10,000 per home. 100% of eligible upgrade costs, up to a maximum of $14,000 per home. 100% of eligible upgrade costs, up to a maximum of $16,000 per home.',
    true,
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
    'Northern top-up** Eligible for program approved central ducted, multi-split and 2 single-head mini-split heat pumps $3,000 $3,000 N/A. Northern top-up** Eligible for program approved single-head mini-split heat pump $1,500 $1,500 N/A.',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $11,500 per home. 100% of eligible upgrade costs, up to a maximum of $6,500 per home. 100% of eligible upgrade costs, up to a maximum of $15,000 per home. 100% of eligible upgrade costs, up to a maximum of $10,000 per home.',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $11,500 per home. 100% of eligible upgrade costs, up to a maximum of $6,500 per home. 100% of eligible upgrade costs, up to a maximum of $15,000 per home. 100% of eligible upgrade costs, up to a maximum of $10,000 per home.',
    true,
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53042'::uuid,
    'dfhp_product_specs_meet_requirements',
    'Checks dual-fuel ducted heat pump product specifications from the matched AHRI product-list row. Pseudocode: 1. Resolve the matched AHRI product row from invoice_versions.ahri_product_id, which is written by hp_ahri_product_validation. 2. If no matched AHRI product row is available, return info because product validation owns the product-list match. 3. Read SEER, HSPF, SEER2, HSPF2, and rated_capacity_btu_at_minus_5c from the matched AHRI product row. 4. Pass the efficiency check when either SEER >= 16.0 and HSPF >= 10.0, or SEER2 >= 15.2 and HSPF2 >= 8.5. 5. Warn when neither complete efficiency pair is available. 6. Fail when complete values are available and neither efficiency path passes. 7. Pass the capacity check when the matched product row capacity is at least 12,000 BTU. 8. Warn when capacity is missing or not numeric. 9. Fail when capacity is present and below 12,000 BTU. 10. Do not check variable speed compressor because the dual-fuel ducted heat pump requirements table says variable speed compressor is not required. 11. Do not check multi-split indoor-head count because the dual-fuel ducted heat pump table has no multi-split indoor-head rule. 12. Combine the checks: fail if any check fails, warn if no check fails but any check is incomplete, otherwise pass. 13. In calculation, show the matched AHRI row values used.',
    true,
    'No follow-up is required when the matched AHRI row satisfies the DFHP efficiency and 12,000 BTU capacity checks.',
    'Review the matched AHRI product-list row when DFHP efficiency or capacity values are missing or incomplete.',
    'Confirm the AHRI match before asking the contractor for corrected DFHP product evidence.',
    'Resolve the AHRI product-list match first, then rerun checks.',
    'DFHP-specific replacement for the generic hp_product_minimum_capacity_at_minus_5c and hp_product_efficiency_threshold mappings. It intentionally does not check variable-speed compressor or multi-split indoor-head count.',
    'SEER >= 16.0, HSPF >= 10.0 or SEER2 >= 15.2, HSPF2 >= 8.5 (Region IV). Variable speed compressor not required. Minimum capacity of 12,000 BTU (1 ton).',
    true,
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
    'Northern top-up* Eligible for program approved air-to-water and combined heat pumps. $3,000 $3,000 N/A.',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $16,000 per home. 100% of eligible upgrade costs, up to a maximum of $12,000 per home. 100% of eligible upgrade costs, up to a maximum of $10,500 per home. 100% of eligible upgrade costs, up to a maximum of $5,000 per home.',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $19,500 per home. 100% of eligible upgrade costs, up to a maximum of $16,500 per home. 100% of eligible upgrade costs, up to a maximum of $14,000 per home. 100% of eligible upgrade costs, up to a maximum of $8,500 per home.',
    true,
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
    '3. Minimum capacity of 12,000 BTU (1 ton).',
    true,
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
    'SEER >= 16.0, HSPF >= 10.0 or SEER2 >= 15.2, HSPF2 >= 8.5 (Region IV)',
    true,
    TIMESTAMP '2026-05-14 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53101'::uuid,
    'hpwh_neea_product_validation',
    'Checks heat pump water heater NEEA product validation as one code-owned decision. Pseudocode: 1. Read HPWH product identity from hpwh_manufacturer, hpwh_model_number, hpwh_model_components, and hpwh_make_model. 2. Search claims.v_current_neea_products. 3. Subcheck invoice_hpwh_product_identity_present passes when invoice model evidence exists, otherwise warns. 4. Subcheck neea_product_found_in_download passes when product evidence matches the current imported NEEA list, warns when invoice identity or source rows are missing, and fails when product identity is searched and not found. 5. Subcheck neea_tier_2_or_higher passes when the matched row effective tier is at least 2, warns when no matched row or tier value is available, and fails when the matched row is below Tier 2. 6. Overall result fails if any subcheck fails, warns if no subcheck fails but any subcheck warns, otherwise passes. 7. Write invoice_versions.neea_product_id when a clean product-list match is found. 8. In calculation, list invoice product identity, download lookup, subchecks, failed_subchecks, and warn_subchecks.',
    true,
    'No follow-up is required when the HPWH product identity matches the NEEA list and the matched row is Tier 2 or higher.',
    'Review HPWH model evidence, NEEA import status, or tier values when a NEEA validation subcheck is incomplete.',
    'Ask the contractor for corrected product evidence or an eligible Tier 2+ heat pump water heater model when NEEA validation fails.',
    NULL,
    'This consolidated rule owns HPWH NEEA product-list matching and Tier 2+ validation.',
    'Eligible systems are listed as Tier 2 or higher on NEEA’s Advanced Water Heater Specification Qualified Products List for Heat Pump Water Heaters.',
    true,
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
    '100% of eligible upgrade costs, up to a maximum of $3,500 per home. 80% of eligible upgrade costs, up to a maximum of $2,800 per home. Maximum one heat pump water heater rebate per home, regardless of the number of systems installed.',
    true,
    TIMESTAMP '2026-07-08 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53234'::uuid,
    'esu_timing_within_six_months_of_heat_pump_installation',
    'Checks electrical service upgrade timing against the associated heat pump or heat pump water heater installation date. Pseudocode: 1. Read heat pump installation timing from esu_heat_pump_installation_date_reference. 2. Read ESU service/connection/completion timing from utility supporting-document located field service_completion_or_invoice_date on utility_bill or electrical_utility_upgrade_document. 3. If both dates are parseable, pass when the ESU date is within six months before or after the heat pump installation date; fail when it is outside that window. 4. If the invoice visibly associates the ESU with a heat pump or heat pump water heater on the same invoice and the invoice date is present, pass using the invoice date as a shared timing proxy. 5. Warn when the needed timing evidence is missing or not parseable and same-invoice proxy evidence is not available. 6. In calculation, show ESU service date, heat pump installation date, allowed window, same_invoice_proxy status, and missing date flags when relevant.',
    true,
    'No follow-up is required when the ESU timing is within six months of the associated heat pump or heat pump water heater installation.',
    'Review the ESU utility document date and associated heat pump installation date before deciding whether the six-month timing requirement was met.',
    'The ESU timing appears to be outside the six-month window around the associated heat pump or heat pump water heater installation date.',
    NULL,
    'Requirement PDF: ELECTRICAL SERVICE UPGRADE rebate requirement 3. Uses esu_heat_pump_installation_date_reference, esu_associated_heat_pump_or_hpwh_reference, utility_bill/electrical_utility_upgrade_document service_completion_or_invoice_date, and invoice_versions.di_ocr_invoice_date for same-invoice proxy.',
    'The service upgrade (new wire) is for upgrading to 100, 200 or 400-amp service to an existing home and must be installed within six months of the heat pump installation.',
    true,
    TIMESTAMP '2026-07-10 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53105'::uuid,
    'esu_rebate_math_within_cap',
    'Checks electrical service upgrade rebate amount against the ESU upgrade line amount and the income-level cap. Pseudocode: 1. Read upgrade_specific_rebate_line_amount. 2. Read esu_line_amount. 3. Read users_eligibilitycodes.income_level, falling back to the stored code located field only when needed. 4. Apply cap table: ESP1 $5,000, ESP2 $3,500, ESP3 $1,500. 5. If rebate amount, ESU upgrade amount, or income level is missing or ambiguous, warn. 6. If rebate amount exceeds the income-level cap, fail. 7. If rebate amount exceeds the ESU upgrade amount, fail. 8. Pass only when all named values are clear and the rebate is less than or equal to both the ESU upgrade amount and the applicable cap. 9. In calculation, show upgrade_specific_rebate_line_amount, esu_line_amount, income level, and cap.',
    true,
    'No follow-up is required when the ESU rebate is within the named ESU upgrade amount and income-level cap.',
    'Review the invoice ESU line amount, rebate line, and eligibility-code match before moving the claim forward.',
    'Confirm the invoice ESU line amount, rebate line, and eligibility-code match before asking the contractor for correction.',
    NULL,
    'Requirement PDF: ELECTRICAL SERVICE UPGRADE requirements table. Uses esu_line_amount, upgrade_specific_rebate_line_amount, and users_eligibilitycodes.income_level.',
    '100% of eligible upgrade costs, up to a maximum of $5,000 per home. 100% of eligible upgrade costs, up to a maximum of $3,500 per home. 100% of eligible upgrade costs, up to a maximum of $1,500 per home. Maximum of one electrical service upgrade per home.',
    true,
    TIMESTAMP '2026-07-09 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53151'::uuid,
    'hydronic_awhp_product_validation',
    'Checks hydronic air-to-water / combined heat pump product validation as one code-owned decision. Pseudocode: read invoice product identity fields, read supporting-document product identity fields, confirm both resolve to the same current AWHP product row, write invoice_versions.awhp_product_id when matched, and report subchecks for invoice identity presence, supporting-document match, and product found in download.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched Better Homes BC qualifying-list row.',
    'Refresh the AWHP product-list import if invoice and supporting-document product evidence agree but no current imported list rows are available.',
    'Ask the contractor for corrected invoice/supporting product evidence when product evidence is missing, conflicting, or not found in the imported qualifying list.',
    NULL,
    'The code supplies the detailed invoice/supporting-document product comparison and Better Homes BC qualifying-list match explanation.',
    'be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List.',
    true,
    TIMESTAMP '2026-06-01 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53181'::uuid,
    'ashp_oil_ohpa_product_validation',
    'Checks oil-to-heat-pump OHPA product validation as one code-owned decision. Pseudocode: read hp_ahri_reference from GenAI invoice located fields, read supporting-document ahri_reference, confirm supporting evidence matches invoice AHRI, search claims.v_current_ohpa_products, write invoice_versions.ohpa_product_id when matched, and report subchecks for invoice AHRI presence, supporting-document match, and OHPA product found in download.',
    true,
    'No follow-up is required unless the visible invoice equipment appears inconsistent with the matched NRCan OHPA BC product-list row.',
    'Refresh the OHPA product-list import if invoice and supporting-document AHRI evidence agree but no current imported list rows are available.',
    'Ask the contractor for corrected product evidence when the agreed AHRI reference is not found in the imported OHPA BC product list.',
    NULL,
    'This consolidated rule owns invoice AHRI presence, supporting-document AHRI agreement, and the NRCan OHPA BC product-list lookup for oil ASHP.',
    'be listed as a qualifying system on the Natural Resources Canada Oil to Heat Pump Affordability Qualified Heat Pump Product List for British Columbia.',
    true,
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
    'Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant.',
    true,
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
    'The rebate application and supporting documentation must be submitted by the Registered Contractor within six (6) months of the invoice date.',
    true,
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
    'Eligibility codes for applications received on or after June 18, 2024, are valid for upgrades completed within 6 months of the participants approval date. Beyond this date participants must re-apply to determine their eligibility.',
    true,
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
    'Eligibility codes for applications received on or after June 18, 2024, are valid for upgrades completed within 6 months of the participants approval date. Beyond this date participants must re-apply to determine their eligibility.',
    true,
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

current_upgrade_types = upgrade_type keys on this invoice version
if participant_user_id is missing, warn because prior-rebate history cannot be checked
prior_current_upgrade_types = upgrade_type_keys on current invoice versions for the same participant, excluding this invoice, where invoice status is not ineligible

current_has_space_heating = current_upgrade_types has any key in primary_space_heating_upgrade_types
prior_has_space_heating = prior_current_upgrade_types has any key in primary_space_heating_upgrade_types

warn if participant_user_id is missing
fail if current_has_space_heating and prior_has_space_heating
fail if current has heat_pump_water_heater and prior has heat_pump_water_heater
fail if current has insulation and prior has insulation
fail if current has windows_doors and prior has windows_doors
fail if current has electrical_service_upgrade and prior has electrical_service_upgrade
otherwise pass',
    true,
    'No prior non-ineligible current invoice was found for the same participant and same one-rebate-limited upgrade area.',
    'Could not check prior rebate history because the invoice eligibility code did not match a participant eligibility record in the database. Confirm the eligibility code record, then rerun validation before approving.',
    'A current non-ineligible invoice for this participant already contains the same one-rebate-limited upgrade area. Review the prior invoice before approving another payment.',
    NULL,
    'Uses invoice_versions.participant_user_id, current invoice versions for other invoice parents, claims.invoice_version_upgrade_types, and claims.invoices.status. Primary space heating is checked as one grouped area; heat pump water heater, insulation, windows/doors, and electrical service upgrade are exact upgrade-type checks. The rule warns when participant matching is missing, fails only when a same-area prior rebate is actually found, and otherwise passes.',
    'Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade',
    true,
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
    'Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade',
    true,
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
    'Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2 in the CleanBC Better Homes Energy Savings Program.',
    true,
    TIMESTAMP '2026-06-01 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53106'::uuid,
    'hs_rebate_math_within_cap',
    'Checks whether the claimed health and safety remediation rebate is within the eligible remediation cost and the income-level maximum.

Pseudo-code:
read upgrade_specific_rebate_line_amount from GenAI located fields for this health and safety remediation upgrade
read hs_line_amount from GenAI located fields for this health and safety remediation upgrade
read users_eligibilitycodes.income_level from the matched eligibility-code record, falling back to the code located field if needed

if rebate amount, hs_line_amount, or income level is missing/not numeric, return warn

if income level is 1:
  calculated cap = lesser of 95% of hs_line_amount and $800

if income level is 2:
  calculated cap = lesser of 60% of hs_line_amount and $800

if income level is 3:
  fail when a positive health and safety remediation rebate is claimed because no ESP3 rebate applies

fail if upgrade_specific_rebate_line_amount is greater than hs_line_amount
fail if upgrade_specific_rebate_line_amount is greater than the calculated cap
otherwise pass',
    true,
    'No follow-up is required when the health and safety remediation rebate is within the eligible remediation cost and calculated income-level cap.',
    'Verify the invoice rebate line, health and safety remediation amount, and matched eligibility code before deciding whether the cap is met.',
    'The claimed health and safety remediation rebate appears to exceed the eligible remediation amount or calculated income-level cap.',
    NULL,
    'Uses genai located fields hs_line_amount and upgrade_specific_rebate_line_amount plus claims.users_eligibilitycodes.income_level. ESP1 cap is min(95% of cost, $800); ESP2 cap is min(60% of cost, $800); ESP3 has no health and safety remediation rebate.',
    '95% of eligible upgrade costs, up to a maximum of $800 per home. 60% of eligible upgrade costs, up to a maximum of $800 per home.',
    true,
    TIMESTAMP '2026-07-09 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53107'::uuid,
    'vent_rebate_math_within_cap',
    'Checks whether the claimed ventilation rebate is within the visible ventilation cost and the calculated subtype/income-level maximum.

Pseudo-code:
read upgrade_specific_rebate_line_amount from GenAI located fields for this ventilation upgrade
read vent_line_amount from GenAI located fields for this ventilation upgrade
read users_eligibilitycodes.income_level from the matched eligibility-code record, falling back to the code located field if needed
classify ventilation subtype as bathroom fan, HRV/ERV, or unknown using:
- invoice_versions.vent_fan_product_id when the fan product-list code rule matched
- invoice_versions.herv_product_id when the HRV/ERV product-list code rule matched
- vent_system_type and supporting-document product_category_or_system_type as fallback named evidence

if rebate amount, vent_line_amount, income level, or ventilation subtype is missing/ambiguous, return warn unless a clear failure is present

if subtype is bathroom fan and income level is 1:
  calculated cap = lesser of 95% of vent_line_amount and $300

if subtype is bathroom fan and income level is 2:
  calculated cap = lesser of 60% of vent_line_amount and $300

if subtype is HRV/ERV and income level is 1:
  calculated cap = lesser of 95% of vent_line_amount and $1,600

if subtype is HRV/ERV and income level is 2:
  calculated cap = lesser of 60% of vent_line_amount and $1,600

if income level is 3:
  fail when a positive ventilation rebate is claimed because no ESP3 rebate applies

fail if upgrade_specific_rebate_line_amount is greater than vent_line_amount
fail if upgrade_specific_rebate_line_amount is greater than the calculated cap
otherwise pass',
    true,
    'No follow-up is required when the ventilation rebate is within the eligible ventilation cost and calculated subtype/income-level cap.',
    'Verify the invoice rebate line, ventilation amount, ventilation subtype, and matched eligibility code before deciding whether the cap is met.',
    'The claimed ventilation rebate appears to exceed the eligible ventilation amount or calculated subtype/income-level cap.',
    NULL,
    'Uses genai located fields vent_line_amount, upgrade_specific_rebate_line_amount, vent_system_type; supporting-document product_category_or_system_type; invoice_versions.herv_product_id; invoice_versions.vent_fan_product_id; and claims.users_eligibilitycodes.income_level. Bathroom fan caps: ESP1 min(95% of cost, $300), ESP2 min(60% of cost, $300), ESP3 no rebate. HRV/ERV caps: ESP1 min(95% of cost, $1,600), ESP2 min(60% of cost, $1,600), ESP3 no rebate.',
    '95% of eligible upgrade costs, up to a maximum of $300 per home. 60% of eligible upgrade costs, up to a maximum of $300 per home. 95% of eligible upgrade costs, up to a maximum of $1600 per home. 60% of eligible upgrade costs, up to a maximum of $1600 per home.',
    true,
    TIMESTAMP '2026-07-09 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53120'::uuid,
    'vent_herv_nrcan_product_validation',
    'Checks whether an HRV/ERV ventilation product is listed in the imported NRCan ENERGY STAR heat/energy recovery ventilator product list.

Pseudo-code:
1. Run only for ventilation upgrade types when this code rule is enabled.
2. Read invoice-side named fields: vent_system_type, vent_manufacturer, vent_model_number, vent_make_model, vent_energy_star_reference, and vent_nrcan_or_product_list_reference.
3. Read supporting-document named fields from documents on the same invoice version: brand_and_model, model_number, product_category_or_system_type, energy_star_reference, nrcan_reference, and product_list_reference.
4. If the named evidence clearly indicates bathroom/exhaust fan and does not indicate HRV/ERV, return info because the HRV/ERV product-list lookup is not applicable.
5. If the named evidence does not clearly indicate HRV/ERV, return warn so admin can review vent_system_type and product evidence.
6. Extract usable model values from invoice fields and supporting-document fields.
7. If invoice model evidence is missing, warn because the invoice does not independently identify the installed HRV/ERV product.
8. If supporting-document model evidence is missing, warn because the invoice product is not corroborated by supporting product evidence.
9. If no current imported HERV product-list rows are available, warn and ask admin to refresh the HERV product-list download.
10. Search claims.v_current_herv_products by normalized model number, allowing exact, normalized, regex, and contained-model matches with manufacturer/brand as a scoring boost.
11. Resolve invoice evidence and supporting-document evidence separately.
12. If either side does not resolve to a product-list row, fail.
13. If invoice and supporting-document evidence resolve to different product rows, fail.
14. If both resolve to the same product row, pass and store that row in invoice_versions.herv_product_id.
15. In calculation, show invoice model evidence, supporting-document model evidence, source availability, matched herv_products.id when present, and whether the rule was not applicable because the visible ventilation system was a bathroom fan.',
    true,
    'No follow-up is required unless the visible ventilation equipment appears inconsistent with the matched NRCan ENERGY STAR HERV product-list row.',
    'Refresh the HERV product-list import if invoice and supporting-document product evidence agree but no current imported list rows are available, or review the equipment type if HRV/ERV evidence is unclear.',
    'Ask the contractor for corrected invoice/supporting product evidence when HRV/ERV product evidence is missing, conflicting, or not found in the imported NRCan ENERGY STAR HERV product list.',
    'This rule records information only when the visible ventilation evidence is for a bathroom/exhaust fan rather than an HRV/ERV.',
    'Code-owned deterministic lookup for the ventilation requirement that heat/energy recovery ventilators be ENERGY STAR certified and listed on NRCan searchable product list.',
    'heat/energy recovery ventilators must be ENERGY STAR® certified and listed on Natural Resource’s Canada’s searchable product list.',
    true,
    TIMESTAMP '2026-07-09 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53121'::uuid,
    'vent_fan_energy_star_product_validation',
    'Checks whether a bathroom, utility, exhaust, or ventilating fan product is listed in the imported ENERGY STAR certified ventilating fan product list.

Pseudo-code:
1. Run only for ventilation upgrade types when this code rule is enabled.
2. Read invoice-side named fields: vent_system_type, vent_manufacturer, vent_model_number, vent_make_model, vent_energy_star_reference, and vent_nrcan_or_product_list_reference.
3. Read supporting-document named fields from documents on the same invoice version: brand_and_model, model_number, product_category_or_system_type, energy_star_reference, and product_list_reference.
4. If the named evidence clearly indicates HRV/ERV rather than a bathroom/utility/exhaust fan, return info because the fan product-list lookup is not applicable.
5. If the named evidence does not clearly identify fan equipment, return warn so admin can review vent_system_type and product evidence.
6. Extract usable model values from invoice fields and supporting-document fields.
7. If invoice model evidence is missing, warn because the invoice does not independently identify the installed fan product.
8. If supporting-document model evidence is missing, warn because the invoice product is not corroborated by supporting product evidence.
9. If no current imported fan product-list rows are available, warn and ask admin to refresh the ENERGY STAR fan product-list download.
10. Search claims.v_current_vent_fan_products by normalized model number, allowing exact, normalized, regex, and contained-model matches with manufacturer/brand as a scoring boost.
11. Resolve invoice evidence and supporting-document evidence separately.
12. If either side does not resolve to a product-list row, fail when the visible evidence clearly identifies a fan model but it is absent from the current imported list.
13. If invoice and supporting-document evidence resolve to different product rows, fail.
14. If both resolve to the same product row, pass and store that row in invoice_versions.vent_fan_product_id.
15. In calculation, show invoice model evidence, supporting-document model evidence, source availability, matched vent_fan_products.id when present, fan type, markets, ENERGY STAR Unique ID, and CB Model Identifier.',
    true,
    'No follow-up is required unless the visible ventilation equipment appears inconsistent with the matched ENERGY STAR ventilating-fan product-list row.',
    'Refresh the ENERGY STAR fan product-list import if invoice and supporting-document product evidence agree but no current imported list rows are available, or review the equipment type if fan evidence is unclear.',
    'Ask the contractor for corrected invoice/supporting product evidence when fan product evidence is conflicting or not found in the imported ENERGY STAR certified ventilating fan product list.',
    'This rule records information only when the visible ventilation evidence is for HRV/ERV rather than a bathroom/utility/exhaust fan.',
    'Code-owned deterministic lookup for the ventilation requirement that fans be ENERGY STAR certified and listed on the EPA/DOE searchable product list.',
    'fans must be ENERGY STAR certified and listed on the US Environmental Protection Agency and US Department of Energy’s searchable product list.',
    true,
    TIMESTAMP '2026-07-09 00:00:00',
    NOW()
  ),
  (
    '590f2f3a-3e23-449a-a7d4-2f35c3d53122'::uuid,
    'vent_fan_capacity_meets_minimum',
    'Checks whether a bathroom, utility, exhaust, or ventilating fan has capacity evidence of at least 85 cfm (40 L/s) at 50 Pa (0.2 in. w.c.).

Pseudo-code:
1. Run only for ventilation upgrade types when this code rule is enabled.
2. Use the same named product identity fields as vent_fan_energy_star_product_validation to determine whether the visible ventilation equipment is a bathroom/utility/exhaust fan or HRV/ERV.
3. If the named evidence clearly indicates HRV/ERV rather than a bathroom/utility/exhaust fan, return info because this fan-capacity requirement is not applicable.
4. Use supporting-document named capacity fields bathroom_fan_cfm and static_pressure from documents on the same invoice version.
5. If visible named supporting-document capacity evidence clearly shows at least 85 cfm or 40 L/s at 50 Pa or 0.2 in. w.c., pass.
6. If visible named supporting-document capacity evidence clearly shows less than 85 cfm or 40 L/s at 50 Pa or 0.2 in. w.c., fail.
7. If invoice and supporting-document product evidence resolved to the same imported ENERGY STAR fan product row, read claims.v_current_vent_fan_products.bathroom_utility_airflow_at_0_25_in_wg for that row.
8. If bathroom_utility_airflow_at_0_25_in_wg is at least 85 cfm, pass because this is conservative pass evidence at a stricter listed pressure than 0.2 in. w.c.
9. If the matched product row has a bathroom_utility_airflow_at_0_25_in_wg value below 85 cfm, warn because the imported list field uses 0.25 in. w.g. and does not by itself prove failure at 0.2 in. w.c.; admin should verify a product specification sheet or row detail.
10. If generic cfm evidence is present but does not clearly state 50 Pa or 0.2 in. w.c., warn for admin review rather than pass.
11. If neither a matched product-list row nor named supporting-document capacity fields provide usable capacity evidence, warn.
12. In calculation, show the named capacity fields, matched vent_fan_products.id when present, bathroom_utility_airflow_at_0_25_in_wg, airflow_1_cfm, airflow_2_cfm, airflow_3_cfm, and the exact comparison used.',
    true,
    'No follow-up is required when named visible evidence or the matched imported fan product-list row confirms at least 85 cfm at the required or stricter pressure.',
    'Verify a product specification sheet or ENERGY STAR row detail when capacity evidence is present but the static pressure is missing or the imported 0.25 in. w.g. airflow does not independently confirm the threshold.',
    'Ask the contractor for corrected product specification evidence when named evidence clearly shows the fan below 85 cfm at 50 Pa / 0.2 in. w.c.',
    'Resolve the fan product-list match or request capacity/static-pressure evidence before relying on this requirement.',
    'Code-owned deterministic check for the ventilation requirement that fans have capacity of at least 85 cfm (40 L/s) at static pressure of 50 Pa (0.2 in. w.c.).',
    'fans must have a capacity of at least 85 cfm (40 L/s), at static pressure of 50 pa (0.2” w.c.).',
    true,
    TIMESTAMP '2026-07-09 00:00:00',
    NOW()
  )
),
contractor_display_name_metadata (
  code_rule_key,
  contractor_display_name
) AS (
  VALUES
  ('hp_ahri_product_validation', 'Heat pump AHRI product eligibility'),
  ('ashp_electric_wood_rebate_math_within_cap', 'Heat pump rebate amount for electric or wood conversion'),
  ('ashp_product_specs_meet_requirements', 'Heat pump product specifications'),
  ('ashp_multisplit_minimum_two_indoor_heads', 'Minimum indoor heads for a multi-split heat pump'),
  ('ashp_gas_propane_rebate_math_within_cap', 'Heat pump rebate amount for gas or propane conversion'),
  ('ashp_fossil_northern_top_up_within_cap', 'Northern heat pump top-up amount for fossil-fuel conversion'),
  ('ashp_oil_rebate_math_within_cap', 'Heat pump rebate amount for oil conversion'),
  ('dfhp_rebate_math_within_cap', 'Dual-fuel heat pump rebate amount'),
  ('dfhp_product_specs_meet_requirements', 'Dual-fuel heat pump product specifications'),
  ('heat_pump_northern_top_up_3000_within_cap', 'Northern heat pump top-up amount'),
  ('atw_rebate_math_within_cap', 'Air-to-water heat pump rebate amount'),
  ('cshp_rebate_math_within_cap', 'Combined space and water heat pump rebate amount'),
  ('hp_product_minimum_capacity_at_minus_5c', 'Heat pump cold-weather capacity'),
  ('hp_product_efficiency_threshold', 'Heat pump energy efficiency'),
  ('hpwh_neea_product_validation', 'Heat pump water heater product eligibility'),
  ('hpwh_rebate_math_within_cap', 'Heat pump water heater rebate amount'),
  ('esu_timing_within_six_months_of_heat_pump_installation', 'Electrical service upgrade timing'),
  ('esu_rebate_math_within_cap', 'Electrical service upgrade rebate amount'),
  ('hydronic_awhp_product_validation', 'Air-to-water heat pump product eligibility'),
  ('ashp_oil_ohpa_product_validation', 'Oil-conversion heat pump product eligibility'),
  ('first_class_invoice_fields_present', 'Required invoice information'),
  ('submission_within_six_months', 'Application submitted within six months'),
  ('eligibility_code_valid_for_invoice_date', 'Eligibility code valid on the invoice date'),
  ('eligibility_code_found_in_database', 'Eligibility code recognized'),
  ('prior_same_upgrade_type_rebate_payment_found', 'Previous rebate for the same upgrade'),
  ('current_invoice_cannot_contain_multiple_space_systems', 'One primary heating system per invoice'),
  ('income_level_1_or_2_required', 'Income qualification for this upgrade'),
  ('hs_rebate_math_within_cap', 'Health and safety remediation rebate amount'),
  ('vent_rebate_math_within_cap', 'Ventilation rebate amount'),
  ('vent_herv_nrcan_product_validation', 'HRV or ERV product eligibility'),
  ('vent_fan_energy_star_product_validation', 'Bathroom fan ENERGY STAR eligibility'),
  ('vent_fan_capacity_meets_minimum', 'Bathroom fan airflow capacity')
),
source_quote_metadata (
  code_rule_key,
  section_name,
  action_sentence
) AS (
  VALUES
  ('ashp_electric_wood_rebate_math_within_cap', $$AIR SOURCE HEAT PUMP electric and wood requirements tables$$, $$Check the invoice rebate and upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('ashp_fossil_northern_top_up_within_cap', $$AIR SOURCE HEAT PUMP fossil-fuel conversion requirements table$$, $$Check that the invoice and supporting documents show the northern top-up amount, equipment type, location, and BC Hydro service evidence. Upload clearer documents if needed.$$),
  ('ashp_gas_propane_rebate_math_within_cap', $$AIR SOURCE HEAT PUMP (CONVERT FROM NATURAL GAS OR PROPANE) requirements table$$, $$Check the invoice rebate and upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('ashp_multisplit_minimum_two_indoor_heads', $$AIR SOURCE HEAT PUMP requirements table$$, $$Check that the invoice or product evidence shows at least two indoor head units for a ductless multi-split installation. Upload clearer product evidence if needed.$$),
  ('ashp_oil_ohpa_product_validation', $$AIR SOURCE HEAT PUMP (CONVERT FROM OIL)$$, $$Check the heat pump product reference on the invoice and supporting documents. If the product should be eligible but is not recognized, contact program staff for assistance.$$),
  ('ashp_oil_rebate_math_within_cap', $$AIR SOURCE HEAT PUMP (CONVERT FROM OIL) requirements table$$, $$Check the invoice rebate and upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('ashp_product_specs_meet_requirements', $$AIR SOURCE HEAT PUMP requirements table$$, $$Check that the invoice or product documents clearly show the required efficiency, variable-speed, and capacity details. Upload clearer product evidence if needed.$$),
  ('atw_rebate_math_within_cap', $$AIR-TO-WATER AND COMBINED HEAT PUMP requirements table$$, $$Check the invoice rebate and upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('cshp_rebate_math_within_cap', $$AIR-TO-WATER AND COMBINED HEAT PUMP requirements table$$, $$Check the invoice rebate and upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('current_invoice_cannot_contain_multiple_space_systems', $$General Eligibility Requirements$$, $$Check whether this invoice is claiming more than one primary space-heating system rebate. If so, upload a corrected invoice or contact program staff for assistance.$$),
  ('dfhp_product_specs_meet_requirements', $$DUAL FUEL DUCTED HEAT PUMP requirements table$$, $$Check that the invoice or product documents clearly show the required dual-fuel heat pump efficiency and capacity details. Upload clearer product evidence if needed.$$),
  ('dfhp_rebate_math_within_cap', $$DUAL FUEL DUCTED HEAT PUMP requirements table$$, $$Check the invoice rebate and upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('eligibility_code_found_in_database', $$General Eligibility Requirements$$, $$Contact program staff for assistance if this eligibility code should be valid for the participant and this invoice.$$),
  ('eligibility_code_valid_for_invoice_date', $$General Eligibility Requirements$$, $$Check that the invoice date is within the eligibility-code validity window. If the code or dates look wrong, contact program staff for assistance.$$),
  ('esu_rebate_math_within_cap', $$ELECTRICAL SERVICE UPGRADE requirements table$$, $$Check the invoice rebate and electrical service upgrade cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('esu_timing_within_six_months_of_heat_pump_installation', $$ELECTRICAL SERVICE UPGRADE$$, $$Check that the service-upgrade date is within six months of the associated heat-pump installation. Upload clearer date evidence if needed.$$),
  ('first_class_invoice_fields_present', $$General Eligibility Requirements$$, $$Check that the invoice has the required invoice details, including the itemized CleanBC rebate and amount-due math. Upload a corrected invoice if needed.$$),
  ('heat_pump_northern_top_up_3000_within_cap', $$applicable heat pump requirements table$$, $$Check that the invoice and supporting documents show the northern top-up amount, location, and BC Hydro service evidence. Upload clearer documents if needed.$$),
  ('hp_ahri_product_validation', $$applicable heat pump product requirements$$, $$Check that the AHRI reference on the invoice matches the supporting product documents. If the product should be eligible but is not recognized, contact program staff for assistance.$$),
  ('hp_product_efficiency_threshold', $$AIR SOURCE HEAT PUMP requirements table$$, $$Check that the invoice or product documents clearly show the required SEER/HSPF or SEER2/HSPF2 values. Upload clearer product evidence if needed.$$),
  ('hp_product_minimum_capacity_at_minus_5c', $$AIR SOURCE HEAT PUMP requirements table$$, $$Check that the invoice or product documents clearly show the 12,000 BTU minimum-capacity requirement. Upload clearer product evidence if needed.$$),
  ('hpwh_neea_product_validation', $$HEAT PUMP WATER HEATER$$, $$Check the heat pump water heater model on the invoice and supporting documents. If the product should be eligible but is not recognized, contact program staff for assistance.$$),
  ('hpwh_rebate_math_within_cap', $$HEAT PUMP WATER HEATER requirements table$$, $$Check the invoice rebate and heat pump water heater cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('hs_rebate_math_within_cap', $$HEALTH AND SAFETY REMEDIATION requirements table$$, $$Check the invoice rebate and health and safety remediation cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$),
  ('hydronic_awhp_product_validation', $$AIR-TO-WATER AND COMBINED HEAT PUMP$$, $$Check the hydronic heat pump product reference on the invoice and supporting documents. If the product should be eligible but is not recognized, contact program staff for assistance.$$),
  ('income_level_1_or_2_required', $$applicable Income Level 1 or 2 limited upgrade section$$, $$Contact program staff for assistance if the participant should qualify as Income Level 1 or 2 for this upgrade.$$),
  ('prior_same_upgrade_type_rebate_payment_found', $$General Eligibility Requirements$$, $$Contact program staff for assistance if this participant has not already received the same primary space-heating rebate.$$),
  ('submission_within_six_months', $$General Eligibility Requirements$$, $$Check the invoice date and submission timing. If the dates are not clear, upload clearer date evidence or contact program staff for assistance.$$),
  ('vent_fan_capacity_meets_minimum', $$VENTILATION$$, $$Check that the fan product evidence clearly shows at least 85 cfm at the required static pressure. Upload clearer product evidence if needed.$$),
  ('vent_fan_energy_star_product_validation', $$VENTILATION$$, $$Check the bathroom fan model on the invoice and supporting documents. If the product should be eligible but is not recognized, contact program staff for assistance.$$),
  ('vent_herv_nrcan_product_validation', $$VENTILATION$$, $$Check the HRV/ERV model on the invoice and supporting documents. If the product should be eligible but is not recognized, contact program staff for assistance.$$),
  ('vent_rebate_math_within_cap', $$VENTILATION requirements table$$, $$Check the invoice rebate and ventilation cost. If the amounts are not clear or appear over the limit, upload a corrected invoice or contact program staff for assistance.$$)
)
INSERT INTO claims.code_rules (
  id,
  code_rule_key,
  contractor_display_name,
  description,
  enabled,
  pass_admin_message,
  warn_admin_message,
  fail_admin_message,
  info_admin_message,
  admin_notes,
  source_quote,
  contractor_visibility,
  contractor_blocking_policy,
  created_at,
  updated_at
)
SELECT
  id,
  code_rule_key,
  contractor_display_name_metadata.contractor_display_name,
  description,
  enabled,
  pass_admin_message,
  warn_admin_message,
  fail_admin_message,
  info_admin_message,
  admin_notes,
  CASE
    WHEN source_quote_metadata.section_name IS NULL THEN source_quote
    ELSE '**From the ' || source_quote_metadata.section_name || ' section of the PDF:**' || E'\n\n' ||
      regexp_replace(replace(replace(source_quote, E'\r\n', E'\n'), E'\r', E'\n'), '(^|\n)([^\n]+)', '\1_\2_', 'g') ||
      E'\n\n**Action:** ' || source_quote_metadata.action_sentence
  END AS source_quote,
  CASE
    WHEN legacy_contractor_visible_flag THEN 'fail_only'
    ELSE 'hidden'
  END AS contractor_visibility,
  'non_blocking' AS contractor_blocking_policy,
  created_at,
  updated_at
FROM code_rules_seed
JOIN contractor_display_name_metadata
  USING (code_rule_key)
LEFT JOIN source_quote_metadata
  USING (code_rule_key)
ON CONFLICT (code_rule_key) DO UPDATE SET
  contractor_display_name = EXCLUDED.contractor_display_name,
  description = EXCLUDED.description,
  pass_admin_message = EXCLUDED.pass_admin_message,
  warn_admin_message = EXCLUDED.warn_admin_message,
  fail_admin_message = EXCLUDED.fail_admin_message,
  info_admin_message = EXCLUDED.info_admin_message,
  admin_notes = COALESCE(claims.code_rules.admin_notes, EXCLUDED.admin_notes),
  source_quote = EXCLUDED.source_quote,
  contractor_visibility = EXCLUDED.contractor_visibility,
  contractor_blocking_policy = EXCLUDED.contractor_blocking_policy,
  updated_at = NOW();

WITH code_rule_upgrade_type_seed (
  code_rule_key,
  upgrade_type_key
) AS (
  VALUES
  ('hp_ahri_product_validation', 'air_source_heat_pump_electric'),
  ('hp_ahri_product_validation', 'air_source_heat_pump_wood'),
  ('hp_ahri_product_validation', 'air_source_heat_pump_gas_propane'),
  ('hp_ahri_product_validation', 'dual_fuel_ducted_heat_pump'),
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
  ('income_level_1_or_2_required', 'air_source_heat_pump_electric'),
  ('income_level_1_or_2_required', 'air_source_heat_pump_wood'),
  ('income_level_1_or_2_required', 'health_and_safety_remediation'),
  ('income_level_1_or_2_required', 'ventilation'),
  ('vent_rebate_math_within_cap', 'ventilation'),
  ('vent_herv_nrcan_product_validation', 'ventilation'),
  ('vent_fan_energy_star_product_validation', 'ventilation'),
  ('vent_fan_capacity_meets_minimum', 'ventilation'),
  ('esu_rebate_math_within_cap', 'electrical_service_upgrade'),
  ('esu_timing_within_six_months_of_heat_pump_installation', 'electrical_service_upgrade'),
  ('hpwh_neea_product_validation', 'heat_pump_water_heater'),
  ('hpwh_rebate_math_within_cap', 'heat_pump_water_heater'),
  ('hs_rebate_math_within_cap', 'health_and_safety_remediation'),
  ('hydronic_awhp_product_validation', 'air_to_water_heat_pump'),
  ('hydronic_awhp_product_validation', 'combined_space_water_heat_pump'),
  ('ashp_oil_ohpa_product_validation', 'air_source_heat_pump_oil')
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
