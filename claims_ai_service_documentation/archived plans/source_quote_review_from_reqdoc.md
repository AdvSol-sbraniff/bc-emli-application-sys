# Source Quote Review From Annotated Requirement Word Doc

Generated from `claims_ai_service_documentation/Test Data/V2 - RebateEligibilityRequirements_ESP_1June2026.docx`.

## Summary

- Current seeded rule keys detected: 89
- Annotated rule keys detected in Word doc: 63
- Auto-apply candidates: 51
- Needs Stephen review: 12
- Current seeded rules with no annotation detected: 26

## How To Review

- `AUTO_APPLY_CANDIDATE` means the rule key matched the current seed and the nearest preceding requirement text looks like a usable quote.
- `ASK_STEPHEN` means the rule was renamed, table-derived, commentary-heavy, short/ambiguous, or not found in the current seed.
- `source_quote` is the proposed exact quote to populate into the new rule registry field.

## Auto-Apply Candidates

### `ashp_electric_backup_heat_electric_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `472`
- Proposed source paragraph: `465`

Annotation text:

> [GENAI-RULE =ashp_electric_backup_heat_electric_present

Proposed `source_quote`:

```text
replace an existing hard-wired electric heating system (e.g. electric baseboards, radiant ceilings, radiant floors, or forced-air furnace). The back-up space heating system must be electric.
```

Nearby preceding requirement context:

- P460: The home must primarily be heated by electricity (a primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C).
- P464: The new heat pump must:
- P465: replace an existing hard-wired electric heating system (e.g. electric baseboards, radiant ceilings, radiant floors, or forced-air furnace). The back-up space heating system must be electric.

### `ashp_electric_existing_heat_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `463`
- Proposed source paragraph: `460`

Annotation text:

> Genai rule = ashp_electric_existing_heat_context_present

Proposed `source_quote`:

```text
The home must primarily be heated by electricity (a primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C).
```

Nearby preceding requirement context:

- P442: Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2 in the CleanBC Better Homes Energy Savings Program.
- P456: Maximum one primary space heating system rebate per home, regardless of the number of systems installed.
- P460: The home must primarily be heated by electricity (a primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C).

### `ashp_gas_propane_existing_heat_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `855`
- Proposed source paragraph: `852`

Annotation text:

> [GENAI-RULE = ashp_gas_propane_existing_heat_context_present

Proposed `source_quote`:

```text
The home must be primarily heated by fossil fuel (natural gas or propane). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.
```

Nearby preceding requirement context:

- P848: AIR SOURCE HEAT PUMP (CONVERT FROM NATURAL GAS OR PROPANE)
- P849: Rebate requirements:
- P852: The home must be primarily heated by fossil fuel (natural gas or propane). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.

### `ashp_gas_propane_rebate_math_within_cap`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `988`
- Proposed source paragraph: `978`

Annotation text:

> [code-rule = ashp_gas_propane_rebate_math_within_cap

Proposed `source_quote`:

```text
Eligible for program approved single-head mini-split heat
```

Nearby preceding requirement context:

- P970: Eligible for program approved central ducted, multi-split and 2 single-head mini-split heat pumps
- P977: Northern top-up\*
- P978: Eligible for program approved single-head mini-split heat

### `ashp_oil_consumption_baseline_proof_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1088`
- Proposed source paragraph: `1085`

Annotation text:

> [Genai-rule = ashp_oil_consumption_baseline_proof_present

Proposed `source_quote`:

```text
The home must meet a minimum oil consumption baseline of 500 Ltrs. annually. Proof of oil consumption from the 12 months prior to application must be submitted at the time of application, such as receipts, fuel bills or invoices.
```

Nearby preceding requirement context:

- P1078: Rebate requirements:
- P1081: The home must be primarily heated by oil. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.
- P1085: The home must meet a minimum oil consumption baseline of 500 Ltrs. annually. Proof of oil consumption from the 12 months prior to application must be submitted at the time of application, such as receipts, fuel bills or invoices.

### `ashp_oil_existing_heat_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1082`
- Proposed source paragraph: `1081`

Annotation text:

> [genai-rule = ashp_oil_existing_heat_context_present

Proposed `source_quote`:

```text
The home must be primarily heated by oil. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.
```

Nearby preceding requirement context:

- P1077: AIR SOURCE HEAT PUMP (CONVERT FROM OIL)
- P1078: Rebate requirements:
- P1081: The home must be primarily heated by oil. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.

### `ashp_oil_ohpa_product_validation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1105`
- Proposed source paragraph: `1104`

Annotation text:

> Coderule = ashp_oil_ohpa_product_validation

Proposed `source_quote`:

```text
be listed as a qualifying system on the Natural Resources Canada Oil to Heat Pump Affordability Qualified Heat Pump Product List for British Columbia.
```

Nearby preceding requirement context:

- P1100: replace the existing fossil fuel heating system and all fossil fuel heating equipment (piping, appliances, fuel containers, vents and associated infrastructure) must be removed in accordance with all applicable laws.
- P1101: Rc,dRc,dhave an AHRI certified reference number that references all components of the heat pump.
- P1104: be listed as a qualifying system on the Natural Resources Canada Oil to Heat Pump Affordability Qualified Heat Pump Product List for British Columbia.

### `ashp_oil_rebate_math_within_cap`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1228`
- Proposed source paragraph: `1226`

Annotation text:

> [code-rule = ashp_oil_rebate_math_within_cap]

Proposed `source_quote`:

```text
**Eligible homes must be located north of and including the District of 100 Mile House (latitude 51.628°N) and must be connected to BC Hydro electric service.
```

Nearby preceding requirement context:

- P1218: approved single-head mini-split heat pump
- P1225: \*A ducted mini-split that has two supply outlets is eligible for the same rebate value as a 2-Head Multi-spit heat pump.
- P1226: \*\*Eligible homes must be located north of and including the District of 100 Mile House (latitude 51.628°N) and must be connected to BC Hydro electric service.

### `ashp_wood_backup_heat_not_fossil_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `714`
- Proposed source paragraph: `713`

Annotation text:

> [GENAI-RULE = ashp_wood_backup_heat_not_fossil_present

Proposed `source_quote`:

```text
The back-up heating system must be wood or electric. Fossil fuel back-up systems (e.g. dual fuel ducted heat pumps or standalone fossil fuel heating systems) are not eligible for wood-to-heat pump upgrades.
```

Nearby preceding requirement context:

- P705: be listed as a qualifying system on the Qualified Heat Pump Product List.
- P710: RRbe installed in accordance with the Heat Pump Best Practices Installation Guide for Existing Homes.
- P713: The back-up heating system must be wood or electric. Fossil fuel back-up systems (e.g. dual fuel ducted heat pumps or standalone fossil fuel heating systems) are not eligible for wood-to-heat pump upgrades.

### `ashp_wood_existing_heat_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `693`
- Proposed source paragraph: `690`

Annotation text:

> [GENAI-RULE = ashp_wood_existing_heat_context_present

Proposed `source_quote`:

```text
The home must primarily be heated by a wood or solid fuel heating system (wood or pellet stove, insert or furnace). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C
```

Nearby preceding requirement context:

- P681: Wood to heat pump upgrade rebates are only eligible for participants who are registered and approved as Income Level 1 or 2 in the CleanBC Better Homes Energy Savings Program.
- P687: Maximum one primary space heating system rebate per home, regardless of the number of systems installed.
- P690: The home must primarily be heated by a wood or solid fuel heating system (wood or pellet stove, insert or furnace). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C

### `ashp_wood_removal_or_wett_supporting_document_attached`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `830`
- Proposed source paragraph: `828`

Annotation text:

> [GENAI-RULE = ashp_wood_removal_or_wett_supporting_document_attached

Proposed `source_quote`:

```text
The inspection report must be dated within the 12-month period before or 6-month period following the date of the heat pump installation invoice and include the inspector’s WETT certification number, the site address of the wood or solid fuel heating system, and whether the installation is compliant with relevant codes.
```

Nearby preceding requirement context:

- P824: L3,4L3,4Before and after photos of the wood or solid fuel heating system if it is removed.
- P827: Copy of an inspection report completed by a Wood Energy Technology Transfer Inc. (WETT)-certified professional if the wood or solid fuel heating system is being retained in safe and working order.
- P828: The inspection report must be dated within the 12-month period before or 6-month period following the date of the heat pump installation invoice and include the inspector’s WETT certification number, the site address of the wood or solid fuel heating system, and whether the installation is compliant with relevant codes.

### `atw_rebate_math_within_cap`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1612`
- Proposed source paragraph: `1610`

Annotation text:

> Code-rule = atw_rebate_math_within_cap

Proposed `source_quote`:

```text
*Eligible homes must be located north of and including the District of 100 Mile House (latitude 51.628°N) and must be connected to BC Hydro electric service.
```

Nearby preceding requirement context:

- P1601: Northern top-up\*
- P1602: Eligible for program approved air-to-water and combined heat
- P1610: \*Eligible homes must be located north of and including the District of 100 Mile House (latitude 51.628°N) and must be connected to BC Hydro electric service.

### `cshp_rebate_math_within_cap`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1613`
- Proposed source paragraph: `1610`

Annotation text:

> Code-rule = cshp_rebate_math_within_cap

Proposed `source_quote`:

```text
*Eligible homes must be located north of and including the District of 100 Mile House (latitude 51.628°N) and must be connected to BC Hydro electric service.
```

Nearby preceding requirement context:

- P1601: Northern top-up\*
- P1602: Eligible for program approved air-to-water and combined heat
- P1610: \*Eligible homes must be located north of and including the District of 100 Mile House (latitude 51.628°N) and must be connected to BC Hydro electric service.

### `current_invoice_cannot_contain_multiple_space_systems`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `168`
- Proposed source paragraph: `155`

Annotation text:

> [CODE RULE = current_invoice_cannot_contain_multiple_space_systems

Proposed `source_quote`:

```text
Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade
```

Nearby preceding requirement context:

- P148: All upgrades must be installed by a Registered Contractor, as defined by the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions. To find a Registered Contractor, use the Find
- P149: a Contractor search tool or email betterhomesESP@clearesult.com. Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.
- P155: Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade

### `dfhp_existing_heat_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1276`
- Proposed source paragraph: `1275`

Annotation text:

> [Genai-rule = dfhp_existing_heat_context_present

Proposed `source_quote`:

```text
The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.
```

Nearby preceding requirement context:

- P1271: DUAL - AIR SOURCE HEAT PUMP WITH FOSSIL FUEL BACK-UP (DUAL FUEL DUCTED HEAT PUMP)
- P1272: Rebate requirements:
- P1275: The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG). A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.

### `dfhp_heat_load_calc_supporting_document_acceptable`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1324`
- Proposed source paragraph: `1321`

Annotation text:

> [genai-rule = dfhp_heat_load_calc_supporting_document_acceptable

Proposed `source_quote`:

```text
A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted. Supplemental heating from other electric or non-fossil fuel heating systems may be considered in the heat load calculation. Supplemental heating from fossil fuel heating systems (e.g. gas fireplace) cannot be considered in the heat load calculation. If you’re unsure if your current heat load calculation methodology meets the program criteria, please contact betterhomesbc@gov.bc.ca.
```

Nearby preceding requirement context:

- P1317: have an AHRI certified reference number that references the outdoor unit and the indoor unit(s) of the heat pump, and the furnace model number.
- P1320: be installed in accordance with the Heat Pump Best Practices Installation Guide for Existing Homes.
- P1321: A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted. Supplemental heating from other electric or non-fossil fuel heating systems may be considered in the heat load calculation. Supplemental heating from fossil fuel heating systems (e.g. gas fireplace) cannot be considered in the heat load calculation. If you’re unsure if your current heat load calculation methodology meets the program criteria, please contact betterhomesbc@gov.bc.ca.

### `dfhp_switchover_setpoint_specific`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1307`
- Proposed source paragraph: `1305`

Annotation text:

> [Genai-rule = dfhp_switchover_setpoint_specific

Proposed `source_quote`:

```text
Southern Interior and Northern B.C. regions: ≤2°C
```

Nearby preceding requirement context:

- P1301: RbRbhave the thermostat, outdoor temperature switch-over control or equipment control board set to the following region-specific temperatures for the duration of the product lifetime:
- P1304: Lower Mainland and Vancouver Island regions: ≤5°C
- P1305: Southern Interior and Northern B.C. regions: ≤2°C

### `eligibility_code_found_in_database`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `126`
- Proposed source paragraph: `121`

Annotation text:

> Code-rule = eligibility_code_found_in_database

Proposed `source_quote`:

```text
Eligibility codes for applications received on or after June 18, 2024, are valid for upgrades completed within 6 months of the participants approval date. Beyond this date participants must re-apply to determine their eligibility.
```

Nearby preceding requirement context:

- P114: For participants registering in the CleanBC Energy Savings Program as Income Level 3 on or after April 1, 2026, the property must have a total assessed value at or under $1,820,000 in the BC Assessment listing for the address of the applicant’s home in the year of program registration.
- P117: Participants must pre-register and confirm eligibility prior to installing upgrades. Following pre-registration, eligible participants will receive an eligibility code.
- P121: Eligibility codes for applications received on or after June 18, 2024, are valid for upgrades completed within 6 months of the participants approval date. Beyond this date participants must re-apply to determine their eligibility.

### `eligibility_code_valid_for_invoice_date`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `130`
- Proposed source paragraph: `121`

Annotation text:

> [CODE RULE = eligibility_code_valid_for_invoice_date

Proposed `source_quote`:

```text
Eligibility codes for applications received on or after June 18, 2024, are valid for upgrades completed within 6 months of the participants approval date. Beyond this date participants must re-apply to determine their eligibility.
```

Nearby preceding requirement context:

- P114: For participants registering in the CleanBC Energy Savings Program as Income Level 3 on or after April 1, 2026, the property must have a total assessed value at or under $1,820,000 in the BC Assessment listing for the address of the applicant’s home in the year of program registration.
- P117: Participants must pre-register and confirm eligibility prior to installing upgrades. Following pre-registration, eligible participants will receive an eligibility code.
- P121: Eligibility codes for applications received on or after June 18, 2024, are valid for upgrades completed within 6 months of the participants approval date. Beyond this date participants must re-apply to determine their eligibility.

### `esu_contractor_utility_billed_work_on_one_invoice`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1808`
- Proposed source paragraph: `1807`

Annotation text:

> Genai-rule = esu_contractor_utility_billed_work_on_one_invoice

Proposed `source_quote`:

```text
To be eligible for the electrical service upgrade the electrician and/or heat pump contractor completing the electrical service upgrade must manage the line upgrade with the electrical utility (BC Hydro or FortisBC) that the home is connected to. Either the contractor or the participant can be billed by the utility for the line upgrade. If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice. See the sample invoice or contact betterhomesESP@clearesult.com.
```

Nearby preceding requirement context:

- P1796: weather head alteration or replacement.
- P1800: Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible.
- P1807: To be eligible for the electrical service upgrade the electrician and/or heat pump contractor completing the electrical service upgrade must manage the line upgrade with the electrical utility (BC Hydro or FortisBC) that the home is connected to. Either the contractor or the participant can be billed by the utility for the line upgrade. If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice. See the sample invoice or contact betterhomesESP@clearesult.com.

### `esu_heat_pump_conversion_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1774`
- Proposed source paragraph: `1773`

Annotation text:

> New genai-rule = esu_heat_pump_conversion_context_present

Proposed `source_quote`:

```text
Only homes that convert from a fossil fuel (oil, propane or natural gas) primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program are eligible. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.
```

Nearby preceding requirement context:

- P1769: ELECTRICAL SERVICE UPGRADE
- P1770: Rebate requirements:
- P1773: Only homes that convert from a fossil fuel (oil, propane or natural gas) primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program are eligible. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.

### `esu_not_panel_only_or_connection_only`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1803`
- Proposed source paragraph: `1800`

Annotation text:

> Genai-rule = esu_not_panel_only_or_connection_only

Proposed `source_quote`:

```text
Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible.
```

Nearby preceding requirement context:

- P1795: conduit replacement, meter base alterations or replacements.
- P1796: weather head alteration or replacement.
- P1800: Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible.

### `esu_rebate_math_within_cap`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1849`
- Proposed source paragraph: `1847`

Annotation text:

> Code-rule = esu_rebate_math_within_cap

Proposed `source_quote`:

```text
Maximum of one electrical service upgrade per home
```

Nearby preceding requirement context:

- P1845: 100% of eligible upgrade costs, up to a maximum of
- P1846: $1,500 per home
- P1847: Maximum of one electrical service upgrade per home

### `esu_service_size_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1786`
- Proposed source paragraph: `1783`

Annotation text:

> Genai-rule = esu_service_size_present (the 100,200 or 400 check)

Proposed `source_quote`:

```text
The service upgrade (new wire) is for upgrading to 100, 200 or 400-amp service to an existing home and must be installed within six months of the heat pump installation.
```

Nearby preceding requirement context:

- P1773: Only homes that convert from a fossil fuel (oil, propane or natural gas) primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program are eligible. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.
- P1780: The electric service (new wire) must be upgraded by the participants electrical utility (BC Hydro or FortisBC).
- P1783: The service upgrade (new wire) is for upgrading to 100, 200 or 400-amp service to an existing home and must be installed within six months of the heat pump installation.

### `esu_timing_within_six_months_of_heat_pump_installation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1787`
- Proposed source paragraph: `1783`

Annotation text:

> And code-rule for date math, code-rule = esu_timing_within_six_months_of_heat_pump_installation

Proposed `source_quote`:

```text
The service upgrade (new wire) is for upgrading to 100, 200 or 400-amp service to an existing home and must be installed within six months of the heat pump installation.
```

Nearby preceding requirement context:

- P1773: Only homes that convert from a fossil fuel (oil, propane or natural gas) primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program are eligible. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.
- P1780: The electric service (new wire) must be upgraded by the participants electrical utility (BC Hydro or FortisBC).
- P1783: The service upgrade (new wire) is for upgrading to 100, 200 or 400-amp service to an existing home and must be installed within six months of the heat pump installation.

### `esu_utility_upgrade_supporting_document_attached`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1781`
- Proposed source paragraph: `1780`

Annotation text:

> Genai-rule = esu_utility_upgrade_supporting_document_attached

Proposed `source_quote`:

```text
The electric service (new wire) must be upgraded by the participants electrical utility (BC Hydro or FortisBC).
```

Nearby preceding requirement context:

- P1770: Rebate requirements:
- P1773: Only homes that convert from a fossil fuel (oil, propane or natural gas) primary space and/or water heating system to a heat pump through the CleanBC Energy Savings Program are eligible. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C.
- P1780: The electric service (new wire) must be upgraded by the participants electrical utility (BC Hydro or FortisBC).

### `homeowner_identity_matches_eligibility_record`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `120`
- Proposed source paragraph: `117`
- Notes: annotation contains commentary; confirm quote pairing

Annotation text:

> This is a genai rule homeowner_identity_matches_eligibility_record

Proposed `source_quote`:

```text
Participants must pre-register and confirm eligibility prior to installing upgrades. Following pre-registration, eligible participants will receive an eligibility code.
```

Nearby preceding requirement context:

- P113: For participants registering in the CleanBC Energy Savings Program as Income Level 1 or 2 on or after April 1, 2026, the property must have a total assessed value at or under $1,200,000 in the BC Assessment listing for the address of the applicant’s home in the year of program registration.
- P114: For participants registering in the CleanBC Energy Savings Program as Income Level 3 on or after April 1, 2026, the property must have a total assessed value at or under $1,820,000 in the BC Assessment listing for the address of the applicant’s home in the year of program registration.
- P117: Participants must pre-register and confirm eligibility prior to installing upgrades. Following pre-registration, eligible participants will receive an eligibility code.

### `hp_ahri_product_validation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `490`
- Proposed source paragraph: `489`

Annotation text:

> [CODE-RULE = hp_ahri_product_validation

Proposed `source_quote`:

```text
be listed as a qualifying system on the Qualified Heat Pump Product List.
```

Nearby preceding requirement context:

- P480: serve a main living area (e.g. family room, living room or open-concept kitchen-living room).
- P485: have an AHRI certified reference number that references all components of the heat pump.
- P489: be listed as a qualifying system on the Qualified Heat Pump Product List.

### `hp_fossil_backup_not_fossil_primary`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `882`
- Proposed source paragraph: `879`

Annotation text:

> [GENAI-RULE = hp_fossil_backup_not_fossil_primary

Proposed `source_quote`:

```text
The back-up heating system must be electric or wood. Homes with a natural gas or propane fireplaces are able to retain the fireplace, if the fireplace is a secondary heating system.
```

Nearby preceding requirement context:

- P875: Homes in Non-Integrated Areas of the electricity grid must contact betterhomesbc@gov.bc.ca for pre-approval prior to installation.
- P876: Heat pumps with a maximum static pressure of less than 0.6” Water Column (WC) are considered ductless mini-split or ductless multi-split systems.
- P879: The back-up heating system must be electric or wood. Homes with a natural gas or propane fireplaces are able to retain the fireplace, if the fireplace is a secondary heating system.

### `hp_no_existing_or_secondary_heat_pump_flag`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `500`
- Proposed source paragraph: `499`

Annotation text:

> [genai-rule hp_no_existing_or_secondary_heat_pump_flag

Proposed `source_quote`:

```text
Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.
```

Nearby preceding requirement context:

- P489: be listed as a qualifying system on the Qualified Heat Pump Product List.
- P495: RRbe installed in accordance with the Heat Pump Best Practices Installation Guide for Existing Homes.
- P499: Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible.

### `hpwh_neea_product_validation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1666`
- Proposed source paragraph: `1665`

Annotation text:

> Code rule = hpwh_neea_product_validation

Proposed `source_quote`:

```text
Eligible systems are listed as Tier 2 or higher on NEEA’s Advanced Water Heater Specification Qualified Products List for Heat Pump Water Heaters.
```

Nearby preceding requirement context:

- P1658: Rebate requirements:
- P1661: The existing water heater being replaced must be the home’s primary water heater.
- P1665: Eligible systems are listed as Tier 2 or higher on NEEA’s Advanced Water Heater Specification Qualified Products List for Heat Pump Water Heaters.

### `hpwh_no_existing_or_secondary_hpwh_flag`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1676`
- Proposed source paragraph: `1673`

Annotation text:

> Genai-rule = hpwh_no_existing_or_secondary_hpwh_flag

Proposed `source_quote`:

```text
Replacing or adding a secondary heat pump water heater to a home with an existing heat pump water heater is not eligible.
```

Nearby preceding requirement context:

- P1661: The existing water heater being replaced must be the home’s primary water heater.
- P1665: Eligible systems are listed as Tier 2 or higher on NEEA’s Advanced Water Heater Specification Qualified Products List for Heat Pump Water Heaters.
- P1673: Replacing or adding a secondary heat pump water heater to a home with an existing heat pump water heater is not eligible.

### `hpwh_primary_replacement_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1664`
- Proposed source paragraph: `1661`

Annotation text:

> Genai rule = hpwh_primary_replacement_context_present

Proposed `source_quote`:

```text
The existing water heater being replaced must be the home’s primary water heater.
```

Nearby preceding requirement context:

- P1657: HEAT PUMP (HOT) WATER HEATER
- P1658: Rebate requirements:
- P1661: The existing water heater being replaced must be the home’s primary water heater.

### `hs_associated_upgrade_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1877`
- Proposed source paragraph: `1874`

Annotation text:

> Genai rule = hs_associated_upgrade_present

Proposed `source_quote`:

```text
RRcompleted in association with an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for health and safety remediation on its own.
```

Nearby preceding requirement context:

- P1868: RRfor existing health and safety issues in the home.
- P1873: required to enable the safe installation and operation of a CleanBC Energy Savings Program rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade.
- P1874: RRcompleted in association with an eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for health and safety remediation on its own.

### `hs_before_after_photos_attached`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1927`
- Proposed source paragraph: `1924`

Annotation text:

> Genai-rule = hs_before_after_photos_attached

Proposed `source_quote`:

```text
Before and after photos of the health and safety issue that was remediated.
```

Nearby preceding requirement context:

- P1916: Supporting documentation:
- P1919: Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.
- P1924: Before and after photos of the health and safety issue that was remediated.

### `hs_issue_type_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1871`
- Proposed source paragraph: `1868`

Annotation text:

> Genai rule = hs_issue_type_present

Proposed `source_quote`:

```text
RRfor existing health and safety issues in the home.
```

Nearby preceding requirement context:

- P1866: Rebate requirements:
- P1867: Remediation must be:
- P1868: RRfor existing health and safety issues in the home.

### `hs_rebate_math_within_cap`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1914`
- Proposed source paragraph: `1911`

Annotation text:

> Code-rule hs_rebate_math_within_cap

Proposed `source_quote`:

```text
60% of eligible upgrade costs, up to a maximum of $800 per home
```

Nearby preceding requirement context:

- P1907: insulation or window/door upgrade
- P1909: 95% of eligible upgrade costs, up to a maximum of $800 per home
- P1911: 60% of eligible upgrade costs, up to a maximum of $800 per home

### `hydronic_awhp_product_validation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1477`
- Proposed source paragraph: `1476`

Annotation text:

> [code-rule = hydronic_awhp_product_validation

Proposed `source_quote`:

```text
be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List.
```

Nearby preceding requirement context:

- P1472: be sized to function as the primary heating system for the home.
- P1473: RcRcserve a main living area (e.g. family room, living room or open-concept kitchen-living room).
- P1476: be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List.

### `hydronic_conversion_context_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1468`
- Proposed source paragraph: `1467`

Annotation text:

> [Genai-rule hydronic_conversion_context_present]

Proposed `source_quote`:

```text
The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.
```

Nearby preceding requirement context:

- P1463: ALSO - ‘Combined AIR-TO-WATER space heater HEAT PUMP + water heater’ embedded section (confusing)
- P1464: Rebate requirements:
- P1467: The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood. A primary heating system must have the capacity to heat a minimum of 50% of the home for the entire heating season to 21°C. A fireplace is not considered a primary heating system.

### `hydronic_wood_removal_or_wett_supporting_document_attached`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1647`
- Proposed source paragraph: `1645`

Annotation text:

> Genai-rule = hydronic_wood_removal_or_wett_supporting_document_attached

Proposed `source_quote`:

```text
The inspection report must be dated within the 12-month period before or 6-month period following the date of the heat pump installation invoice and include the inspector’s WETT certification number, the site address of the wood or solid fuel heating system, and whether the installation is compliant with relevant codes.
```

Nearby preceding requirement context:

- P1639: Before and after photos of the wood or solid fuel heating system if the heat pump replaced a wood or solid fuel heating system and is removed.
- P1642: Copy of an inspection report completed by a Wood Energy Technology Transfer Inc. (WETT)-certified professional if the heat pump replaced a wood or solid fuel heating system and it is being retained in safe and working order.
- P1645: The inspection report must be dated within the 12-month period before or 6-month period following the date of the heat pump installation invoice and include the inspector’s WETT certification number, the site address of the wood or solid fuel heating system, and whether the installation is compliant with relevant codes.

### `income_level_1_or_2_required`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `443`
- Proposed source paragraph: `442`

Annotation text:

> [CODE-RULE = income_level_1_or_2_required

Proposed `source_quote`:

```text
Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2 in the CleanBC Better Homes Energy Savings Program.
```

Nearby preceding requirement context:

- P436: AIR SOURCE HEAT PUMP (CONVERT FROM ELECTRIC)
- P438: Rebate requirements:
- P442: Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2 in the CleanBC Better Homes Energy Savings Program.

### `overall_invoice_arithmetic_consistent`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `635`
- Proposed source paragraph: `633`

Annotation text:

> There are 2 common rules above implied: GENAI-RULE overall_invoice_arithmetic_consistent & GENAI-RULE = rebate_line_evidence_present

Proposed `source_quote`:

```text
Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.
```

Nearby preceding requirement context:

- P629: At the outside winter design temperature, required heating facilities shall be capable of maintaining an indoor air temperature of not less than 22°C in all living spaces, 18°C in unfinished basements, common service rooms, ancillary spaces and exits in houses with a secondary suite, and 15°C in heated crawl spaces.
- P630: Supporting documentation:
- P633: Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.

### `overall_rebate_not_over_invoice_total`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `191`
- Proposed source paragraph: `188`

Annotation text:

> [GENAI - Rule = overall_rebate_not_over_invoice_total

Proposed `source_quote`:

```text
Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade.
```

Nearby preceding requirement context:

- P183: Indigenous Communities Conservation Program; or
- P185: Indigenous Community Heat Pump Incentive.
- P188: Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade.

### `overall_rebate_not_over_paid_cost_of_upgrade`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `200`
- Proposed source paragraph: `188`

Annotation text:

> [genai rule = overall_rebate_not_over_paid_cost_of_upgrade

Proposed `source_quote`:

```text
Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade.
```

Nearby preceding requirement context:

- P183: Indigenous Communities Conservation Program; or
- P185: Indigenous Community Heat Pump Incentive.
- P188: Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade.

### `prior_same_upgrade_type_rebate_payment_found`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `158`
- Proposed source paragraph: `155`

Annotation text:

> [CODE RULE = prior_same_upgrade_type_rebate_payment_found

Proposed `source_quote`:

```text
Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade
```

Nearby preceding requirement context:

- P148: All upgrades must be installed by a Registered Contractor, as defined by the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions. To find a Registered Contractor, use the Find
- P149: a Contractor search tool or email betterhomesESP@clearesult.com. Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.
- P155: Participants may only receive one rebate payment for a primary heating system (a central ducted heat pump, ductless mini-split heat pump, ductless multi-split heat pump, dual fuel ducted heat pump, air-to-water heat pump, combined air-to-water heat pump, natural gas furnace, boiler or combination space heating and hot water system), one rebate payment for a heat pump water heater, one rebate payment for an insulation upgrade, and one rebate for a windows and doors upgrade

### `rebate_line_evidence_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `635`
- Proposed source paragraph: `633`

Annotation text:

> There are 2 common rules above implied: GENAI-RULE overall_invoice_arithmetic_consistent & GENAI-RULE = rebate_line_evidence_present

Proposed `source_quote`:

```text
Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.
```

Nearby preceding requirement context:

- P629: At the outside winter design temperature, required heating facilities shall be capable of maintaining an indoor air temperature of not less than 22°C in all living spaces, 18°C in unfinished basements, common service rooms, ancillary spaces and exits in houses with a secondary suite, and 15°C in heated crawl spaces.
- P630: Supporting documentation:
- P633: Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.

### `submission_within_six_months`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `650`
- Proposed source paragraph: `648`

Annotation text:

> [CODE-RULE = submission_within_six_months

Proposed `source_quote`:

```text
The rebate application and supporting documentation must be submitted by the Registered Contractor within six (6) months of the invoice date.
```

Nearby preceding requirement context:

- P633: Invoice (see sample invoice for requirements), which must show the itemized CleanBC rebate and deduct the CleanBC rebate from the total amount owed by the participant. The rebate must be accurately calculated in accordance with the participant’s income level and the Rebate Eligibility Requirements.
- P644: A CSA-F280-12 Heat Load Calculation may be requested to confirm the heat pump system is adequately sized.
- P648: The rebate application and supporting documentation must be submitted by the Registered Contractor within six (6) months of the invoice date.

### `vent_associated_upgrade_present`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `genai`
- Annotation paragraph: `1942`
- Proposed source paragraph: `1941`

Annotation text:

> Genai-rule = vent_associated_upgrade_present

Proposed `source_quote`:

```text
be installed in association with a CleanBC Energy Savings Program rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for ventilation upgrades on their own.
```

Nearby preceding requirement context:

- P1937: Rebate requirements:
- P1940: Ventilation upgrades must:
- P1941: be installed in association with a CleanBC Energy Savings Program rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. Rebates will not be paid for ventilation upgrades on their own.

### `vent_fan_capacity_meets_minimum`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1981`
- Proposed source paragraph: `1980`

Annotation text:

> code rule = vent_fan_capacity_meets_minimum

Proposed `source_quote`:

```text
fans must have a capacity of at least 85 cfm (40 L/s), at static pressure of 50 pa (0.2” w.c.).
```

Nearby preceding requirement context:

- P1969: Department of Energy’s searchable product list.
- P1973: UbUbfans must be ducted directly to the outside of the premises and at least one fan must be installed in the main bathroom, which contains a bathtub and/or shower.
- P1980: fans must have a capacity of at least 85 cfm (40 L/s), at static pressure of 50 pa (0.2” w.c.).

### `vent_fan_energy_star_product_validation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1970`
- Proposed source paragraph: `1969`

Annotation text:

> Code rule = vent_fan_energy_star_product_validation

Proposed `source_quote`:

```text
Department of Energy’s searchable product list.
```

Nearby preceding requirement context:

- P1967: Bathroom fan systems must meet the following requirements:
- P1968: fans must be ENERGY STAR® certified and listed on the US Environmental Protection Agency and US
- P1969: Department of Energy’s searchable product list.

### `vent_herv_nrcan_product_validation`

- Bucket: `AUTO_APPLY_CANDIDATE`
- Rule type: `code`
- Annotation paragraph: `1953`
- Proposed source paragraph: `1952`

Annotation text:

> Code rule = vent_herv_nrcan_product_validation

Proposed `source_quote`:

```text
heat/energy recovery ventilators must be ENERGY STAR® certified and listed on Natural Resource’s Canada’s searchable product list.
```

Nearby preceding requirement context:

- P1947: result in improved air circulation in the home.
- P1951: Heat/energy recovery ventilators must meet the following requirements:
- P1952: heat/energy recovery ventilators must be ENERGY STAR® certified and listed on Natural Resource’s Canada’s searchable product list.

## Ask Stephen

### `ashp_electric_wood_rebate_math_within_cap`

- Bucket: `ASK_STEPHEN`
- Rule type: `code`
- Annotation paragraph: `595`
- Proposed source paragraph: `574`
- Notes: quote is short or likely a table fragment

Annotation text:

> [CODE-RULE = ashp_electric_wood_rebate_math_within_cap

Proposed `source_quote`:

```text
3.Minimum capacity of 12,000 BTU (1 ton)
```

Nearby preceding requirement context:

- P569: 15.2, HSPF2 ≥ 8.5 (Region IV)
- P570: 2.Variable speed compressor
- P574: 3.Minimum capacity of 12,000 BTU (1 ton)

### `ashp_fossil_fuel_removal_supporting_document_attached`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Word doc key: `ashp_gas_propane_removal_supporting_document_attached`
- Annotation paragraph: `1066`
- Proposed source paragraph: `1065`
- Notes: doc annotation uses old/stale key `ashp_gas_propane_removal_supporting_document_attached`; quote is short or likely a table fragment

Annotation text:

> [genai-rule = ashp_gas_propane_removal_supporting_document_attached

Proposed `source_quote`:

```text
date of removal.
```

Nearby preceding requirement context:

- P1063: invoice from the removal company or heat pump installation company, which must include:
- P1064: description of the work completed (e.g. the oil system, including oil tank, was removed according to applicable regulations and local government bylaws).
- P1065: date of removal.

### `ashp_fossil_northern_top_up_within_cap`

- Bucket: `ASK_STEPHEN`
- Rule type: `code`
- Word doc key: `ashp_gas_propane_northern_top_up_within_cap`
- Annotation paragraph: `1008`
- Proposed source paragraph: `978`
- Notes: doc annotation uses old/stale key `ashp_gas_propane_northern_top_up_within_cap`

Annotation text:

> [CODE-RULE ashp_gas_propane_northern_top_up_within_cap

Proposed `source_quote`:

```text
Eligible for program approved single-head mini-split heat
```

Nearby preceding requirement context:

- P970: Eligible for program approved central ducted, multi-split and 2 single-head mini-split heat pumps
- P977: Northern top-up\*
- P978: Eligible for program approved single-head mini-split heat

### `ashp_multisplit_minimum_two_indoor_heads`

- Bucket: `ASK_STEPHEN`
- Rule type: `code`
- Word doc key: `ashp_electric_multisplit_minimum_two_indoor_heads`
- Annotation paragraph: `613`
- Proposed source paragraph: `574`
- Notes: doc annotation uses old/stale key `ashp_electric_multisplit_minimum_two_indoor_heads`; quote is short or likely a table fragment

Annotation text:

> [CODE RULE = ashp_electric_multisplit_minimum_two_indoor_heads

Proposed `source_quote`:

```text
3.Minimum capacity of 12,000 BTU (1 ton)
```

Nearby preceding requirement context:

- P569: 15.2, HSPF2 ≥ 8.5 (Region IV)
- P570: 2.Variable speed compressor
- P574: 3.Minimum capacity of 12,000 BTU (1 ton)

### `ashp_product_specs_meet_requirements`

- Bucket: `ASK_STEPHEN`
- Rule type: `code`
- Word doc key: `ashp_electric_product_specs_meet_requirements`
- Annotation paragraph: `602`
- Proposed source paragraph: `574`
- Notes: doc annotation uses old/stale key `ashp_electric_product_specs_meet_requirements`; quote is short or likely a table fragment

Annotation text:

> [CODE RULE = ashp_electric_product_specs_meet_requirements

Proposed `source_quote`:

```text
3.Minimum capacity of 12,000 BTU (1 ton)
```

Nearby preceding requirement context:

- P569: 15.2, HSPF2 ≥ 8.5 (Region IV)
- P570: 2.Variable speed compressor
- P574: 3.Minimum capacity of 12,000 BTU (1 ton)

### `contractor_identity_matches_record`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Annotation paragraph: `151`
- Proposed source paragraph: `149`
- Notes: annotation contains commentary; confirm quote pairing

Annotation text:

> First, we check that the contractor-company on the invoice pdf matches the contractor (the staff submitting is staff to a contractor-company) via rule geanai-rule contractor_identity_matches_record

Proposed `source_quote`:

```text
a Contractor search tool or email betterhomesESP@clearesult.com. Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.
```

Nearby preceding requirement context:

- P141: Organizations which are approved by the Province of British Columbia and which act to the benefit of other persons who meet the requirements defined in these Rebate Eligibility Requirements may also be accepted as Participants in the CleanBC Better Homes Energy Savings Program. Contact betterhomesESP@clearesult.com for pre-approval if this applies to you.
- P148: All upgrades must be installed by a Registered Contractor, as defined by the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions. To find a Registered Contractor, use the Find
- P149: a Contractor search tool or email betterhomesESP@clearesult.com. Registered Contractors must comply with the CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions.

### `dfhp_fossil_fuel_removal_or_modification_supporting_document_attached`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Annotation paragraph: `1446`
- Proposed source paragraph: `1444`
- Notes: quote is short or likely a table fragment

Annotation text:

> [Genai-rule = dfhp_fossil_fuel_removal_or_modification_supporting_document_attached]

Proposed `source_quote`:

```text
date of removal or modification.
```

Nearby preceding requirement context:

- P1442: invoice from the removal or modification company or heat pump installation company, which must include:
- P1443: description of work completed pertaining to removal or modification, as applicable for the upgrade.
- P1444: date of removal or modification.

### `esu_eligible_expense_lines_present`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Annotation paragraph: `1798`
- Proposed source paragraph: `1796`
- Notes: quote is short or likely a table fragment

Annotation text:

> Genai-rule = esu_eligible_expense_lines_present

Proposed `source_quote`:

```text
weather head alteration or replacement.
```

Nearby preceding requirement context:

- P1794: service mast alterations or replacement.
- P1795: conduit replacement, meter base alterations or replacements.
- P1796: weather head alteration or replacement.

### `hpwh_fossil_removal_supporting_document_attached`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Annotation paragraph: `1760`
- Proposed source paragraph: `1759`
- Notes: quote is short or likely a table fragment

Annotation text:

> Genai-rule = hpwh_fossil_removal_supporting_document_attached

Proposed `source_quote`:

```text
date of removal.
```

Nearby preceding requirement context:

- P1757: invoice from the removal company or heat pump water heater installation company, which must include:
- P1758: description of work completed (e.g. the gas water heater was removed according to applicable regulations and local government bylaws).
- P1759: date of removal.

### `hpwh_rebate_math_within_cap`

- Bucket: `ASK_STEPHEN`
- Rule type: `code`
- Annotation paragraph: `1743`
- Proposed source paragraph: `1740`
- Notes: quote is short or likely a table fragment

Annotation text:

> The above table has New code-rule = hpwh_rebate_math_within_cap

Proposed `source_quote`:

```text
number of systems installed
```

Nearby preceding requirement context:

- P1728: regardless of the
- P1739: number of systems installed
- P1740: number of systems installed

### `hs_pre_confirmation_evidence_present`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Annotation paragraph: `1888`
- Proposed source paragraph: `1887`
- Notes: quote is short or likely a table fragment

Annotation text:

> Genai rule = hs_pre_confirmation_evidence_present

Proposed `source_quote`:

```text
betterhomesESP@clearesult.com.
```

Nearby preceding requirement context:

- P1880: LdLdcompleted in accordance with all applicable laws, orders, ordinances, standards, codes and other rules, licenses and permits of all lawful authorities, and in accordance with manufacturer’s specifications, and requirements of Technical Safety BC.
- P1884: RRconfirmed as rebate-eligible prior to beginning remediation. For confirmation, contact
- P1887: betterhomesESP@clearesult.com.

### `hydronic_fossil_fuel_removal_supporting_document_attached`

- Bucket: `ASK_STEPHEN`
- Rule type: `genai`
- Annotation paragraph: `1638`
- Proposed source paragraph: `1637`
- Notes: quote is short or likely a table fragment

Annotation text:

> New genai-rule = hydronic_fossil_fuel_removal_supporting_document_attached

Proposed `source_quote`:

```text
date of removal.
```

Nearby preceding requirement context:

- P1635: invoice from the removal company or heat pump water heater installation company, which must include:
- P1636: description of work completed (e.g. the gas water heater was removed according to applicable regulations and local government bylaws).
- P1637: date of removal.

## Current Seeded Rules With No Annotation Detected

- `dfhp_rebate_math_within_cap` (code)
- `dfhp_product_specs_meet_requirements` (code)
- `heat_pump_northern_top_up_3000_within_cap` (code)
- `hp_product_minimum_capacity_at_minus_5c` (code)
- `hp_product_efficiency_threshold` (code)
- `first_class_invoice_fields_present` (code)
- `vent_rebate_math_within_cap` (code)
- `wd_u_factor_threshold` (code)
- `ins_health_safety_issue_flag` (genai)
- `ins_material_and_location_present` (genai)
- `ins_minimum_r_value_and_boundary_present` (genai)
- `ins_r_value_and_area_present` (genai)
- `ins_rebate_math_within_cap` (genai)
- `ins_supporting_documents_attached` (genai)
- `vent_multiple_ventilation_rebate_or_fan_count_review` (genai)
- `warranty_or_home_insurance_costs_not_claimed` (genai)
- `wd_certification_reference_present` (genai)
- `wd_customer_portion_math_matches` (genai)
- `wd_envelope_replacement_evidence_present` (genai)
- `wd_label_photo_supporting_document_attached` (genai)
- `wd_no_skylights` (genai)
- `wd_per_home_rebate_math_within_cap` (genai)
- `wd_per_unit_rebate_math_within_cap` (genai)
- `wd_preapproval_supporting_document_attached` (genai)
- `wd_rough_opening_evidence_present` (genai)
- `wd_vancouver_municipal_boundary_review` (genai)
