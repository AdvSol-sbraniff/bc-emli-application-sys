BEGIN;

WITH genai_rules_seed (
  genai_rule_key,
  prompt_text,
  enabled,
  source_quote,
  legacy_contractor_visible_flag,
  created_at,
  updated_at
) AS (
  VALUES
  ('ashp_electric_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by hard-wired electric space heating and that the new air-source heat pump is replacing that system.
A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.
Use invoice evidence first, and treat supporting-document facts only as corroborating context.
Set rule_result="pass" when electric primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, or is contradicted by supplied supporting-document facts.', true, 'The home must primarily be heated by electricity (a primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C).', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_electric_backup_heat_electric_present', 'Check whether the electric-to-heat-pump backup space heating system is electric.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hp_backup_heat_evidence: visible backup heat evidence and whether it appears electric, wood, fossil fuel, or unclear.
- hp_existing_electric_heat_evidence: visible hard-wired electric heating evidence, only as corroborating context when it also speaks to retained or backup heat.

For AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC), the back-up space heating system must be electric.

Set rule_result="pass" when hp_backup_heat_evidence clearly shows electric backup heat, such as electric baseboard, electric resistance, electric furnace, electric boiler, radiant electric ceiling/floor, or other electric backup space heating.
Set rule_result="warn" when backup heat context is missing, ambiguous, or only implied by the prior electric heating system without clear backup wording.
Set rule_result="fail" when hp_backup_heat_evidence clearly shows wood, natural gas, propane, oil, dual-fuel fossil backup, or another non-electric backup space heating system.
In calculation, state hp_backup_heat_evidence and whether the backup heat is electric, non-electric, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'replace an existing hard-wired electric heating system (e.g. electric baseboards, radiant ceilings, radiant floors, or forced-air furnace). The back-up space heating system must be electric.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_gas_propane_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by fossil fuel natural gas or propane and that the new air-source heat pump is replacing that system.

Natural-gas or propane primary-heating evidence includes natural gas furnace, propane furnace, fossil-fuel furnace, gas boiler, propane boiler, FortisBC gas, PNG gas, propane tank, or similar wording.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.

Use invoice evidence first, and treat supporting-document facts only as corroborating context.

Set rule_result="pass" when natural-gas/propane primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, or is contradicted by supplied supporting-document facts.', true, 'The home must be primarily heated by fossil fuel (natural gas or propane). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_fossil_fuel_removal_supporting_document_attached', 'Check whether an acceptable fossil-fuel heating-system removal supporting document is present for this air-source heat pump conversion from natural gas, propane, or oil.

Use these named document types and located fields as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
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
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the path decision.', true, '3. Proof of fossil fuel (natural gas or propane) system removal. One of the following documents will be accepted:
a. local government permit or inspection report, which must include:
i. date of inspection.
ii. address where inspection took place.
b. invoice from the removal company or heat pump installation company, which must include:
i. description of the work completed (e.g. the oil system, including oil tank, was removed according to applicable regulations and local government bylaws).
ii. date of removal.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_oil_consumption_baseline_proof_present', 'Check whether the submitted evidence proves the 500 L annual oil-consumption baseline for this oil-to-heat-pump claim.

Use these named document types and located fields as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- utility_bill: utility_service_type_or_fuel_evidence, utility_provider, account_or_bill_date, account_number_or_reference, and fuel_consumption_quantity_or_period.
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.

Accepted proof may be an oil receipt, heating-oil or fuel-oil bill, fuel delivery invoice, or similar oil-consumption invoice when it is routed under utility_bill and the located fields support oil/fuel-oil consumption in the 12 months prior to application.

Set rule_result="pass" when utility_bill is present with supporting_document_routing_quality="usable" and the located fields show readable oil/fuel-oil consumption proof tied to the participant/home or account, with a bill/receipt/invoice date or service period in the 12 months prior to application, and the visible quantity shows at least 500 L annually or enough bills/receipts/invoices for admin to confirm at least 500 L.
Set rule_result="warn" when an accepted document type is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears to be oil-consumption proof but the fuel type, date/service period, quantity, account/home tie, or located-field text is missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when utility_bill is missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, present only with supporting_document_routing_quality="unusable", clearly does not show oil/fuel-oil consumption proof, or clearly shows consumption below 500 L for the relevant annual period.
In calculation, state whether utility_bill was present, missing, or unclear; list the relevant located fields and whether each is present/usable; and show the visible oil quantity/date comparison to the 500 L annual baseline when available.
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the decision.', true, 'The home must meet a minimum oil consumption baseline of 500 Ltrs. annually. Proof of oil consumption from the 12 months prior to application must be submitted at the time of application, such as receipts, fuel bills or invoices.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_oil_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by oil and that the new air-source heat pump is replacing that system.

Oil primary-heating evidence includes oil furnace, oil boiler, oil-fired heating system, heating oil tank, fuel oil delivery or consumption, or similar wording.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21 degrees Celsius. A fireplace is not considered a primary heating system.

Use invoice evidence first, and treat supporting-document facts only as corroborating context.

Set rule_result="pass" when oil primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, relies only on a fireplace as the prior primary heating system, or is contradicted by supplied supporting-document facts.', true, 'The home must be primarily heated by oil. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_wood_backup_heat_not_fossil_present', 'Check whether visible backup heat evidence for this wood-to-heat-pump upgrade appears to be wood or electric rather than fossil fuel.
Set rule_result="pass" when backup heat is clearly wood/electric or no fossil-backup concern is visible.
Set rule_result="warn" when backup fuel context is missing or ambiguous.
Set rule_result="fail" when visible evidence shows fossil-fuel backup remains as a backup or primary heating system.', true, 'The back-up heating system must be wood or electric. Fossil fuel back-up systems (e.g. dual fuel ducted heat pumps or standalone fossil fuel heating systems) are not eligible for wood-to-heat pump upgrades.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_wood_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by a wood or solid fuel heating system and that the new air-source heat pump is replacing that system.

Wood or solid fuel heating evidence includes wood stove, pellet stove, insert, wood furnace, solid fuel furnace, or similar wording.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.

Use invoice evidence first, and treat supporting-document facts only as corroborating context.

Set rule_result="pass" when wood/solid-fuel primary heat replacement is clear.
Set rule_result="warn" when the conversion context is plausible but incomplete.
Set rule_result="fail" when the prior heating context is missing, points to a different fuel path, or is contradicted by supplied supporting-document facts.', true, 'The home must primarily be heated by a wood or solid fuel heating system (wood or pellet stove, insert or furnace). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('ashp_wood_removal_or_wett_supporting_document_attached', 'Check whether the required wood/solid-fuel removal or safe-retention supporting document is present for this wood-to-heat-pump upgrade.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hp_wood_system_removal_or_wett_evidence: invoice evidence about whether the existing wood or solid-fuel heating system was removed, retained, WETT-inspected, decommissioned, or otherwise addressed.
- supporting_document_summary_for_upgrade_type: the routed supporting-document summary for this upgrade type, including before_after_photo_set and wett_report document types, routing quality, not-present document types, and located fields.
- before_after_photo_set located fields, including photo_role, visible_subject_or_area, visible_condition_summary, image_quality_or_legibility, and visible_text_or_label_values.
- wett_report located fields, including wett_inspection_date, wett_inspector_certification_number, site_address, compliance_or_removal_conclusion, wett_inspector_or_company_name, and wett_appliance_or_system_reference.

If the visible evidence shows the wood or solid-fuel heating system was removed, require before_after_photo_set evidence for the removed wood/solid-fuel heating system.
If the visible evidence shows the wood or solid-fuel heating system was retained in safe and working order, require wett_report evidence.
If the removal/retention path is unclear, do not guess which document is required.

Use the supporting-document types, routing summaries, and located fields as evidence, but judge the substance of the evidence rather than treating routing labels as automatic pass/fail gates. Image-based before/after photo evidence may naturally require visual review; that alone should not prevent a pass when the photo roles and visible-condition summaries clearly support the requirement.

Set rule_result="pass" when the removal/retention path is clear and the required evidence for that path is present and substantively supports the requirement.
Set rule_result="warn" when the removal/retention path is unclear, or when the required evidence appears present but is incomplete, ambiguous, low-quality, inconsistent, or does not give enough substance to confidently confirm the requirement.
Set rule_result="fail" when the removal/retention path is clear and the required evidence for that path is missing, unusable, or clearly contradicts the requirement.
In calculation, state the visible path used: removed, retained, or unclear; then identify the required evidence for that path and summarize the evidence found.
In evidence_text, cite the exact invoice or supporting-document wording/located fields that support the path and document decision.', true, 'Before and after photos of the wood or solid fuel heating system if it is removed.

Copy of an inspection report completed by a Wood Energy Technology Transfer Inc. (WETT)-certified professional if the wood or solid fuel heating system is being retained in safe and working order.

The inspection report must be dated within the 12-month period before or 6-month period following the date of the heat pump installation invoice and include the inspector’s WETT certification number, the site address of the wood or solid fuel heating system, and whether the installation is compliant with relevant codes.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('contractor_identity_matches_record', 'Check whether the contractor/vendor identity visible on the invoice appears to match the contractor record that uploaded or owns the invoice.
Use contractors.business_name and contractors.address from the supplied database values.
Use invoice_contractor_name and invoice_contractor_address from the OCR/DI JSON.
Set rule_result="pass" when the visible contractor name clearly matches the database contractor name, including obvious legal-name/DBA/trade-name formatting differences, and the visible address does not contradict the database address.
Set rule_result="info" when the contractor appears to match but there is a harmless variation worth explaining, such as abbreviated legal suffix, DBA wording, missing unit number, or invoice address omitted while the name clearly matches. This is a blue pass: no contractor correction is requested, but the match is not as squeaky clean as an exact green pass.
Set rule_result="warn" when the visible contractor name or address is missing/ambiguous, or when the database contractor fact is missing, so admin should verify identity from the contractor record or supporting documents.
Set rule_result="fail" when the invoice visibly appears to belong to a different contractor/vendor than the database contractor record.
In evidence_text, include the visible invoice contractor name/address and the supplied database contractor name/address.
In reason_and_likely_causes, explain exactly what matches, what differs, and whether the admin should ignore, verify, or treat it as a likely wrong-contractor upload.', true, 'All upgrades must be installed by a Registered Contractor, as defined by the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions. To find a Registered Contractor, use the Find a Contractor search tool or email betterhomesESP@clearesult.com. Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_fossil_fuel_removal_or_modification_supporting_document_attached', 'Check whether an acceptable fossil-fuel propane or natural-gas system removal or modification supporting document is present for this dual-fuel ducted heat-pump upgrade.

Use these named document types and located fields as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
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
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the path decision.', true, '2. Proof of fossil fuel (propane or natural gas) system removal or modification (as applicable for the upgrade). One of the following documents will be accepted:
a. local government permit or inspection report, which must include:
i. date of inspection.
ii. address where inspection took place.
b. invoice from the removal or modification company or heat pump installation company, which must include:
i. description of work completed pertaining to removal or modification, as applicable for the upgrade.
ii. date of removal or modification.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_heat_load_calc_supporting_document_acceptable', 'Check whether an acceptable program-approved heat-load calculation is present for this dual-fuel ducted heat-pump upgrade.

Use these named document types and located fields as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- supporting_document_summary_for_upgrade_type: routed document types, supporting_document_routing_quality, present documents, and not_present_applicable_type_keys.
- f280_heat_load_calculation: calculation_date, site_address, design_heat_load_value, professional_or_company_name, calculation_standard_reference, approval_or_professional_reference, approval_status_or_condition, sizing_method_or_rule_of_thumb_evidence, and supplemental_heat_source_assumptions.

The heat-load calculation must support proper system sizing. Rule-of-thumb equipment sizing is not acceptable. Supplemental heating from electric or other non-fossil fuel heating systems may be considered in the heat-load calculation. Supplemental heating from fossil fuel heating systems, including a gas fireplace, natural gas, propane, or oil system, must not be considered in the heat-load calculation.

Set rule_result="pass" when f280_heat_load_calculation is present with supporting_document_routing_quality="usable" and the named located fields show readable heat-load sizing evidence, program approval or professional/program acceptance evidence, no rule-of-thumb sizing concern, and no fossil-fuel supplemental heat considered in the calculation.
Set rule_result="warn" when f280_heat_load_calculation is present but supporting_document_routing_quality is needs_review or requires_visual_review, or when the document appears relevant but approval/program acceptance, sizing method, design heat-load value, or supplemental-heat assumptions are missing, null, low-confidence, visually limited, or too unclear for confident review.
Set rule_result="fail" when f280_heat_load_calculation is missing, listed in not_present_applicable_type_keys with no acceptable present equivalent, present only with supporting_document_routing_quality="unusable", clearly uses rule-of-thumb equipment sizing, or clearly considers fossil-fuel supplemental heat such as a gas fireplace, natural gas, propane, or oil system.
In calculation, state whether f280_heat_load_calculation is present/usable, then list calculation_standard_reference, design_heat_load_value, approval_or_professional_reference, approval_status_or_condition, sizing_method_or_rule_of_thumb_evidence, and supplemental_heat_source_assumptions.
In evidence_text, cite the exact supporting-document summary and located-field wording that supports the decision.', true, 'A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted. Supplemental heating from other electric or non-fossil fuel heating systems may be considered in the heat load calculation. Supplemental heating from fossil fuel heating systems (e.g. gas fireplace) cannot be considered in the heat load calculation. If you’re unsure if your current heat load calculation methodology meets the program criteria, please contact betterhomesbc@gov.bc.ca.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_existing_heat_context_present', 'Check whether the invoice supports that the home was primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG), and that the new dual-fuel ducted heat pump is integrated with that existing fossil-fuel heating system.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- dfhp_existing_heat_evidence: visible evidence of PNG natural gas, PNG propane, tanked propane, generic natural gas, generic propane, or unclear prior primary heating context.
- dfhp_source_fuel_path: visible source-fuel path, only as corroborating context.
- dfhp_equipment_type: visible dual-fuel ducted heat pump evidence, only as corroborating context.

A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21 degrees Celsius. A fireplace is not considered a primary heating system.

Set rule_result="pass" when the named evidence clearly supports that the prior primary heating system was tanked propane, PNG natural gas, or PNG propane, and the invoice supports dual-fuel integration with that system.
Set rule_result="warn" when the prior primary heat context is plausible but incomplete, such as visible propane without clear tanked-propane evidence, visible natural gas without clear PNG evidence, or dual-fuel integration wording without enough prior-heating context.
Set rule_result="fail" when the prior primary heating evidence is missing, points to a different fuel path, relies only on a fireplace as the prior primary heating system, shows generic natural gas without PNG support, shows generic propane without tanked-propane support, or is contradicted by supplied supporting-document facts.
In calculation, state dfhp_existing_heat_evidence, dfhp_source_fuel_path, and whether the accepted path is PNG natural gas, PNG propane, tanked propane, generic/unsupported, unclear, or contradicted.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_switchover_setpoint_specific', 'Check whether the thermostat, outdoor temperature switch-over control, or equipment control board is set to the required region-specific temperature for this dual-fuel ducted heat pump.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- dfhp_switchover_setpoint_evidence: invoice-visible thermostat, outdoor temperature switch-over control, equipment control board, setpoint, lockout temperature, region, or similar control evidence.
- dual_fuel_control_document located fields: control_setup_date, equipment_reference, switchover_setpoint, backup_fuel_or_integration_evidence, and region_or_temperature_threshold_evidence.

Thresholds:
- Lower Mainland and Vancouver Island regions: setpoint must be <=5 C.
- Southern Interior and Northern B.C. regions: setpoint must be <=2 C.

Set rule_result="pass" when the named evidence clearly identifies a thermostat, outdoor temperature switch-over control, or equipment control board tied to the dual-fuel ducted heat pump and clearly shows a setpoint at or below the required threshold for the visible region.
Set rule_result="warn" when control equipment is referenced but the setpoint is missing, the region is missing, the equipment tie is unclear, or the located fields are low-confidence, visually limited, or too ambiguous for confident comparison.
Set rule_result="fail" when the named evidence clearly shows the setpoint is above the required threshold for the visible region, or clearly shows no thermostat/switch-over/control-board setup for the dual-fuel ducted heat pump.
In calculation, state the visible region, required threshold, visible setpoint, whether the evidence came from dfhp_switchover_setpoint_evidence or dual_fuel_control_document, and whether the setpoint is within threshold.
In evidence_text, cite the exact named-field wording that supports the region, setpoint, and control-equipment decision.', true, 'Southern Interior and Northern B.C. regions: ≤2°C', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_contractor_utility_billed_work_on_one_invoice', 'Decide whether the electrical service upgrade complies with the utility-management and billing rule. The electrician or heat pump contractor must manage the utility line upgrade. Either the participant or contractor may be billed; only contractor-billed utility work must appear with contractor work on one invoice. Read the package as a whole and use ordinary professional judgment. Management may be reasonably inferred from a coherent contractor/electrician service-upgrade record; literal management wording and a separate utility document are not required. Pass when compliance is reasonably supported. Use info for a meaningful but non-actionable limitation. Warn only for a concrete material reason to doubt compliance, and fail on clear contradiction.', true, 'To be eligible for the electrical service upgrade the electrician and/or heat pump contractor completing the electrical service upgrade must manage the line upgrade with the electrical utility (BC Hydro or FortisBC) that the home is connected to. Either the contractor or the participant can be billed by the utility for the line upgrade. If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice. See the sample invoice or contact betterhomesESP@clearesult.com.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_eligible_expense_lines_present', 'Decide whether the electrical service upgrade charge is substantially for eligible costs: utility connection, panel or sub-panel upgrade, service mast, conduit, meter base, weather head, or labour. Read the billed scope as a whole and use ordinary professional judgment. Pass when it clearly represents eligible work tied to a utility service upgrade. Warn only when the billed work is genuinely ambiguous or inseparably mixed with unrelated electrical work. Fail when it is clearly ineligible. Utility billing arrangements and rebate arithmetic are handled by separate rules.', true, '4. Eligible expenses include:
a. utility connection fees.
b. electrical panel or sub-panel upgrade.
c. service mast alterations or replacement.
d. conduit replacement, meter base alterations or replacements.
e. weather head alteration or replacement.
f. labour.', true, TIMESTAMP '2026-07-09 00:00:00', NOW()),
  ('esu_heat_pump_conversion_context_present', 'Decide whether the electrical service upgrade is associated with an eligible conversion from oil, propane, or natural-gas primary space or water heating to a heat pump. Read the package as a whole and use ordinary professional judgment. For primary space heating, confirm that the evidence supports capacity to heat at least 50% of the home throughout the heating season to 21°C. Program association may be inferred from the complete claim context; documents do not need to repeat the program name. Pass when the eligible conversion is reasonably supported. Warn only when a material conversion fact is genuinely uncertain. Fail on clear contradiction or a clearly ineligible conversion path.', true, 'Only homes that convert from a fossil fuel (oil, propane or natural gas) primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program are eligible. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_not_panel_only_or_connection_only', 'Check whether the claimed electrical service upgrade includes an electric utility service/new-wire upgrade, rather than only a panel upgrade, sub-panel upgrade, breaker work, or heat-pump connection to the panel.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- esu_ineligible_panel_only_evidence: visible evidence that the invoice is only a panel/sub-panel or heat pump connection without utility service upgrade.
- esu_utility_reference: visible BC Hydro, FortisBC, utility connection, line upgrade, or utility bill/invoice references.
- esu_service_size, esu_previous_service_size, and esu_new_service_size: visible upgraded service-size evidence.
- esu_eligible_expense_lines: visible ESU expense lines, including whether they are tied to utility service/new-wire work or only panel/sub-panel/connection work.
- supporting_document_summary_for_upgrade_type, utility_bill, and electrical_utility_upgrade_document located fields when available, including utility_provider, previous_service_size, new_service_size, service_address, service_completion_or_invoice_date, and utility_upgrade_cost_or_reference.

Set rule_result="pass" when the named evidence shows utility service/new-wire/line-upgrade context, such as BC Hydro or FortisBC service upgrade, utility connection, service mast/weather head/meter base work tied to service upgrade, or upgraded 100/200/400 amp service evidence.
Set rule_result="warn" when panel/sub-panel/connection work is visible and utility service evidence is missing, incomplete, or ambiguous after considering invoice and supporting-document evidence, but the work is not clearly limited to ineligible panel-only or heat-pump-connection-only scope.
Set rule_result="fail" when the named evidence clearly shows only panel upgrade, sub-panel upgrade, breaker work, heat-pump connection to the panel, or other internal electrical work with no electric utility service/new-wire upgrade by BC Hydro or FortisBC.
In calculation, state esu_ineligible_panel_only_evidence, esu_utility_reference, service-size evidence, utility supporting-document evidence used, and classify the visible scope as utility_service_upgrade, ambiguous, or panel_or_connection_only.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_service_size_present', 'Check whether the invoice or configured supporting-document located fields clearly reference a 100, 200, or 400 amp electrical service upgrade.
Use utility_bill and electrical_utility_upgrade_document located fields such as previous_service_size, new_service_size, service_address, service_completion_or_invoice_date, and utility_upgrade_cost_or_reference.
Set rule_result="warn" if electrical work is visible but service size is missing or ambiguous after checking the utility supporting documents.', true, 'The service upgrade (new wire) is for upgrading to 100, 200 or 400-amp service to an existing home and must be installed within six months of the heat pump installation.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_utility_upgrade_supporting_document_attached', 'Determine whether the supplied invoice or supporting documents support that BC Hydro or FortisBC upgraded the electric service/new wire. The requirement accepts either a utility bill or an invoice for the 100, 200, or 400 amp electrical service upgrade. Treat the primary contractor invoice as the invoice path when it identifies the utility and qualifying service upgrade and itemizes and deducts the program rebate; do not require a separate utility attachment in that case. Pass when either accepted evidence path supports the requirement. Warn only when the supplied invoice and supporting documents leave the utility involvement or qualifying service upgrade genuinely unclear. Fail on clear contradiction.', true, 'The electric service (new wire) must be upgraded by the participants electrical utility (BC Hydro or FortisBC). Supporting documentation: Utility bill or invoice for the electrical service upgrade (100, 200, or 400 amp service), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('homeowner_identity_matches_eligibility_record', 'Check whether the homeowner/customer name visible on the invoice appears to match the participant/homeowner associated with the classifier-located eligibility code.
Use invoice_homeowner_name from the supplied invoice located fields and users.participant_name from the supplied database values.
The eligibility code is only the lookup key used to select the participant record. Do not compare classifier.eligibility_code with users_eligibilitycodes.eligibility_code. The deterministic eligibility_code_found_in_database rule owns whether the code resolves to a database record.
Set rule_result="pass" when the invoice-visible homeowner/customer name clearly matches users.participant_name, including common first-name/last-name ordering, initials, spouse/household formatting, accents, middle names, or minor OCR spelling differences.
An additional middle or given name by itself is a harmless name variation and should pass when the remaining name components match and no competing homeowner identity appears.
Set rule_result="info" when the name likely matches but a harmless alternate format, such as first initial plus last name, spouse/household wording, or a minor OCR typo, prevents an exact clean match. This is a blue pass: no contractor correction is requested, but the match is not as squeaky clean as an exact green pass.
Set rule_result="warn" when the invoice homeowner/customer name is missing or ambiguous, or when users.participant_name is missing.
Set rule_result="fail" when both names are clear and the invoice visibly appears to be for a different homeowner/customer than the participant associated with the eligibility code.
In evidence_text, include the visible invoice homeowner/customer name and database participant name. The eligibility code may be included only to identify which participant record was selected; do not present it as another value being compared by this rule.
In reason_and_likely_causes, explain whether this is a clear match, harmless formatting variation, missing/ambiguous evidence, or likely wrong-homeowner invoice.', true, 'Participants must pre-register and confirm eligibility prior to installing upgrades. Following pre-registration, eligible participants will receive an eligibility code.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_fossil_backup_not_fossil_primary', 'Check whether the backup heating system for this fossil-fuel-to-heat-pump upgrade is electric or wood, with only the allowed exception for a retained natural-gas/propane fireplace that is clearly secondary.

Use this named field as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hp_backup_heat_evidence: visible backup heat evidence and whether it appears electric, wood, fossil fuel, fireplace-only, secondary, primary, or unclear.

Set rule_result="pass" when hp_backup_heat_evidence clearly shows the backup heating system is electric or wood.
Set rule_result="pass" when the only visible natural-gas/propane retained heat is a fireplace and the evidence clearly shows it is secondary, not the backup heating system and not the primary heating system.
Set rule_result="warn" when backup heat context is missing, ambiguous, or when a natural-gas/propane fireplace is visible but the evidence does not clearly show whether it is secondary.
Set rule_result="fail" when hp_backup_heat_evidence clearly shows natural gas, propane, oil, dual-fuel fossil backup, or another fossil-fuel system remains as the backup heating system.
Set rule_result="fail" when a natural-gas/propane fireplace is visible and the evidence shows it is primary, backup, or not clearly limited to a secondary fireplace role.
In calculation, state hp_backup_heat_evidence and classify the visible backup context as electric, wood, secondary gas/propane fireplace, fossil backup, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'The back-up heating system must be electric or wood. Homes with a natural gas or propane fireplaces are able to retain the fireplace, if the fireplace is a secondary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_no_existing_or_secondary_heat_pump_flag', 'Check whether invoice text suggests the work is replacing, adding to, or adding a secondary heat pump for a home with an existing heat pump.
Set rule_result="pass" when no existing/add-on/secondary heat-pump concern is visible.
Set rule_result="warn" when the invoice wording is ambiguous and admin should verify whether this is a new eligible primary system.
Set rule_result="fail" when visible evidence shows replacement of an existing heat pump, an add-on to an existing heat pump, or a secondary heat pump for a home with an existing heat pump.', true, 'Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_fossil_removal_supporting_document_attached', 'Check whether an acceptable gas/fossil-fuel water-heater removal supporting document is present when the heat pump water heater replaced a fossil-fuel water heating system.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
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
In evidence_text, cite the exact named-field wording that supports the decision.', true, '2. Proof of gas water heater removal if the heat pump water heater replaced a fossil fuel water heating system. One of the following documents will be accepted:
a. local government permit or inspection report, which must include:
i. date of inspection.
ii. address where inspection took place.
b. invoice from the removal company or heat pump water heater installation company, which must include:
i. description of work completed (e.g. the gas water heater was removed according to applicable regulations and local government bylaws).
ii. date of removal.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_no_existing_or_secondary_hpwh_flag', 'Check whether the named evidence suggests the upgrade is replacing an existing heat pump water heater, adding to a home with an existing heat pump water heater, or adding a secondary/additional heat pump water heater.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hpwh_existing_hpwh_flag: evidence of an existing heat pump water heater or secondary/additional heat pump water heater.
- hpwh_existing_water_heater_evidence: evidence about the existing primary water heater being replaced.
- hpwh_secondary_system_flag: evidence that the invoice is for a secondary/additional water heater rather than replacement of the primary system.

Set rule_result="pass" when the named evidence shows a new heat pump water heater replacing a non-heat-pump primary water heater, and no existing/additional/secondary heat pump water heater concern is visible.
Set rule_result="warn" when the evidence is incomplete or ambiguous about whether an existing heat pump water heater is already present or whether the new system is secondary/additional.
Set rule_result="fail" when the named evidence clearly shows replacement of an existing heat pump water heater, adding a secondary/additional heat pump water heater, or adding a heat pump water heater to a home that already has an existing heat pump water heater.
In calculation, state hpwh_existing_hpwh_flag, hpwh_existing_water_heater_evidence, hpwh_secondary_system_flag, and classify the concern as none, existing_hpwh_replacement, secondary_or_additional_hpwh, existing_hpwh_home, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'Replacing or adding a secondary heat pump water heater to a home with an existing heat pump water heater is not eligible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_primary_replacement_context_present', 'Check whether the invoice provides evidence that the heat pump water heater replaces the home''s primary water heater.
Set rule_result="warn" if this likely requires application/DB context and the invoice does not show a secondary/additional system.', true, 'The existing water heater being replaced must be the home’s primary water heater.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_associated_upgrade_present', 'Check whether the named evidence supports that health and safety remediation was required to enable safe installation and operation of an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade, and was completed in association with that eligible upgrade rather than claimed on its own.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hs_associated_upgrade_evidence: evidence that remediation enabled heat pump, heat pump water heater, insulation, or windows/doors work.
- hs_remediation_scope: description of the remediation work completed.
- hs_issue_type: health/safety issue type being remediated.
- hs_line_amount and upgrade_specific_rebate_line_amount: visible health and safety remediation cost/rebate context, only as supporting invoice-scope evidence.
- invoice_upgrade_type_evidence and the classified invoice upgrade type context when supplied.

Set rule_result="pass" when the named evidence clearly connects the remediation to an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade and does not show the remediation being claimed as a standalone upgrade.
Set rule_result="warn" when the remediation appears plausibly associated with an eligible upgrade but the connection likely requires application/DB context, associated-invoice context, or admin confirmation; or when the invoice does not contradict association but the association is incomplete or ambiguous.
Set rule_result="fail" when the named evidence clearly shows health and safety remediation is being claimed on its own without an associated eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade, or clearly connects the remediation only to an ineligible/unrelated project.
In calculation, state hs_associated_upgrade_evidence, hs_remediation_scope, hs_issue_type, any supplied upgrade-type context, and classify the association as associated_eligible_upgrade, standalone, unrelated_ineligible_project, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'Health and safety remediation must be completed in association with an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for health and safety remediation on its own.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_before_after_photos_attached', 'Determine whether the supplied evidence contains clear before and after photos of the health and safety issue that was remediated. Consider the supporting-document summary, routing explanation, and located visual evidence together. Do not return a warning solely because the evidence is photographic or has requires_visual_review routing.
Set rule_result="pass" when both states are identifiable and depict the same issue or remediated area.
Set rule_result="warn" when the photos are present but their roles, quality, subject relationship, or condition change is genuinely unclear.
Set rule_result="fail" when the required photos are missing, unusable, or clearly do not depict the relevant remediation.', true, 'Before and after photos of the health and safety issue that was remediated.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_issue_type_present', 'Check whether the named evidence identifies an existing health and safety issue in the home that was remediated.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hs_issue_type: health/safety issue type, such as pest, asbestos, structural, mould, vermiculite, or other safety concern.
- hs_remediation_scope: description of remediation work completed.
- hs_resolution_completion_date: remediation completion/resolution date if visible.
- hs_technical_safety_or_permit_reference: permit, Technical Safety BC, lawful authority, manufacturer specification, or by-law compliance references when visible.

Set rule_result="pass" when the named evidence clearly identifies an existing health and safety issue in the home and the visible issue type is pest, asbestos, structural, mould, vermiculite, or a similar safety concern.
Set rule_result="warn" when remediation work is visible but the pre-existing health/safety issue type is missing, generic, incomplete, or too ambiguous to classify confidently.
Set rule_result="fail" when the named evidence clearly shows the work is not remediation for an existing health and safety issue in the home, or the visible issue is unrelated to health/safety remediation eligibility.
In calculation, state hs_issue_type, hs_remediation_scope, hs_resolution_completion_date, hs_technical_safety_or_permit_reference, and classify the issue as eligible_issue, unclear, or unrelated.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'Health and safety remediation is for existing health and safety issues in the home.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_pre_confirmation_evidence_present', 'Check whether the named evidence supports that the health and safety remediation was confirmed as rebate-eligible before remediation began.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- hs_pre_confirmation_reference: pre-confirmation or rebate-eligible confirmation reference.
- hs_confirmation_date_or_reference: date/reference for pre-confirmation that remediation was rebate-eligible.
- hs_remediation_scope: description of remediation work completed.
- hs_resolution_completion_date: remediation completion/resolution date if visible.

Set rule_result="pass" when the named evidence clearly shows the remediation was confirmed as rebate-eligible before remediation began or before visible remediation completion.
Set rule_result="warn" when pre-confirmation evidence is missing, incomplete, or likely lives in application/admin records rather than invoice OCR, and the named evidence does not contradict pre-confirmation.
Set rule_result="fail" when the named evidence clearly shows remediation began or was completed before rebate-eligibility confirmation, or shows confirmation was denied/not eligible.
In calculation, state hs_pre_confirmation_reference, hs_confirmation_date_or_reference, hs_remediation_scope, hs_resolution_completion_date, and classify pre-confirmation status as confirmed_before_remediation, missing_or_admin_context_needed, contradicted, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'Health and safety remediation must be confirmed as rebate-eligible prior to beginning remediation. For confirmation, contact betterhomesESP@clearesult.com.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_conversion_context_present', 'Check whether the named evidence supports that the home was primarily heated by fossil fuel, electricity, or wood/solid fuel before the hydronic heat-pump upgrade.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
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
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_fossil_fuel_removal_supporting_document_attached', 'Check whether an acceptable fossil-fuel heating-system removal supporting document is present when the hydronic heat pump replaced an oil, propane, or natural-gas heating system.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
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
In evidence_text, cite the exact named-field wording that supports the decision.', true, '3. Proof of fossil fuel (oil, propane or natural gas) system removal if the heat pump replaced a fossil fuel heating system. One of the following documents will be accepted:
a. local government permit or inspection report, which must include:
i. date of inspection.
ii. address where inspection took place.
b. invoice from the removal company or heat pump water heater installation company, which must include:
i. description of work completed (e.g. the gas water heater was removed according to applicable regulations and local government bylaws).
ii. date of removal.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_wood_removal_or_wett_supporting_document_attached', 'If the visible source-fuel path is wood or solid fuel, check whether the required wood/solid-fuel removal or safe-retention supporting document is present.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
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
In evidence_text, cite the exact invoice or supporting-document wording/located fields that support the path and document decision.', true, 'The inspection report must be dated within the 12-month period before or 6-month period following the date of the heat pump installation invoice and include the inspector’s WETT certification number, the site address of the wood or solid fuel heating system, and whether the installation is compliant with relevant codes.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_invoice_arithmetic_consistent', 'Check whether the invoice visibly itemizes the CleanBC / Better Homes / Energy Savings Program rebate, deducts it from the participant financial responsibility, and presents amounts that reconcile.

Use the complete invoice layout to identify the reasonable roles of visible charges, tax, rebates or credits, totals, payments, and balances. An invoice can show intermediate gross, net, participant-facing, or third-party amounts, and its labels may be unconventional without making its arithmetic wrong. Do not subtract a rebate twice when a displayed amount already includes it.

This rule evaluates numerical reconciliation and whether the rebate reduces participant responsibility. It does not audit tax policy or decide whether tax should legally or conventionally be calculated before or after a rebate. Treat a clearly displayed tax amount as part of the invoice arithmetic. A rebate or credit may reduce the participant balance without changing the displayed taxable basis.
Evaluate only the monetary reconciliation in this rule; do not lower the result for invoice, payment, installation, or other date or chronology issues.

Treat Amount Due as the participant or customer balance unless the invoice clearly labels it as a program or other third-party receivable. Do not require a customer-facing Amount Due value to equal the program rebate.

Set rule_result="pass" when the visible amounts reconcile under a reasonable interpretation supported by the document.
Set rule_result="info" when the amounts reconcile but a specific unconventional or imperfect label or structure prevents a clean pass. State the concrete non-blocking caveat; do not use info merely because the arithmetic is interesting or deserves explanation.
Set rule_result="warn" when a necessary amount is missing or unreadable, or the amount roles remain genuinely ambiguous after considering the complete layout.
Set rule_result="fail" only when the visible numbers cannot reconcile under any reasonable document-supported arithmetic sequence, or when the itemized rebate is not actually deducted from participant responsibility. Do not fail for unconventional labels, presentation choices, or the displayed tax basis when the arithmetic itself reconciles.

In calculation, show one reasonable reconstruction of the visible arithmetic and identify the participant-facing total or balance. In reason_and_likely_causes, explain the document-supported structure without imposing a predefined accounting model.', true, 'Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_not_over_invoice_total', 'Determine whether the rebate shown on the invoice exceeds the invoice total. Read the invoice as a whole and use ordinary professional judgment to identify the relevant amounts. Pass when the rebate is less than or equal to the invoice total, warn only when the comparison cannot be made confidently, and fail when the rebate exceeds the invoice total. Show the calculation.', true, 'Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_not_over_paid_cost_of_upgrade', 'Determine whether the rebate shown on the invoice exceeds the paid or payable cost of the claimed upgrade. Read the invoice as a whole and use ordinary professional judgment. Do not mistake a post-rebate customer balance for the upgrade cost. Pass when the rebate is less than or equal to the paid or payable upgrade cost, warn only when the comparison cannot be made confidently, and fail when the rebate exceeds that cost. Show the calculation.', true, 'Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('rebate_line_evidence_present', 'Determine whether the invoice visibly itemizes the CleanBC rebate and makes the rebate amount understandable. Read the invoice and supplied program context as a whole. Pass when the program rebate is clearly identified, warn when rebate evidence exists but its identity or amount is genuinely unclear, and fail when no program rebate evidence is visible or the invoice contradicts its existence. The word "estimated" by itself does not weaken an otherwise clearly identified and quantified program rebate line. Do not evaluate invoice arithmetic in this rule.', true, 'Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_associated_upgrade_present', 'Check whether the named evidence supports that the ventilation upgrade was installed in association with a CleanBC Energy Savings Program rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade, rather than claimed on its own.

Use these named fields and facts as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- vent_associated_upgrade_evidence: evidence that ventilation is installed with heat pump, heat pump water heater, insulation, or windows/doors work.
- invoice_upgrade_type_evidence: broad invoice upgrade-type evidence, especially when it shows both ventilation and an eligible associated upgrade on the same invoice.
- vent_system_type: ventilation system type, only as supporting context that the ventilation portion is identifiable.
- vent_line_amount and upgrade_specific_rebate_line_amount: visible ventilation cost/rebate context, only as supporting invoice-scope evidence.

Set rule_result="pass" when the named evidence clearly connects the ventilation work to an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
Set rule_result="warn" when ventilation work is visible and the association with an eligible upgrade is missing, incomplete, or likely requires application/DB context, but the named evidence does not clearly show ventilation being claimed on its own.
Set rule_result="fail" when the named evidence clearly shows the ventilation upgrade is being claimed on its own without an associated eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade, or clearly connects the ventilation work only to an ineligible/unrelated project.
In calculation, state vent_associated_upgrade_evidence, invoice_upgrade_type_evidence, vent_system_type, any visible ventilation rebate/cost context, and classify the association as associated_eligible_upgrade, standalone_ventilation, unrelated_ineligible_project, or unclear.
In evidence_text, cite the exact named-field wording that supports the decision.', true, 'be installed in association with a CleanBC Energy Savings Program rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for ventilation upgrades on their own.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_multiple_ventilation_rebate_or_fan_count_review', 'Check whether the visible invoice evidence suggests more than one ventilation rebate, more than one eligible ventilation system, or multiple bathroom fans/HRV/ERV units that admin should review against the one-ventilation-rebate-per-home limit.

Use named fields and visible invoice context as the main evidence:
- vent_system_type: HRV, ERV, bathroom fan, exhaust fan, or similar ventilation subtype wording.
- vent_make_model, vent_manufacturer, vent_model_number, vent_energy_star_reference, and vent_nrcan_or_product_list_reference: product identity evidence that may show one or multiple ventilation products.
- vent_line_amount and upgrade_specific_rebate_line_amount: visible ventilation cost/rebate context.
- invoice_upgrade_type_evidence and vent_associated_upgrade_evidence: surrounding invoice wording that may show a ventilation scope bundled with another eligible upgrade.
- DI line items, quantities, descriptions, and totals when available in the context window.

Set rule_result="pass" when the invoice clearly shows a single ventilation rebate and a single eligible ventilation system/product, or when no visible quantity/model/rebate wording suggests multiple ventilation rebates or multiple eligible ventilation systems.
Set rule_result="warn" when the invoice shows possible multiple bathroom fans, multiple HRV/ERV units, quantity greater than 1, repeated ventilation product/model lines, plural wording such as "fans" or "ventilators", or multiple ventilation line items, but it is not clear that more than one ventilation rebate is being claimed.
Set rule_result="fail" only when the invoice clearly claims more than one separate ventilation rebate for the home, or explicitly claims separate rebates for multiple ventilation systems/fans.
Do not fail merely because one line item uses plural wording if the invoice shows only one rebate amount or the count is ambiguous.
In calculation, state the visible count/quantity/model/rebate evidence used and classify the review as single_visible_system, possible_multiple_systems_review, or multiple_rebates_claimed.
In evidence_text, cite the exact visible line item, quantity, model, or rebate wording that supports the decision.', true, 'Maximum one ventilation rebate per home.', true, TIMESTAMP '2026-07-09 00:00:00', NOW()),
  ('warranty_or_home_insurance_costs_not_claimed', 'Check whether claimed upgrade costs exclude costs covered by warranty or home insurance.

Use these named fields as the main evidence for this rule. When other supplied context is helpful, include the exact field or document name in calculation and evidence_text:
- warranty_or_home_insurance_cost_evidence: visible warranty, home-insurance, insurance-claim, no-charge replacement, covered repair, credit, deductible, or claim-paid cost evidence.

Set rule_result="pass" when warranty_or_home_insurance_cost_evidence is null, or when it shows only ordinary post-installation warranty terms such as manufacturer warranty, parts warranty, compressor warranty, labour warranty period, installation workmanship warranty, or warranty coverage available after installation, with no evidence that the claimed upgrade cost was paid, credited, covered, or reduced by warranty or home insurance.
Set rule_result="warn" when warranty_or_home_insurance_cost_evidence mentions warranty, home insurance, insurance, claim, deductible, no-charge, covered repair, covered replacement, credit, or similar wording but it is unclear whether any claimed upgrade cost was paid, credited, covered, or reduced.
Set rule_result="fail" when warranty_or_home_insurance_cost_evidence clearly shows claimed upgrade costs are covered by warranty or home insurance, paid by warranty or insurance, credited under warranty or insurance, supplied as a no-charge warranty/insurance replacement, reduced by a warranty/insurance discount or deductible arrangement, or otherwise not actually paid as an eligible upgrade cost.
Do not fail solely because ordinary post-installation warranty coverage language is visible.
In calculation, state warranty_or_home_insurance_cost_evidence and classify the evidence as none_visible, standard_post_installation_terms, possible_cost_coverage_review, or covered_cost_claimed.
In reason_and_likely_causes, distinguish standard warranty/insurance terms from warranty-paid, insurance-paid, credited, no-charge, or otherwise covered invoice costs.', true, 'Upgrade costs covered by warranty or home insurance are not eligible for rebates.', true, TIMESTAMP '2026-05-26 00:00:00', NOW())
),
contractor_display_name_metadata (
  genai_rule_key,
  contractor_display_name
) AS (
  VALUES
  ('ashp_electric_existing_heat_context_present', 'Existing electric heating system'),
  ('ashp_electric_backup_heat_electric_present', 'Electric backup heating'),
  ('ashp_gas_propane_existing_heat_context_present', 'Existing natural gas or propane heating system'),
  ('ashp_fossil_fuel_removal_supporting_document_attached', 'Proof of fossil-fuel heating system removal'),
  ('ashp_oil_consumption_baseline_proof_present', 'Proof of minimum oil consumption'),
  ('ashp_oil_existing_heat_context_present', 'Existing oil heating system'),
  ('ashp_wood_backup_heat_not_fossil_present', 'Backup heating is not fossil fuel'),
  ('ashp_wood_existing_heat_context_present', 'Existing wood heating system'),
  ('ashp_wood_removal_or_wett_supporting_document_attached', 'Proof of wood system removal or WETT inspection'),
  ('contractor_identity_matches_record', 'Contractor information matches'),
  ('dfhp_fossil_fuel_removal_or_modification_supporting_document_attached', 'Proof of fossil-fuel system removal or modification'),
  ('dfhp_heat_load_calc_supporting_document_acceptable', 'Acceptable heat load calculation'),
  ('dfhp_existing_heat_context_present', 'Existing heating system for a dual-fuel heat pump'),
  ('dfhp_switchover_setpoint_specific', 'Dual-fuel heat pump switchover temperature'),
  ('esu_contractor_utility_billed_work_on_one_invoice', 'Electrical and utility work billed correctly'),
  ('esu_eligible_expense_lines_present', 'Eligible electrical service upgrade costs'),
  ('esu_heat_pump_conversion_context_present', 'Eligible fossil-to-heat-pump conversion'),
  ('esu_not_panel_only_or_connection_only', 'Complete electrical service upgrade'),
  ('esu_service_size_present', 'Electrical service size'),
  ('esu_utility_upgrade_supporting_document_attached', 'Utility electrical upgrade documents'),
  ('homeowner_identity_matches_eligibility_record', 'Invoice homeowner matches participant'),
  ('hp_fossil_backup_not_fossil_primary', 'Fossil-fuel fireplace is secondary only'),
  ('hp_no_existing_or_secondary_heat_pump_flag', 'No existing heat pump at the home'),
  ('hpwh_fossil_removal_supporting_document_attached', 'Proof of gas water heater removal'),
  ('hpwh_no_existing_or_secondary_hpwh_flag', 'No existing heat pump water heater'),
  ('hpwh_primary_replacement_context_present', 'Primary water heater replacement'),
  ('hs_associated_upgrade_present', 'Health and safety work associated with an eligible upgrade'),
  ('hs_before_after_photos_attached', 'Health and safety before and after photos'),
  ('hs_issue_type_present', 'Eligible health and safety issue'),
  ('hs_pre_confirmation_evidence_present', 'Health and safety pre-approval'),
  ('hydronic_conversion_context_present', 'Existing heating system for hydronic heat pump conversion'),
  ('hydronic_fossil_fuel_removal_supporting_document_attached', 'Proof of fossil-fuel system removal for a hydronic heat pump'),
  ('hydronic_wood_removal_or_wett_supporting_document_attached', 'Proof of wood system removal or WETT inspection for a hydronic heat pump'),
  ('overall_invoice_arithmetic_consistent', 'Invoice totals and rebate arithmetic'),
  ('overall_rebate_not_over_invoice_total', 'Rebate does not exceed the invoice total'),
  ('overall_rebate_not_over_paid_cost_of_upgrade', 'Rebate does not exceed the paid upgrade cost'),
  ('rebate_line_evidence_present', 'CleanBC rebate shown on the invoice'),
  ('vent_associated_upgrade_present', 'Ventilation installed with an eligible upgrade'),
  ('vent_multiple_ventilation_rebate_or_fan_count_review', 'One ventilation rebate per home'),
  ('warranty_or_home_insurance_costs_not_claimed', 'Costs are not covered by warranty or home insurance')
),
source_quote_metadata (
  genai_rule_key,
  section_name,
  contractor_action
) AS (
  VALUES
  ('ashp_electric_backup_heat_electric_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC)$$, $$Check that the invoice or supporting documents show the backup space heating system is electric. Upload clearer evidence if needed.$$),
  ('ashp_electric_existing_heat_context_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC)$$, $$Check that the invoice shows the hard-wired electric heating system being replaced by the heat pump. Upload a corrected invoice or clearer evidence if needed.$$),
  ('ashp_fossil_fuel_removal_supporting_document_attached', $$AIR SOURCE HEAT PUMP fossil-fuel conversion$$, $$Upload one accepted removal proof document and make sure it clearly shows the required date, address, and work-completed details.$$),
  ('ashp_gas_propane_existing_heat_context_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM NATURAL GAS OR PROPANE)$$, $$Check that the invoice shows the natural gas or propane primary heating system being replaced by the heat pump. Upload a corrected invoice or clearer evidence if needed.$$),
  ('ashp_oil_consumption_baseline_proof_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM OIL)$$, $$Upload oil-consumption proof from the relevant 12-month period and make sure the visible quantity supports the 500 L annual baseline.$$),
  ('ashp_oil_existing_heat_context_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM OIL)$$, $$Check that the invoice shows the oil primary heating system being replaced by the heat pump. Upload a corrected invoice or clearer evidence if needed.$$),
  ('ashp_wood_backup_heat_not_fossil_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM WOOD)$$, $$Check that any visible backup heating evidence is wood or electric, not a fossil-fuel backup system. Upload clearer evidence if needed.$$),
  ('ashp_wood_existing_heat_context_present', $$AIR SOURCE HEAT PUMP (CONVERT FROM WOOD)$$, $$Check that the invoice shows the wood or solid-fuel primary heating system being replaced by the heat pump. Upload a corrected invoice or clearer evidence if needed.$$),
  ('ashp_wood_removal_or_wett_supporting_document_attached', $$AIR SOURCE HEAT PUMP (CONVERT FROM WOOD)$$, $$Upload the required before/after photo evidence if the wood system was removed, or the WETT inspection report if it was retained.$$),
  ('contractor_identity_matches_record', $$General Eligibility Requirements$$, $$Check that the invoice contractor name matches the registered contractor account used for this submission. Upload a corrected invoice or contact program staff for assistance if needed.$$),
  ('dfhp_existing_heat_context_present', $$DUAL FUEL DUCTED HEAT PUMP$$, $$Check that the invoice shows tanked propane or PNG natural gas as the prior primary heating system. Upload a corrected invoice or clearer evidence if needed.$$),
  ('dfhp_fossil_fuel_removal_or_modification_supporting_document_attached', $$DUAL FUEL DUCTED HEAT PUMP$$, $$Upload one accepted removal or modification proof document and make sure it clearly shows the required date, address, and work-completed details.$$),
  ('dfhp_heat_load_calc_supporting_document_acceptable', $$DUAL FUEL DUCTED HEAT PUMP$$, $$Upload the required heat load calculation and make sure it identifies the sizing basis without relying on rule-of-thumb sizing.$$),
  ('dfhp_switchover_setpoint_specific', $$DUAL FUEL DUCTED HEAT PUMP$$, $$Check that the invoice or supporting documents show the required switchover control settings for the applicable region. Upload clearer controls evidence if needed.$$),
  ('esu_contractor_utility_billed_work_on_one_invoice', $$ELECTRICAL SERVICE UPGRADE$$, $$Check that the invoice or supporting documents show the BC Hydro/FortisBC line upgrade path and that contractor-billed utility work appears on one invoice when applicable.$$),
  ('esu_eligible_expense_lines_present', $$ELECTRICAL SERVICE UPGRADE$$, $$Check that the claimed electrical service upgrade charges are from the eligible expense categories listed here. Upload a corrected invoice if needed.$$),
  ('esu_heat_pump_conversion_context_present', $$ELECTRICAL SERVICE UPGRADE$$, $$Provide evidence showing that the heat pump replaced an oil, propane, or natural-gas primary space- or water-heating system. This may be an updated invoice, work order, removal or decommissioning record, or another supporting document identifying the previous system.$$),
  ('esu_not_panel_only_or_connection_only', $$ELECTRICAL SERVICE UPGRADE$$, $$Check that the invoice shows a utility service/new-wire upgrade, not only a panel/sub-panel upgrade or heat-pump panel connection. Upload a corrected invoice if needed.$$),
  ('esu_service_size_present', $$ELECTRICAL SERVICE UPGRADE$$, $$Check that the invoice or utility evidence shows the new service size is 100, 200, or 400 amps. Upload clearer evidence if needed.$$),
  ('esu_utility_upgrade_supporting_document_attached', $$ELECTRICAL SERVICE UPGRADE$$, $$Provide a utility bill or a corrected or clearer electrical-service-upgrade invoice showing the BC Hydro or FortisBC new-wire/service upgrade.$$),
  ('homeowner_identity_matches_eligibility_record', $$General Eligibility Requirements$$, $$Check that the homeowner or customer name on the invoice matches the participant registered for this application. Upload a corrected invoice or contact program staff if the invoice belongs to a different person.$$),
  ('hp_fossil_backup_not_fossil_primary', $$AIR SOURCE HEAT PUMP fossil-fuel conversion$$, $$Check that backup heating is electric or wood, and that any retained gas or propane fireplace is only secondary. Upload clearer evidence if needed.$$),
  ('hp_no_existing_or_secondary_heat_pump_flag', $$General Heat Pump Requirements$$, $$Check that the invoice does not describe replacing, adding to, or adding a secondary heat pump to a home with an existing heat pump. Upload a corrected invoice if needed.$$),
  ('hpwh_fossil_removal_supporting_document_attached', $$HEAT PUMP WATER HEATER$$, $$Upload one accepted gas water-heater removal proof document and make sure it clearly shows the required date, address, and work-completed details when fossil-fuel water heating was replaced.$$),
  ('hpwh_no_existing_or_secondary_hpwh_flag', $$HEAT PUMP WATER HEATER$$, $$Check that the invoice does not describe replacing or adding a secondary heat pump water heater where one already exists. Upload a corrected invoice if needed.$$),
  ('hpwh_primary_replacement_context_present', $$HEAT PUMP WATER HEATER$$, $$Check that the invoice shows the home primary water heater was replaced. Upload clearer evidence if needed.$$),
  ('hs_associated_upgrade_present', $$HEALTH AND SAFETY REMEDIATION$$, $$Check that the invoice or supporting documents connect the remediation to an eligible upgrade and not a standalone claim. Upload clearer evidence if needed.$$),
  ('hs_before_after_photos_attached', $$HEALTH AND SAFETY REMEDIATION$$, $$Upload before and after photos showing the health and safety issue that was remediated.$$),
  ('hs_issue_type_present', $$HEALTH AND SAFETY REMEDIATION$$, $$Check that the remediation scope is one of the eligible issue types. Upload a corrected invoice or clearer evidence if needed.$$),
  ('hs_pre_confirmation_evidence_present', $$HEALTH AND SAFETY REMEDIATION$$, $$Contact program staff for assistance if the remediation eligibility was reviewed before work began but the evidence is not being recognized.$$),
  ('hydronic_conversion_context_present', $$AIR-TO-WATER AND COMBINED HEAT PUMP$$, $$Check that the invoice shows the prior primary heating system was fossil fuel, electricity, or wood. Upload a corrected invoice or clearer evidence if needed.$$),
  ('hydronic_fossil_fuel_removal_supporting_document_attached', $$AIR-TO-WATER AND COMBINED HEAT PUMP$$, $$Upload one accepted fossil-fuel removal proof document and make sure it clearly shows the required date, address, and work-completed details when fossil-fuel heating was replaced.$$),
  ('hydronic_wood_removal_or_wett_supporting_document_attached', $$AIR-TO-WATER AND COMBINED HEAT PUMP$$, $$Upload the required before/after photo evidence if the wood system was removed, or the WETT inspection report if it was retained.$$),
  ('overall_invoice_arithmetic_consistent', $$General Eligibility Requirements$$, $$Check that the invoice shows the CleanBC rebate, deducts it from the participant amount owed, and reconciles clearly. Upload a corrected invoice if needed.$$),
  ('overall_rebate_not_over_invoice_total', $$General Eligibility Requirements$$, $$Check that the overall rebate does not exceed the invoice cost. Upload a corrected invoice or contact program staff for assistance if needed.$$),
  ('overall_rebate_not_over_paid_cost_of_upgrade', $$General Eligibility Requirements$$, $$Check that the overall rebate does not exceed the paid cost of the claimed upgrade. Upload a corrected invoice or contact program staff for assistance if needed.$$),
  ('rebate_line_evidence_present', $$General Eligibility Requirements$$, $$Check that the invoice visibly itemizes the CleanBC rebate and makes the rebate amount understandable. Upload a corrected invoice if needed.$$),
  ('vent_associated_upgrade_present', $$VENTILATION$$, $$Check that the invoice or supporting documents show the ventilation upgrade was completed with an eligible associated upgrade. Upload clearer evidence if needed.$$),
  ('vent_multiple_ventilation_rebate_or_fan_count_review', $$VENTILATION$$, $$Check that the invoice is claiming no more than one ventilation rebate for the home. Upload a corrected invoice if needed.$$),
  ('warranty_or_home_insurance_costs_not_claimed', $$General Eligibility Requirements$$, $$Check that the claimed upgrade costs are not covered by warranty or home insurance. Upload a corrected invoice or contact program staff for assistance if needed.$$)
)
INSERT INTO claims.genai_rules (
  genai_rule_key,
  contractor_display_name,
  prompt_text,
  enabled,
  source_quote,
  contractor_action,
  contractor_visibility,
  contractor_blocking_policy,
  admin_workflow_policy,
  created_at,
  updated_at
)
SELECT
  genai_rule_key,
  contractor_display_name_metadata.contractor_display_name,
  prompt_text,
  enabled,
  CASE
    WHEN source_quote_metadata.section_name IS NULL THEN source_quote
    ELSE '**From the ' || source_quote_metadata.section_name || ' section of the PDF:**' || E'\n\n' ||
      regexp_replace(replace(replace(source_quote, E'\r\n', E'\n'), E'\r', E'\n'), '(^|\n)([^\n]+)', '\1_\2_', 'g')
  END AS source_quote,
  source_quote_metadata.contractor_action,
  CASE
    WHEN legacy_contractor_visible_flag THEN 'fail_only'
    ELSE 'hidden'
  END AS contractor_visibility,
  'non_blocking' AS contractor_blocking_policy,
  'warn_and_fail' AS admin_workflow_policy,
  created_at,
  updated_at
FROM genai_rules_seed
JOIN contractor_display_name_metadata
  USING (genai_rule_key)
LEFT JOIN source_quote_metadata
  USING (genai_rule_key)
ON CONFLICT (genai_rule_key) DO UPDATE SET
  contractor_display_name = EXCLUDED.contractor_display_name,
  prompt_text = EXCLUDED.prompt_text,
  source_quote = EXCLUDED.source_quote,
  contractor_action = EXCLUDED.contractor_action,
  contractor_visibility = EXCLUDED.contractor_visibility,
  contractor_blocking_policy = EXCLUDED.contractor_blocking_policy,
  admin_workflow_policy = EXCLUDED.admin_workflow_policy,
  updated_at = NOW();

WITH genai_rule_upgrade_types_seed (
  upgrade_type_key,
  genai_rule_key
) AS (
  VALUES
  ('air_source_heat_pump_electric', 'ashp_electric_backup_heat_electric_present'),
  ('air_source_heat_pump_electric', 'ashp_electric_existing_heat_context_present'),
  ('air_source_heat_pump_electric', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('air_source_heat_pump_gas_propane', 'ashp_fossil_fuel_removal_supporting_document_attached'),
  ('air_source_heat_pump_gas_propane', 'ashp_gas_propane_existing_heat_context_present'),
  ('air_source_heat_pump_gas_propane', 'hp_fossil_backup_not_fossil_primary'),
  ('air_source_heat_pump_gas_propane', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('air_source_heat_pump_oil', 'ashp_fossil_fuel_removal_supporting_document_attached'),
  ('air_source_heat_pump_oil', 'ashp_oil_consumption_baseline_proof_present'),
  ('air_source_heat_pump_oil', 'ashp_oil_existing_heat_context_present'),
  ('air_source_heat_pump_oil', 'hp_fossil_backup_not_fossil_primary'),
  ('air_source_heat_pump_oil', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('air_source_heat_pump_wood', 'ashp_wood_backup_heat_not_fossil_present'),
  ('air_source_heat_pump_wood', 'ashp_wood_existing_heat_context_present'),
  ('air_source_heat_pump_wood', 'ashp_wood_removal_or_wett_supporting_document_attached'),
  ('air_source_heat_pump_wood', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('air_to_water_heat_pump', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('air_to_water_heat_pump', 'hydronic_conversion_context_present'),
  ('air_to_water_heat_pump', 'hydronic_fossil_fuel_removal_supporting_document_attached'),
  ('air_to_water_heat_pump', 'hydronic_wood_removal_or_wett_supporting_document_attached'),
  ('combined_space_water_heat_pump', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('combined_space_water_heat_pump', 'hydronic_conversion_context_present'),
  ('combined_space_water_heat_pump', 'hydronic_fossil_fuel_removal_supporting_document_attached'),
  ('combined_space_water_heat_pump', 'hydronic_wood_removal_or_wett_supporting_document_attached'),
  ('common', 'contractor_identity_matches_record'),
  ('common', 'homeowner_identity_matches_eligibility_record'),
  ('common', 'overall_invoice_arithmetic_consistent'),
  ('common', 'overall_rebate_not_over_invoice_total'),
  ('common', 'overall_rebate_not_over_paid_cost_of_upgrade'),
  ('common', 'rebate_line_evidence_present'),
  ('common', 'warranty_or_home_insurance_costs_not_claimed'),
  ('dual_fuel_ducted_heat_pump', 'dfhp_existing_heat_context_present'),
  ('dual_fuel_ducted_heat_pump', 'dfhp_fossil_fuel_removal_or_modification_supporting_document_attached'),
  ('dual_fuel_ducted_heat_pump', 'dfhp_heat_load_calc_supporting_document_acceptable'),
  ('dual_fuel_ducted_heat_pump', 'dfhp_switchover_setpoint_specific'),
  ('dual_fuel_ducted_heat_pump', 'hp_no_existing_or_secondary_heat_pump_flag'),
  ('electrical_service_upgrade', 'esu_contractor_utility_billed_work_on_one_invoice'),
  ('electrical_service_upgrade', 'esu_eligible_expense_lines_present'),
  ('electrical_service_upgrade', 'esu_heat_pump_conversion_context_present'),
  ('electrical_service_upgrade', 'esu_not_panel_only_or_connection_only'),
  ('electrical_service_upgrade', 'esu_service_size_present'),
  ('electrical_service_upgrade', 'esu_utility_upgrade_supporting_document_attached'),
  ('health_and_safety_remediation', 'hs_associated_upgrade_present'),
  ('health_and_safety_remediation', 'hs_before_after_photos_attached'),
  ('health_and_safety_remediation', 'hs_issue_type_present'),
  ('health_and_safety_remediation', 'hs_pre_confirmation_evidence_present'),
  ('heat_pump_water_heater', 'hpwh_fossil_removal_supporting_document_attached'),
  ('heat_pump_water_heater', 'hpwh_no_existing_or_secondary_hpwh_flag'),
  ('heat_pump_water_heater', 'hpwh_primary_replacement_context_present'),
  ('ventilation', 'vent_associated_upgrade_present'),
  ('ventilation', 'vent_multiple_ventilation_rebate_or_fan_count_review')
)
INSERT INTO claims.genai_rule_upgrade_types (
  genai_rule_id,
  invoice_upgrade_type_id,
  created_at,
  updated_at
)
SELECT
  gr.id,
  iut.id,
  NOW(),
  NOW()
FROM genai_rule_upgrade_types_seed seed
JOIN claims.genai_rules gr
  ON gr.genai_rule_key = seed.genai_rule_key
JOIN claims.invoice_upgrade_types iut
  ON iut.upgrade_type_key = seed.upgrade_type_key
ON CONFLICT (genai_rule_id, invoice_upgrade_type_id) DO UPDATE SET
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
  ('contractor_gst_number', 'Locate contractor GST number within the invoice.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_line_amount', 'Locate combined space/water heat pump line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('cshp_product_list_reference', 'Locate air-to-water/combined heat pump qualifying product list references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('customer_payment_or_deposit', 'Locate visible evidence of a payment or deposit made by the participant or customer.

Return the payment or deposit amount supported by the invoice. Preserve the exact visible label and any visible payment date in evidence_text so downstream rules can distinguish a completed payment from a deposit.

Do not assume that every paid amount is a deposit, and do not infer whether the payment occurred before or after the rebate was applied unless the invoice labels and arithmetic make that clear.

When multiple payments or deposits are visible, return their total only when the invoice clearly presents them as cumulative payments against this invoice; otherwise use value=null and explain the ambiguity in evidence_text.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_equipment_type', 'Locate dual fuel ducted heat pump evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_existing_heat_evidence', 'Locate visible evidence that the home was primarily heated by tanked propane, PNG natural gas, PNG propane, generic natural gas, generic propane, or a fireplace. Include wording that supports or contradicts the prior primary heating context, whether the fuel was tanked/PNG/generic, and whether the fossil system is being retained or integrated with the new dual-fuel ducted heat pump. Use value=null when prior primary heating context is not visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_fossil_modification_evidence', 'Locate fossil fuel removal/modification evidence, permit, inspection, capping, piping, vent, or appliance changes.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_heat_load_calc_reference', 'Locate program-approved heat load calculation, CSA-F280, Manual J, or sizing evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_line_amount', 'Locate the visible eligible charge for the dual-fuel ducted heat pump upgrade itself before CleanBC rebates, credits, deposits, or prior payments are deducted. Include only the dual-fuel ducted heat pump equipment, materials, and installation charges that belong to this upgrade. Exclude separately itemized northern top-up amounts, CleanBC rebate lines, customer deposits/payments, financing, taxes-only totals, unrelated upgrades, and fossil-fuel removal/modification work unless the invoice explicitly bundles that work into the dual-fuel ducted heat pump upgrade cost. Use value=null when the eligible DFHP upgrade charge is not visible or cannot be separated from unrelated work. In evidence_text, cite the exact line item, subtotal, or totals wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_make_model', 'Locate heat pump and furnace make/model numbers.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_source_fuel_path', 'Locate whether the visible source/fuel path appears to be PNG natural gas, PNG propane, tank propane, generic natural gas, generic propane, or unclear.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('dfhp_switchover_setpoint_evidence', 'Locate thermostat, outdoor temperature switchover, equipment control board, <=5 C, <=2 C, or similar controls evidence.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('eligibility_code', 'Locate the eligibility code if visible in invoice text. Expected prefixes are ESP1, ESP2, or ESP3. If the invoice does not visibly show one, do not invent it from the supplied database values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_associated_heat_pump_or_hpwh_reference', 'Locate visible evidence connecting the electrical service upgrade to an associated heat pump or heat pump water heater installation. Include invoice/work references such as heat pump, air-source heat pump, air-to-water heat pump, dual-fuel heat pump, heat pump water heater, HPWH, model/equipment references, installation wording, or same-invoice work descriptions. Use value=null when the invoice does not visibly connect the electrical service upgrade to a heat pump or heat pump water heater. In evidence_text, cite the exact wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_contractor_utility_management_evidence', 'Locate evidence that contractor/electrician managed the line upgrade with the electrical utility.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_eligible_expense_lines', 'Locate service upgrade expense lines, such as connection fees, panel or sub-panel upgrade, service mast, conduit, meter base, weather head, or labour.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_fossil_to_heat_pump_context', 'Locate visible evidence that the electrical service upgrade is associated with conversion from a fossil-fuel primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program. Fossil-fuel source evidence includes oil, propane, natural gas, gas furnace, gas boiler, oil furnace, oil boiler, propane furnace, propane boiler, gas water heater, propane water heater, oil water heater, or similar wording. Include wording that supports whether the fossil system was primary space heating, primary water heating, or both. For space-heating evidence, include any wording about the primary system heating at least 50% of the home for the full heating season to 21 degrees Celsius when visible. Use value=null when fossil-fuel-to-heat-pump conversion context is not visible. In evidence_text, cite the exact wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_heat_pump_installation_date_reference', 'Locate the best-supported installation or completion date for the associated heat pump or heat pump water heater using the primary invoice and all supporting-document OCR, located fields, and visual findings. Prefer explicit installed, completed, commissioned, or final-inspection evidence. A final heat-pump installation invoice date may be used as a proxy when no explicit completion date is available. Do not treat a quote, scheduled date, order, deposit, shipment, or manufacture date as installation. If credible dates conflict or no credible date is visible, return null. In evidence_text, identify the source document and page, cite the relevant wording, and state whether the date is explicit or a proxy.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_ineligible_panel_only_evidence', 'Locate evidence that the invoice is only a panel/sub-panel or heat pump connection without utility service upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_line_amount', 'Locate the visible eligible charge for the electrical service upgrade itself before CleanBC rebates, credits, deposits, or prior payments are deducted. Include only eligible electrical service upgrade charges such as utility connection fees, electrical panel or sub-panel upgrade tied to the service upgrade, service mast alteration or replacement, conduit replacement, meter base alteration or replacement, weather head alteration or replacement, and labour for the service upgrade. Exclude CleanBC rebate lines, customer deposits/payments, financing, taxes-only totals, unrelated electrical work, heat-pump equipment, heat-pump connection-only work, EV charger work, generator work, and panel-only work with no utility service/new-wire upgrade context. Use value=null when the eligible ESU upgrade charge is not visible or cannot be separated from unrelated work. In evidence_text, cite the exact line item, subtotal, or totals wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_new_service_size', 'Locate new service size if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_permit_or_ahj_reference', 'Locate permit, inspection, Technical Safety BC, Authority Having Jurisdiction, or by-law compliance references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_previous_service_size', 'Locate previous service size if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_service_size', 'Locate upgraded electrical service size, such as 100 amp, 200 amp, or 400 amp service.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_utility_billing_reference', 'Locate utility billing evidence for the line/service upgrade.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('esu_utility_reference', 'Locate BC Hydro, FortisBC, utility connection, line upgrade, or utility bill/invoice references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hp_backup_heat_evidence', 'Locate backup heat evidence and note if it appears electric, wood, fossil fuel, fireplace-only, secondary, primary, or unclear. If a natural-gas or propane fireplace is visible, state whether the wording supports that it is secondary rather than the backup or primary heating system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
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
  ('hp_ahri_reference', 'Locate the visible AHRI certified reference number for the heat pump system on the invoice. Return only the AHRI reference identifier itself, typically a numeric AHRI certified reference number. Do not return model numbers, serial numbers, NEEA references, NRCan/OHPA list wording, ENERGY STAR wording, or generic product-list wording unless the same visible text explicitly labels the value as an AHRI reference. Use value=null when no invoice-visible AHRI reference is shown. In evidence_text, cite the exact label or wording that identifies the value as AHRI.', true, TIMESTAMP '2026-07-10 00:00:00', NOW()),
  ('ashp_upgrade_line_amount', 'Locate the visible line-item amount or subtotal for the claimed air-source heat pump upgrade.

Return the amount for the air-source heat pump equipment and installation scope tied to this upgrade type. Include outdoor unit, indoor head units, air handler, central ducted heat-pump components, and installation labour when they are presented as part of the same air-source heat pump upgrade line or subtotal.

Do not include CleanBC / Better Homes / ESP rebate amounts, customer payments, deposits, taxes-only totals, invoice-wide totals, unrelated upgrades, electrical service upgrades, heat pump water heaters, air-to-water heat pumps, dual-fuel heat pumps, ventilation, insulation, windows/doors, health and safety remediation, warranty/maintenance plans, financing charges, or fossil-fuel removal work unless the invoice clearly includes them in a single labelled air-source heat pump upgrade subtotal.

Use value=null when the air-source heat pump upgrade amount is missing, ambiguous, bundled with unrelated upgrades without a clear subtotal, or cannot be separated from other work.

In evidence_text, cite the exact visible line label, subtotal label, or arithmetic used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
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
  ('hpwh_new_equipment_type', 'Locate heat pump water heater equipment type.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hpwh_secondary_system_flag', 'Locate evidence the invoice is for a secondary/additional water heater rather than replacing the primary system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_associated_upgrade_evidence', 'Locate evidence that remediation enabled heat pump, heat pump water heater, insulation, or windows/doors work.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_confirmation_date_or_reference', 'Locate the date/reference for pre-confirmation that remediation was rebate-eligible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_issue_type', 'Locate health/safety issue type, such as pest, asbestos, structural, mould, vermiculite, or other safety concern.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_line_amount', 'Locate the visible eligible charge for the health and safety remediation work itself before CleanBC rebates, credits, deposits, or prior payments are deducted. Include only remediation work for health and safety issues such as pest, asbestos, structural, mould, vermiculite, or similar safety concerns. Exclude CleanBC rebate lines, customer deposits/payments, financing, taxes-only totals, unrelated heat pump, heat pump water heater, insulation, windows/doors, ventilation, or electrical upgrade work unless the invoice explicitly labels the amount as health and safety remediation. Use value=null when the eligible health and safety remediation charge is not visible or cannot be separated from unrelated work. In evidence_text, cite the exact line item, subtotal, or totals wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_pre_confirmation_reference', 'Locate pre-confirmation or rebate-eligible confirmation references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_registered_contractor_evidence', 'Locate registered/approved contractor evidence if visible.

Health and safety', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_remediation_scope', 'Locate description of remediation work completed.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_resolution_completion_date', 'Locate remediation completion/resolution date if visible.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hs_technical_safety_or_permit_reference', 'Locate Technical Safety BC, permit, lawful authority, manufacturer specification, or by-law compliance references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_conversion_source_fuel_evidence', 'Locate visible evidence of the home''s existing primary heating source before the hydronic heat pump upgrade. Accepted source paths are fossil fuel (oil, propane, or natural gas), electricity, and wood/solid fuel. Include wording that supports whether the system was the primary heating system, whether it could heat at least 50% of the home for the full heating season to 21 degrees Celsius, and whether any fireplace evidence appears to be only a fireplace rather than the primary heating system. Use value=null when the prior primary heating source is not visible. In evidence_text, cite the exact wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_fossil_removal_evidence', 'Locate fossil-fuel removal/decommissioning evidence if fossil fuel is involved.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('hydronic_wood_removal_or_wett_evidence', 'Locate wood-system removal or WETT evidence if wood is involved.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_contractor_address', 'Locate the contractor/vendor business address visibly shown on the invoice if present.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_contractor_name', 'Locate the contractor, vendor, supplier, or business name visibly shown on the invoice. Prefer the invoice header/vendor name over generic text in descriptions.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_homeowner_name', 'Locate the homeowner, customer, bill-to, ship-to, or participant name visibly shown on the invoice. Prefer explicit customer/bill-to/homeowner fields over payment-history names or generic references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('invoice_upgrade_type_evidence', 'Locate text that indicates the broad upgrade type, such as windows, doors, heat pump, insulation, ventilation, electrical service, health/safety, or water heater.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('labour_cost_invoice_total', 'Locate total invoice labour cost if shown separately.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_line_amount', 'Locate the visible overall CleanBC / Better Homes / Energy Savings Program rebate amount for the whole invoice.

Return the single invoice-level total rebate amount when the invoice clearly shows one.
If the invoice does not show a single invoice-level total rebate amount, but does show multiple visible CleanBC / Better Homes / ESP rebate amounts for specific upgrade lines, return the sum of those visible rebate amounts.
Use value=null when neither a single invoice-level total rebate amount nor summable upgrade-specific rebate amounts are visible.
Do not include discounts, taxes, deposits, customer payments, credits, financing amounts, warranty coverage, insurance coverage, or non-program rebates unless the visible label clearly identifies the amount as a CleanBC / Better Homes / ESP rebate.
In evidence_text, cite the exact visible rebate label or totals-line wording. If summing multiple upgrade-specific rebate amounts, show the arithmetic using the visible labels and values.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('overall_rebate_line_description', 'Locate the text description for the overall rebate line, explicit total rebate summary, or visible split upgrade-specific rebate lines that together form the invoice-level rebate.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('paid_cost_of_upgrade_amount', 'Locate the best visible evidence for the paid or payable cost of the claimed upgrade work.

Prefer a visible claimed-upgrade cost, upgrade subtotal, project total for the claimed work, or invoice total when the invoice shows that the total is for the claimed upgrade work. Also capture relevant visible arithmetic involving rebates, customer payments, deposits, credits, warranty coverage, insurance coverage, no-charge replacement, amount due, or customer portion owed when those labels help explain what was paid or payable.

Do not treat a post-rebate customer balance as the whole paid/payable upgrade cost when the invoice arithmetic shows it is only the amount remaining after the CleanBC / Better Homes / ESP rebate was deducted. In that case, return the best cost basis supported by the invoice and explain the post-rebate balance in evidence_text.

Use value=null when the paid/payable cost basis for the claimed upgrade is missing, bundled with unrelated work, or too ambiguous to identify confidently.
In evidence_text, cite the exact visible labels and arithmetic used, and note when a visible amount is a post-rebate balance rather than the cost basis.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('warranty_or_home_insurance_cost_evidence', 'Locate visible evidence that any claimed upgrade cost may be covered, paid, credited, reduced, or replaced at no charge by warranty or home insurance. Include wording such as warranty claim, warranty credit, covered by warranty, no-charge warranty replacement, insurance claim, home insurance, insurer paid, insurance credit, deductible, covered repair, covered replacement, or similar cost-coverage wording. Use value=null when the invoice shows no warranty or insurance wording, or when it shows only ordinary post-installation warranty terms such as manufacturer warranty, parts warranty, compressor warranty, labour warranty period, installation workmanship warranty, or warranty coverage available after installation with no cost coverage or credit. In evidence_text, cite the exact visible wording and explain whether it appears to be standard terms or possible cost coverage.', true, TIMESTAMP '2026-07-09 00:00:00', NOW()),
  ('upgrade_specific_rebate_line_amount', 'Locate the CleanBC/Better Homes/ESP rebate amount for this specific upgrade only.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_associated_upgrade_evidence', 'Locate visible evidence that the ventilation work was installed in association with a CleanBC Energy Savings Program rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Include same-invoice line items, headings, descriptions, bundled scope wording, or nearby upgrade references that connect HRV, ERV, bathroom fan, exhaust fan, or ventilation work to heat pump, HPWH, insulation, window, or door work. Use value=null when the invoice only shows ventilation work or the associated eligible upgrade is not visible. In evidence_text, cite the exact line item, heading, or surrounding wording used.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_contractor_license_evidence', 'Locate HVAC, heat pump, electrical, or approved contractor references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_direct_exterior_ducting_evidence', 'Locate evidence that bathroom fans are ducted directly outdoors.

Ventilation', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_ducting_evidence', 'Locate ducting, exterior exhaust, sealed joints, insulated ducts, or duct hood references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_energy_star_reference', 'Locate ENERGY STAR references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_improved_air_circulation_evidence', 'Locate text indicating improved air circulation.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_line_amount', 'Locate ventilation line-item totals.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_make_model', 'Locate combined HRV/ERV or bathroom fan make/model text for admin readability when present. This is a fallback/display field; prefer vent_manufacturer and vent_model_number for exact product-list matching.', true, TIMESTAMP '2026-07-09 00:00:00', NOW()),
  ('vent_manufacturer', 'Locate the HRV/ERV or bathroom fan manufacturer, brand, or vendor product brand as a standalone value. Do not include the model number unless the invoice only shows a combined phrase.', true, TIMESTAMP '2026-07-09 00:00:00', NOW()),
  ('vent_main_bathroom_evidence', 'Locate main bathroom / bathtub / shower evidence for bathroom fan systems.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_model_number', 'Locate the HRV/ERV or bathroom fan model number exactly as shown on the invoice, label, quote, or product line. Do not include the manufacturer/brand unless the invoice only shows a combined phrase.', true, TIMESTAMP '2026-07-09 00:00:00', NOW()),
  ('vent_nrcan_or_product_list_reference', 'Locate NRCan product list or ENERGY STAR product list references.', true, TIMESTAMP '2026-05-26 00:00:00', NOW()),
  ('vent_system_type', 'Locate ventilation system type, such as HRV, ERV, heat recovery ventilator, energy recovery ventilator, bathroom fan, or fan system.', true, TIMESTAMP '2026-05-26 00:00:00', NOW())
),
genai_located_fields_with_names AS (
  SELECT
    seed.*,
    replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(
      CASE
        WHEN genai_field_key = 'before_after_photo_reference' THEN 'Before/after photo reference'
        WHEN genai_field_key = 'labour_cost_invoice_total' THEN 'Total invoice labour cost'
        WHEN genai_field_key = 'overall_rebate_line_amount' THEN 'Overall rebate amount'
        WHEN genai_field_key = 'paid_cost_of_upgrade_amount' THEN 'Paid cost of upgrade'
        WHEN genai_field_key = 'upgrade_specific_rebate_line_amount' THEN 'Upgrade-specific rebate amount'
        WHEN genai_field_key LIKE 'ashp_%' THEN 'Air-source heat pump ' || lower(replace(substr(genai_field_key, 6), '_', ' '))
        WHEN genai_field_key LIKE 'atw_%' THEN 'Air-to-water heat pump ' || lower(replace(substr(genai_field_key, 5), '_', ' '))
        WHEN genai_field_key LIKE 'cshp_%' THEN 'Combined space and water heat pump ' || lower(replace(substr(genai_field_key, 6), '_', ' '))
        WHEN genai_field_key LIKE 'dfhp_%' THEN 'Dual-fuel ducted heat pump ' || lower(replace(substr(genai_field_key, 6), '_', ' '))
        WHEN genai_field_key LIKE 'esu_%' THEN 'Electrical service upgrade ' || lower(replace(substr(genai_field_key, 5), '_', ' '))
        WHEN genai_field_key LIKE 'hpwh_%' THEN 'Heat pump water heater ' || lower(replace(substr(genai_field_key, 6), '_', ' '))
        WHEN genai_field_key LIKE 'hp_%' THEN 'Heat pump ' || lower(replace(substr(genai_field_key, 4), '_', ' '))
        WHEN genai_field_key LIKE 'hs_%' THEN 'Health and safety ' || lower(replace(substr(genai_field_key, 4), '_', ' '))
        WHEN genai_field_key LIKE 'vent_%' THEN 'Ventilation ' || lower(replace(substr(genai_field_key, 6), '_', ' '))
        ELSE upper(left(replace(genai_field_key, '_', ' '), 1)) || lower(substr(replace(genai_field_key, '_', ' '), 2))
      END,
      'ahri', 'AHRI'),
      'hspf', 'HSPF'),
      'hpwh', 'HPWH'),
      'hvac', 'HVAC'),
      'nrcan', 'NRCan'),
      'seer', 'SEER'),
      'wett', 'WETT'),
      'gst', 'GST'),
      'before after', 'before/after'),
      'heat load calc', 'heat load calculation'),
      'make model', 'make and model'),
      'line amount', 'cost'),
      'ahj', 'AHJ'),
      'energy star', 'ENERGY STAR'),
      ' flag', ' indicator'),
      'top up', 'top-up'),
      'pre confirmation', 'pre-confirmation'),
      'upgrade specific', 'upgrade-specific'
    ) AS contractor_display_name
  FROM genai_located_fields_seed seed
)
INSERT INTO claims.genai_located_fields (
  genai_field_key,
  contractor_display_name,
  prompt_text,
  enabled,
  created_at,
  updated_at
)
SELECT
  genai_field_key,
  contractor_display_name,
  prompt_text,
  enabled,
  created_at,
  updated_at
FROM genai_located_fields_with_names
ON CONFLICT (genai_field_key) DO UPDATE SET
  contractor_display_name = EXCLUDED.contractor_display_name,
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
  ('air_source_heat_pump_electric', 'hp_make_model', 3),
  ('air_source_heat_pump_electric', 'hp_ahri_reference', 4),
  ('air_source_heat_pump_electric', 'hp_new_equipment_type', 1),
  ('air_source_heat_pump_electric', 'hp_product_list_reference', 5),
  ('air_source_heat_pump_electric', 'hp_registered_contractor_or_permit_evidence', 13),
  ('air_source_heat_pump_electric', 'hp_backup_heat_evidence', 14),
  ('air_source_heat_pump_electric', 'upgrade_specific_rebate_line_amount', 10),
  ('air_source_heat_pump_gas_propane', 'hp_backup_heat_evidence', 12),
  ('air_source_heat_pump_gas_propane', 'hp_efficiency_and_capacity', 6),
  ('air_source_heat_pump_gas_propane', 'hp_existing_gas_propane_heat_evidence', 2),
  ('air_source_heat_pump_gas_propane', 'hp_existing_heat_pump_flag', 14),
  ('air_source_heat_pump_gas_propane', 'hp_fossil_combination_boiler_evidence', 15),
  ('air_source_heat_pump_gas_propane', 'hp_fossil_fuel_removal_evidence', 7),
  ('air_source_heat_pump_gas_propane', 'hp_heat_load_calc_reference', 8),
  ('air_source_heat_pump_gas_propane', 'ashp_upgrade_line_amount', 10),
  ('air_source_heat_pump_gas_propane', 'hp_make_model', 3),
  ('air_source_heat_pump_gas_propane', 'hp_ahri_reference', 4),
  ('air_source_heat_pump_gas_propane', 'hp_new_equipment_type', 1),
  ('air_source_heat_pump_gas_propane', 'hp_northern_top_up_evidence', 9),
  ('air_source_heat_pump_gas_propane', 'hp_product_list_reference', 5),
  ('air_source_heat_pump_gas_propane', 'upgrade_specific_rebate_line_amount', 11),
  ('air_source_heat_pump_oil', 'hp_backup_heat_evidence', 13),
  ('air_source_heat_pump_oil', 'hp_efficiency_and_capacity', 6),
  ('air_source_heat_pump_oil', 'hp_existing_heat_pump_flag', 15),
  ('air_source_heat_pump_oil', 'hp_existing_oil_heat_evidence', 2),
  ('air_source_heat_pump_oil', 'hp_fossil_combination_boiler_evidence', 16),
  ('air_source_heat_pump_oil', 'hp_heat_load_calc_reference', 8),
  ('air_source_heat_pump_oil', 'ashp_upgrade_line_amount', 10),
  ('air_source_heat_pump_oil', 'hp_make_model', 3),
  ('air_source_heat_pump_oil', 'hp_ahri_reference', 4),
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
  ('air_source_heat_pump_wood', 'hp_make_model', 3),
  ('air_source_heat_pump_wood', 'hp_ahri_reference', 4),
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
  ('air_to_water_heat_pump', 'hp_make_model', 3),
  ('air_to_water_heat_pump', 'hp_northern_top_up_evidence', 10),
  ('air_to_water_heat_pump', 'hydronic_conversion_source_fuel_evidence', 2),
  ('air_to_water_heat_pump', 'hydronic_fossil_removal_evidence', 5),
  ('air_to_water_heat_pump', 'hydronic_wood_removal_or_wett_evidence', 6),
  ('air_to_water_heat_pump', 'upgrade_specific_rebate_line_amount', 9),
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
  ('common', 'customer_payment_or_deposit', 4),
  ('common', 'eligibility_code', 2),
  ('common', 'invoice_contractor_address', 10),
  ('common', 'invoice_contractor_name', 9),
  ('common', 'invoice_homeowner_name', 11),
  ('common', 'invoice_upgrade_type_evidence', 8),
  ('common', 'labour_cost_invoice_total', 3),
  ('common', 'overall_rebate_line_amount', 5),
  ('common', 'overall_rebate_line_description', 6),
  ('common', 'paid_cost_of_upgrade_amount', 7),
  ('common', 'warranty_or_home_insurance_cost_evidence', 12),
  ('dual_fuel_ducted_heat_pump', 'dfhp_equipment_type', 1),
  ('dual_fuel_ducted_heat_pump', 'dfhp_existing_heat_evidence', 2),
  ('dual_fuel_ducted_heat_pump', 'dfhp_fossil_modification_evidence', 7),
  ('dual_fuel_ducted_heat_pump', 'dfhp_heat_load_calc_reference', 6),
  ('dual_fuel_ducted_heat_pump', 'dfhp_line_amount', 8),
  ('dual_fuel_ducted_heat_pump', 'dfhp_make_model', 3),
  ('dual_fuel_ducted_heat_pump', 'hp_ahri_reference', 4),
  ('dual_fuel_ducted_heat_pump', 'dfhp_source_fuel_path', 10),
  ('dual_fuel_ducted_heat_pump', 'dfhp_switchover_setpoint_evidence', 5),
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
  ('heat_pump_water_heater', 'hpwh_new_equipment_type', 3),
  ('heat_pump_water_heater', 'hpwh_secondary_system_flag', 10),
  ('heat_pump_water_heater', 'upgrade_specific_rebate_line_amount', 14),
  ('ventilation', 'upgrade_specific_rebate_line_amount', 13),
  ('ventilation', 'vent_associated_upgrade_evidence', 2),
  ('ventilation', 'vent_contractor_license_evidence', 11),
  ('ventilation', 'vent_direct_exterior_ducting_evidence', 16),
  ('ventilation', 'vent_ducting_evidence', 10),
  ('ventilation', 'vent_energy_star_reference', 4),
  ('ventilation', 'vent_improved_air_circulation_evidence', 3),
  ('ventilation', 'vent_line_amount', 12),
  ('ventilation', 'vent_make_model', 17),
  ('ventilation', 'vent_manufacturer', 18),
  ('ventilation', 'vent_main_bathroom_evidence', 15),
  ('ventilation', 'vent_model_number', 19),
  ('ventilation', 'vent_nrcan_or_product_list_reference', 5),
  ('ventilation', 'vent_system_type', 1)
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
