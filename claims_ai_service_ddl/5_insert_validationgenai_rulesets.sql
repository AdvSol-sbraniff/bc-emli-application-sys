BEGIN;

-- Depends on 4_insert_invoice_upgrade_types.sql.
WITH config_row (
  id,
  system_record,
  classifier_system_record,
  user_record0,
  admin_advice_intro,
  admin_advice_closing,
  created_at,
  updated_at
) AS (
  VALUES
  (
    '0c2b1d8e-3a63-41ef-97d9-b7c1f7e4a001'::uuid,
    $system$
purpose-statement:
You assist admins with a pre-review of a contractor invoice for the Better Homes BC Energy Savings Program (ESP).

You are not making a final eligibility decision. For v1, you locate evidence and perform the rulechecks using only the OCR/DI JSON and database values provided in the prompt.

Required execution order:
1. Build located_fields[] first.
2. Build rulechecks[] second using located_fields plus the supplied OCR/database facts.
3. Set overall.* last.

Output-json-schema:
{
  "overall": {
    "overall_confidence": 0,
    "all_rulechecks_pass_flag": false,
    "admin_advice": "string (SECTION-LEVEL CONTRACTOR ADVICE FOR THIS RULESET CALL ONLY. Do not write a greeting, intro, sign-off, or closing. Write directly to the contractor in second person. Use a concise bullet list of issues + requested fixes, each bullet referencing rule_number and any relevant field_key. No internal-only notes. Plain language. Do not mention GenAI, OCR, source_engine, confidence scores, or internal implementation details.)"
  },
  "located_fields": [
    {
      "field_key": "string",
      "line_number": 0,
      "value": null,
      "confidence": 0,
      "page": null,
      "polygon": null,
      "evidence_text": null
    }
  ],
  "rulechecks": [
    {
      "rule_number": 0,
      "rule_key": "string",
      "source_requirement_id": "string",
      "evidence_source": "invoice_pdf|supporting_document|database|external_list|admin_review",
      "rule_name": "string",
      "rule_pass_flag": false,
      "confidence": 0,
      "expected_text": null,
      "observed_text": null,
      "calculation": null,
      "evidence_text": null,
      "reason_and_likely_causes": null
    }
  ]
}

Rules:
- Return strict JSON only.
- Do not include markdown outside JSON.
- Use rule_pass_flag=true only when the invoice/database evidence supports the rule.
- Use rule_pass_flag=false when evidence is missing, unclear, insufficient, or appears to fail the rule. Explain the issue in observed_text and/or reason_and_likely_causes.
- For v1, perform rulechecks using only the OCR text/DI JSON and database values provided in the prompt.
- Show simple calculations when they are needed for a rulecheck.
- Do not query external systems, invent database values, or make final eligibility decisions.
- Return exact invoice evidence where possible.
- For every located_fields[] item based on visible invoice evidence, set page and polygon from the matching Document Intelligence field, line, word, or table bounding region when available. Use polygon=null only for inferred/database-derived values or when no reliable DI polygon exists.
- For every non-common upgrade-specific ruleset call, include a located_fields[] item with field_key="upgrade_specific_rebate_line_amount" for the CleanBC / Better Homes / Energy Savings Program rebate amount attributable to that specific upgrade type. Use value=null when the invoice does not clearly allocate a rebate to this upgrade type.
- Do not make final eligibility decisions.
$system$,
    $classifier_system$
purpose-statement:
You classify which Better Homes BC Energy Savings Program invoice upgrade types appear to be present in the supplied invoice OCR/Document Intelligence JSON and locate the customer eligibility code if visible.

You are not making a final eligibility decision. You are only identifying likely upgrade domains and the visible eligibility code so the application can decide which rulesets and database lookups to run next.

Allowed upgrade_type_key values:
- windows_doors
- air_source_heat_pump_electric
- air_source_heat_pump_wood
- air_source_heat_pump_gas_propane
- air_source_heat_pump_oil
- dual_fuel_ducted_heat_pump
- air_to_water_heat_pump
- combined_space_water_heat_pump
- electrical_service_upgrade
- health_and_safety_remediation
- heat_pump_water_heater
- insulation
- ventilation

Output-json-schema:
{
  "eligibility_code": null,
  "detected_upgrade_types": [
    {
      "upgrade_type_key": "windows_doors",
      "confidence": 0,
      "evidence_text": "exact short invoice evidence",
      "classifier_notes": null,
      "why_not_boilerplate": "string"
    }
  ],
  "lineitem_mappings": [
    {
      "lineitem_seqno": 0,
      "upgrade_type_key": "windows_doors",
      "confidence": 0,
      "evidence_text": "exact short invoice evidence",
      "classifier_notes": null
    }
  ],
  "not_detected_upgrade_types": [
    {
      "upgrade_type_key": "air_source_heat_pump_oil",
      "reason": "not enough direct invoice evidence"
    }
  ],
  "classifier_notes": null
}

Rules:
- Return strict JSON only.
- Do not include markdown outside JSON.
- Return only allowed upgrade_type_key values.
- Set eligibility_code to the exact visible invoice token when present. Expected prefixes are ESP1, ESP2, ESP3, or ESPI. Use null when no eligibility code is visible.
- Include an upgrade type only when direct invoice evidence supports completed or invoiced work for that exact upgrade type.
- Do not classify from generic program boilerplate, rebate table summaries, sample-invoice instructions, supporting-document checklists, or text that merely lists possible Better Homes BC upgrades.
- Do not classify broad "heat pump" when a more exact heat-pump key is required. Choose the exact key only when the invoice shows both heat-pump work and enough context for the source fuel/system path or equipment class.
- For air-source heat pump conversion keys, require evidence of the new air-source heat pump plus evidence or strong invoice context for the prior source fuel: electric, wood/solid fuel, natural gas/propane, or oil.
- For dual_fuel_ducted_heat_pump, require dual-fuel/fossil-backup/ducted heat-pump evidence. Do not use this key for a normal full fuel-switch heat pump.
- For air_to_water_heat_pump and combined_space_water_heat_pump, require explicit air-to-water or combined space/water heat-pump evidence. Do not infer these from water-heater or generic heat-pump wording.
- For electrical_service_upgrade, require utility/service-upgrade evidence such as 100/200/400 amp service, service mast, meter base, utility connection, BC Hydro/FortisBC service upgrade, or similar.
- For heat_pump_water_heater, require water-heater evidence. Do not infer it from space-heating heat pump wording.
- For insulation, windows_doors, ventilation, and health_and_safety_remediation, require direct invoice line/work-scope evidence for that work.
- Use lineitem_mappings to map visible invoice line items to an allowed upgrade_type_key when the line item evidence is clear. Use an empty array if line-item mapping is unclear.
- Use confidence from 0 to 100.
- Prefer exact invoice phrases in evidence_text.
- Prefer under-classification over over-classification. If the invoice clearly has two upgrade domains, return two, not every related program possibility.
- If no upgrade type is visible, return an empty detected_upgrade_types array and explain briefly in classifier_notes.
$classifier_system$,
    $user0$
User record 0 (Document Intelligence / OCR context):
The user message includes Azure Document Intelligence raw JSON from the invoice OCR result.
Use documents[0].fields for stable invoice header/totals when the field exists and the value is plausible.
Do not blindly trust first-class fields when confidence is low or arithmetic/content contradicts the field value. Cross-check important money/date/name values against content, pages[*].words[*], and tables[*].
Use content, pages[*].words[*], and tables[*] for upgrade-specific product/service evidence because prebuilt invoice Items[*] may only capture high-level cost rows and may miss detailed rebate evidence.
For located_fields, page and polygon must come from Document Intelligence field/line/word/table boundingRegions or polygon evidence whenever a visible evidence snippet is matched.
If evidence_text is copied from a DI pages[*].lines[*].content value, copy that line's polygon into polygon and that page number into page.
If evidence_text is copied from a DI pages[*].words[*].content value, copy that word's polygon into polygon and that page number into page.
If evidence_text is copied from a DI documents[0].fields.* or tables[*] cell value with boundingRegions, copy the first boundingRegions[0].polygon into polygon and boundingRegions[0].pageNumber into page.
Leave page/polygon null only when the value is inferred, database-derived, or no DI field/line/word/table polygon can be matched.
Do not return polygon null for a located field whose exact evidence_text appears in DI with a polygon.
For repeated invoice line evidence, use the Document Intelligence Items[*] index only when Items[*] truly represents the product/service row being cited. If Items[*] is incomplete or only contains summary rows, use content/pages/tables evidence and set line_number=0.
Use exact short evidence snippets from the invoice text. Do not paraphrase evidence_text when an exact phrase/value is available.

Supported first-class invoice fields commonly seen in Document Intelligence:
- CustomerName, CustomerId, PurchaseOrder
- InvoiceId, InvoiceDate, DueDate
- VendorName, VendorAddress, VendorAddressRecipient, VendorTaxId
- CustomerAddress, CustomerAddressRecipient, CustomerTaxId
- BillingAddress, BillingAddressRecipient
- ShippingAddress, ShippingAddressRecipient
- SubTotal, TotalDiscount, TotalTax, InvoiceTotal, AmountDue, PreviousUnpaidBalance
- RemittanceAddress, RemittanceAddressRecipient
- ServiceAddress, ServiceAddressRecipient, ServiceStartDate, ServiceEndDate
- PaymentTerm

Supported repeated/array fields commonly seen in Document Intelligence:
- Items[*].Description
- Items[*].Quantity
- Items[*].Unit
- Items[*].UnitPrice
- Items[*].Amount
- Items[*].Date
- Items[*].ProductCode
- Items[*].Tax
- Items[*].TaxRate
- TaxDetails[*].Amount
- TaxDetails[*].Rate
- PaymentDetails[*].IBAN, SWIFT, BankAccountNumber, BPayBillerCode, BPayReference

Observed DI caveat from local samples:
On contractor invoices, product details such as model numbers, certification references, quantities, U-factor, rebate notes, and install/material cost rows may appear in content/pages/tables but not in Items[*]. In those cases, prefer the raw text/table evidence over a missing or incomplete Items[*] record.
$user0$,
    $intro$
Thanks for submitting your invoice. We reviewed the information provided and need the following updates before we can continue processing it:
$intro$,
    $closing$
Please upload the corrected invoice or supporting documents, then resubmit when you are ready.
$closing$,
    TIMESTAMP '2026-03-13 21:27:54.352533',
    NOW()
  )
),
common_ruleset_row (
  user_record1
) AS (
  VALUES
  (
    $common$
Common ESP invoice evidence tasks.
These common tasks run as the common invoice evidence ruleset before upgrade-type-specific rulesets.

Common located fields:
1 [field_key: contractor_gst_number] Locate contractor GST number within the invoice.
2 [field_key: eligibility_code] Locate the eligibility code if visible in invoice text. Expected prefixes are ESP1, ESP2, or ESP3. If the invoice does not visibly show one, do not invent it from the supplied database values.
3 [field_key: labour_cost_invoice_total] Locate total invoice labour cost if shown separately.
4 [field_key: customer_deposit] Locate customer deposit or customer payment already made.
5 [field_key: overall_rebate_line_amount] Locate the overall CleanBC / Better Homes / Energy Savings Program rebate amount for the whole invoice. If the invoice has several upgrade-specific rebate lines but no single total rebate line, add them only when the arithmetic is explicitly visible and explain the calculation in evidence_text; otherwise use value=null.
6 [field_key: overall_rebate_line_description] Locate the text description for the overall rebate line or explicit total rebate summary.
7 [field_key: amount_due_after_rebate] Locate amount due / customer owing after rebate and deposits.
8 [field_key: invoice_upgrade_type_evidence] Locate text that indicates the broad upgrade type, such as windows, doors, heat pump, insulation, ventilation, electrical service, health/safety, or water heater.

Common GenAI rulecheck tasks:
For v1, create these rulechecks from the OCR/DI JSON and supplied database values.
For shared database facts such as sessions.submitted_at and users_eligibilitycodes.*, use the supplied database values exactly as provided.
For invoice dates, use the best-supported invoice date visible in the OCR/DI JSON.
Show the date math in calculation when a date rule is evaluated.

rule 001 [rule_key: upgrade_type_evidence_present, source_requirement_id: ESP-2026-COM-000]
Check whether the invoice text provides evidence of the claimed upgrade type.
Set rule_pass_flag=true if the invoice clearly describes the claimed upgrade domain.
Set rule_pass_flag=false if the upgrade type is unclear.

rule 002 [rule_key: rebate_line_evidence_present, source_requirement_id: ESP-2026-COM-015]
Check whether the invoice visibly itemizes a CleanBC / Better Homes / ESP rebate line and appears to deduct it from the customer total.
For v1, GenAI owns this rulecheck. Perform visible invoice arithmetic only when the values are clear; otherwise return rule_pass_flag=false and explain what is missing.

rule 003 [rule_key: warranty_costs_flag, source_requirement_id: ESP-2026-COM-012]
Check whether the invoice appears to include warranty-covered costs or warranty language that should be reviewed by an admin.
Set rule_pass_flag=false only if warranty-covered costs appear to be claimed.
Set rule_pass_flag=true if no warranty-covered costs or warranty language are visible.

rule 004 [rule_key: source_vintage_applies, source_requirement_id: ESP-2026-COM-001]
Check whether the invoice date is on or after 2026-04-01.
Use the best-supported invoice date visible in the OCR/DI JSON.
Set rule_pass_flag=true only when the invoice date is clear and is on or after 2026-04-01.
Set rule_pass_flag=false when the invoice date is missing, ambiguous, or earlier than 2026-04-01.
In calculation, show the date comparison you used.

rule 005 [rule_key: submission_within_six_months, source_requirement_id: ESP-2026-COM-017]
Check whether the contractor submission date is within 6 months of the invoice date.
Use sessions.submitted_at from the supplied database values.
Use the best-supported invoice date visible in the OCR/DI JSON.
Set rule_pass_flag=true only when both dates are clear and sessions.submitted_at is on or before invoice_date + 6 months.
Set rule_pass_flag=false when either date is missing/ambiguous or the comparison fails.
In calculation, show invoice_date + 6 months and compare it to sessions.submitted_at.

rule 006 [rule_key: eligibility_code_valid_for_invoice_date, source_requirement_id: ESP-2026-COM-008]
Check whether the invoice date falls within the eligibility-code validity window.
Use users_eligibilitycodes.approved_at and users_eligibilitycodes.expires_at from the supplied database values.
Use the best-supported invoice date visible in the OCR/DI JSON as the v1 upgrade-completion proxy unless the invoice clearly shows a more explicit installation/completion date.
If users_eligibilitycodes.expires_at is missing but users_eligibilitycodes.approved_at is present, treat the validity window end as approved_at + 6 months.
Set rule_pass_flag=true only when the dates are clear and the invoice/completion date is on or after approved_at and on or before the validity-window end.
Set rule_pass_flag=false when the dates are missing, ambiguous, or the comparison fails.
If the visible invoice eligibility code conflicts with the supplied database eligibility code, mention that conflict in observed_text.
In calculation, show the approval date, expiry/window end, and invoice/completion date you used.
$common$
  )
),
seeded_config AS (
INSERT INTO claims.validationgenai_config (
  id,
  system_record,
  classifier_system_record,
  user_record0,
  admin_advice_intro,
  admin_advice_closing,
    created_at,
    updated_at
  )
  SELECT
    id,
    system_record,
    classifier_system_record,
    user_record0,
    admin_advice_intro,
    admin_advice_closing,
    created_at,
    updated_at
  FROM config_row
  ON CONFLICT (id) DO UPDATE SET
    system_record = EXCLUDED.system_record,
    classifier_system_record = EXCLUDED.classifier_system_record,
    user_record0 = EXCLUDED.user_record0,
    admin_advice_intro = EXCLUDED.admin_advice_intro,
    admin_advice_closing = EXCLUDED.admin_advice_closing,
    updated_at = NOW()
  RETURNING id
),
seed_rows (
  id,
  upgrade_type_key,
  ruleset_shortname,
  user_record1,
  created_at,
  updated_at
) AS (
  SELECT
    '83c167b8-8f7f-4db9-9c3b-d6e6e5f61708'::uuid,
    'common',
    'esp_common_invoice_evidence_2026_04_v1',
    cr.user_record1,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  FROM common_ruleset_row cr
  UNION ALL
  VALUES
  (
    '4bf85215-6bb3-4533-b0a2-f73e0d9b6cd6'::uuid,
    'windows_doors',
    'esp_windows_doors_2026_04_v1',
    $windows$
Upgrade type: Windows and doors.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Windows/doors located fields:
101 [field_key: certification_body_reference] Locate references to accepted certification bodies or rating/certification identifiers.
Accepted certification bodies and common references include:
- Canadian Standards Association (CSA)
- Intertek Canada (Intertek)
- Labtest Certification (LC / LabTest)
- QAI Laboratories (QAI)
- Keystone Certification (KC / Keystone)
- National Accreditation and Management Institute Certification (NAMI)
- National Fenestration Ratings Council (NFRC)
- NFRC Certified Products Directory (CPD)
Return the exact text found, not a paraphrase.
102 [field_key: manufacturer_label_photo_reference] Locate text suggesting manufacturer label photos are included, attached, or required.
103 [field_key: quote_preapproval_reference] Locate quote pre-approval, pre-approval, or approval-before-installation references.
104 [field_key: nrcan_number] Locate NRCan ENERGY STAR fenestration registration number, if present.
105 [field_key: cpd_number] Locate CPD / NFRC Certified Products Directory identifier, if present.
106 [field_key: brand_and_model] Locate brand and model of windows/doors if present.
107 [field_key: metric_u_factor] Locate metric U-factor numeric values.
108 [field_key: window_or_door_quantity] Locate quantity of windows/doors.
109 [field_key: rough_opening_count] Locate rough opening count if explicitly stated.
110 [field_key: pane_count] Locate pane count if invoice appears to count panes instead of rough openings.
111 [field_key: hardware_per_unit] Locate hardware/material price per unit.
112 [field_key: labour_per_unit] Locate labour breakdown per unit.
113 [field_key: window_or_door_line_amount] Locate total amount for each window/door line item.
114 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for the windows/doors upgrade only.
115 [field_key: skylight_detected] Locate evidence that any claimed item is a skylight; value should be true/false/null.

Windows/doors GenAI/manual-review rulecheck tasks:

rule 101 [rule_key: wd_no_skylights, source_requirement_id: ESP-2026-WD-004]
Check whether the invoice appears to include skylights as part of the Windows and doors claim.
Set rule_pass_flag=false only if the invoice clearly claims skylights.
Set rule_pass_flag=true if there is no clear skylight evidence.

rule 102 [rule_key: wd_certification_reference_present, source_requirement_id: ESP-2026-WD-005]
Check whether the invoice contains any product/certification reference that would help an admin verify the accepted certification body requirement.
Look specifically for CSA, Intertek, Labtest/LC, QAI, Keystone/KC, NAMI, NFRC, CPD, NRCan/ENERGY STAR fenestration numbers, or similar product-rating identifiers.
Set rule_pass_flag=true if at least one useful certification/rating reference is clearly visible.
Set rule_pass_flag=false if there is no visible certification/rating reference.
This is not a final product-list validation.

rule 103 [rule_key: wd_rough_opening_evidence_present, source_requirement_id: ESP-2026-WD-006]
Check whether the invoice appears to provide enough quantity/count evidence for an admin to reason about Rough Openings (RO).
Program meaning:
- The eligible count is based on Rough Openings (RO), not panes or individual glass sections.
- Each RO counts as one eligible window/door rebate unit.
- A bay window may contain several window sections/panes, but it counts as one RO and qualifies for one rebate.
Set rule_pass_flag=true if the invoice clearly lists rough openings, window/door unit counts, or line items that appear to map cleanly to replacement openings.
Set rule_pass_flag=false if the count basis is unclear.
Set rule_pass_flag=false only if the invoice clearly appears to count panes/sections as separate rebate units without RO evidence.
In observed_text, say whether the invoice appears RO-based, unit-count based, pane-count based, or unclear.

rule 104 [rule_key: wd_description_sufficient_for_review, source_requirement_id: ESP-2026-WD-003]
Check whether the invoice description is sufficiently detailed for admin pre-review of Windows and doors work.
Look for line items that identify windows/doors, quantities, models, U-factor, labour/materials, and rebate lines.

rule 105 [rule_key: wd_label_photo_reference_present, source_requirement_id: ESP-2026-WD-013]
Check whether the invoice or OCR text references manufacturer label photos.
Set rule_pass_flag=false if the invoice/OCR does not reference manufacturer label photos or if supporting-document evidence is unavailable to the model.

rule 106 [rule_key: wd_quote_preapproval_reference_present, source_requirement_id: ESP-2026-WD-002]
Check whether the invoice text references quote pre-approval.
This is not a final pre-approval validation; the DB/program record must verify it.

rule 107 [rule_key: wd_per_unit_rebate_math_within_cap, source_requirement_id: ESP-2026-WD-010]
Check whether the per-unit rebate calculations are visibly shown and appear to be within the per-window/per-door cap.
Use the original v1 calculation reference:
1. full_unit_subtotal = hardware price per unit + labour price per unit.
2. If labour per unit is not shown, it may be estimated as labour total divided by quantity of units, but only when those values are clearly visible.
3. full_unit_after_tax_subtotal = full_unit_subtotal * 1.05.
4. rebate_percentage is 95% for ESP1 and 60% for ESP2. If the eligibility code/income level is missing or unclear, set rule_pass_flag=false and explain what is missing.
5. rebate_per_unit = full_unit_after_tax_subtotal * rebate_percentage.
6. Each rebate_per_unit is capped at $950 per window or door.
Set rule_pass_flag=true only when the invoice provides enough visible values and the claimed per-unit rebate appears within the cap.
Set rule_pass_flag=false only when the visible values clearly show the claimed per-unit rebate exceeds the cap or calculation.
Set rule_pass_flag=false when hardware, labour, quantity, eligibility code, tax basis, or claimed per-unit rebate is missing/ambiguous.
In calculation, show the visible formula and values used. Do not invent missing line-item values.

rule 108 [rule_key: wd_per_home_rebate_math_within_cap, source_requirement_id: ESP-2026-WD-011]
Check whether the total invoice/home rebate appears within the per-home cap.
Use the original v1 calculation reference:
1. Add the rebate_per_unit values for all eligible windows/doors across the invoice.
2. The total invoice/home rebate is capped at $9,500.
Set rule_pass_flag=true only when visible invoice values clearly show the total claimed rebate is at or below $9,500.
Set rule_pass_flag=false only when the visible claimed rebate clearly exceeds $9,500.
Set rule_pass_flag=false when eligible unit count, per-unit rebate values, or total claimed rebate are missing/ambiguous.
In calculation, show the visible total rebate and cap comparison. Do not invent missing line-item values.

rule 109 [rule_key: wd_customer_portion_math_matches, source_requirement_id: ESP-2026-WD-012]
Check whether the customer-portion calculation on the invoice appears to match the official customer-portion calculation.
Use the original v1 calculation reference:
1. afterrebate_invoicecost = total_invoice_cost - capped_invoice_total_rebate.
2. customer_portion = afterrebate_invoicecost - customer_deposit.
3. If customer_portion is positive, the homeowner/customer still owes the contractor.
4. If customer_portion is negative, the contractor owes the customer.
Set rule_pass_flag=true only when visible invoice values clearly match the calculated customer portion or amount due.
Set rule_pass_flag=false only when visible invoice values clearly contradict the calculated customer portion or amount due.
Set rule_pass_flag=false when total invoice cost, capped rebate, customer deposit, or amount due after rebate is missing/ambiguous.
In calculation, show the visible formula and values used. Do not invent missing line-item values.
$windows$,
    TIMESTAMP '2026-03-13 21:27:54.352533',
    NOW()
  ),
  (
    'd05e0b98-5f84-4bec-9555-070ff8f7b054'::uuid,
    'air_source_heat_pump_electric',
    'esp_air_source_heat_pump_electric_2026_04_v1',
    $ashp_electric$
Upgrade type: Air source heat pump - convert from electric.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as an air-source heat pump replacing hard-wired electric primary space heating.
Do not use this ruleset for wood, gas/propane, oil, dual fuel, air-to-water, combined space/water, or heat pump water heater work.

Located fields:
101 [field_key: hp_new_equipment_type] Locate ductless mini-split, ductless multi-split, central ducted, low-static ducted mini, indoor heads/zones, or similar.
102 [field_key: hp_existing_electric_heat_evidence] Locate hard-wired electric baseboard, radiant ceiling/floor, electric furnace, electric boiler, or other electric primary heat evidence.
103 [field_key: hp_make_model] Locate make/model numbers.
104 [field_key: hp_ahri_reference] Locate AHRI reference/certificate numbers.
105 [field_key: hp_product_list_reference] Locate qualified heat pump product list, NRCan, ENERGY STAR, NEEP, or similar references.
106 [field_key: hp_efficiency_and_capacity] Locate SEER/HSPF/SEER2/HSPF2, variable speed compressor, BTU/tonnage, or capacity evidence.
107 [field_key: hp_heat_load_calc_reference] Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.
108 [field_key: hp_line_amount] Locate air-source heat pump line-item totals.
109 [field_key: hp_installation_labour_amount] Locate installation labour amount if shown separately.
110 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this electric-to-heat-pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: ashp_electric_existing_heat_context_present, source_requirement_id: ESP-2026-ASHP-ELEC-001]
Check whether invoice text supports electric primary heating conversion context.
rule 102 [rule_key: ashp_electric_product_reference_present, source_requirement_id: ESP-2026-ASHP-ELEC-004]
Check whether invoice text includes useful product evidence such as AHRI, make/model, qualified product list, capacity, or efficiency ratings.
rule 103 [rule_key: ashp_electric_primary_system_scope_present, source_requirement_id: ESP-2026-ASHP-ELEC-002/003]
Check whether the invoice describes a primary heat-pump system rather than a secondary/add-on system.
rule 104 [rule_key: ashp_electric_description_sufficient_for_review, source_requirement_id: ESP-2026-ASHP-ELEC-009]
Check whether the invoice description is sufficient for admin pre-review of equipment, scope, labour/materials, and this upgrade's rebate line.
$ashp_electric$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'e72258a1-1a2b-44a0-b55d-69007861c8bc'::uuid,
    'air_source_heat_pump_wood',
    'esp_air_source_heat_pump_wood_2026_04_v1',
    $ashp_wood$
Upgrade type: Air source heat pump - convert from wood.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as an air-source heat pump replacing or displacing a wood or solid-fuel primary heating system.

Located fields:
101 [field_key: hp_new_equipment_type] Locate ductless mini-split, ductless multi-split, central ducted, indoor heads/zones, or similar.
102 [field_key: hp_existing_wood_heat_evidence] Locate wood stove, pellet stove, insert, wood furnace, solid fuel, or similar existing primary heat evidence.
103 [field_key: hp_make_model] Locate make/model numbers.
104 [field_key: hp_ahri_reference] Locate AHRI reference/certificate numbers.
105 [field_key: hp_product_list_reference] Locate qualified heat pump product list, NRCan, ENERGY STAR, NEEP, or similar references.
106 [field_key: hp_efficiency_and_capacity] Locate SEER/HSPF/SEER2/HSPF2, variable speed compressor, BTU/tonnage, or capacity evidence.
107 [field_key: hp_wood_system_removal_or_wett_evidence] Locate wood/solid-fuel removal evidence, retained-appliance evidence, or WETT report reference.
108 [field_key: hp_heat_load_calc_reference] Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.
109 [field_key: hp_line_amount] Locate air-source heat pump line-item totals.
110 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this wood-to-heat-pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: ashp_wood_existing_heat_context_present, source_requirement_id: ESP-2026-ASHP-WOOD-001]
Check whether invoice text supports wood/solid-fuel primary heating conversion context.
rule 102 [rule_key: ashp_wood_product_reference_present, source_requirement_id: ESP-2026-ASHP-WOOD-004]
Check whether invoice text includes useful product evidence such as AHRI, make/model, qualified product list, capacity, or efficiency ratings.
rule 103 [rule_key: ashp_wood_removal_or_wett_reference_present, source_requirement_id: ESP-2026-ASHP-WOOD-SUPP]
Check whether invoice/supporting-document text references wood-system removal or WETT documentation when relevant.
rule 104 [rule_key: ashp_wood_description_sufficient_for_review, source_requirement_id: ESP-2026-ASHP-WOOD-011]
Check whether the invoice description is sufficient for admin pre-review of equipment, scope, labour/materials, and this upgrade's rebate line.
$ashp_wood$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '0a58c6a7-31e7-44a3-806d-9e96f2b8b199'::uuid,
    'air_source_heat_pump_gas_propane',
    'esp_air_source_heat_pump_gas_propane_2026_04_v1',
    $ashp_gas_propane$
