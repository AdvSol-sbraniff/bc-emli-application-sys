BEGIN;

-- Retired GenAI rules now handled by deterministic code rules or narrower prompts.
-- Delete before inserting current mappings so old rule-order slots do not conflict.
DELETE FROM claims.genai_rules
WHERE genai_rule_key IN (
  'ashp_electric_product_reference_present',
  'ashp_gas_propane_product_reference_present',
  'ashp_oil_product_reference_present',
  'ashp_wood_product_reference_present',
  'atw_not_combined_or_hpwh_scope',
  'atw_product_reference_present',
  'atw_scope_present',
  'atw_rebate_math_within_cap',
  'cshp_product_reference_present',
  'cshp_rebate_math_within_cap',
  'hp_product_reference_present',
  'hpwh_fossil_removal_evidence_present',
  'hpwh_rebate_math_within_cap',
  'hpwh_secondary_system_flag',
  'hydronic_product_reference_present',
  'income_level_allows_rebate',
  'wd_income_level_and_vancouver_review',
  'ashp_electric_utility_account_supporting_document_attached',
  'ashp_electric_utility_account_supporting_document_present',
  'ashp_gas_propane_removal_reference_present',
  'ashp_gas_propane_removal_supporting_document_attached',
  'ashp_oil_consumption_baseline_reference_present',
  'ashp_oil_consumption_proof_supporting_document_attached',
  'ashp_oil_removal_reference_present',
  'ashp_oil_removal_supporting_document_attached',
  'ashp_wood_removal_or_wett_reference_present',
  'dfhp_heat_load_calc_reference_present',
  'dfhp_png_or_tank_propane_path_present',
  'esu_utility_upgrade_evidence_present',
  'hs_before_after_photos_present',
  'income_verification_supporting_documents_present',
  'ins_supporting_document_reference_present',
  'utility_account_supporting_document_present',
  'wd_label_photo_reference_present',
  'wd_quote_preapproval_reference_present',
  'ashp_electric_main_living_area_or_primary_capacity_present',
  'ashp_wood_backup_and_primary_capacity_review',
  'ashp_electric_no_existing_heat_pump_flag',
  'ashp_wood_no_existing_heat_pump_flag',
  'hp_fossil_no_existing_heat_pump_flag',
  'hydronic_no_existing_heat_pump_flag',
  'ashp_electric_primary_system_scope_present',
  'ashp_gas_propane_non_integrated_area_review',
  'dfhp_fossil_modification_or_removal_supporting_document_attached',
  'dfhp_fossil_backup_system_supporting_document_attached',
  'dfhp_controls_reference_present',
  'dfhp_description_sufficient_for_review',
  'dfhp_dual_fuel_scope_present',
  'dfhp_non_integrated_area_review',
  'dfhp_heat_load_calc_supporting_document_attached',
  'dfhp_rebate_math_within_cap',
  'hydronic_fossil_removal_supporting_document_attached',
  'hydronic_non_integrated_area_review',
  'ashp_gas_propane_rebate_math_within_cap',
  'ashp_oil_rebate_math_within_cap',
  'ashp_oil_non_integrated_area_review',
  'esu_description_sufficient_for_review',
  'hp_description_sufficient_for_review',
  'hpwh_non_integrated_area_review',
  'hpwh_description_sufficient_for_review',
  'hs_description_sufficient_for_review',
  'ins_description_sufficient_for_review',
  'vent_description_sufficient_for_review',
  'wd_description_sufficient_for_review'
);

-- Retired GenAI located fields replaced by clearer field keys.
DELETE FROM claims.genai_located_fields
WHERE genai_field_key IN (
  'dfhp_existing_png_or_tank_propane_evidence',
  'esu_utility_bill_or_invoice_reference',
  'hp_non_integrated_area_preapproval_reference',
  'hpwh_non_integrated_area_preapproval_reference'
);