Upgrade type: Air source heat pump - convert from natural gas or propane.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as an air-source heat pump replacing natural gas or propane primary space heating with non-fossil backup.
Do not use this ruleset for dual-fuel ducted heat pumps where fossil backup remains intentionally integrated.

Located fields:
101 [field_key: hp_new_equipment_type] Locate single-head mini-split, 2-head/multi-split, central ducted, indoor heads/zones, or similar.
102 [field_key: hp_existing_gas_propane_heat_evidence] Locate natural gas, propane, furnace, boiler, tank propane, PNG, FortisBC gas, or similar existing heat evidence.
103 [field_key: hp_make_model] Locate make/model numbers.
104 [field_key: hp_ahri_reference] Locate AHRI reference/certificate numbers.
105 [field_key: hp_product_list_reference] Locate qualified heat pump product list, NRCan, ENERGY STAR, NEEP, or similar references.
106 [field_key: hp_efficiency_and_capacity] Locate SEER/HSPF/SEER2/HSPF2, variable speed compressor, BTU/tonnage, or capacity evidence.
107 [field_key: hp_fossil_fuel_removal_evidence] Locate removal, decommissioning, capping, disconnection, appliance/piping/vent/fuel-container removal, permit, or inspection evidence.
108 [field_key: hp_heat_load_calc_reference] Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.
109 [field_key: hp_northern_top_up_evidence] Locate northern top-up evidence if shown.
110 [field_key: hp_line_amount] Locate air-source heat pump line-item totals.
111 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this gas/propane-to-heat-pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: ashp_gas_propane_existing_heat_context_present, source_requirement_id: ESP-2026-ASHP-GAS-001]
Check whether invoice text supports natural gas or propane primary heating conversion context.
rule 102 [rule_key: ashp_gas_propane_product_reference_present, source_requirement_id: ESP-2026-ASHP-GAS-003]
Check whether invoice text includes useful product evidence such as AHRI, make/model, qualified product list, capacity, or efficiency ratings.
rule 103 [rule_key: ashp_gas_propane_removal_reference_present, source_requirement_id: ESP-2026-ASHP-GAS-SUPP]
Check whether invoice/supporting-document text references fossil-fuel system removal or decommissioning.
rule 104 [rule_key: ashp_gas_propane_description_sufficient_for_review, source_requirement_id: ESP-2026-ASHP-GAS-011]
Check whether the invoice description is sufficient for admin pre-review of equipment, scope, labour/materials, and this upgrade's rebate line.
$ashp_gas_propane$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '6f0bf0ef-931d-4b9c-9ad0-5c98b2dfc845'::uuid,
    'air_source_heat_pump_oil',
    'esp_air_source_heat_pump_oil_2026_04_v1',
    $ashp_oil$
Upgrade type: Air source heat pump - convert from oil.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as an air-source heat pump replacing oil primary space heating.

Located fields:
101 [field_key: hp_new_equipment_type] Locate single-head mini-split, 2-head/multi-split, central ducted, indoor heads/zones, or similar.
102 [field_key: hp_existing_oil_heat_evidence] Locate oil furnace, oil boiler, oil tank, fuel oil, 500 L oil baseline, or similar existing heat evidence.
103 [field_key: hp_make_model] Locate make/model numbers.
104 [field_key: hp_ahri_reference] Locate AHRI reference/certificate numbers.
105 [field_key: hp_product_list_reference] Locate NRCan Oil to Heat Pump Affordability qualified product list or similar references.
106 [field_key: hp_efficiency_and_capacity] Locate SEER/HSPF/SEER2/HSPF2, variable speed compressor, BTU/tonnage, or capacity evidence.
107 [field_key: hp_oil_system_removal_evidence] Locate oil system and oil tank removal, decommissioning, capping, disconnection, permit, or inspection evidence.
108 [field_key: hp_heat_load_calc_reference] Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.
109 [field_key: hp_northern_top_up_evidence] Locate northern top-up evidence if shown.
110 [field_key: hp_line_amount] Locate air-source heat pump line-item totals.
111 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this oil-to-heat-pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: ashp_oil_existing_heat_context_present, source_requirement_id: ESP-2026-ASHP-OIL-001/002]
Check whether invoice text supports oil primary heating conversion context.
rule 102 [rule_key: ashp_oil_product_reference_present, source_requirement_id: ESP-2026-ASHP-OIL-004]
Check whether invoice text includes useful product evidence such as AHRI, make/model, qualified product list, capacity, or efficiency ratings.
rule 103 [rule_key: ashp_oil_removal_reference_present, source_requirement_id: ESP-2026-ASHP-OIL-SUPP]
Check whether invoice/supporting-document text references oil system and oil tank removal.
rule 104 [rule_key: ashp_oil_description_sufficient_for_review, source_requirement_id: ESP-2026-ASHP-OIL-012]
Check whether the invoice description is sufficient for admin pre-review of equipment, scope, labour/materials, and this upgrade's rebate line.
$ashp_oil$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'aa71d06b-990a-4712-91c4-bbc497af7f7b'::uuid,
    'dual_fuel_ducted_heat_pump',
    'esp_dual_fuel_ducted_heat_pump_2026_04_v1',
    $dual_fuel$