WITH genai_rules_seed (
  genai_rule_key,
  prompt_text,
  enabled,
  created_at,
  updated_at
) AS (
  VALUES
  ('ashp_electric_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by hard-wired electric space heating and that the new air-source heat pump is replacing that system.
A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.
Use invoice evidence first, and treat supporting-document facts only as corroborating context.
Set rule_result="pass" when electric primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, or is contradicted by supplied supporting-document facts.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_electric_backup_heat_electric_present', 'Check whether the electric-to-heat-pump backup space heating system is electric.

Use only these named fields and facts:
- hp_backup_heat_evidence: visible backup heat evidence and whether it appears electric, wood, fossil fuel, or unclear.
- hp_existing_electric_heat_evidence: visible hard-wired electric heating evidence, only as corroborating context when it also speaks to retained or backup heat.

For AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC), the back-up space heating system must be electric.

Set rule_result="pass" when hp_backup_heat_evidence clearly shows electric backup heat, such as electric baseboard, electric resistance, electric furnace, electric boiler, radiant electric ceiling/floor, or other electric backup space heating.
Set rule_result="warn" when backup heat context is missing, ambiguous, or only implied by the prior electric heating system without clear backup wording.
Set rule_result="fail" when hp_backup_heat_evidence clearly shows wood, natural gas, propane, oil, dual-fuel fossil backup, or another non-electric backup space heating system.
In calculation, state hp_backup_heat_evidence and whether the backup heat is electric, non-electric, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_gas_propane_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by fossil fuel natural gas or propane and that the new air-source heat pump is replacing that system.

Natural-gas or propane primary-heating evidence includes natural gas furnace, propane furnace, fossil-fuel furnace, gas boiler, propane boiler, FortisBC gas, PNG gas, propane tank, or similar wording.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.

Use invoice evidence first, and treat supporting-document facts only as corroborating context.

Set rule_result="pass" when natural-gas/propane primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, or is contradicted by supplied supporting-document facts.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_fossil_fuel_removal_supporting_document_attached', 'Check whether an acceptable fossil-fuel heating-system removal supporting document is present for this air-source heat pump conversion from natural gas, propane, or oil.

Use only these named document types and located fields:
- permit_document: permit_date, permit_address, authority_name, permit_scope_or_equipment_reference, and permit_status_or_completion_evidence.
- fossil_fuel_removal_proof: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, and removal_scope_or_description.
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.

Accepted path 1: local government permit or inspection report.
For this path, require a permit_document with supporting_document_routing_quality="usable", readable permit_date showing an inspection/permit/completion/approval date, readable permit_address showing the address where inspection/removal-related work took place, and permit_scope_or_equipment_reference or permit_status_or_completion_evidence that supports fossil-fuel heating-system removal, inspection, decommissioning, capping, venting, oil-tank removal, or related completion.

Accepted path 2: invoice from the removal company or heat-pump installation company.
For this path, require fossil_fuel_removal_proof with supporting_document_routing_quality="usable", readable removal_scope_or_description describing the work completed for natural-gas, propane, oil, or other fossil-fuel heating-system removal/decommissioning/capping/disconnection. For oil conversions, the description should support oil heating-system and oil-tank removal when those facts are visible. Also require readable removal_date_or_permit_reference showing the date of removal or decommissioning.

Set rule_result="pass" when either accepted path is present, usable, and has the required located-field evidence for that path.
Set rule_result="warn" when an acceptable document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears relevant but one or more required located fields for its path are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when both acceptable document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".
In calculation, state which path was used: permit_or_inspection, removal_invoice, both, missing, or unclear; then list the required fields for that path and whether each is present/usable.
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the path decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_oil_consumption_baseline_proof_present', 'Check whether the submitted evidence proves the 500 L annual oil-consumption baseline for this oil-to-heat-pump claim.

Use only these named document types and located fields:
- utility_bill: utility_service_type_or_fuel_evidence, utility_provider, account_or_bill_date, account_number_or_reference, and fuel_consumption_quantity_or_period.
- utility_account_document: utility_service_type_or_fuel_evidence, utility_provider, account_or_bill_date, account_number_or_reference, and fuel_consumption_quantity_or_period.
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.

Accepted proof may be an oil receipt, heating-oil or fuel-oil bill, fuel delivery invoice, or similar oil-consumption invoice when it is routed under utility_bill or utility_account_document and the located fields support oil/fuel-oil consumption in the 12 months prior to application.

Set rule_result="pass" when utility_bill or utility_account_document is present with supporting_document_routing_quality="usable" and the located fields show readable oil/fuel-oil consumption proof tied to the participant/home or account, with a bill/receipt/invoice date or service period in the 12 months prior to application, and the visible quantity shows at least 500 L annually or enough bills/receipts/invoices for admin to confirm at least 500 L.
Set rule_result="warn" when an accepted document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears to be oil-consumption proof but the fuel type, date/service period, quantity, account/home tie, or located-field text is missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when both accepted document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, present only with supporting_document_routing_quality="unusable", clearly do not show oil/fuel-oil consumption proof, or clearly show consumption below 500 L for the relevant annual period.
In calculation, state whether utility_bill, utility_account_document, both, missing, or unclear was used; list the relevant located fields and whether each is present/usable; and show the visible oil quantity/date comparison to the 500 L annual baseline when available.
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_oil_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by oil and that the new air-source heat pump is replacing that system.

Oil primary-heating evidence includes oil furnace, oil boiler, oil-fired heating system, heating oil tank, fuel oil delivery or consumption, or similar wording.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21 degrees Celsius. A fireplace is not considered a primary heating system.

Use invoice evidence first, and treat supporting-document facts only as corroborating context.

Set rule_result="pass" when oil primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, relies only on a fireplace as the prior primary heating system, or is contradicted by supplied supporting-document facts.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_wood_backup_heat_not_fossil_present', 'Check whether visible backup heat evidence for this wood-to-heat-pump upgrade appears to be wood or electric rather than fossil fuel.
Set rule_result="pass" when backup heat is clearly wood/electric or no fossil-backup concern is visible.
Set rule_result="warn" when backup fuel context is missing or ambiguous.
Set rule_result="fail" when visible evidence shows fossil-fuel backup remains as a backup or primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_wood_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by a wood or solid fuel heating system and that the new air-source heat pump is replacing that system.

Wood or solid fuel heating evidence includes wood stove, pellet stove, insert, wood furnace, solid fuel furnace, or similar wording.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.

Use invoice evidence first, and treat supporting-document facts only as corroborating context.

Set rule_result="pass" when wood/solid-fuel primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, or is contradicted by supplied supporting-document facts.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_wood_removal_or_wett_supporting_document_attached', 'Check whether the required wood/solid-fuel removal or safe-retention supporting document is present for this wood-to-heat-pump upgrade.

Use only these named fields and facts:
- hp_wood_system_removal_or_wett_evidence: invoice evidence about whether the existing wood or solid-fuel heating system was removed, retained, WETT-inspected, decommissioned, or otherwise addressed.
- supporting_document_summary_for_upgrade_type: the routed supporting-document summary for this upgrade type, including before_after_photo_set and wett_report document types, routing quality, not-present document types, and located fields.
- before_after_photo_set located fields, including photo_role, visible_subject_or_area, visible_condition_summary, image_quality_or_legibility, and visible_text_or_label_values.
- wett_report located fields, including wett_inspection_date, wett_inspector_certification_number, site_address, compliance_or_removal_conclusion, wett_inspector_or_company_name, and wett_appliance_or_system_reference.

If the visible evidence shows the wood or solid-fuel heating system was removed, require before_after_photo_set evidence for the removed wood/solid-fuel heating system.
If the visible evidence shows the wood or solid-fuel heating system was retained in safe and working order, require wett_report evidence.
If the removal/retention path is unclear, do not guess which document is required.

Set rule_result="pass" when the removal/retention path is clear and the required document type for that path is present with supporting_document_routing_quality="usable" and enough readable located-field evidence for review.
Set rule_result="warn" when the removal/retention path is unclear, or when the required document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or key located fields are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when the removal/retention path is clear and the required document type for that path is missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".
In calculation, state the visible path used: removed, retained, or unclear; then list the required document type and whether it is present/usable.
In evidence_text, cite the exact invoice or supporting-document wording/located fields that support the path and document decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('contractor_identity_matches_record', 'Check whether the contractor/vendor identity visible on the invoice appears to match the contractor record that uploaded or owns the invoice.
Use contractors.business_name and contractors.address from the supplied database values.
Use invoice_contractor_name and invoice_contractor_address from the OCR/DI JSON.
Set rule_result="pass" when the visible contractor name clearly matches the database contractor name, including obvious legal-name/DBA/trade-name formatting differences, and the visible address does not contradict the database address.
Set rule_result="info" when the contractor appears to match but there is a harmless variation worth explaining, such as abbreviated legal suffix, DBA wording, missing unit number, or invoice address omitted while the name clearly matches. This is context only, not a requested fix.
Set rule_result="warn" when the visible contractor name or address is missing/ambiguous, or when the database contractor fact is missing, so admin should verify identity from the contractor record or supporting documents.
Set rule_result="fail" when the invoice visibly appears to belong to a different contractor/vendor than the database contractor record.
In evidence_text, include the visible invoice contractor name/address and the supplied database contractor name/address.
In reason_and_likely_causes, explain exactly what matches, what differs, and whether the admin should ignore, verify, or treat it as a likely wrong-contractor upload.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_combined_space_and_water_scope_present', 'Check whether the invoice clearly shows both space-heating and domestic-hot-water scope in one combined heat-pump upgrade.
Set rule_result="warn" if the combined nature is ambiguous and admin should verify whether this is one combined space/water system.
Set rule_result="fail" if only space heating is clearly visible or only water heating is clearly visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_scope_present', 'Check whether invoice text supports combined space and water heat-pump scope.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_fossil_fuel_removal_or_modification_supporting_document_attached', 'Check whether an acceptable fossil-fuel propane or natural-gas system removal or modification supporting document is present for this dual-fuel ducted heat-pump upgrade.

Use only these named document types and located fields:
- permit_document: permit_date, permit_address, authority_name, permit_scope_or_equipment_reference, and permit_status_or_completion_evidence.
- fossil_fuel_removal_proof: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, and removal_scope_or_description.
- fossil_backup_system_document: backup_equipment_type, backup_system_document_date_or_permit_reference, site_address, contractor_or_authority_name, and backup_system_scope_or_description.
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.

Accepted path 1: local government permit or inspection report.
For this path, require permit_document with supporting_document_routing_quality="usable", readable permit_date showing an inspection/permit/completion/approval date, readable permit_address showing where inspection or fossil-fuel work took place, and permit_scope_or_equipment_reference or permit_status_or_completion_evidence that supports propane/natural-gas system removal, modification, capping, disconnection, piping/vent/fuel-container modification, inspection, completion, or related by-law/compliance work.

Accepted path 2: invoice from the removal or modification company or heat-pump installation company.
For this path, accept fossil_fuel_removal_proof or fossil_backup_system_document with supporting_document_routing_quality="usable". Require readable contractor_or_authority_name when visible, readable site_address or another clear site tie when visible, readable removal_date_or_permit_reference or backup_system_document_date_or_permit_reference showing the date of removal/modification or related document date, and readable removal_scope_or_description or backup_system_scope_or_description describing work completed pertaining to propane/natural-gas system removal or modification.

Set rule_result="pass" when either accepted path is present, usable, and has the required located-field evidence for that path.
Set rule_result="warn" when an acceptable document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears relevant but one or more required located fields for its path are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when all acceptable document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".
In calculation, state which path was used: permit_or_inspection, removal_or_modification_invoice, both, missing, or unclear; then list the required fields for that path and whether each is present/usable.
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the path decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_heat_load_calc_supporting_document_acceptable', 'Check whether an acceptable program-approved heat-load calculation is present for this dual-fuel ducted heat-pump upgrade.

Use only these named document types and located fields:
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.
- f280_heat_load_calculation: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference, approval_or_professional_reference, approval_status_or_condition, sizing_method_or_rule_of_thumb_evidence, and supplemental_heat_source_assumptions.

The heat-load calculation must support proper system sizing. Rule-of-thumb equipment sizing is not acceptable. Supplemental heating from electric or other non-fossil fuel heating systems may be considered in the heat-load calculation. Supplemental heating from fossil fuel heating systems, including a gas fireplace, natural gas, propane, or oil system, must not be considered in the heat-load calculation.

Set rule_result="pass" when f280_heat_load_calculation is present with supporting_document_routing_quality="usable" and the named located fields show readable heat-load sizing evidence, program approval or professional/program acceptance evidence, no rule-of-thumb sizing concern, and no fossil-fuel supplemental heat considered in the calculation.
Set rule_result="warn" when f280_heat_load_calculation is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears relevant but approval/program acceptance, sizing method, design heat-load value, or supplemental-heat assumptions are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when f280_heat_load_calculation is missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, present only with supporting_document_routing_quality="unusable", clearly uses rule-of-thumb equipment sizing, or clearly considers fossil-fuel supplemental heat such as a gas fireplace, natural gas, propane, or oil system.
In calculation, state whether f280_heat_load_calculation is present/usable, then list calculation_standard_reference, design_heat_load_value, approval_or_professional_reference, approval_status_or_condition, sizing_method_or_rule_of_thumb_evidence, and supplemental_heat_source_assumptions.
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG), and that the new dual-fuel ducted heat pump is integrated with that existing fossil-fuel heating system.

Use only these named fields and facts:
- dfhp_existing_heat_evidence: visible evidence of PNG natural gas, PNG propane, tanked propane, generic natural gas, generic propane, or unclear prior primary heating context.
- dfhp_source_fuel_path: visible source-fuel path, only as corroborating context.
- dfhp_equipment_type: visible dual-fuel ducted heat pump evidence, only as corroborating context.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21 degrees Celsius. A fireplace is not considered a primary heating system.

Set rule_result="pass" when the named evidence clearly supports that the prior primary heating system was tanked propane, PNG natural gas, or PNG propane, and the invoice supports dual-fuel integration with that system.
Set rule_result="warn" when the prior primary heat context is plausible but incomplete, such as visible propane without clear tanked-propane evidence, visible natural gas without clear PNG evidence, or dual-fuel integration wording without enough prior-heating context.
Set rule_result="fail" when the prior primary heating evidence is missing, points to a different fuel path, relies only on a fireplace as the prior primary heating system, shows generic natural gas without PNG support, shows generic propane without tanked-propane support, or is contradicted by supplied supporting-document facts.
In calculation, state dfhp_existing_heat_evidence, dfhp_source_fuel_path, and whether the accepted path is PNG natural gas, PNG propane, tanked propane, generic/unsupported, unclear, or contradicted.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_switchover_setpoint_specific', 'Check whether the thermostat, outdoor temperature switch-over control, or equipment control board is set to the required region-specific temperature for this dual-fuel ducted heat pump.

Use only these named fields and facts:
- dfhp_switchover_setpoint_evidence: invoice-visible thermostat, outdoor temperature switch-over control, equipment control board, setpoint, lockout temperature, region, or similar control evidence.
- dual_fuel_control_document located fields: control_setup_date, equipment_reference, switchover_setpoint, backup_fuel_or_integration_evidence, and region_or_temperature_threshold_evidence.

Thresholds:
- Lower Mainland and Vancouver Island regions: setpoint must be <=5 C.
- Southern Interior and Northern B.C. regions: setpoint must be <=2 C.

Set rule_result="pass" when the named evidence clearly identifies a thermostat, outdoor temperature switch-over control, or equipment control board tied to the dual-fuel ducted heat pump and clearly shows a setpoint at or below the required threshold for the visible region.
Set rule_result="warn" when control equipment is referenced but the setpoint is missing, the region is missing, the equipment tie is unclear, or the located fields are low-confidence, visually limited, or too ambiguous for confident comparison.
Set rule_result="fail" when the named evidence clearly shows the setpoint is above the required threshold for the visible region, or clearly shows no thermostat/switch-over/control-board setup for the dual-fuel ducted heat pump.
In calculation, state the visible region, required threshold, visible setpoint, whether the evidence came from dfhp_switchover_setpoint_evidence or dual_fuel_control_document, and whether the setpoint is within threshold.
In evidence_text, cite the exact named-field wording that supports the region, setpoint, and control-equipment decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_contractor_utility_billed_work_on_one_invoice', 'Check whether contractor-managed utility line-upgrade work appears to be documented on the same invoice when the contractor is being billed by the utility for the line upgrade.
Use esu_contractor_utility_management_evidence and esu_utility_billing_reference from the invoice, and utility_bill or electrical_utility_upgrade_document supporting-document located fields such as utility_provider, previous_service_size, new_service_size, service_address, service_completion_or_invoice_date, and utility_upgrade_cost_or_reference.
Set rule_result="pass" when contractor-managed utility billing evidence is visible and the invoice itself includes both contractor work and utility line/service-upgrade charges or references clearly enough to treat them as one invoice package.
Set rule_result="info" when no contractor-billed-by-utility scenario is visible; the one-invoice condition does not appear triggered from the supplied evidence.
Set rule_result="warn" when contractor utility-management evidence is visible but the utility charges appear only in a separate supporting document, or the invoice/supporting-document relationship is too ambiguous to confirm one-invoice treatment.
Set rule_result="fail" when the supplied evidence clearly shows the contractor was billed by the utility for the line upgrade and the contractor and utility work are split across separate invoices in conflict with the requirement.
In evidence_text, quote the contractor-utility management phrase and the utility charge/invoice evidence used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_heat_pump_conversion_context_present', 'Check whether invoice text ties the service upgrade to a fossil-fuel-to-heat-pump conversion.
Set rule_result="warn" if this likely requires application/DB context and the invoice does not contradict the association.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_not_panel_only_or_connection_only', 'Check whether the invoice or configured supporting-document located fields appear to include utility service/new-wire upgrade evidence rather than only a panel, sub-panel, breaker, or heat-pump connection.
Set rule_result="warn" if utility service evidence is missing after checking utility supporting documents but the visible work is not clearly panel-only/connection-only.
Set rule_result="fail" if the visible work clearly appears panel-only/connection-only.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_one_per_home_manual_review', 'Flag the maximum-one-per-home rule for admin/application-history review.
Set rule_result="pass" when the supplied invoice/DB/application context does not show another electrical service upgrade rebate already claimed for this home.
Set rule_result="fail" only when supplied database/application history clearly indicates another electrical service upgrade rebate was already claimed for this home.
Set rule_result="warn" when duplicate-claim history is not supplied and admin/application system should verify claim history.
Do not fail solely because invoice text cannot prove this is the first or only electrical service upgrade claim for the home.
In reason_and_likely_causes, say whether duplicate-claim evidence was supplied, absent, or not available to the model.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_rebate_math_within_cap', 'Check whether the claimed rebate for this electrical service upgrade appears to stay within the visible eligible cost and the program maximum for the participant''s eligibility level.
Use the visible esu_line_amount, upgrade_specific_rebate_line_amount, and eligibility code.
Use these maximum rebate amounts: ESP1 up to $5,000; ESP2 up to $3,500; ESP3 up to $1,500.
Set rule_result="pass" only when the invoice clearly shows the rebate amount, visible eligible cost, and eligibility code, and the claimed rebate is less than or equal to both the visible eligible cost and the applicable cap.
Set rule_result="warn" when the eligibility code, rebate amount, or visible eligible cost is missing/ambiguous but no visible value clearly exceeds the cap.
Set rule_result="fail" when the rebate clearly exceeds the visible eligible cost or applicable cap.
In calculation, show the eligibility code, visible eligible cost, claimed rebate, and cap comparison.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_service_size_present', 'Check whether the invoice or configured supporting-document located fields clearly reference a 100, 200, or 400 amp electrical service upgrade.
Use utility_bill and electrical_utility_upgrade_document located fields such as previous_service_size, new_service_size, service_address, service_completion_or_invoice_date, and utility_upgrade_cost_or_reference.
Set rule_result="warn" if electrical work is visible but service size is missing or ambiguous after checking the utility supporting documents.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_timing_within_six_months_evidence', 'Check whether visible invoice dates and configured supporting-document located fields provide enough evidence to compare service upgrade timing against heat pump installation timing.
Pass this rule when either:
1. Both the electrical service upgrade date from invoice or utility supporting documents and associated heat pump / heat pump water heater installation date are visible and appear within the allowed timing window.
2. The electrical service upgrade and associated heat pump / heat pump water heater work appear on the same invoice and share the same invoice, service, or completion date, with no contradictory timing evidence.
Set rule_result="fail" when visible dates clearly place the service upgrade outside the allowed timing window.
Set rule_result="fail" when the service upgrade appears on a separate invoice and no associated heat pump / heat pump water heater install date or associated invoice date is visible.
If same-invoice evidence is used, explain in reason_and_likely_causes that the invoice-level date is being used as the shared timing proxy.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_utility_upgrade_supporting_document_attached', 'Check whether supporting_document_summary_for_upgrade_type includes utility_bill or electrical_utility_upgrade_document.
Set rule_result="pass" if an acceptable document is present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable evidence for review.
Set rule_result="warn" if present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" if all acceptable document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('homeowner_identity_matches_eligibility_record', 'Check whether the homeowner/customer name visible on the invoice appears to match the participant/homeowner associated with the eligibility code on record.
Use users.participant_name, users_eligibilitycodes.eligibility_code, and classifier.eligibility_code from the supplied database values.
Use invoice_homeowner_name and eligibility_code from the OCR/DI JSON.
Set rule_result="pass" when the invoice-visible homeowner/customer name clearly matches users.participant_name, including common first-name/last-name ordering, initials, spouse/household formatting, accents, middle names, or minor OCR spelling differences.
Set rule_result="info" when the name likely matches but the invoice uses a harmless alternate format worth surfacing, such as first initial plus last name, spouse/household wording, or a minor OCR typo. This is context only, not a requested fix.
Set rule_result="warn" when the invoice homeowner/customer name is missing or ambiguous, when users.participant_name is missing, or when the eligibility-code lookup is missing and admin should verify the applicant/homeowner identity from the application record.
Set rule_result="fail" when both names are clear and the invoice visibly appears to be for a different homeowner/customer than the participant associated with the eligibility code.
If the visible invoice eligibility code conflicts with users_eligibilitycodes.eligibility_code or classifier.eligibility_code, mention that conflict here only as identity context; the eligibility-code date/window code rule owns final eligibility-code timing.
In evidence_text, include the visible invoice homeowner/customer name, visible invoice eligibility code if present, database participant name, and database eligibility code.
In reason_and_likely_causes, explain whether this is a clear match, harmless formatting variation, missing/ambiguous evidence, or likely wrong-homeowner invoice.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_conditioned_space_distribution_present', 'Check whether invoice evidence or located fields show the heat pump can distribute heat through the conditioned space formerly served by the primary heating system.
Set rule_result="pass" when distribution through the former primary conditioned space is clear.
Set rule_result="warn" when distribution/coverage evidence is missing or ambiguous.
Set rule_result="fail" when visible evidence clearly limits the system to a secondary, partial, or unrelated area that contradicts this eligibility requirement.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_no_existing_or_secondary_heat_pump_review', 'Check whether invoice text suggests a combined space/water heat-pump claim is replacing, adding to, or adding a secondary heat pump for a home with an existing heat pump.
Set rule_result="pass" when no existing/add-on/secondary heat-pump concern is visible.
Set rule_result="warn" when existing/add-on/secondary heat-pump wording is visible, because the extracted 2026 combined space/water table does not state the same explicit no-existing-heat-pump sentence found in the air-to-water section.
Set rule_result="fail" only when supplied program facts or visible invoice evidence clearly contradict combined space/water heat-pump eligibility.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_fossil_backup_not_fossil_primary', 'Check whether the backup heating system for this fossil-fuel-to-heat-pump upgrade is electric or wood, with only the allowed exception for a retained natural-gas/propane fireplace that is clearly secondary.

Use only this named field:
- hp_backup_heat_evidence: visible backup heat evidence and whether it appears electric, wood, fossil fuel, fireplace-only, secondary, primary, or unclear.

Set rule_result="pass" when hp_backup_heat_evidence clearly shows the backup heating system is electric or wood.
Set rule_result="pass" when the only visible natural-gas/propane retained heat is a fireplace and the evidence clearly shows it is secondary, not the backup heating system and not the primary heating system.
Set rule_result="warn" when backup heat context is missing, ambiguous, or when a natural-gas/propane fireplace is visible but the evidence does not clearly show whether it is secondary.
Set rule_result="fail" when hp_backup_heat_evidence clearly shows natural gas, propane, oil, dual-fuel fossil backup, or another fossil-fuel system remains as the backup heating system.
Set rule_result="fail" when a natural-gas/propane fireplace is visible and the evidence shows it is primary, backup, or not clearly limited to a secondary fireplace role.
In calculation, state hp_backup_heat_evidence and classify the visible backup context as electric, wood, secondary gas/propane fireplace, fossil backup, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_main_living_area_or_primary_capacity_present', 'Check whether invoice evidence or located fields show the heat pump is sized/described as the home''s primary heating system or serves a main living area.
Set rule_result="pass" when primary-heating capacity or main-living-area service is clear.
Set rule_result="warn" when this evidence is missing or ambiguous.
Set rule_result="fail" when visible evidence clearly contradicts primary-heating or main-living-area eligibility.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_no_existing_or_secondary_heat_pump_flag', 'Check whether invoice text suggests the work is replacing, adding to, or adding a secondary heat pump for a home with an existing heat pump.
Set rule_result="pass" when no existing/add-on/secondary heat-pump concern is visible.
Set rule_result="warn" when the invoice wording is ambiguous and admin should verify whether this is a new eligible primary system.
Set rule_result="fail" when visible evidence shows replacement of an existing heat pump, an add-on to an existing heat pump, or a secondary heat pump for a home with an existing heat pump.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_fossil_removal_supporting_document_attached', 'Check whether an acceptable gas/fossil-fuel water-heater removal supporting document is present when the heat pump water heater replaced a fossil-fuel water heating system.

Use only these named fields and facts:
- hpwh_existing_fuel_type: invoice evidence about whether the heat pump water heater replaced a fossil-fuel water heating system.
- permit_document: permit_date, permit_address, authority_name, permit_scope_or_equipment_reference, and permit_status_or_completion_evidence.
- fossil_fuel_removal_proof: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, and removal_scope_or_description.
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.

Set rule_result="pass" if hpwh_existing_fuel_type does not show a fossil-fuel water-heater source path. In calculation, state fossil_removal_required=false.

If hpwh_existing_fuel_type clearly shows natural gas, gas water heater, propane, oil, fuel oil, fossil fuel, or similar fossil-fuel water-heating replacement, require one accepted supporting-document path.

Accepted path 1: local government permit or inspection report.
For this path, require permit_document with supporting_document_routing_quality="usable", readable permit_date showing an inspection/permit/completion/approval date, readable permit_address showing the address where inspection or fossil-fuel water-heater removal-related work took place, and permit_scope_or_equipment_reference or permit_status_or_completion_evidence that supports gas/fossil-fuel water-heater removal, decommissioning, capping, disconnection, inspection, completion, or related by-law/compliance work.

Accepted path 2: invoice from the removal company or heat pump water heater installation company.
For this path, require fossil_fuel_removal_proof with supporting_document_routing_quality="usable", readable removal_scope_or_description describing the work completed for gas, natural-gas, propane, oil, or other fossil-fuel water-heater removal/decommissioning/capping/disconnection. Also require readable removal_date_or_permit_reference showing the date of removal or decommissioning.

Set rule_result="pass" when fossil-fuel water-heater replacement is visible and either accepted path is present, usable, and has the required located-field evidence for that path.
Set rule_result="warn" when the water-heater source path is unclear, when an acceptable document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears relevant but one or more required located fields for its path are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when fossil-fuel water-heater replacement is visible and both acceptable document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".
In calculation, state fossil_removal_required, which path was used: permit_or_inspection, removal_invoice, both, missing, not_required, or unclear; then list the required fields for that path and whether each is present/usable.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_no_existing_or_secondary_hpwh_flag', 'Check whether the named evidence suggests the upgrade is replacing an existing heat pump water heater, adding to a home with an existing heat pump water heater, or adding a secondary/additional heat pump water heater.

Use only these named fields and facts:
- hpwh_existing_hpwh_flag: evidence of an existing heat pump water heater or secondary/additional heat pump water heater.
- hpwh_existing_water_heater_evidence: evidence about the existing primary water heater being replaced.
- hpwh_secondary_system_flag: evidence that the invoice is for a secondary/additional water heater rather than replacement of the primary system.

Set rule_result="pass" when the named evidence shows a new heat pump water heater replacing a non-heat-pump primary water heater, and no existing/additional/secondary heat pump water heater concern is visible.
Set rule_result="warn" when the evidence is incomplete or ambiguous about whether an existing heat pump water heater is already present or whether the new system is secondary/additional.
Set rule_result="fail" when the named evidence clearly shows replacement of an existing heat pump water heater, adding a secondary/additional heat pump water heater, or adding a heat pump water heater to a home that already has an existing heat pump water heater.
In calculation, state hpwh_existing_hpwh_flag, hpwh_existing_water_heater_evidence, hpwh_secondary_system_flag, and classify the concern as none, existing_hpwh_replacement, secondary_or_additional_hpwh, existing_hpwh_home, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_primary_replacement_context_present', 'Check whether the invoice provides evidence that the heat pump water heater replaces the home''s primary water heater.
Set rule_result="warn" if this likely requires application/DB context and the invoice does not show a secondary/additional system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_product_reference_present', 'Check whether the invoice or configured supporting-document located fields include useful product references for later validation, such as make/model, NEEA, qualified product list, or Tier 2+ evidence.
Use product_spec_sheet, manufacturer_label_photo, and energy_star_label located fields such as brand_and_model, model_number, neea_reference, tier_reference, product_list_reference, efficiency_or_capacity_rating, capacity_btu_or_kw, equipment_type_or_product_category, nrcan_reference, and label_legibility_concern.
This is not final product-list validation.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_associated_upgrade_present', 'Check whether the invoice connects remediation to an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
Set rule_result="warn" if association likely requires DB/application context and the invoice does not contradict an associated eligible upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_before_after_photos_attached', 'Check whether supporting_document_summary_for_upgrade_type includes before_after_photo_set.
Set rule_result="pass" if present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable evidence for review.
Set rule_result="warn" if present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" if missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_issue_type_present', 'Check whether the invoice clearly identifies an existing health and safety issue being remediated.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_not_standalone_flag', 'Flag whether the invoice appears to claim health and safety remediation on its own.
Set rule_result="fail" only if it clearly appears standalone without an associated eligible upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_pre_confirmation_evidence_present', 'Check whether invoice text references prior confirmation that the remediation was rebate-eligible.
Set rule_result="warn" if not visible. Admin should verify pre-confirmation in application/supporting records; absence from invoice OCR is not a material failure by itself.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_rebate_math_within_cap', 'Check whether the claimed rebate for this health and safety remediation upgrade appears to stay within the visible remediation cost and the program maximum for the participant''s eligibility level.
Use the visible hs_line_amount, upgrade_specific_rebate_line_amount, and eligibility code.
Use these maximum rebate amounts: ESP1 up to 95% of eligible upgrade costs, capped at $800 per home; ESP2 up to 60% of eligible upgrade costs, capped at $800 per home; ESP3 has no health and safety remediation rebate.
Set rule_result="pass" only when the invoice clearly shows the rebate amount, visible remediation cost, and eligibility code, and the claimed rebate is less than or equal to both the visible remediation cost and the applicable cap.
Set rule_result="warn" when the eligibility code, rebate amount, or visible remediation cost is missing/ambiguous but no visible value clearly exceeds the cap.
Set rule_result="fail" when the rebate clearly exceeds the visible remediation cost or applicable cap.
In calculation, show the eligibility code, visible remediation cost, claimed rebate, and cap comparison.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_conversion_context_present', 'Check whether the named evidence supports that the home was primarily heated by fossil fuel, electricity, or wood/solid fuel before the hydronic heat-pump upgrade.

Use only these named fields and facts:
- hydronic_conversion_source_fuel_evidence: visible evidence of the home''s existing primary heating source before the hydronic heat pump upgrade, including whether it was fossil fuel, electricity, wood/solid fuel, a fireplace only, or unclear.
- hydronic_fossil_removal_evidence: corroborating evidence when the source path is fossil fuel.
- hydronic_wood_removal_or_wett_evidence: corroborating evidence when the source path is wood or solid fuel.
- supporting-document located fields as corroboration when present, including removed_equipment_type, removal_scope_or_description, before_photo_evidence, after_photo_evidence, wett_appliance_or_system_reference, site_address, and calculation_standard_reference.

Accepted prior primary-heating source paths are fossil fuel (oil, propane, or natural gas), electricity, and wood/solid fuel. A primary heating system must have the capacity to heat a minimum of 50% of the home for the full heating season to 21 degrees Celsius. A fireplace is not considered a primary heating system.

Set rule_result="pass" when hydronic_conversion_source_fuel_evidence clearly supports an accepted prior primary-heating source path and the conversion context is understandable for the claimed hydronic heat-pump upgrade.
Set rule_result="warn" when the source-fuel path, primary-heating status, 50%/21C capacity context, or conversion context is missing, incomplete, low-confidence, or needs application/supporting-document confirmation.
Set rule_result="fail" when the named evidence clearly shows the prior heating source is outside the accepted paths, the only prior heat evidence is a fireplace, the evidence contradicts primary-heating status, or the visible conversion story contradicts hydronic heat-pump eligibility.
Do not fail this rule solely because fossil-removal/photo/WETT supporting documents are missing; hydronic_fossil_fuel_removal_supporting_document_attached and hydronic_wood_removal_or_wett_supporting_document_attached own those conditional attachment checks.
In calculation, state hydronic_conversion_source_fuel_evidence, the classified prior source path, whether primary-heating status is supported, whether fireplace-only evidence is present, and whether supporting-document corroboration was used.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_fossil_fuel_removal_supporting_document_attached', 'Check whether an acceptable fossil-fuel heating-system removal supporting document is present when the hydronic heat pump replaced an oil, propane, or natural-gas heating system.

Use only these named fields and facts:
- hydronic_conversion_source_fuel_evidence: invoice evidence about whether the hydronic heat pump replaced a fossil-fuel heating system.
- permit_document: permit_date, permit_address, authority_name, permit_scope_or_equipment_reference, and permit_status_or_completion_evidence.
- fossil_fuel_removal_proof: removed_equipment_type, removal_date_or_permit_reference, site_address, contractor_or_authority_name, and removal_scope_or_description.
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.

Set rule_result="pass" if hydronic_conversion_source_fuel_evidence does not show a fossil-fuel source path. In calculation, state fossil_removal_required=false.

If hydronic_conversion_source_fuel_evidence clearly shows oil, propane, natural gas, fossil fuel, gas boiler, propane boiler, oil boiler, gas furnace, propane furnace, oil furnace, or similar fossil-fuel heating-system replacement, require one accepted supporting-document path.

Accepted path 1: local government permit or inspection report.
For this path, require permit_document with supporting_document_routing_quality="usable", readable permit_date showing an inspection/permit/completion/approval date, readable permit_address showing the address where inspection or fossil-fuel removal-related work took place, and permit_scope_or_equipment_reference or permit_status_or_completion_evidence that supports fossil-fuel heating-system removal, decommissioning, capping, disconnection, oil-tank removal, inspection, completion, or related by-law/compliance work.

Accepted path 2: invoice from the removal company or heat-pump installation company.
For this path, require fossil_fuel_removal_proof with supporting_document_routing_quality="usable", readable removal_scope_or_description describing the work completed for oil, propane, natural gas, or other fossil-fuel heating-system removal/decommissioning/capping/disconnection. Also require readable removal_date_or_permit_reference showing the date of removal or decommissioning.

Set rule_result="pass" when fossil-fuel replacement is visible and either accepted path is present, usable, and has the required located-field evidence for that path.
Set rule_result="warn" when the source-fuel path is unclear, when an acceptable document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears relevant but one or more required located fields for its path are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when fossil-fuel replacement is visible and both acceptable document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".
In calculation, state fossil_removal_required, which path was used: permit_or_inspection, removal_invoice, both, missing, not_required, or unclear; then list the required fields for that path and whether each is present/usable.
In evidence_text, cite the exact named-field wording that supports the decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_wood_removal_or_wett_supporting_document_attached', 'If the visible source-fuel path is wood or solid fuel, check whether the required wood/solid-fuel removal or safe-retention supporting document is present.

Use only these named fields and facts:
- InvoiceDate: the DI invoice date for the heat pump installation invoice.
- hydronic_conversion_source_fuel_evidence: invoice evidence about whether the hydronic heat pump replaced a wood or solid-fuel heating system.
- hydronic_wood_removal_or_wett_evidence: invoice evidence about whether the existing wood or solid-fuel heating system was removed, retained, WETT-inspected, decommissioned, or otherwise addressed.
- supporting_document_summary_for_upgrade_type: the routed supporting-document summary for this upgrade type, including before_after_photo_set and wett_report document types, routing quality, not-present document types, and located fields.
- before_after_photo_set located fields, including photo_role, visible_subject_or_area, visible_condition_summary, image_quality_or_legibility, and visible_text_or_label_values.
- wett_report located fields, including wett_inspection_date, wett_inspector_certification_number, site_address, compliance_or_removal_conclusion, wett_inspector_or_company_name, and wett_appliance_or_system_reference.

Set rule_result="pass" if wood/solid-fuel source path is not visible or not claimed.

Removed-system path:
If the visible evidence shows the heat pump replaced a wood or solid-fuel heating system and that system was removed, require before_after_photo_set supporting-document evidence with both roles visible: at least one usable before photo and at least one usable after photo. The located fields must support that the photographed subject is the wood or solid-fuel heating system, such as wood stove, pellet stove, insert, furnace, boiler, chimney, venting, fuel storage, or the installation area where that system was removed. Do not pass this path on a single photo, unknown photo_role only, unrelated construction photos, or photos that do not show the wood/solid-fuel system or its removed condition.

Retained-system path:
If the visible evidence shows the heat pump replaced a wood or solid-fuel heating system and that system was retained in safe and working order, require wett_report supporting-document evidence. The WETT report must have supporting_document_routing_quality="usable", a readable wett_inspection_date, readable wett_inspector_certification_number, readable site_address, readable wett_appliance_or_system_reference tying the report to the wood or solid-fuel heating system, and readable compliance_or_removal_conclusion showing whether the installation is compliant with relevant codes or otherwise safe/working.

For the retained-system path, compare wett_inspection_date to InvoiceDate. The WETT inspection/report date must be within the allowed window: no earlier than 12 months before InvoiceDate and no later than 6 months after InvoiceDate.
If the wood/solid-fuel source path is visible but the removal/retention path is unclear, do not guess which document is required.

Set rule_result="pass" when the wood/solid-fuel path does not apply, or when the removal/retention path is clear and every required document, role, located field, and date-window check for that path is present, usable, and satisfied.
Set rule_result="warn" when the wood/solid-fuel source path or removal/retention path is unclear; when the required document type is present but supporting_document_routing_quality is needs_review or requires_visual_review; when required located fields are missing, null, low-confidence, visually limited, or too unclear for confident review; when before/after photo roles cannot be confidently distinguished; or when InvoiceDate or wett_inspection_date is missing or ambiguous so the WETT date window cannot be confidently checked.
Set rule_result="fail" when the wood/solid-fuel source path and removal/retention path are clear and the required document type is missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, present only with supporting_document_routing_quality="unusable", missing a clearly required before or after photo, or has clear WETT date evidence outside the allowed date window.
In calculation, state the visible source-fuel path, removal/retention path, required document type, before_photo_present, after_photo_present, WETT required fields present/usable, InvoiceDate, wett_inspection_date, allowed WETT date window, and whether the date window is satisfied.
In evidence_text, cite the exact invoice or supporting-document wording/located fields that support the path and document decision.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('income_verification_supporting_documents_attached', 'Check whether supporting_document_summary includes income_verification_document.
Set rule_result="pass" if present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable evidence for review.
Set rule_result="warn" if present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" if missing or present with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_health_safety_issue_flag', 'Check whether the invoice references pest, rodent, vermiculite, asbestos, mould, or removed insulation issues.
Set rule_result="fail" only if unresolved issues appear to block processing or if evidence is unclear.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_material_and_location_present', 'Check whether the invoice identifies insulation material and eligible installation location clearly enough for admin pre-review.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_minimum_r_value_and_boundary_present', 'Check whether the invoice provides enough evidence that the insulation location is eligible, is between conditioned and unconditioned space, and meets the minimum R-value added for that location.
Set rule_result="warn" when location, boundary, or R-value evidence is missing/ambiguous and admin should verify the calculation inputs.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_r_value_and_area_present', 'Check whether the invoice provides R-value and area/square-foot evidence needed for rebate calculation review.
Set rule_result="warn" if one or both values are missing or ambiguous and admin should verify the insulation calculation inputs.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_rebate_math_within_cap', 'Check whether the claimed rebate for this insulation upgrade appears to stay within the visible insulation cost and the program maximum.
Use the visible ins_line_amount, upgrade_specific_rebate_line_amount, ins_upgrade_location, and eligibility code.
Use these maximum rebate rules: ESP1/ESP2 only; ESP3 has no insulation rebate; the total insulation rebate is capped at $5,500 per home; a clearly isolated single upgrade location should not visibly exceed the $2,000 location-specific maximum.
When R-value added and area are visible, apply these location-specific formula/rates: attic = R-value added times square feet times $0.05 for ESP1 or $0.04 for ESP2; exterior wall cavity/sheathing and basement/crawlspace = R-value added times square feet times $0.20 for ESP1 or $0.16 for ESP2; exposed floor, floor over crawlspace, or basement header = R-value added times square feet times $0.125 for ESP1 or $0.10 for ESP2.
Minimum new R-value added by location: attic R12; exterior wall cavity R12; exterior wall sheathing R3.8; basement/crawlspace R10; exposed floor, floor over crawlspace, or basement header R20.
Set rule_result="pass" only when the invoice clearly shows the rebate amount, visible insulation cost, and enough location context, and the claimed rebate is less than or equal to the visible insulation cost and does not clearly exceed the visible program cap.
Set rule_result="warn" when the rebate amount or visible insulation cost is missing/ambiguous but no visible value clearly exceeds the cap/formula.
Set rule_result="fail" when the rebate clearly exceeds the visible insulation cost, clearly exceeds $5,500 overall, clearly exceeds the visible single-location cap/formula, or is claimed for ESP3.
In calculation, show the visible location context, R-value added, area, formula/rate if available, visible insulation cost, claimed rebate, and cap comparison.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_supporting_documents_attached', 'Check whether supporting_document_summary_for_upgrade_type includes before_after_photo_set and, when applicable, floor_plan_document.
Set rule_result="pass" if the required document package is present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable evidence for review.
Set rule_result="warn" if present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" if required document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_invoice_arithmetic_consistent', 'Check whether the visible invoice arithmetic is internally consistent when invoice total, overall rebate, deposit, and amount due after rebate are shown.
Invoices may use either of these acceptable arithmetic patterns:
1. Customer amount owing model: expected_customer_due = invoice_total - overall_rebate_line_amount - customer_payment_or_deposit. Pass when expected_customer_due matches the visible customer amount due within normal invoice rounding.
2. Program rebate receivable model: expected_program_due = invoice_total - customer_payment_or_deposit. Pass when expected_program_due matches the visible amount due and also matches the visible CleanBC / Better Homes / ESP rebate total within normal invoice rounding.
If customer_payment_or_deposit is not shown, treat it as zero only when the invoice clearly shows no deposit or prior payment; otherwise treat it as missing.
Set rule_result="pass" when the invoice reconciles cleanly under either acceptable model and no useful extra explanation is needed.
Set rule_result="info" when the invoice reconciles, but the model is worth explaining to admins, such as a payment-history/customer-deposit/program-receivable structure. Do not warn merely because there are multiple payment-history entries if their total is visible and reconciles.
Set rule_result="warn" only when required values are missing, unreadable, duplicated without a clear total, or labelled ambiguously enough that the model cannot determine whether arithmetic reconciles. If warning, state the exact missing or ambiguous value and the concrete review step.
Set rule_result="fail" when the visible values clearly do not reconcile under either acceptable model.
In reason_and_likely_causes, name which model appears to fit the invoice.
In calculation, show both the formula and visible values used, for example: invoice_total - customer_payment_or_deposit = amount_due, and amount_due equals visible rebate total.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_not_over_invoice_total', 'Check whether the visible overall CleanBC / Better Homes / ESP rebate does not exceed the invoice total.

Use only these named fields:
- overall_rebate_line_amount: the visible total program rebate amount for the invoice.
- InvoiceTotal: the Azure Document Intelligence invoice total.

Do not use AmountDue or any other field for this rule.

Set rule_result="pass" only when both overall_rebate_line_amount and InvoiceTotal are present, clear, and overall_rebate_line_amount is less than or equal to InvoiceTotal.
Set rule_result="warn" when overall_rebate_line_amount or InvoiceTotal is missing, null, ambiguous, unreadable, or not confidently tied to the invoice totals.
Set rule_result="fail" when overall_rebate_line_amount is greater than InvoiceTotal.
In calculation, show the named fields and values used, including overall_rebate_line_amount and InvoiceTotal.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_not_over_paid_cost_of_upgrade', 'Check whether the visible overall CleanBC / Better Homes / ESP rebate does not exceed the paid cost of the upgrade.

Use only these named fields:
- overall_rebate_line_amount: the visible total program rebate amount for the invoice.
- paid_cost_of_upgrade_amount: the visible paid cost of the upgrade.

Set rule_result="pass" only when both overall_rebate_line_amount and paid_cost_of_upgrade_amount are present, clear, and overall_rebate_line_amount is less than or equal to paid_cost_of_upgrade_amount.
Set rule_result="warn" when overall_rebate_line_amount or paid_cost_of_upgrade_amount is missing, null, ambiguous, unreadable, or not confidently tied to the claimed upgrade.
Set rule_result="fail" when overall_rebate_line_amount is greater than paid_cost_of_upgrade_amount.
In calculation, show the named fields and values used, including overall_rebate_line_amount and paid_cost_of_upgrade_amount.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('rebate_line_evidence_present', 'Check whether the invoice visibly identifies CleanBC / Better Homes / ESP rebate amounts and makes the rebate amount understandable.
Set rule_result="pass" when one overall program rebate amount is clearly labelled and no useful extra context is needed.
Set rule_result="info" when multiple upgrade-specific CleanBC / Better Homes / ESP rebate amounts are clearly labelled, summable, and useful to call out as context. A split rebate presentation is acceptable when the amounts are clear; do not warn merely because rebates are split by upgrade type.
Set rule_result="warn" only when rebate evidence exists but the rebate label, amount, or allocation by upgrade type is genuinely unclear from the invoice text. If warning, say exactly which value or label is unclear and what admin should inspect.
Set rule_result="fail" only when no CleanBC / Better Homes / ESP rebate evidence is visible, or when visible invoice text clearly contradicts the existence of a program rebate.
Do not re-check invoice arithmetic in this rule. The common invoice-arithmetic rule owns whether rebate/payment/amount-due math reconciles.
When split rebate lines are visible, show the summed rebate calculation in calculation, such as HVAC rebate + service upgrade rebate = total CleanBC / Better Homes portion.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('upgrade_type_evidence_present', 'Check whether the invoice text provides evidence of the claimed upgrade type.
Set rule_result="pass" if the invoice clearly describes the claimed upgrade domain.
Set rule_result="warn" if the invoice uses broad wording such as HVAC, service upgrade, insulation work, or remediation without enough detail to confirm the precise subtype but does not contradict the claimed domain. Admin should verify the exact upgrade subtype only.
Set rule_result="fail" if the claimed upgrade domain is clearly absent or contradicted by the invoice.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('utility_account_supporting_document_attached', 'Check whether supporting_document_summary includes utility_bill or utility_account_document.
Set rule_result="pass" if present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable evidence for review.
Set rule_result="warn" if present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" if missing or present with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_associated_upgrade_present', 'Check whether invoice text connects ventilation work to an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
Set rule_result="warn" if this likely requires application/DB context and the invoice does not clearly show standalone ventilation.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_not_generic_ductwork_only', 'Check whether the invoice clearly identifies an eligible HRV/ERV or bathroom fan system rather than only generic ductwork, airflow balancing, or HVAC ventilation language.
Set rule_result="fail" if eligible ventilation equipment is not clearly visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_product_or_capacity_evidence_present', 'For HRV/ERV, look in invoice evidence and configured supporting-document located fields for ENERGY STAR/NRCan/product-list evidence.
For bathroom fans, look in invoice evidence and product_spec_sheet/energy_star_label located fields for ENERGY STAR, 85 cfm or 40 L/s, static pressure, continuous duty motor, backdraft damper, direct exterior ducting, main bathroom, duct sealing/insulation, and hood evidence.
Use product_spec_sheet fields such as energy_star_reference, nrcan_reference, product_list_reference, bathroom_fan_cfm, static_pressure, continuous_duty_motor_evidence, backdraft_damper_evidence, direct_exterior_ducting_evidence, main_bathroom_evidence, duct_sealing_evidence, duct_insulation_r_value, installation_standard_or_guide_reference, and product_spec_legibility_concern.
Set rule_result="pass" when the configured subtype and required product/capacity evidence are present in invoice or supporting-document fields.
Set rule_result="warn" when an eligible ventilation subtype is visible but product/capacity details are missing, incomplete, or illegible in the supplied supporting documents.
Set rule_result="fail" only when the supplied evidence clearly contradicts the eligible HRV/ERV or bathroom-fan requirements.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_rebate_math_within_cap', 'Check whether the claimed rebate for this ventilation upgrade appears to stay within the visible ventilation cost and the program maximum for the participant''s eligibility level.
Use the visible vent_line_amount, upgrade_specific_rebate_line_amount, and eligibility code.
Use these maximum rebate amounts: ESP1 up to 95% of eligible upgrade costs, capped at $1,600 per home; ESP2 up to 60% of eligible upgrade costs, capped at $1,600 per home; ESP3 has no ventilation rebate.
Set rule_result="pass" only when the invoice clearly shows the rebate amount, visible ventilation cost, and eligibility code, and the claimed rebate is less than or equal to both the visible ventilation cost and the applicable cap.
Set rule_result="warn" when the eligibility code, rebate amount, or visible ventilation cost is missing/ambiguous but no visible value clearly exceeds the cap.
Set rule_result="fail" when the rebate clearly exceeds the visible ventilation cost or applicable cap.
In calculation, show the eligibility code, visible ventilation cost, claimed rebate, and cap comparison.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_standalone_flag', 'Flag whether the invoice appears to claim ventilation on its own without another eligible upgrade.
Set rule_result="fail" only if clearly standalone.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_system_type_present', 'Check whether the invoice or configured supporting-document located fields identify the ventilation system as HRV/ERV or bathroom fan system.
Use product_spec_sheet and energy_star_label fields such as product_category_or_system_type, brand_and_model, model_number, energy_star_reference, nrcan_reference, and label_legibility_concern.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('warranty_costs_flag', 'Check whether the invoice appears to include warranty-covered costs or warranty language that should be reviewed by an admin.
Set rule_result="fail" only if the invoice clearly indicates claimed upgrade costs are covered by warranty, paid by warranty, credited under warranty, supplied as a no-charge warranty replacement, reduced by a warranty discount, or otherwise not actually paid by the participant/contractor claim.
Set rule_result="warn" if warranty wording might imply a warranty credit/payment but the invoice is not clear. Admin should verify whether any claimed cost was actually warranty-paid.
Set rule_result="pass" when the invoice merely lists ordinary warranty terms, such as manufacturer warranty, parts warranty, compressor warranty, labour warranty period, installation workmanship warranty, or warranty coverage available after installation.
Do not fail solely because warranty coverage language is visible.
In reason_and_likely_causes, distinguish standard post-installation warranty terms from warranty-paid or warranty-credited invoice costs.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_certification_reference_present', 'Check whether the invoice or configured supporting documents contain any product/certification reference that would help an admin verify the accepted certification body requirement.
Look specifically in certification_sheet, fenestration_energy_performance_label, manufacturer_label_photo, and their located fields for CSA, Intertek, Labtest/LC, QAI, Keystone/KC, NAMI, NFRC, CPD, NRCan/ENERGY STAR fenestration numbers, metric_u_factor, brand/model, label legibility, installed-unit coverage, or similar product-rating identifiers.
Set rule_result="pass" if at least one useful certification/rating reference is clearly visible.
Set rule_result="warn" if supporting documents are present but the product/certification fields are unreadable or incomplete.
Set rule_result="fail" if there is no visible certification/rating reference in either invoice evidence or configured supporting-document located fields.
This is not a final product-list validation.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_customer_portion_math_matches', 'Check whether the customer-portion calculation on the invoice appears to match the official customer-portion calculation.
Use the original v1 calculation reference:
1. afterrebate_invoicecost = total_invoice_cost - capped_invoice_total_rebate.
2. customer_portion = afterrebate_invoicecost - customer_deposit.
3. If customer_portion is positive, the homeowner/customer still owes the contractor.
4. If customer_portion is negative, the contractor owes the customer.
Set rule_result="pass" only when visible invoice values clearly match the calculated customer portion or amount due.
Set rule_result="fail" only when visible invoice values clearly contradict the calculated customer portion or amount due.
Set rule_result="warn" when total invoice cost, capped rebate, customer deposit, or amount due after rebate is missing/ambiguous but no visible arithmetic contradiction is present.
Set rule_result="fail" when visible values clearly contradict the calculated customer portion or amount due.
In calculation, show the visible formula and values used. Do not invent missing line-item values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_envelope_replacement_evidence_present', 'Check whether visible text supports replacement of existing exterior/building-envelope windows or doors rather than new construction, additions, skylights, interior doors, or unrelated glazing.
Set rule_result="warn" if the scope is missing or ambiguous and admin should verify scope against application/quote context.
Set rule_result="fail" if the visible scope appears ineligible, such as new construction, additions, skylights, interior doors, or unrelated glazing.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_label_photo_supporting_document_attached', 'Check whether supporting_document_summary_for_upgrade_type includes acceptable window/door label evidence. Accept either manufacturer_label_photo or fenestration_energy_performance_label for this rule.
Set rule_result="pass" if at least one acceptable type is present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable manufacturer/model, U-factor, NRCan, CPD, NFRC, ENERGY STAR, or similar label evidence for review.
Set rule_result="warn" if an acceptable type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" only if both manufacturer_label_photo and fenestration_energy_performance_label are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_no_skylights', 'Check whether the invoice appears to include skylights as part of the Windows and doors claim.
Set rule_result="fail" only if the invoice clearly claims skylights.
Set rule_result="pass" if there is no clear skylight evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_per_home_rebate_math_within_cap', 'Check whether the total invoice/home rebate appears within the per-home cap.
Use the original v1 calculation reference:
1. Add the rebate_per_unit values for all eligible windows/doors across the invoice.
2. The total invoice/home rebate is capped at $9,500.
Windows/doors rebates are ESP1/ESP2 only; ESP3 has no windows/doors rebate.
Set rule_result="pass" only when visible invoice values clearly show the total claimed rebate is at or below $9,500.
Set rule_result="fail" only when the visible claimed rebate clearly exceeds $9,500.
Set rule_result="warn" when eligible unit count, per-unit rebate values, or total claimed rebate are missing/ambiguous but no visible total clearly exceeds the cap.
Set rule_result="fail" when the visible claimed total clearly exceeds $9,500 or the visible eligible cost.
In calculation, show the visible total rebate and cap comparison. Do not invent missing line-item values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_per_unit_rebate_math_within_cap', 'Check whether the per-unit rebate calculations are visibly shown and appear to be within the per-window/per-door cap.
Use the original v1 calculation reference:
1. full_unit_subtotal = hardware price per unit + labour price per unit.
2. If labour per unit is not shown, it may be estimated as labour total divided by quantity of units, but only when those values are clearly visible.
3. full_unit_after_tax_subtotal = full_unit_subtotal * 1.05.
4. rebate_percentage is 95% for ESP1 and 60% for ESP2. ESP3 has no windows/doors rebate. If the eligibility code/income level is missing or unclear, set rule_result="warn" and explain that admin should verify the eligibility record before accepting the math.
5. rebate_per_unit = full_unit_after_tax_subtotal * rebate_percentage.
6. Each rebate_per_unit is capped at $950 per window or door.
For this rule, calculation must explicitly show the lower-of comparison: eligible cost after tax multiplied by the rebate percentage, eligible unit count multiplied by the $950 per-unit cap, the lower of those two values, and the comparison to the claimed windows/doors rebate.
Set rule_result="pass" only when the invoice provides enough visible values and the claimed per-unit rebate appears within the cap.
Set rule_result="fail" only when the visible values clearly show the claimed per-unit rebate exceeds the cap or calculation.
Set rule_result="warn" when hardware, labour, quantity, eligibility code, tax basis, or claimed per-unit rebate is missing/ambiguous but no visible value clearly exceeds the cap.
Set rule_result="fail" when visible values clearly show the claimed per-unit rebate exceeds the eligible cost calculation or $950 per-unit cap.
In calculation, show the visible formula and values used. Do not invent missing line-item values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_preapproval_supporting_document_attached', 'Check whether supporting_document_summary_for_upgrade_type includes preapproval_quote or preapproval_notice.
Set rule_result="pass" if an acceptable document is present with supporting_document_routing_quality="usable" and the expected located_fields are present with enough readable evidence for review.
Set rule_result="warn" if present but supporting_document_routing_quality is needs_review or requires_visual_review, or if key located_fields are missing, null, low-confidence, or too unclear for confident review.
Set rule_result="fail" if all acceptable document types are missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, or present only with supporting_document_routing_quality="unusable".', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_rough_opening_evidence_present', 'Check whether the invoice appears to provide enough quantity/count evidence for an admin to reason about Rough Openings (RO).
Program meaning:
- The eligible count is based on Rough Openings (RO), not panes or individual glass sections.
- Each RO counts as one eligible window/door rebate unit.
- A bay window may contain several window sections/panes, but it counts as one RO and qualifies for one rebate.
Set rule_result="pass" if the invoice clearly lists rough openings, window/door unit counts, or line items that appear to map cleanly to replacement openings.
Set rule_result="fail" if the count basis is unclear.
Set rule_result="fail" only if the invoice clearly appears to count panes/sections as separate rebate units without RO evidence.
In reason_and_likely_causes, say whether the invoice appears RO-based, unit-count based, pane-count based, or unclear.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_vancouver_municipal_boundary_review', 'Check whether any visible invoice/address evidence suggests the home is within the City of Vancouver municipal boundary.
Set rule_result="fail" if the invoice or supplied case facts clearly show the home is within the City of Vancouver municipal boundary.
Set rule_result="warn" if municipality cannot be determined from invoice/DB context; explain that admin/application data is needed and this is not a material invoice failure by itself.
Set rule_result="pass" if visible invoice and supplied case-fact evidence clearly point outside the City of Vancouver or contain no City of Vancouver concern.', true, TIMESTAMP '2026-05-26 00:00:00', NOW())
)
INSERT INTO claims.genai_rules (
  genai_rule_key,
  prompt_text,
  enabled,
  created_at,
  updated_at
)
SELECT
  genai_rule_key,
  prompt_text,
  enabled,
  created_at,
  updated_at
FROM genai_rules_seed
ON CONFLICT (genai_rule_key) DO UPDATE SET
  prompt_text = EXCLUDED.prompt_text,
  updated_at = NOW();

WITH genai_rule_upgrade_types_seed (
  upgrade_type_key,
  genai_rule_key,
  rule_number
) AS (
  VALUES
  ('air_source_heat_pump_electric', 'ashp_electric_existing_heat_context_present', 1),
  ('air_source_heat_pump_electric', 'ashp_electric_backup_heat_electric_present', 8),
  ('air_source_heat_pump_electric', 'hp_main_living_area_or_primary_capacity_present', 7),
  ('air_source_heat_pump_electric', 'hp_no_existing_or_secondary_heat_pump_flag', 6),
  ('air_source_heat_pump_gas_propane', 'ashp_gas_propane_existing_heat_context_present', 1),
  ('air_source_heat_pump_gas_propane', 'hp_conditioned_space_distribution_present', 2),
  ('air_source_heat_pump_gas_propane', 'ashp_fossil_fuel_removal_supporting_document_attached', 3),
  ('air_source_heat_pump_gas_propane', 'hp_fossil_backup_not_fossil_primary', 6),
  ('air_source_heat_pump_gas_propane', 'hp_no_existing_or_secondary_heat_pump_flag', 7),
  ('air_source_heat_pump_oil', 'ashp_oil_consumption_baseline_proof_present', 6),
  ('air_source_heat_pump_oil', 'ashp_oil_existing_heat_context_present', 1),
  ('air_source_heat_pump_oil', 'hp_conditioned_space_distribution_present', 2),
  ('air_source_heat_pump_oil', 'ashp_fossil_fuel_removal_supporting_document_attached', 3),
  ('air_source_heat_pump_oil', 'hp_fossil_backup_not_fossil_primary', 7),
  ('air_source_heat_pump_oil', 'hp_no_existing_or_secondary_heat_pump_flag', 8),
  ('air_source_heat_pump_wood', 'hp_main_living_area_or_primary_capacity_present', 7),
  ('air_source_heat_pump_wood', 'ashp_wood_backup_heat_not_fossil_present', 8),
  ('air_source_heat_pump_wood', 'ashp_wood_existing_heat_context_present', 1),
  ('air_source_heat_pump_wood', 'hp_no_existing_or_secondary_heat_pump_flag', 6),
  ('air_source_heat_pump_wood', 'ashp_wood_removal_or_wett_supporting_document_attached', 3),
  ('air_to_water_heat_pump', 'hp_main_living_area_or_primary_capacity_present', 2),
  ('air_to_water_heat_pump', 'hydronic_conversion_context_present', 3),
  ('air_to_water_heat_pump', 'hydronic_fossil_fuel_removal_supporting_document_attached', 9),
  ('air_to_water_heat_pump', 'hp_no_existing_or_secondary_heat_pump_flag', 7),
  ('air_to_water_heat_pump', 'hydronic_wood_removal_or_wett_supporting_document_attached', 10),
  ('combined_space_water_heat_pump', 'cshp_combined_space_and_water_scope_present', 6),
  ('combined_space_water_heat_pump', 'cshp_scope_present', 1),
  ('combined_space_water_heat_pump', 'hydronic_conversion_context_present', 3),
  ('combined_space_water_heat_pump', 'hydronic_fossil_fuel_removal_supporting_document_attached', 9),
  ('combined_space_water_heat_pump', 'cshp_no_existing_or_secondary_heat_pump_review', 7),
  ('combined_space_water_heat_pump', 'hydronic_wood_removal_or_wett_supporting_document_attached', 10),
  ('common', 'contractor_identity_matches_record', 7),
  ('common', 'homeowner_identity_matches_eligibility_record', 8),
  ('common', 'income_verification_supporting_documents_attached', 10),
  ('common', 'overall_invoice_arithmetic_consistent', 6),
  ('common', 'overall_rebate_not_over_invoice_total', 4),
  ('common', 'overall_rebate_not_over_paid_cost_of_upgrade', 5),
  ('common', 'rebate_line_evidence_present', 2),
  ('common', 'upgrade_type_evidence_present', 1),
  ('common', 'utility_account_supporting_document_attached', 9),
  ('common', 'warranty_costs_flag', 3),
  ('dual_fuel_ducted_heat_pump', 'dfhp_fossil_fuel_removal_or_modification_supporting_document_attached', 9),
  ('dual_fuel_ducted_heat_pump', 'dfhp_heat_load_calc_supporting_document_acceptable', 3),
  ('dual_fuel_ducted_heat_pump', 'dfhp_existing_heat_context_present', 6),
  ('dual_fuel_ducted_heat_pump', 'dfhp_switchover_setpoint_specific', 7),
  ('dual_fuel_ducted_heat_pump', 'hp_conditioned_space_distribution_present', 10),
  ('dual_fuel_ducted_heat_pump', 'hp_no_existing_or_secondary_heat_pump_flag', 11),
  ('electrical_service_upgrade', 'esu_contractor_utility_billed_work_on_one_invoice', 9),
  ('electrical_service_upgrade', 'esu_heat_pump_conversion_context_present', 3),
  ('electrical_service_upgrade', 'esu_not_panel_only_or_connection_only', 7),
  ('electrical_service_upgrade', 'esu_one_per_home_manual_review', 8),
  ('electrical_service_upgrade', 'esu_rebate_math_within_cap', 6),
  ('electrical_service_upgrade', 'esu_service_size_present', 1),
  ('electrical_service_upgrade', 'esu_timing_within_six_months_evidence', 4),
  ('electrical_service_upgrade', 'esu_utility_upgrade_supporting_document_attached', 2),
  ('health_and_safety_remediation', 'hs_associated_upgrade_present', 2),
  ('health_and_safety_remediation', 'hs_before_after_photos_attached', 7),
  ('health_and_safety_remediation', 'hs_issue_type_present', 1),
  ('health_and_safety_remediation', 'hs_not_standalone_flag', 3),
  ('health_and_safety_remediation', 'hs_pre_confirmation_evidence_present', 4),
  ('health_and_safety_remediation', 'hs_rebate_math_within_cap', 6),
  ('heat_pump_water_heater', 'hpwh_fossil_removal_supporting_document_attached', 9),
  ('heat_pump_water_heater', 'hpwh_no_existing_or_secondary_hpwh_flag', 8),
  ('heat_pump_water_heater', 'hpwh_primary_replacement_context_present', 1),
  ('heat_pump_water_heater', 'hpwh_product_reference_present', 2),
  ('insulation', 'ins_health_safety_issue_flag', 3),
  ('insulation', 'ins_material_and_location_present', 1),
  ('insulation', 'ins_minimum_r_value_and_boundary_present', 7),
  ('insulation', 'ins_r_value_and_area_present', 2),
  ('insulation', 'ins_rebate_math_within_cap', 6),
  ('insulation', 'ins_supporting_documents_attached', 4),
  ('ventilation', 'vent_associated_upgrade_present', 1),
  ('ventilation', 'vent_not_generic_ductwork_only', 7),
  ('ventilation', 'vent_product_or_capacity_evidence_present', 3),
  ('ventilation', 'vent_rebate_math_within_cap', 6),
  ('ventilation', 'vent_standalone_flag', 4),
  ('ventilation', 'vent_system_type_present', 2),
  ('windows_doors', 'wd_certification_reference_present', 2),
  ('windows_doors', 'wd_customer_portion_math_matches', 9),
  ('windows_doors', 'wd_envelope_replacement_evidence_present', 11),
  ('windows_doors', 'wd_label_photo_supporting_document_attached', 5),
  ('windows_doors', 'wd_no_skylights', 1),
  ('windows_doors', 'wd_per_home_rebate_math_within_cap', 8),
  ('windows_doors', 'wd_per_unit_rebate_math_within_cap', 7),
  ('windows_doors', 'wd_preapproval_supporting_document_attached', 6),
  ('windows_doors', 'wd_rough_opening_evidence_present', 3),
  ('windows_doors', 'wd_vancouver_municipal_boundary_review', 10)
)
INSERT INTO claims.genai_rule_upgrade_types (
  genai_rule_id,
  invoice_upgrade_type_id,
  rule_number,
  created_at,
  updated_at
)
SELECT
  gr.id,
  iut.id,
  seed.rule_number,
  NOW(),
  NOW()
FROM genai_rule_upgrade_types_seed seed
JOIN claims.genai_rules gr
  ON gr.genai_rule_key = seed.genai_rule_key
JOIN claims.invoice_upgrade_types iut
  ON iut.upgrade_type_key = seed.upgrade_type_key
ON CONFLICT (genai_rule_id, invoice_upgrade_type_id) DO UPDATE SET
  rule_number = EXCLUDED.rule_number,
  updated_at = NOW();

WITH genai_located_fields_seed (
  genai_field_key,
  prompt_text,
  enabled,
  created_at,
  updated_at
) AS (
  VALUES
  ('atw_equipment_type', 'Locate air-to-water heat pump evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('atw_line_amount', 'Locate air-to-water heat pump line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('atw_product_list_reference', 'Locate air-to-water qualifying product list references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('atw_space_heating_only_evidence', 'Locate evidence that the air-to-water system is for space heating only rather than combined domestic hot water.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('before_after_photo_reference', 'Locate text indicating before and after photos are attached or required.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('brand_and_model', 'Locate brand and model of windows/doors if present.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('certification_body_reference', 'Locate references to accepted certification bodies or rating/certification identifiers.
Accepted certification bodies and common references include:
- Canadian Standards Association (CSA)
- Intertek Canada (Intertek)
- Labtest Certification (LC / LabTest)
- QAI Laboratories (QAI)
- Keystone Certification (KC / Keystone)
- National Accreditation and Management Institute Certification (NAMI)
- National Fenestration Ratings Council (NFRC)
- NFRC Certified Products Directory (CPD)
Return the exact text found, not a paraphrase.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('city_of_vancouver_evidence', 'Locate any address, municipality, or explicit City of Vancouver evidence. This is usually application/DB context, but capture visible invoice text if present.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('contractor_gst_number', 'Locate contractor GST number within the invoice.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cpd_number', 'Locate CPD / NFRC Certified Products Directory identifier, if present.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_domestic_hot_water_evidence', 'Locate domestic hot water, potable water, DHW, combination system, or integrated tank evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_equipment_type', 'Locate combined space and water heat pump evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_line_amount', 'Locate combined space/water heat pump line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_product_list_reference', 'Locate air-to-water/combined heat pump qualifying product list references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('customer_deposit', 'Locate customer deposit or customer payment already made.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_equipment_type', 'Locate dual fuel ducted heat pump evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_existing_heat_evidence', 'Locate visible evidence that the home was primarily heated by tanked propane, PNG natural gas, PNG propane, generic natural gas, generic propane, or a fireplace. Include wording that supports or contradicts the prior primary heating context, whether the fuel was tanked/PNG/generic, and whether the fossil system is being retained or integrated with the new dual-fuel ducted heat pump. Use value=null when prior primary heating context is not visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_fossil_modification_evidence', 'Locate fossil fuel removal/modification evidence, permit, inspection, capping, piping, vent, or appliance changes.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_heat_load_calc_reference', 'Locate program-approved heat load calculation, CSA-F280, Manual J, or sizing evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_line_amount', 'Locate the visible eligible charge for the dual-fuel ducted heat pump upgrade itself before CleanBC rebates, credits, deposits, or prior payments are deducted. Include only the dual-fuel ducted heat pump equipment, materials, and installation charges that belong to this upgrade. Exclude separately itemized northern top-up amounts, CleanBC rebate lines, customer deposits/payments, financing, taxes-only totals, unrelated upgrades, and fossil-fuel removal/modification work unless the invoice explicitly bundles that work into the dual-fuel ducted heat pump upgrade cost. Use value=null when the eligible DFHP upgrade charge is not visible or cannot be separated from unrelated work. In evidence_text, cite the exact line item, subtotal, or totals wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_make_model', 'Locate heat pump and furnace make/model numbers.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_source_fuel_path', 'Locate whether the visible source/fuel path appears to be PNG natural gas, PNG propane, tank propane, generic natural gas, generic propane, or unclear.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_switchover_setpoint_evidence', 'Locate thermostat, outdoor temperature switchover, equipment control board, <=5 C, <=2 C, or similar controls evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('eligibility_code', 'Locate the eligibility code if visible in invoice text. Expected prefixes are ESP1, ESP2, or ESP3. If the invoice does not visibly show one, do not invent it from the supplied database values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('envelope_replacement_evidence', 'Locate evidence that the work replaces existing windows/doors between heated indoor space and unheated/outdoor space.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_associated_heat_pump_or_hpwh_reference', 'Locate associated heat pump or heat pump water heater invoice/work references.

Electrical service upgrade', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_contractor_utility_management_evidence', 'Locate evidence that contractor/electrician managed the line upgrade with the electrical utility.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_eligible_expense_lines', 'Locate service upgrade expense lines, such as connection fees, panel or sub-panel upgrade, service mast, conduit, meter base, weather head, or labour.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_fossil_to_heat_pump_context', 'Locate evidence that the upgrade is associated with conversion from oil, propane, or natural gas primary heating or water heating to a heat pump.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_heat_pump_installation_date_reference', 'Locate heat pump installation date or timing evidence if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_ineligible_panel_only_evidence', 'Locate evidence that the invoice is only a panel/sub-panel or heat pump connection without utility service upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_line_amount', 'Locate electrical service upgrade line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_new_service_size', 'Locate new service size if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_permit_or_ahj_reference', 'Locate permit, inspection, Technical Safety BC, Authority Having Jurisdiction, or by-law compliance references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_previous_service_size', 'Locate previous service size if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_service_size', 'Locate upgraded electrical service size, such as 100 amp, 200 amp, or 400 amp service.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_utility_billing_reference', 'Locate utility billing evidence for the line/service upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_utility_reference', 'Locate BC Hydro, FortisBC, utility connection, line upgrade, or utility bill/invoice references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hardware_per_unit', 'Locate hardware/material price per unit.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_backup_heat_evidence', 'Locate backup heat evidence and note if it appears electric, wood, fossil fuel, fireplace-only, secondary, primary, or unclear. If a natural-gas or propane fireplace is visible, state whether the wording supports that it is secondary rather than the backup or primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_conditioned_space_distribution_evidence', 'Locate evidence that the heat pump distributes heat through the conditioned space formerly served by the primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_efficiency_and_capacity', 'Locate SEER/HSPF/SEER2/HSPF2, variable speed compressor, BTU/tonnage, or capacity evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_existing_electric_heat_evidence', 'Locate hard-wired electric baseboard, radiant ceiling/floor, electric furnace, electric boiler, or other electric primary heat evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_existing_gas_propane_heat_evidence', 'Locate natural gas, propane, furnace, boiler, tank propane, PNG, FortisBC gas, or similar existing heat evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_existing_heat_pump_flag', 'Locate evidence of an existing heat pump, add-on heat pump, secondary heat pump, or replacement of an existing heat pump.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_existing_oil_heat_evidence', 'Locate oil furnace, oil boiler, oil tank, fuel oil, 500 L oil baseline, or similar existing heat evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_existing_wood_heat_evidence', 'Locate wood stove, pellet stove, insert, wood furnace, solid fuel, or similar existing primary heat evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_fossil_combination_boiler_evidence', 'Locate fossil combination boiler or domestic-hot-water hydronic space-heating references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_fossil_fuel_removal_evidence', 'Locate removal, decommissioning, capping, disconnection, appliance/piping/vent/fuel-container removal, permit, or inspection evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_heat_load_calc_reference', 'Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_installation_labour_amount', 'Locate installation labour amount if shown separately.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_upgrade_line_amount', 'Locate the visible line-item amount or subtotal for the claimed air-source heat pump upgrade.

Return the amount for the air-source heat pump equipment and installation scope tied to this upgrade type. Include outdoor unit, indoor head units, air handler, central ducted heat-pump components, and installation labour when they are presented as part of the same air-source heat pump upgrade line or subtotal.

Do not include CleanBC / Better Homes / ESP rebate amounts, customer payments, deposits, taxes-only totals, invoice-wide totals, unrelated upgrades, electrical service upgrades, heat pump water heaters, air-to-water heat pumps, dual-fuel heat pumps, ventilation, insulation, windows/doors, health and safety remediation, warranty/maintenance plans, financing charges, or fossil-fuel removal work unless the invoice clearly includes them in a single labelled air-source heat pump upgrade subtotal.

Use value=null when the air-source heat pump upgrade amount is missing, ambiguous, bundled with unrelated upgrades without a clear subtotal, or cannot be separated from other work.

In evidence_text, cite the exact visible line label, subtotal label, or arithmetic used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_main_living_area_evidence', 'Locate evidence that the heat pump serves a main living area or whole-home/primary heating load.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_make_model', 'Locate make/model numbers.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_new_equipment_type', 'Locate single-head mini-split, 2-head/multi-split, ductless mini-split, ductless multi-split, central ducted, low-static ducted mini, indoor heads/zones, or similar.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_northern_top_up_evidence', 'Locate northern top-up evidence if shown.

Return the visible separate northern top-up amount, exact top-up label or wording, location evidence for north of and including the District of 100 Mile House, and evidence that the home is connected to BC Hydro electric service.

Use value=null when no separate northern top-up is visible.

In evidence_text, cite the exact visible top-up label, amount, location wording, and BC Hydro service wording when present. If the top-up is visible but location or BC Hydro evidence is missing, say which part is missing.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_oil_consumption_baseline_evidence', 'Locate 500 L annual oil-consumption evidence, fuel bills, receipts, or similar references if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_oil_system_removal_evidence', 'Locate oil system and oil tank removal, decommissioning, capping, disconnection, permit, or inspection evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_product_list_reference', 'Locate qualified heat pump product list, NRCan, ENERGY STAR, NEEP, NRCan Oil to Heat Pump Affordability qualified product list, or similar references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_registered_contractor_or_permit_evidence', 'Locate registered contractor, AHJ, permit, inspection, Technical Safety BC, or by-law compliance references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_wood_system_removal_or_wett_evidence', 'Locate wood/solid-fuel removal evidence, retained-appliance evidence, or WETT report reference.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_existing_fuel_type', 'Locate visible evidence for the existing primary water-heater fuel/source path before the heat pump water heater upgrade. Classify the path as fossil fuel when the evidence shows natural gas, gas water heater, propane, oil, fuel oil, or other fossil-fuel water heating. Classify the path as electric or wood when the evidence shows electric water heater, electricity, wood, pellet, or solid fuel. Use value=null when the prior water-heater fuel/source path is not visible or cannot be separated from unrelated space-heating evidence. In evidence_text, cite the exact line item or surrounding wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_existing_hpwh_flag', 'Locate evidence of an existing heat pump water heater or secondary/additional heat pump water heater.

Heat pump water heater', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_existing_water_heater_evidence', 'Locate text about the existing primary water heater being replaced.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_fossil_fuel_removal_evidence', 'Locate removal, decommissioning, capping, disconnection, piping/appliance/container/vent removal, or permit/inspection references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_fossil_removal_date_or_permit', 'Locate removal/decommissioning date, permit, inspection, or removal-company invoice details if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_line_amount', 'Locate the visible eligible charge for the heat pump water heater upgrade itself before CleanBC rebates, credits, deposits, or prior payments are deducted. Include only the heat pump water heater equipment, materials, and installation charges that belong to this upgrade. Exclude CleanBC rebate lines, customer deposits/payments, financing, taxes-only totals, unrelated upgrades, and fossil-fuel removal/decommissioning work unless the invoice explicitly bundles that work into the heat pump water heater upgrade cost. Use value=null when the eligible HPWH upgrade charge is not visible or cannot be separated from unrelated work. In evidence_text, cite the exact line item, subtotal, or totals wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_make_model', 'Locate combined heat pump water heater make/model text for admin readability when present. This is a fallback/display field; prefer hpwh_manufacturer, hpwh_model_number, and hpwh_model_components for exact product-list matching.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_manufacturer', 'Locate the heat pump water heater manufacturer, brand, or vendor product brand as a standalone value. Do not include the model number unless the invoice only shows a combined phrase.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_model_components', 'Locate multiple model numbers/components if the invoice shows a split-system water heater, heat pump unit plus storage tank, or multiple component model numbers. Preserve the component relationship and separators such as "&" when visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_model_number', 'Locate the heat pump water heater model number exactly as shown on the invoice, label, quote, or product line. Do not include the manufacturer/brand unless the invoice only shows a combined phrase.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_neea_reference', 'Locate NEEA Advanced Water Heater Specification or qualified product list references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_new_equipment_type', 'Locate heat pump water heater equipment type.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_secondary_system_flag', 'Locate evidence the invoice is for a secondary/additional water heater rather than replacing the primary system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_tier_reference', 'Locate Tier 2 or higher evidence if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_associated_upgrade_evidence', 'Locate evidence that remediation enabled heat pump, heat pump water heater, insulation, or windows/doors work.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_confirmation_date_or_reference', 'Locate the date/reference for pre-confirmation that remediation was rebate-eligible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_issue_type', 'Locate health/safety issue type, such as pest, asbestos, structural, mould, vermiculite, or other safety concern.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_line_amount', 'Locate health and safety remediation line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_pre_confirmation_reference', 'Locate pre-confirmation or rebate-eligible confirmation references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_registered_contractor_evidence', 'Locate registered/approved contractor evidence if visible.

Health and safety', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_remediation_scope', 'Locate description of remediation work completed.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_resolution_completion_date', 'Locate remediation completion/resolution date if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_technical_safety_or_permit_reference', 'Locate Technical Safety BC, permit, lawful authority, manufacturer specification, or by-law compliance references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_conversion_source_fuel_evidence', 'Locate visible evidence of the home''s existing primary heating source before the hydronic heat pump upgrade. Accepted source paths are fossil fuel (oil, propane, or natural gas), electricity, and wood/solid fuel. Include wording that supports whether the system was the primary heating system, whether it could heat at least 50% of the home for the full heating season to 21 degrees Celsius, and whether any fireplace evidence appears to be only a fireplace rather than the primary heating system. Use value=null when the prior primary heating source is not visible. In evidence_text, cite the exact wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_fossil_removal_evidence', 'Locate fossil-fuel removal/decommissioning evidence if fossil fuel is involved.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_wood_removal_or_wett_evidence', 'Locate wood-system removal or WETT evidence if wood is involved.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_area_square_feet', 'Locate square feet / upgrade area.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_conditioned_boundary_evidence', 'Locate evidence that insulation is between conditioned and unconditioned space.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_existing_r_value', 'Locate pre-existing R-value if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_floor_plan_reference', 'Locate floor plan drawing references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_health_safety_resolution_evidence', 'Locate evidence that pest, rodent, vermiculite, asbestos, or mould issues were resolved before insulation work.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_line_amount', 'Locate insulation line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_location_specific_rebate_amount', 'Locate location-specific insulation rebate amounts if itemized.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_material_type', 'Locate insulation material type, such as batt, loose fill, board, or spray foam.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_minimum_r_value_requirement_evidence', 'Locate any stated minimum R-value requirement or code/program reference.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_new_r_value', 'Locate new R-value.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_r_value_added', 'Locate R-value added or difference in R-value.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_rebate_formula_or_rate_evidence', 'Locate rebate-rate/formula text, such as dollars per R-value added per square foot.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_registered_contractor_evidence', 'Locate registered/approved insulation contractor evidence if visible.

Insulation', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_removed_existing_insulation_evidence', 'Locate evidence of removed pre-existing insulation due to pest, mould, or similar issue.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ins_upgrade_location', 'Locate insulation location, such as attic, exterior wall cavity, exterior wall sheathing, basement/crawlspace, exposed floor, floor over crawlspace, or basement header.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_contractor_address', 'Locate the contractor/vendor business address visibly shown on the invoice if present.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_contractor_name', 'Locate the contractor, vendor, supplier, or business name visibly shown on the invoice. Prefer the invoice header/vendor name over generic text in descriptions.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_homeowner_name', 'Locate the homeowner, customer, bill-to, ship-to, or participant name visibly shown on the invoice. Prefer explicit customer/bill-to/homeowner fields over payment-history names or generic references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_upgrade_type_evidence', 'Locate text that indicates the broad upgrade type, such as windows, doors, heat pump, insulation, ventilation, electrical service, health/safety, or water heater.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('labour_cost_invoice_total', 'Locate total invoice labour cost if shown separately.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('labour_per_unit', 'Locate labour breakdown per unit.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('manufacturer_label_photo_reference', 'Locate text suggesting manufacturer label photos are included, attached, or required.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('metric_u_factor', 'Locate metric U-factor numeric values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('nrcan_number', 'Locate NRCan ENERGY STAR fenestration registration number, if present.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_line_amount', 'Locate the visible overall CleanBC / Better Homes / Energy Savings Program rebate amount for the whole invoice.

Return the single invoice-level total rebate amount when the invoice clearly shows one.
If the invoice does not show a single invoice-level total rebate amount, but does show multiple visible CleanBC / Better Homes / ESP rebate amounts for specific upgrade lines, return the sum of those visible rebate amounts.
Use value=null when neither a single invoice-level total rebate amount nor summable upgrade-specific rebate amounts are visible.
Do not include discounts, taxes, deposits, customer payments, credits, financing amounts, warranty coverage, insurance coverage, or non-program rebates unless the visible label clearly identifies the amount as a CleanBC / Better Homes / ESP rebate.
In evidence_text, cite the exact visible rebate label or totals-line wording. If summing multiple upgrade-specific rebate amounts, show the arithmetic using the visible labels and values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_line_description', 'Locate the text description for the overall rebate line, explicit total rebate summary, or visible split upgrade-specific rebate lines that together form the invoice-level rebate.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('paid_cost_of_upgrade_amount', 'Locate the visible paid cost of the upgrade.

This field is the participant/customer paid cost for the claimed upgrade after CleanBC / Better Homes / ESP rebates have been applied, including amounts already paid by the participant and amounts still owed by the participant for that upgrade.
Use value only when the invoice clearly shows the paid cost of the claimed upgrade, or when the invoice clearly shows enough named totals to calculate it from visible invoice arithmetic.
Do not use InvoiceTotal for this field unless the invoice clearly shows no rebate, credit, deposit, payment, insurance, warranty, or other deduction affects the participant-paid cost.
Do not use AmountDue by itself unless the invoice label, totals section, or visible arithmetic clearly shows AmountDue represents the participant/customer paid cost for the claimed upgrade.
Use value=null when the paid cost of the upgrade is missing, ambiguous, not separated from other upgrades, or cannot be confidently calculated from visible named invoice fields.
In evidence_text, cite the exact visible labels and arithmetic used, such as participant total owed, customer payment, deposit, balance paid, amount due, rebate, credit, or upgrade subtotal.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('pane_count', 'Locate pane count if invoice appears to count panes instead of rough openings.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('quote_preapproval_reference', 'Locate quote pre-approval, pre-approval, or approval-before-installation references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('rough_opening_count', 'Locate rough opening count if explicitly stated.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('skylight_detected', 'Locate evidence that any claimed item is a skylight; value should be true/false/null.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('upgrade_specific_rebate_line_amount', 'Locate the CleanBC/Better Homes/ESP rebate amount for this specific upgrade only.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_associated_upgrade_evidence', 'Locate evidence that ventilation is installed with heat pump, heat pump water heater, insulation, or windows/doors work.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_backdraft_damper_evidence', 'Locate self-closing backdraft damper evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_bathroom_fan_cfm', 'Locate bathroom fan capacity in cfm or L/s.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_continuous_duty_motor_evidence', 'Locate continuous duty or permanently lubricated motor evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_contractor_license_evidence', 'Locate HVAC, heat pump, electrical, or approved contractor references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_direct_exterior_ducting_evidence', 'Locate evidence that bathroom fans are ducted directly outdoors.

Ventilation', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_ducting_evidence', 'Locate ducting, exterior exhaust, sealed joints, insulated ducts, or duct hood references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_energy_star_reference', 'Locate ENERGY STAR references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_generic_ductwork_only_flag', 'Locate evidence that the work is merely ductwork, airflow balancing, or HVAC distribution rather than an eligible HRV/ERV or bathroom fan system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_improved_air_circulation_evidence', 'Locate text indicating improved air circulation.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_line_amount', 'Locate ventilation line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_main_bathroom_evidence', 'Locate main bathroom / bathtub / shower evidence for bathroom fan systems.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_nrcan_or_product_list_reference', 'Locate NRCan product list or ENERGY STAR product list references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_static_pressure', 'Locate static pressure rating evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_system_type', 'Locate ventilation system type, such as HRV, ERV, heat recovery ventilator, energy recovery ventilator, bathroom fan, or fan system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('wd_registered_contractor_evidence', 'Locate registered contractor, approved contractor, or contractor company evidence if visible.

Windows/doors', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('window_or_door_line_amount', 'Locate total amount for each window/door line item.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('window_or_door_quantity', 'Locate quantity of windows/doors.', true, TIMESTAMP '2026-05-26 00:00:00', NOW())
)
INSERT INTO claims.genai_located_fields (
  genai_field_key,
  prompt_text,
  enabled,
  created_at,
  updated_at
)
SELECT
  genai_field_key,
  prompt_text,
  enabled,
  created_at,
  updated_at
FROM genai_located_fields_seed
ON CONFLICT (genai_field_key) DO UPDATE SET
  prompt_text = EXCLUDED.prompt_text,
  updated_at = NOW();

WITH genai_located_field_upgrade_types_seed (
  upgrade_type_key,
  genai_field_key,
  field_number
) AS (
  VALUES
  ('air_source_heat_pump_electric', 'hp_efficiency_and_capacity', 6),
  ('air_source_heat_pump_electric', 'hp_existing_electric_heat_evidence', 2),
  ('air_source_heat_pump_electric', 'hp_existing_heat_pump_flag', 12),
  ('air_source_heat_pump_electric', 'hp_heat_load_calc_reference', 7),
  ('air_source_heat_pump_electric', 'hp_installation_labour_amount', 9),
  ('air_source_heat_pump_electric', 'ashp_upgrade_line_amount', 8),
  ('air_source_heat_pump_electric', 'hp_main_living_area_evidence', 11),
  ('air_source_heat_pump_electric', 'hp_make_model', 3),
  ('air_source_heat_pump_electric', 'hp_new_equipment_type', 1),
  ('air_source_heat_pump_electric', 'hp_product_list_reference', 5),
  ('air_source_heat_pump_electric', 'hp_registered_contractor_or_permit_evidence', 13),
  ('air_source_heat_pump_electric', 'hp_backup_heat_evidence', 14),
  ('air_source_heat_pump_electric', 'upgrade_specific_rebate_line_amount', 10),
  ('air_source_heat_pump_gas_propane', 'hp_backup_heat_evidence', 12),
  ('air_source_heat_pump_gas_propane', 'hp_conditioned_space_distribution_evidence', 16),
  ('air_source_heat_pump_gas_propane', 'hp_efficiency_and_capacity', 6),
  ('air_source_heat_pump_gas_propane', 'hp_existing_gas_propane_heat_evidence', 2),
  ('air_source_heat_pump_gas_propane', 'hp_existing_heat_pump_flag', 14),
  ('air_source_heat_pump_gas_propane', 'hp_fossil_combination_boiler_evidence', 15),
  ('air_source_heat_pump_gas_propane', 'hp_fossil_fuel_removal_evidence', 7),
  ('air_source_heat_pump_gas_propane', 'hp_heat_load_calc_reference', 8),
  ('air_source_heat_pump_gas_propane', 'ashp_upgrade_line_amount', 10),
  ('air_source_heat_pump_gas_propane', 'hp_make_model', 3),
  ('air_source_heat_pump_gas_propane', 'hp_new_equipment_type', 1),
  ('air_source_heat_pump_gas_propane', 'hp_northern_top_up_evidence', 9),
  ('air_source_heat_pump_gas_propane', 'hp_product_list_reference', 5),
  ('air_source_heat_pump_gas_propane', 'upgrade_specific_rebate_line_amount', 11),
  ('air_source_heat_pump_oil', 'hp_backup_heat_evidence', 13),
  ('air_source_heat_pump_oil', 'hp_conditioned_space_distribution_evidence', 17),
  ('air_source_heat_pump_oil', 'hp_efficiency_and_capacity', 6),
  ('air_source_heat_pump_oil', 'hp_existing_heat_pump_flag', 15),
  ('air_source_heat_pump_oil', 'hp_existing_oil_heat_evidence', 2),
  ('air_source_heat_pump_oil', 'hp_fossil_combination_boiler_evidence', 16),
  ('air_source_heat_pump_oil', 'hp_heat_load_calc_reference', 8),
  ('air_source_heat_pump_oil', 'ashp_upgrade_line_amount', 10),
  ('air_source_heat_pump_oil', 'hp_make_model', 3),
  ('air_source_heat_pump_oil', 'hp_new_equipment_type', 1),
  ('air_source_heat_pump_oil', 'hp_northern_top_up_evidence', 9),
  ('air_source_heat_pump_oil', 'hp_oil_consumption_baseline_evidence', 12),
  ('air_source_heat_pump_oil', 'hp_oil_system_removal_evidence', 7),
  ('air_source_heat_pump_oil', 'hp_product_list_reference', 5),
  ('air_source_heat_pump_oil', 'upgrade_specific_rebate_line_amount', 11),
  ('air_source_heat_pump_wood', 'hp_backup_heat_evidence', 13),
  ('air_source_heat_pump_wood', 'hp_efficiency_and_capacity', 6),
  ('air_source_heat_pump_wood', 'hp_existing_heat_pump_flag', 12),
  ('air_source_heat_pump_wood', 'hp_existing_wood_heat_evidence', 2),
  ('air_source_heat_pump_wood', 'hp_heat_load_calc_reference', 8),
  ('air_source_heat_pump_wood', 'ashp_upgrade_line_amount', 9),
  ('air_source_heat_pump_wood', 'hp_main_living_area_evidence', 11),
  ('air_source_heat_pump_wood', 'hp_make_model', 3),
  ('air_source_heat_pump_wood', 'hp_new_equipment_type', 1),
  ('air_source_heat_pump_wood', 'hp_product_list_reference', 5),
  ('air_source_heat_pump_wood', 'hp_registered_contractor_or_permit_evidence', 14),
  ('air_source_heat_pump_wood', 'hp_wood_system_removal_or_wett_evidence', 7),
  ('air_source_heat_pump_wood', 'upgrade_specific_rebate_line_amount', 10),
  ('air_to_water_heat_pump', 'atw_equipment_type', 1),
  ('air_to_water_heat_pump', 'atw_line_amount', 8),
  ('air_to_water_heat_pump', 'atw_product_list_reference', 4),
  ('air_to_water_heat_pump', 'atw_space_heating_only_evidence', 13),
  ('air_to_water_heat_pump', 'hp_existing_heat_pump_flag', 12),
  ('air_to_water_heat_pump', 'hp_heat_load_calc_reference', 7),
  ('air_to_water_heat_pump', 'hp_main_living_area_evidence', 14),
  ('air_to_water_heat_pump', 'hp_make_model', 3),
  ('air_to_water_heat_pump', 'hp_northern_top_up_evidence', 10),
  ('air_to_water_heat_pump', 'hydronic_conversion_source_fuel_evidence', 2),
  ('air_to_water_heat_pump', 'hydronic_fossil_removal_evidence', 5),
  ('air_to_water_heat_pump', 'hydronic_wood_removal_or_wett_evidence', 6),
  ('air_to_water_heat_pump', 'upgrade_specific_rebate_line_amount', 9),
  ('combined_space_water_heat_pump', 'cshp_domestic_hot_water_evidence', 10),
  ('combined_space_water_heat_pump', 'cshp_equipment_type', 1),
  ('combined_space_water_heat_pump', 'cshp_line_amount', 8),
  ('combined_space_water_heat_pump', 'cshp_product_list_reference', 4),
  ('combined_space_water_heat_pump', 'hp_existing_heat_pump_flag', 13),
  ('combined_space_water_heat_pump', 'hp_heat_load_calc_reference', 7),
  ('combined_space_water_heat_pump', 'hp_make_model', 3),
  ('combined_space_water_heat_pump', 'hp_northern_top_up_evidence', 11),
  ('combined_space_water_heat_pump', 'hydronic_conversion_source_fuel_evidence', 2),
  ('combined_space_water_heat_pump', 'hydronic_fossil_removal_evidence', 5),
  ('combined_space_water_heat_pump', 'hydronic_wood_removal_or_wett_evidence', 6),
  ('combined_space_water_heat_pump', 'upgrade_specific_rebate_line_amount', 9),
  ('common', 'contractor_gst_number', 1),
  ('common', 'customer_deposit', 4),
  ('common', 'eligibility_code', 2),
  ('common', 'invoice_contractor_address', 10),
  ('common', 'invoice_contractor_name', 9),
  ('common', 'invoice_homeowner_name', 11),
  ('common', 'invoice_upgrade_type_evidence', 8),
  ('common', 'labour_cost_invoice_total', 3),
  ('common', 'overall_rebate_line_amount', 5),
  ('common', 'overall_rebate_line_description', 6),
  ('common', 'paid_cost_of_upgrade_amount', 7),
  ('dual_fuel_ducted_heat_pump', 'dfhp_equipment_type', 1),
  ('dual_fuel_ducted_heat_pump', 'dfhp_existing_heat_evidence', 2),
  ('dual_fuel_ducted_heat_pump', 'dfhp_fossil_modification_evidence', 7),
  ('dual_fuel_ducted_heat_pump', 'dfhp_heat_load_calc_reference', 6),
  ('dual_fuel_ducted_heat_pump', 'dfhp_line_amount', 8),
  ('dual_fuel_ducted_heat_pump', 'dfhp_make_model', 3),
  ('dual_fuel_ducted_heat_pump', 'dfhp_source_fuel_path', 10),
  ('dual_fuel_ducted_heat_pump', 'dfhp_switchover_setpoint_evidence', 5),
  ('dual_fuel_ducted_heat_pump', 'hp_conditioned_space_distribution_evidence', 13),
  ('dual_fuel_ducted_heat_pump', 'hp_existing_heat_pump_flag', 14),
  ('dual_fuel_ducted_heat_pump', 'hp_northern_top_up_evidence', 11),
  ('dual_fuel_ducted_heat_pump', 'hp_registered_contractor_or_permit_evidence', 12),
  ('dual_fuel_ducted_heat_pump', 'upgrade_specific_rebate_line_amount', 9),
  ('electrical_service_upgrade', 'esu_associated_heat_pump_or_hpwh_reference', 14),
  ('electrical_service_upgrade', 'esu_contractor_utility_management_evidence', 7),
  ('electrical_service_upgrade', 'esu_eligible_expense_lines', 5),
  ('electrical_service_upgrade', 'esu_fossil_to_heat_pump_context', 3),
  ('electrical_service_upgrade', 'esu_heat_pump_installation_date_reference', 4),
  ('electrical_service_upgrade', 'esu_ineligible_panel_only_evidence', 6),
  ('electrical_service_upgrade', 'esu_line_amount', 9),
  ('electrical_service_upgrade', 'esu_new_service_size', 12),
  ('electrical_service_upgrade', 'esu_permit_or_ahj_reference', 8),
  ('electrical_service_upgrade', 'esu_previous_service_size', 11),
  ('electrical_service_upgrade', 'esu_service_size', 1),
  ('electrical_service_upgrade', 'esu_utility_billing_reference', 13),
  ('electrical_service_upgrade', 'esu_utility_reference', 2),
  ('electrical_service_upgrade', 'upgrade_specific_rebate_line_amount', 10),
  ('health_and_safety_remediation', 'before_after_photo_reference', 5),
  ('health_and_safety_remediation', 'hs_associated_upgrade_evidence', 2),
  ('health_and_safety_remediation', 'hs_confirmation_date_or_reference', 9),
  ('health_and_safety_remediation', 'hs_issue_type', 1),
  ('health_and_safety_remediation', 'hs_line_amount', 7),
  ('health_and_safety_remediation', 'hs_pre_confirmation_reference', 3),
  ('health_and_safety_remediation', 'hs_registered_contractor_evidence', 11),
  ('health_and_safety_remediation', 'hs_remediation_scope', 4),
  ('health_and_safety_remediation', 'hs_resolution_completion_date', 10),
  ('health_and_safety_remediation', 'hs_technical_safety_or_permit_reference', 6),
  ('health_and_safety_remediation', 'upgrade_specific_rebate_line_amount', 8),
  ('heat_pump_water_heater', 'hp_registered_contractor_or_permit_evidence', 16),
  ('heat_pump_water_heater', 'hpwh_existing_fuel_type', 2),
  ('heat_pump_water_heater', 'hpwh_existing_hpwh_flag', 17),
  ('heat_pump_water_heater', 'hpwh_existing_water_heater_evidence', 1),
  ('heat_pump_water_heater', 'hpwh_fossil_fuel_removal_evidence', 11),
  ('heat_pump_water_heater', 'hpwh_fossil_removal_date_or_permit', 15),
  ('heat_pump_water_heater', 'hpwh_line_amount', 13),
  ('heat_pump_water_heater', 'hpwh_make_model', 7),
  ('heat_pump_water_heater', 'hpwh_manufacturer', 4),
  ('heat_pump_water_heater', 'hpwh_model_components', 6),
  ('heat_pump_water_heater', 'hpwh_model_number', 5),
  ('heat_pump_water_heater', 'hpwh_neea_reference', 8),
  ('heat_pump_water_heater', 'hpwh_new_equipment_type', 3),
  ('heat_pump_water_heater', 'hpwh_secondary_system_flag', 10),
  ('heat_pump_water_heater', 'hpwh_tier_reference', 9),
  ('heat_pump_water_heater', 'upgrade_specific_rebate_line_amount', 14),
  ('insulation', 'before_after_photo_reference', 10),
  ('insulation', 'ins_area_square_feet', 7),
  ('insulation', 'ins_conditioned_boundary_evidence', 3),
  ('insulation', 'ins_existing_r_value', 5),
  ('insulation', 'ins_floor_plan_reference', 11),
  ('insulation', 'ins_health_safety_resolution_evidence', 9),
  ('insulation', 'ins_line_amount', 12),
  ('insulation', 'ins_location_specific_rebate_amount', 14),
  ('insulation', 'ins_material_type', 1),
  ('insulation', 'ins_minimum_r_value_requirement_evidence', 15),
  ('insulation', 'ins_new_r_value', 4),
  ('insulation', 'ins_r_value_added', 6),
  ('insulation', 'ins_rebate_formula_or_rate_evidence', 16),
  ('insulation', 'ins_registered_contractor_evidence', 17),
  ('insulation', 'ins_removed_existing_insulation_evidence', 8),
  ('insulation', 'ins_upgrade_location', 2),
  ('insulation', 'upgrade_specific_rebate_line_amount', 13),
  ('ventilation', 'upgrade_specific_rebate_line_amount', 13),
  ('ventilation', 'vent_associated_upgrade_evidence', 2),
  ('ventilation', 'vent_backdraft_damper_evidence', 9),
  ('ventilation', 'vent_bathroom_fan_cfm', 6),
  ('ventilation', 'vent_continuous_duty_motor_evidence', 8),
  ('ventilation', 'vent_contractor_license_evidence', 11),
  ('ventilation', 'vent_direct_exterior_ducting_evidence', 16),
  ('ventilation', 'vent_ducting_evidence', 10),
  ('ventilation', 'vent_energy_star_reference', 4),
  ('ventilation', 'vent_generic_ductwork_only_flag', 14),
  ('ventilation', 'vent_improved_air_circulation_evidence', 3),
  ('ventilation', 'vent_line_amount', 12),
  ('ventilation', 'vent_main_bathroom_evidence', 15),
  ('ventilation', 'vent_nrcan_or_product_list_reference', 5),
  ('ventilation', 'vent_static_pressure', 7),
  ('ventilation', 'vent_system_type', 1),
  ('windows_doors', 'brand_and_model', 6),
  ('windows_doors', 'certification_body_reference', 1),
  ('windows_doors', 'city_of_vancouver_evidence', 17),
  ('windows_doors', 'cpd_number', 5),
  ('windows_doors', 'envelope_replacement_evidence', 16),
  ('windows_doors', 'hardware_per_unit', 11),
  ('windows_doors', 'labour_per_unit', 12),
  ('windows_doors', 'manufacturer_label_photo_reference', 2),
  ('windows_doors', 'metric_u_factor', 7),
  ('windows_doors', 'nrcan_number', 4),
  ('windows_doors', 'pane_count', 10),
  ('windows_doors', 'quote_preapproval_reference', 3),
  ('windows_doors', 'rough_opening_count', 9),
  ('windows_doors', 'skylight_detected', 15),
  ('windows_doors', 'upgrade_specific_rebate_line_amount', 14),
  ('windows_doors', 'wd_registered_contractor_evidence', 18),
  ('windows_doors', 'window_or_door_line_amount', 13),
  ('windows_doors', 'window_or_door_quantity', 8)
)
INSERT INTO claims.genai_located_field_upgrade_types (
  genai_field_id,
  invoice_upgrade_type_id,
  field_number,
  created_at,
  updated_at
)
SELECT
  gf.id,
  iut.id,
  seed.field_number,
  NOW(),
  NOW()
FROM genai_located_field_upgrade_types_seed seed
JOIN claims.genai_located_fields gf
  ON gf.genai_field_key = seed.genai_field_key
JOIN claims.invoice_upgrade_types iut
  ON iut.upgrade_type_key = seed.upgrade_type_key
ON CONFLICT (genai_field_id, invoice_upgrade_type_id) DO UPDATE SET
  field_number = EXCLUDED.field_number,
  updated_at = NOW();

COMMIT;