Upgrade type: Dual fuel ducted heat pump.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as a dual-fuel ducted heat pump with fossil-fuel backup integration.

Located fields:
101 [field_key: dfhp_equipment_type] Locate dual fuel ducted heat pump evidence.
102 [field_key: dfhp_existing_png_or_tank_propane_evidence] Locate Pacific Northern Gas, PNG, tank propane, natural gas, propane, or similar primary heating evidence.
103 [field_key: dfhp_make_model] Locate heat pump and furnace make/model numbers.
104 [field_key: dfhp_ahri_reference] Locate AHRI reference/certificate numbers for outdoor unit, indoor unit(s), and furnace where visible.
105 [field_key: dfhp_switchover_setpoint_evidence] Locate thermostat, outdoor temperature switchover, equipment control board, <=5 C, <=2 C, or similar controls evidence.
106 [field_key: dfhp_heat_load_calc_reference] Locate program-approved heat load calculation, CSA-F280, Manual J, or sizing evidence.
107 [field_key: dfhp_fossil_modification_evidence] Locate fossil fuel removal/modification evidence, permit, inspection, capping, piping, vent, or appliance changes.
108 [field_key: dfhp_line_amount] Locate dual-fuel heat pump line-item totals.
109 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this dual-fuel ducted heat pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: dfhp_dual_fuel_scope_present, source_requirement_id: ESP-2026-DFHP-001/002]
Check whether invoice text supports dual-fuel ducted heat-pump scope with fossil backup.
rule 102 [rule_key: dfhp_controls_reference_present, source_requirement_id: ESP-2026-DFHP-002]
Check whether invoice text references switchover controls or dual-fuel control setup.
rule 103 [rule_key: dfhp_heat_load_calc_reference_present, source_requirement_id: ESP-2026-DFHP-003]
Check whether invoice/supporting-document text references required heat load calculation.
rule 104 [rule_key: dfhp_description_sufficient_for_review, source_requirement_id: ESP-2026-DFHP-008]
Check whether the invoice description is sufficient for admin pre-review of equipment, fossil-backup integration, labour/materials, and this upgrade's rebate line.
$dual_fuel$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '777f63f0-1f2c-4280-a6d8-4cd83aa58c14'::uuid,
    'air_to_water_heat_pump',
    'esp_air_to_water_heat_pump_2026_04_v1',
    $air_to_water$
Upgrade type: Air-to-water heat pump.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as an air-to-water heat pump for space heating only.
Do not use this ruleset for combined space and water heat pumps or heat pump water heaters.

Located fields:
101 [field_key: atw_equipment_type] Locate air-to-water heat pump evidence.
102 [field_key: atw_conversion_source_fuel_evidence] Locate fossil fuel, electric, wood, or unclear source-fuel evidence.
103 [field_key: atw_make_model] Locate make/model numbers.
104 [field_key: atw_product_list_reference] Locate air-to-water qualifying product list references.
105 [field_key: atw_fossil_removal_evidence] Locate fossil-fuel removal/decommissioning evidence if fossil fuel is involved.
106 [field_key: atw_wood_removal_or_wett_evidence] Locate wood-system removal or WETT evidence if wood is involved.
107 [field_key: atw_heat_load_calc_reference] Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.
108 [field_key: atw_line_amount] Locate air-to-water heat pump line-item totals.
109 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this air-to-water heat pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: atw_scope_present, source_requirement_id: ESP-2026-ATW-001/002]
Check whether invoice text supports air-to-water space-heating scope.
rule 102 [rule_key: atw_product_reference_present, source_requirement_id: ESP-2026-ATW-002]
Check whether invoice text includes useful qualifying product-list or make/model evidence.
rule 103 [rule_key: atw_conversion_context_present, source_requirement_id: ESP-2026-ATW-001/003/004]
Check whether invoice text identifies source-fuel conversion context and any removal/supporting-document references.
rule 104 [rule_key: atw_description_sufficient_for_review, source_requirement_id: ESP-2026-ATW-010]
Check whether the invoice description is sufficient for admin pre-review of equipment, scope, labour/materials, and this upgrade's rebate line.
$air_to_water$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '960870a8-4f32-4856-b005-d5fb98132f2a'::uuid,
    'combined_space_water_heat_pump',
    'esp_combined_space_water_heat_pump_2026_04_v1',
    $combined_space_water$
Upgrade type: Combined space and water heat pump.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

Target scope:
Use this ruleset only for invoices classified as a combined space-heating and water-heating heat pump.
Do not use this ruleset for air-to-water space-heating-only systems or standalone heat pump water heaters.

Located fields:
101 [field_key: cshp_equipment_type] Locate combined space and water heat pump evidence.
102 [field_key: cshp_conversion_source_fuel_evidence] Locate fossil fuel, electric, wood, or unclear source-fuel evidence.
103 [field_key: cshp_make_model] Locate make/model numbers.
104 [field_key: cshp_product_list_reference] Locate air-to-water/combined heat pump qualifying product list references.
105 [field_key: cshp_fossil_removal_evidence] Locate fossil-fuel removal/decommissioning evidence if fossil fuel is involved.
106 [field_key: cshp_wood_removal_or_wett_evidence] Locate wood-system removal or WETT evidence if wood is involved.
107 [field_key: cshp_heat_load_calc_reference] Locate heat load calculation, sizing report, CSA-F280, Manual J, or similar.
108 [field_key: cshp_line_amount] Locate combined space/water heat pump line-item totals.
109 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for this combined space/water heat pump upgrade only.

Rulecheck tasks:
rule 101 [rule_key: cshp_scope_present, source_requirement_id: ESP-2026-CSHP-001/002]
Check whether invoice text supports combined space and water heat-pump scope.
rule 102 [rule_key: cshp_product_reference_present, source_requirement_id: ESP-2026-CSHP-002]
Check whether invoice text includes useful qualifying product-list or make/model evidence.
rule 103 [rule_key: cshp_conversion_context_present, source_requirement_id: ESP-2026-CSHP-001/003/004]
Check whether invoice text identifies source-fuel conversion context and any removal/supporting-document references.
rule 104 [rule_key: cshp_description_sufficient_for_review, source_requirement_id: ESP-2026-CSHP-010]
Check whether the invoice description is sufficient for admin pre-review of equipment, scope, labour/materials, and this upgrade's rebate line.
$combined_space_water$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '69d586a3-8cb3-47a3-830a-a31de628c2ce'::uuid,
    'electrical_service_upgrade',
    'esp_electrical_service_upgrade_2026_04_v1',
    $electrical$
Upgrade type: Electrical service upgrade.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

First-pass scope:
Electrical service upgrade evidence is strongly connected to a fossil-fuel-to-heat-pump conversion and utility service work.
For v1, locate invoice evidence and flag utility/service/associated-heat-pump questions. Do not make final eligibility decisions from invoice text alone.

Electrical service upgrade located fields:
101 [field_key: esu_service_size] Locate upgraded electrical service size, such as 100 amp, 200 amp, or 400 amp service.
102 [field_key: esu_utility_reference] Locate BC Hydro, FortisBC, utility connection, line upgrade, or utility bill/invoice references.
103 [field_key: esu_fossil_to_heat_pump_context] Locate evidence that the upgrade is associated with conversion from oil, propane, or natural gas primary heating or water heating to a heat pump.
104 [field_key: esu_heat_pump_installation_date_reference] Locate heat pump installation date or timing evidence if visible.
105 [field_key: esu_eligible_expense_lines] Locate service upgrade expense lines, such as connection fees, panel or sub-panel upgrade, service mast, conduit, meter base, weather head, or labour.
106 [field_key: esu_ineligible_panel_only_evidence] Locate evidence that the invoice is only a panel/sub-panel or heat pump connection without utility service upgrade.
107 [field_key: esu_contractor_utility_management_evidence] Locate evidence that contractor/electrician managed the line upgrade with the electrical utility.
108 [field_key: esu_permit_or_ahj_reference] Locate permit, inspection, Technical Safety BC, Authority Having Jurisdiction, or by-law compliance references.
109 [field_key: esu_line_amount] Locate electrical service upgrade line-item totals.
110 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for the electrical service upgrade only.

Electrical service upgrade GenAI/manual-review rulecheck tasks:

rule 101 [rule_key: esu_service_size_present, source_requirement_id: ESP-2026-ESU-003]
Check whether the invoice clearly references a 100, 200, or 400 amp electrical service upgrade.
Set rule_pass_flag=false if electrical work is visible but service size is missing.

rule 102 [rule_key: esu_utility_upgrade_evidence_present, source_requirement_id: ESP-2026-ESU-002/005]
Check whether the invoice contains evidence of a utility service upgrade by BC Hydro/FortisBC or another electrical utility.
Set false only if the invoice clearly appears to be panel/sub-panel work or heat-pump panel connection only without utility service upgrade.

rule 103 [rule_key: esu_heat_pump_conversion_context_present, source_requirement_id: ESP-2026-ESU-001]
Check whether invoice text ties the service upgrade to a fossil-fuel-to-heat-pump conversion.
Set rule_pass_flag=false if this likely requires application/DB context.

rule 104 [rule_key: esu_timing_within_six_months_evidence, source_requirement_id: ESP-2026-ESU-003]
Check whether visible invoice dates provide enough evidence to compare service upgrade timing against heat pump installation timing.
Set rule_pass_flag=false unless both dates are visible.

rule 105 [rule_key: esu_description_sufficient_for_review, source_requirement_id: ESP-2026-ESU-004/006]
Check whether the invoice description is sufficient for admin pre-review of eligible electrical service upgrade costs.
Look for utility connection fees, panel/sub-panel upgrade, mast, conduit, meter base, weather head, labour, and CleanBC rebate line.
$electrical$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '98a31bc0-515b-4c21-8ff6-1f443c1de822'::uuid,
    'health_and_safety_remediation',
    'esp_health_and_safety_remediation_2026_04_v1',
    $health$
Upgrade type: Health and safety remediation.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

First-pass scope:
Health and safety remediation is only eligible when it enables another rebate-eligible upgrade.
For v1, locate evidence of remediation type, associated upgrade, pre-confirmation, and before/after photo references. Do not make final eligibility decisions from invoice text alone.

Health and safety located fields:
101 [field_key: hs_issue_type] Locate health/safety issue type, such as pest, asbestos, structural, mould, vermiculite, or other safety concern.
102 [field_key: hs_associated_upgrade_evidence] Locate evidence that remediation enabled heat pump, heat pump water heater, insulation, or windows/doors work.
103 [field_key: hs_pre_confirmation_reference] Locate pre-confirmation or rebate-eligible confirmation references.
104 [field_key: hs_remediation_scope] Locate description of remediation work completed.
105 [field_key: hs_before_after_photo_reference] Locate text indicating before and after photos are attached or required.
106 [field_key: hs_technical_safety_or_permit_reference] Locate Technical Safety BC, permit, lawful authority, manufacturer specification, or by-law compliance references.
107 [field_key: hs_line_amount] Locate health and safety remediation line-item totals.
108 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for the health and safety remediation upgrade only.

Health and safety GenAI/manual-review rulecheck tasks:

rule 101 [rule_key: hs_issue_type_present, source_requirement_id: ESP-2026-HS-001]
Check whether the invoice clearly identifies an existing health and safety issue being remediated.

rule 102 [rule_key: hs_associated_upgrade_present, source_requirement_id: ESP-2026-HS-001]
Check whether the invoice connects remediation to an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
Set rule_pass_flag=false if association likely requires DB/application context.

rule 103 [rule_key: hs_not_standalone_flag, source_requirement_id: ESP-2026-HS-001]
Flag whether the invoice appears to claim health and safety remediation on its own.
Set false only if it clearly appears standalone without an associated eligible upgrade.

rule 104 [rule_key: hs_pre_confirmation_evidence_present, source_requirement_id: ESP-2026-HS-001]
Check whether invoice text references prior confirmation that the remediation was rebate-eligible.
Set rule_pass_flag=false if not visible.

rule 105 [rule_key: hs_description_sufficient_for_review, source_requirement_id: ESP-2026-HS-002]
Check whether the invoice description is sufficient for admin pre-review of remediation work, issue type, associated upgrade, rebate line, and amount.
$health$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'be21f1ee-4ee4-4cc0-b4e8-ad70e972390b'::uuid,
    'heat_pump_water_heater',
    'esp_heat_pump_water_heater_2026_04_v1',
    $hpwh$
Upgrade type: Heat pump water heater.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

First-pass scope:
Heat pump water heater evidence depends on primary water heater replacement, product-list references, and sometimes fossil-fuel equipment removal.
For v1, locate invoice evidence and flag supporting-document questions. Do not make final eligibility decisions from invoice text alone.

Heat pump water heater located fields:
101 [field_key: hpwh_existing_water_heater_evidence] Locate text about the existing primary water heater being replaced.
102 [field_key: hpwh_existing_fuel_type] Locate fossil fuel, electric, wood, or unclear existing water-heating fuel evidence.
103 [field_key: hpwh_new_equipment_type] Locate heat pump water heater equipment type.
104 [field_key: hpwh_make_model] Locate heat pump water heater make/model numbers.
105 [field_key: hpwh_neea_reference] Locate NEEA Advanced Water Heater Specification or qualified product list references.
106 [field_key: hpwh_tier_reference] Locate Tier 2 or higher evidence if visible.
107 [field_key: hpwh_secondary_system_flag] Locate evidence the invoice is for a secondary/additional water heater rather than replacing the primary system.
108 [field_key: hpwh_fossil_fuel_removal_evidence] Locate removal, decommissioning, capping, disconnection, piping/appliance/container/vent removal, or permit/inspection references.
109 [field_key: hpwh_non_integrated_area_preapproval_reference] Locate Non-Integrated Area or pre-approval references if fossil fuel is involved.
110 [field_key: hpwh_line_amount] Locate heat pump water heater line-item totals.
111 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for the heat pump water heater upgrade only.

Heat pump water heater GenAI/manual-review rulecheck tasks:

rule 101 [rule_key: hpwh_primary_replacement_context_present, source_requirement_id: ESP-2026-HPWH-001]
Check whether the invoice provides evidence that the heat pump water heater replaces the home's primary water heater.
Set rule_pass_flag=false if this likely requires application/DB context.

rule 102 [rule_key: hpwh_product_reference_present, source_requirement_id: ESP-2026-HPWH-002]
Check whether the invoice includes useful product references for later validation, such as make/model, NEEA, qualified product list, or Tier 2+ evidence.
This is not final product-list validation.

rule 103 [rule_key: hpwh_fossil_removal_evidence_present, source_requirement_id: ESP-2026-HPWH-003]
If fossil fuel water heating evidence is present, check whether invoice text references removal/decommissioning of fossil-fuel equipment.
Set rule_pass_flag=true if fossil fuel evidence is not present. Set rule_pass_flag=false if supporting documents are required but not visible.

rule 104 [rule_key: hpwh_secondary_system_flag, source_requirement_id: ESP-2026-HPWH-005]
Check whether the invoice suggests a secondary or additional heat pump water heater rather than replacement of the primary water heater.
Set false only if secondary/additional wording is clearly present.

rule 105 [rule_key: hpwh_description_sufficient_for_review, source_requirement_id: ESP-2026-HPWH-007/008]
Check whether the invoice description is sufficient for admin pre-review of heat pump water heater work, product reference, labour/materials, rebate line, and amount.
$hpwh$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '1f108fa3-bf82-4492-b6f1-47d6c801b44b'::uuid,
    'insulation',
    'esp_insulation_2026_04_v1',
    $insulation$
Upgrade type: Insulation.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

First-pass scope:
Insulation eligibility depends on location, material, R-value, area, conditioned/unconditioned boundary, and supporting photos/floor plans.
For v1, locate invoice evidence and flag missing information for admin review. Do not make final eligibility decisions from invoice text alone.

Insulation located fields:
101 [field_key: ins_material_type] Locate insulation material type, such as batt, loose fill, board, or spray foam.
102 [field_key: ins_upgrade_location] Locate insulation location, such as attic, exterior wall cavity, exterior wall sheathing, basement/crawlspace, exposed floor, floor over crawlspace, or basement header.
103 [field_key: ins_conditioned_boundary_evidence] Locate evidence that insulation is between conditioned and unconditioned space.
104 [field_key: ins_new_r_value] Locate new R-value.
105 [field_key: ins_existing_r_value] Locate pre-existing R-value if visible.
106 [field_key: ins_r_value_added] Locate R-value added or difference in R-value.
107 [field_key: ins_area_square_feet] Locate square feet / upgrade area.
108 [field_key: ins_removed_existing_insulation_evidence] Locate evidence of removed pre-existing insulation due to pest, mould, or similar issue.
109 [field_key: ins_health_safety_resolution_evidence] Locate evidence that pest, rodent, vermiculite, asbestos, or mould issues were resolved before insulation work.
110 [field_key: ins_before_after_photo_reference] Locate text indicating before and after photos are attached or required.
111 [field_key: ins_floor_plan_reference] Locate floor plan drawing references.
112 [field_key: ins_line_amount] Locate insulation line-item totals.
113 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for the insulation upgrade only.

Insulation GenAI/manual-review rulecheck tasks:

rule 101 [rule_key: ins_material_and_location_present, source_requirement_id: ESP-2026-INS-002]
Check whether the invoice identifies insulation material and eligible installation location clearly enough for admin pre-review.

rule 102 [rule_key: ins_r_value_and_area_present, source_requirement_id: ESP-2026-INS-003]
Check whether the invoice provides R-value and area/square-foot evidence needed for rebate calculation review.
Set rule_pass_flag=false if one or both values are missing or ambiguous.

rule 103 [rule_key: ins_health_safety_issue_flag, source_requirement_id: ESP-2026-INS-004/006]
Check whether the invoice references pest, rodent, vermiculite, asbestos, mould, or removed insulation issues.
Set rule_pass_flag=false only if unresolved issues appear to block processing or if evidence is unclear.

rule 104 [rule_key: ins_supporting_document_reference_present, source_requirement_id: ESP-2026-INS-SUPP]
Check whether invoice text references before/after photos or floor plan drawings.
Set rule_pass_flag=false if supporting documents are not visible to the model.

rule 105 [rule_key: ins_description_sufficient_for_review, source_requirement_id: ESP-2026-INS-002/003]
Check whether the invoice description is sufficient for admin pre-review of insulation scope, material, location, R-value, area, rebate line, and amount.
$insulation$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'ca3451cd-e6e1-49f9-9db0-fbd7b16bb84e'::uuid,
    'ventilation',
    'esp_ventilation_2026_04_v1',
    $ventilation$
Upgrade type: Ventilation.
Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.

First-pass scope:
Ventilation eligibility depends on association with another eligible upgrade and whether the equipment is HRV/ERV or bathroom fan system.
For v1, locate invoice evidence and flag product/capacity/supporting-document questions. Do not make final eligibility decisions from invoice text alone.

Ventilation located fields:
101 [field_key: vent_system_type] Locate ventilation system type, such as HRV, ERV, heat recovery ventilator, energy recovery ventilator, bathroom fan, or fan system.
102 [field_key: vent_associated_upgrade_evidence] Locate evidence that ventilation is installed with heat pump, heat pump water heater, insulation, or windows/doors work.
103 [field_key: vent_improved_air_circulation_evidence] Locate text indicating improved air circulation.
104 [field_key: vent_energy_star_reference] Locate ENERGY STAR references.
105 [field_key: vent_nrcan_or_product_list_reference] Locate NRCan product list or ENERGY STAR product list references.
106 [field_key: vent_bathroom_fan_cfm] Locate bathroom fan capacity in cfm or L/s.
107 [field_key: vent_static_pressure] Locate static pressure rating evidence.
108 [field_key: vent_continuous_duty_motor_evidence] Locate continuous duty or permanently lubricated motor evidence.
109 [field_key: vent_backdraft_damper_evidence] Locate self-closing backdraft damper evidence.
110 [field_key: vent_ducting_evidence] Locate ducting, exterior exhaust, sealed joints, insulated ducts, or duct hood references.
111 [field_key: vent_contractor_license_evidence] Locate HVAC, heat pump, electrical, or approved contractor references.
112 [field_key: vent_line_amount] Locate ventilation line-item totals.
113 [field_key: upgrade_specific_rebate_line_amount] Locate the CleanBC/Better Homes/ESP rebate amount for the ventilation upgrade only.

Ventilation GenAI/manual-review rulecheck tasks:

rule 101 [rule_key: vent_associated_upgrade_present, source_requirement_id: ESP-2026-VENT-001]
Check whether invoice text connects ventilation work to an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
Set rule_pass_flag=false if this likely requires application/DB context.

rule 102 [rule_key: vent_system_type_present, source_requirement_id: ESP-2026-VENT-002/003]
Check whether the invoice identifies the ventilation system as HRV/ERV or bathroom fan system.

rule 103 [rule_key: vent_product_or_capacity_evidence_present, source_requirement_id: ESP-2026-VENT-002/003]
For HRV/ERV, look for ENERGY STAR/NRCan/product-list evidence.
For bathroom fans, look for ENERGY STAR, 85 cfm or 40 L/s, static pressure, continuous duty motor, backdraft damper, and ducting evidence.
Set rule_pass_flag=false when subtype or product/capacity evidence is missing.

rule 104 [rule_key: vent_standalone_flag, source_requirement_id: ESP-2026-VENT-001]
Flag whether the invoice appears to claim ventilation on its own without another eligible upgrade.
Set false only if clearly standalone.

rule 105 [rule_key: vent_description_sufficient_for_review, source_requirement_id: ESP-2026-VENT-004/005]
Check whether the invoice description is sufficient for admin pre-review of ventilation scope, equipment, contractor, rebate line, and amount.
$ventilation$,
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  )
)
INSERT INTO claims.validationgenai_rulesets (
  id,
  invoice_upgrade_type_id,
  ruleset_shortname,
  user_record1,
  created_at,
  updated_at
)
SELECT
  sr.id,
  ut.id AS invoice_upgrade_type_id,
  sr.ruleset_shortname,
  sr.user_record1,
  sr.created_at,
  sr.updated_at
FROM seed_rows sr
JOIN claims.invoice_upgrade_types ut
  ON ut.upgrade_type_key = sr.upgrade_type_key
CROSS JOIN seeded_config
ON CONFLICT (id) DO UPDATE SET
  invoice_upgrade_type_id = EXCLUDED.invoice_upgrade_type_id,
  ruleset_shortname = EXCLUDED.ruleset_shortname,
  user_record1 = EXCLUDED.user_record1,
  updated_at = NOW();

-- Keep the singleton-style config table tidy for local/dev rebuilds.
DELETE FROM claims.validationgenai_config
WHERE id <> '0c2b1d8e-3a63-41ef-97d9-b7c1f7e4a001'::uuid;

-- Local/dev cleanup: keep only the curated working rulesets unless other rows
-- are protected by FK history. This preserves ingest history while keeping the UI tidy.
DELETE FROM claims.validationgenai_rulesets r
WHERE r.id NOT IN (
  '83c167b8-8f7f-4db9-9c3b-d6e6e5f61708'::uuid,
  '4bf85215-6bb3-4533-b0a2-f73e0d9b6cd6'::uuid,
  'd05e0b98-5f84-4bec-9555-070ff8f7b054'::uuid,
  'e72258a1-1a2b-44a0-b55d-69007861c8bc'::uuid,
  '0a58c6a7-31e7-44a3-806d-9e96f2b8b199'::uuid,
  '6f0bf0ef-931d-4b9c-9ad0-5c98b2dfc845'::uuid,
  'aa71d06b-990a-4712-91c4-bbc497af7f7b'::uuid,
  '777f63f0-1f2c-4280-a6d8-4cd83aa58c14'::uuid,
  '960870a8-4f32-4856-b005-d5fb98132f2a'::uuid,
  '69d586a3-8cb3-47a3-830a-a31de628c2ce'::uuid,
  '98a31bc0-515b-4c21-8ff6-1f443c1de822'::uuid,
  'be21f1ee-4ee4-4cc0-b4e8-ad70e972390b'::uuid,
  '1f108fa3-bf82-4492-b6f1-47d6c801b44b'::uuid,
  'ca3451cd-e6e1-49f9-9db0-fbd7b16bb84e'::uuid
)
AND NOT EXISTS (
  SELECT 1
  FROM claims.invoice_version_upgrade_types ivut
  WHERE ivut.validationgenai_ruleset_id = r.id
)
AND NOT EXISTS (
  SELECT 1
  FROM claims.ingest_step_runs s
  WHERE s.validationgenai_ruleset_id = r.id
);

DELETE FROM claims.invoice_upgrade_types ut
WHERE ut.upgrade_type_key NOT IN (
  'common',
  'windows_doors',
  'air_source_heat_pump_electric',
  'air_source_heat_pump_wood',
  'air_source_heat_pump_gas_propane',
  'air_source_heat_pump_oil',
  'dual_fuel_ducted_heat_pump',
  'air_to_water_heat_pump',
  'combined_space_water_heat_pump',
  'heat_pump_water_heater',
  'electrical_service_upgrade',
  'insulation',
  'ventilation',
  'health_and_safety_remediation'
)
AND NOT EXISTS (
  SELECT 1 FROM claims.validationgenai_rulesets r
  WHERE r.invoice_upgrade_type_id = ut.id
)
AND NOT EXISTS (
  SELECT 1 FROM claims.invoice_version_upgrade_types ivut
  WHERE ivut.invoice_upgrade_type_id = ut.id
)
AND NOT EXISTS (
  SELECT 1 FROM claims.invoice_version_located_fields lf
  WHERE lf.invoice_upgrade_type_id = ut.id
)
AND NOT EXISTS (
  SELECT 1 FROM claims.invoice_version_rulechecks rc
  WHERE rc.invoice_upgrade_type_id = ut.id
)
AND NOT EXISTS (
  SELECT 1 FROM claims.lineitems li
  WHERE li.invoice_upgrade_type_id = ut.id
)
AND NOT EXISTS (
  SELECT 1 FROM claims.ingest_step_runs s
  WHERE s.invoice_upgrade_type_id = ut.id
);

COMMIT;
