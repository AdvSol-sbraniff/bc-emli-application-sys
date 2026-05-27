"""
Legacy DOCX snapshot generator.

The working source of truth for the tracker is now:
`claims_ai_service_documentation/esp_requirements_impl_tracker_2026.md`

This script should be treated only as historical source material / snapshot tooling.
"""

from pathlib import Path
import os
import shutil
import tempfile

from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

from pypdf import PdfReader


OUT_PATH = Path(
    r"\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
    r"\claims_ai_service_documentation\esp_requirements_impl_tracker_2026.docx"
)
FALLBACK_OUT_PATH = Path(
    r"\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
    r"\claims_ai_service_documentation\esp_requirements_traceability_audit_2026.docx"
)
PDF_PATH = Path(
    r"\\wsl.localhost\Ubuntu\home\sbraniff\bc-emli-application-sys"
    r"\claims_ai_service_documentation\esp_requirements_2026.pdf"
)


SECTIONS = [
    {
        "title": "How To Read This Audit",
        "items": [
            {
                "quote": (
                    "This working document quotes the actual 2026 Energy Savings Program requirement text "
                    "and then marks coverage in red."
                ),
                "status": "Audit method",
                "implemented": [
                    "Only real persisted keys are named here: `rule_key` from `claims.invoice_version_rulechecks` and `code_rule_key` from `claims.code_rules`.",
                    "No made-up requirement labels are used in this document.",
                    "GenAI `rule_key=upgrade_type_evidence_present` is a cross-cutting invoice-domain-evidence rule used to confirm that the invoice text supports the claimed upgrade domain. It is not tied neatly to one single PDF sentence, so it is documented here as a shared audit note rather than attached to just one requirement quote."
                ],
                "missing": [
                    "If a source requirement has no clear implemented check, it is marked `Missing now` with a priority so we can sequence follow-up work."
                ],
                "priority": "N/A",
            }
        ],
    },
    {
        "title": "General Eligibility Requirements",
        "items": [
            {
                "quote": "Effective date: For invoices dated on or after April 1, 2026.",
                "status": "Implemented now",
                "implemented": [
                    "Code `rule_key=source_vintage_applies`."
                ],
                "missing": [],
                "priority": "Low",
            },
            {
                "quote": (
                    "Participant must reside in an income qualified household... Income verification "
                    "documentation must be submitted for each member of the household that is over the age of 18..."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No persisted check currently verifies the underlying household income documents against the requirement text.",
                    "Current implementation relies on the existence of an eligibility code elsewhere, not on validating the listed income-document rules here."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Home must be a year-round primary residence in British Columbia that is at least 12 months old... "
                    "The following types of homes are not eligible..."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No persisted `rule_key` currently enforces home-type, home-age, bulk-application, or ineligible-home exclusions from invoice/database evidence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The home must be connected to a residential account with one of the following utilities... "
                    "The home must be primarily heated by one of the following..."
                ),
                "status": "Partial",
                "implemented": [
                    "Upgrade-specific heat-pump `rule_key`s do check heating-context clues in several sections, for example `ashp_electric_existing_heat_context_present`, `ashp_wood_existing_heat_context_present`, `ashp_gas_propane_existing_heat_context_present`, and `ashp_oil_existing_heat_context_present`."
                ],
                "missing": [
                    "No general persisted check currently validates the eligible-utility list itself.",
                    "No general persisted check currently validates the broader primary-heating requirement across all claim types."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The property must have a total assessed value at or under the referenced BC Assessment listing..."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No persisted `rule_key` or `code_rule_key` currently validates the BC Assessment cap logic."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Participants must pre-register and confirm eligibility prior to installing upgrades. "
                    "Eligibility codes... are valid for upgrades completed within 6 months of the participants approval date."
                ),
                "status": "Partial",
                "implemented": [
                    "Code `rule_key=eligibility_code_valid_for_invoice_date`."
                ],
                "missing": [
                    "No persisted check clearly proves pre-registration occurred before installation; current coverage is mainly date-validity logic tied to the eligibility code."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be installed by a Registered Contractor... Registered Contractors must comply with the "
                    "CleanBC Better Homes Energy Savings Program Registered Contractor Terms and Conditions."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=contractor_identity_matches_record`.",
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces the upstream registered-contractor gate as its own explicit audit result.",
                    "No persisted check currently enforces contractor terms/compliance status directly inside the claims rulecheck layer."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Participants may only receive one rebate payment... under any of the following programs..."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No persisted duplicate-history or cross-program one-rebate-per-upgrade check currently enforces this requirement end to end."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Rebates cannot exceed the cost on the invoice and the paid cost of the upgrade. "
                    "Upgrade costs covered by warranty or home insurance are not eligible for rebates."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=overall_rebate_not_over_invoice_total`.",
                    "GenAI `rule_key=warranty_costs_flag`.",
                    "GenAI `rule_key=overall_invoice_arithmetic_consistent`.",
                    "Code `rule_key=first_class_invoice_fields_present` supports the invoice evidence path."
                ],
                "missing": [
                    "Paid-cost versus financed/credited amounts still depends on visible invoice evidence and may need deeper payment-state integration later."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Utility accounts must be in the name of the resident and/or homeowner... "
                    "If you currently rent your home, the registered property owner must complete the Landlord Consent Form... "
                    "Landlords and/or property owners are only eligible... with two eligible homes..."
                ),
                "status": "Missing now",
                "implemented": [
                    "GenAI `rule_key=homeowner_identity_matches_eligibility_record` covers some identity comparison only."
                ],
                "missing": [
                    "No persisted check currently validates utility-account ownership, landlord consent, or the two-home landlord cap."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Insulation",
        "items": [
            {
                "quote": (
                    "Insulation upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ins_income_level_allows_rebate`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "New insulation must be batt, loose fill, board or spray foam... installed in an eligible location... "
                    "installed between a conditioned and unconditioned space... result in an increased R-value."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ins_material_and_location_present`.",
                    "GenAI `rule_key=ins_minimum_r_value_and_boundary_present`.",
                    "GenAI `rule_key=ins_description_sufficient_for_review`."
                ],
                "missing": [
                    "No persisted check currently proves Best Practice Guide compliance.",
                    "The conditioned/unconditioned-space and heat-loss intent portions still rely on review-oriented interpretation rather than a deterministic validator."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Rebates are calculated based on R-value of the new insulation added... "
                    "If pre-existing insulation was removed... the rebate is calculated on the difference in R-value..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ins_r_value_and_area_present`.",
                    "GenAI `rule_key=ins_rebate_math_within_cap`."
                ],
                "missing": [
                    "No persisted check currently models the pre-existing-insulation-difference calculation path explicitly."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Pest infestations and rodent tunnels... must be resolved prior to installation... "
                    "Any existing health and safety concerns (vermiculite, asbestos, mould)... must be resolved prior to installation..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ins_health_safety_issue_flag`."
                ],
                "missing": [
                    "No persisted check currently proves pest or rodent resolution.",
                    "No persisted supplement workflow currently validates the remediation evidence itself."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install insulation..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this insulation contractor-registration requirement as its own explicit audit result."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Before and after photos of the insulation area... Floor plan drawing... may be requested. "
                    "Invoice... must show the itemized CleanBC rebate and deduct the CleanBC rebate... "
                    "The rebate application... must be submitted... within six (6) months of the invoice date."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ins_supporting_document_reference_present`.",
                    "GenAI `rule_key=rebate_line_evidence_present`.",
                    "Code `rule_key=first_class_invoice_fields_present`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The supplement path does not yet do structured OCR/table validation for the before/after photos or floor-plan evidence."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Windows And Doors",
        "items": [
            {
                "quote": (
                    "Windows and doors upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=wd_income_level_and_vancouver_review`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Pre-approval is required; a quote for windows and doors upgrades must be submitted and approved prior to installation."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=wd_quote_preapproval_reference_present`."
                ],
                "missing": [
                    "Current coverage looks for quote/pre-approval evidence, but there is no persisted system-level workflow validation proving the approval was actually granted."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The new windows and/or doors must replace existing windows and doors in the building envelope... "
                    "skylights are not eligible... be listed with one of the following certification bodies..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=wd_envelope_replacement_evidence_present`.",
                    "GenAI `rule_key=wd_no_skylights`.",
                    "GenAI `rule_key=wd_certification_reference_present`."
                ],
                "missing": [
                    "No persisted check currently proves compliance with the Best Practices for Window and Door Replacement guide.",
                    "Certification-body validation still relies on review-oriented evidence rather than a structured certification lookup."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The number of windows and/or doors eligible for rebates is based on the number of Rough Openings..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=wd_rough_opening_evidence_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install windows and doors..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this windows-and-doors contractor-registration requirement as its own explicit audit result."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Install eligible window/doors with a U-factor of 1.22 (W/m2-K) or less... "
                    "95% or 60% of eligible upgrade costs... $950 per window or door... Homes within the City of Vancouver municipal boundary are not eligible..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=wd_income_level_and_vancouver_review`.",
                    "GenAI `rule_key=wd_per_unit_rebate_math_within_cap`.",
                    "GenAI `rule_key=wd_per_home_rebate_math_within_cap`.",
                    "GenAI `rule_key=wd_customer_portion_math_matches`."
                ],
                "missing": [
                    "No persisted check currently validates the U-factor itself from a structured product source."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "A photo of a manufacturer label from each installed window/door... "
                    "The rebate application... must be submitted... within six (6) months of the invoice date."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=wd_label_photo_reference_present`.",
                    "GenAI `rule_key=wd_description_sufficient_for_review`.",
                    "GenAI `rule_key=rebate_line_evidence_present`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The supplement path does not yet do structured label-photo OCR/validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Air Source Heat Pump (Convert From Electric)",
        "items": [
            {
                "quote": (
                    "Electric to heat pump upgrades are only eligible for participants who are registered and approved as Income Level 1 or 2..."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No electric-to-heat-pump-specific persisted income-level validator currently enforces this source sentence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The home must primarily be heated by electricity... The new heat pump must replace an existing hard-wired electric heating system... "
                    "be sized to function as the primary heating system... serve a main living area..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_electric_existing_heat_context_present`.",
                    "GenAI `rule_key=ashp_electric_primary_system_scope_present`.",
                    "GenAI `rule_key=ashp_electric_main_living_area_or_primary_capacity_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The new heat pump must have an AHRI certified reference number... be listed as a qualifying system on the Qualified Heat Pump Product List... "
                    "SEER / HSPF thresholds... Minimum capacity of 12,000 BTU..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_electric_product_reference_present`.",
                    "Code `code_rule_key=hp_ahri_found_in_product_list`.",
                    "Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.",
                    "Code `code_rule_key=hp_product_efficiency_threshold`."
                ],
                "missing": [
                    "No persisted check currently proves installation-guide compliance."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_electric_no_existing_heat_pump_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... "
                    "The rebate application... must be submitted... within six (6) months of the invoice date."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_electric_rebate_math_within_cap`.",
                    "GenAI `rule_key=ashp_electric_description_sufficient_for_review`.",
                    "GenAI `rule_key=rebate_line_evidence_present`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The F280 support-document path is still review-oriented rather than structured supplement validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Air Source Heat Pump (Convert From Wood)",
        "items": [
            {
                "quote": (
                    "Wood to heat pump upgrade rebates are only eligible for participants who are registered and approved as Income Level 1 or 2..."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No wood-to-heat-pump-specific persisted income-level validator currently enforces this source sentence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The home must primarily be heated by a wood or solid fuel heating system... "
                    "The back-up heating system must be wood or electric. Fossil fuel back-up systems are not eligible..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_wood_existing_heat_context_present`.",
                    "GenAI `rule_key=ashp_wood_backup_and_primary_capacity_review`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The new heat pump must be sized... serve a main living area... have an AHRI certified reference number... "
                    "be listed as a qualifying system on the Qualified Heat Pump Product List..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_wood_product_reference_present`.",
                    "Code `code_rule_key=hp_ahri_found_in_product_list`.",
                    "Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.",
                    "Code `code_rule_key=hp_product_efficiency_threshold`."
                ],
                "missing": [
                    "No persisted check currently proves installation-guide compliance."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The existing wood or solid fuel heating system may be retained in safe and working order or removed... "
                    "Before and after photos... Copy of a WETT-certified inspection report..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_wood_removal_or_wett_reference_present`."
                ],
                "missing": [
                    "The supplement path does not yet do structured validation for the photo evidence or WETT report details."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Replacing, adding to an existing heat pump or adding a secondary heat pump to a home with an existing heat pump is not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_wood_no_existing_heat_pump_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... "
                    "The rebate application... must be submitted... within six (6) months of the invoice date."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_wood_rebate_math_within_cap`.",
                    "GenAI `rule_key=ashp_wood_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The F280 support-document path remains review-oriented rather than structured supplement validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Air Source Heat Pump (Convert From Natural Gas Or Propane)",
        "items": [
            {
                "quote": (
                    "The home must be primarily heated by fossil fuel (natural gas or propane)..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_gas_propane_existing_heat_context_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The new heat pump must be capable of distributing heat throughout all the conditioned space... "
                    "replace the existing fossil fuel heating system... have an AHRI certified reference number... "
                    "be listed as a qualifying system on the Qualified Heat Pump Product List..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_gas_propane_product_reference_present`.",
                    "GenAI `rule_key=ashp_gas_propane_removal_reference_present`.",
                    "Code `code_rule_key=hp_ahri_found_in_product_list`.",
                    "Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.",
                    "Code `code_rule_key=hp_product_efficiency_threshold`."
                ],
                "missing": [
                    "The removal-proof supplement path is not yet structured or deterministic."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_gas_propane_non_integrated_area_review`."
                ],
                "missing": [
                    "Current coverage is review-only; no persisted system integration proves pre-approval happened."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The back-up heating system must be electric or wood... Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_gas_propane_backup_not_fossil_primary`.",
                    "GenAI `rule_key=ashp_gas_propane_no_existing_heat_pump_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... "
                    "Proof of fossil fuel system removal... The rebate application... must be submitted... within six (6) months..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_gas_propane_rebate_math_within_cap`.",
                    "GenAI `rule_key=ashp_gas_propane_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The F280 and removal-proof supplement path is still not structured enough for deterministic validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Air Source Heat Pump (Convert From Oil)",
        "items": [
            {
                "quote": (
                    "The home must be primarily heated by oil... The home must meet a minimum oil consumption baseline of 500 Ltrs. annually..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_oil_existing_heat_context_present`.",
                    "GenAI `rule_key=ashp_oil_consumption_baseline_reference_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The new heat pump must... replace the existing fossil fuel heating system... have an AHRI certified reference number... "
                    "be listed as a qualifying system on the Natural Resources Canada Oil to Heat Pump Affordability Qualified Heat Pump Product List..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_oil_product_reference_present`.",
                    "GenAI `rule_key=ashp_oil_removal_reference_present`.",
                    "Code `code_rule_key=hp_ahri_found_in_product_list`.",
                    "Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.",
                    "Code `code_rule_key=hp_product_efficiency_threshold`."
                ],
                "missing": [
                    "The oil-removal supplement path is not yet structured or deterministic.",
                    "The code layer does not currently use a distinct Oil-to-Heat-Pump product list validator separate from the current AHRI path."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No oil-specific persisted non-integrated-area pre-approval validator currently enforces this sentence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The back-up heating system must be electric or wood... Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=ashp_oil_backup_not_fossil_primary`.",
                    "GenAI `rule_key=ashp_oil_no_existing_heat_pump_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... "
                    "Proof of fossil fuel (oil) system removal... The rebate application... within six (6) months..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=ashp_oil_rebate_math_within_cap`.",
                    "GenAI `rule_key=ashp_oil_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The F280 and oil-removal supplement path is still not structured enough for deterministic validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Dual Fuel Ducted Heat Pump",
        "items": [
            {
                "quote": (
                    "The home must be primarily heated by tanked propane or natural gas provided by Pacific Northern Gas (PNG)..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=dfhp_png_or_tank_propane_path_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The new heat pump must be integrated with a propane or natural gas heating system... "
                    "have the thermostat / outdoor temperature switch-over control set to the following region-specific temperatures... "
                    "be sized to ensure it has the capacity to meet the home's heat demand..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=dfhp_dual_fuel_scope_present`.",
                    "GenAI `rule_key=dfhp_controls_reference_present`.",
                    "GenAI `rule_key=dfhp_switchover_setpoint_specific`.",
                    "Code `code_rule_key=hp_ahri_found_in_product_list`.",
                    "Code `code_rule_key=hp_product_minimum_capacity_at_minus_5c`.",
                    "Code `code_rule_key=hp_product_efficiency_threshold`."
                ],
                "missing": [
                    "The fossil-fuel modification/removal proof is still supplement-driven and not structured end to end."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "A program approved Heat Load Calculation is required to properly size the system. Rule of thumb equipment sizing will not be accepted."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=dfhp_heat_load_calc_reference_present`."
                ],
                "missing": [
                    "The required F280 / approved heat-load document is not yet validated through a structured supplement path."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Homes in Non-Integrated Areas of the electricity grid must contact ... for pre-approval prior to installation."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No dual-fuel-specific persisted non-integrated-area pre-approval validator currently enforces this sentence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... Proof of fossil fuel system removal or modification... "
                    "A copy of CSA-F280-12 Heat Load Calculation is required... within six (6) months..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=dfhp_rebate_math_within_cap`.",
                    "GenAI `rule_key=dfhp_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The removal/modification proof and required heat-load document are still not validated through a structured supplement path."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Air-To-Water Heat Pump",
        "items": [
            {
                "quote": (
                    "The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=atw_scope_present`.",
                    "GenAI `rule_key=atw_conversion_context_present`.",
                    "GenAI `rule_key=atw_not_combined_or_hpwh_scope`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The new air-to-water heat pump must... be listed as an eligible system on the Air-to-Water and Combined Heat Pump Qualifying Product List..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=atw_product_reference_present`."
                ],
                "missing": [
                    "No persisted `code_rule_key` currently validates the air-to-water qualifying product list.",
                    "No persisted check currently proves installation-guide compliance."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "If the new air-to-water heat pump replaces a fossil fuel heating system, all the fossil fuel heating equipment... must be removed... "
                    "If it replaces a wood or solid fuel heating system, the existing wood or solid fuel heating system may be retained... or removed..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=atw_conversion_context_present`."
                ],
                "missing": [
                    "No persisted check currently validates the fossil-fuel removal proof, wood-removal photos, or WETT-retention evidence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible. "
                    "Homes in Non-Integrated Areas... must contact... for pre-approval..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=atw_no_existing_heat_pump_flag`."
                ],
                "missing": [
                    "No persisted air-to-water-specific non-integrated-area pre-approval validator currently enforces this sentence."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... "
                    "Proof of fossil fuel system removal... Before and after photos of the wood or solid fuel heating system... WETT-certified inspection report..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=atw_rebate_math_within_cap`.",
                    "GenAI `rule_key=atw_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The F280, removal-proof, photo, and WETT supplement path is still not structured enough for deterministic validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Combined Space And Water Heat Pump",
        "items": [
            {
                "quote": (
                    "The home must be primarily heated by fossil fuel (oil, propane or natural gas), electricity, or wood..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=cshp_scope_present`.",
                    "GenAI `rule_key=cshp_conversion_context_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Combined space and water heat pump... Must be listed on the air-to-water and combined heat pump qualifying product list."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=cshp_product_reference_present`.",
                    "GenAI `rule_key=cshp_combined_space_and_water_scope_present`."
                ],
                "missing": [
                    "No persisted `code_rule_key` currently validates the combined-system qualifying product list."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "If the new air-to-water heat pump replaces a fossil fuel heating system... must be removed... "
                    "If it replaces a wood or solid fuel heating system... may be retained in safe and working order or removed..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=cshp_conversion_context_present`."
                ],
                "missing": [
                    "No persisted check currently validates fossil-fuel removal proof, wood-removal photos, or WETT-retention evidence for this path."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Replacing, adding to an existing heat pump or adding a secondary heat pump... is not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=cshp_no_existing_heat_pump_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... A CSA-F280-12 Heat Load Calculation may be requested... "
                    "Proof of fossil fuel system removal... Before and after photos... WETT-certified inspection report..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=cshp_rebate_math_within_cap`.",
                    "GenAI `rule_key=cshp_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The F280, removal-proof, photo, and WETT supplement path is still not structured enough for deterministic validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Heat Pump Water Heater",
        "items": [
            {
                "quote": "The existing water heater being replaced must be the home's primary water heater.",
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=hpwh_primary_replacement_context_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Eligible systems are listed as Tier 2 or higher on NEEA's Advanced Water Heater Specification Qualified Products List..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=hpwh_product_reference_present`.",
                    "Code `code_rule_key=hpwh_neea_found_in_product_list`.",
                    "Code `code_rule_key=hpwh_neea_tier_2_or_higher`."
                ],
                "missing": [],
                "priority": "Low",
            },
            {
                "quote": (
                    "If the new heat pump water heater replaces a fossil fuel water heating system, all the fossil fuel heating equipment... "
                    "must be removed or decommissioned... Homes in Non-Integrated Areas... must contact... for pre-approval..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=hpwh_fossil_removal_evidence_present`.",
                    "GenAI `rule_key=hpwh_non_integrated_area_review`."
                ],
                "missing": [
                    "Current coverage is still review-oriented; no persisted structured supplement/external validator proves the removal or the non-integrated-area approval."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Replacing or adding a secondary heat pump water heater to a home with an existing heat pump water heater is not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=hpwh_secondary_system_flag`.",
                    "GenAI `rule_key=hpwh_no_existing_or_secondary_hpwh_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "All upgrades must be installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Invoice... must show the itemized CleanBC rebate... Proof of gas water heater removal... "
                    "The rebate application... must be submitted... within six (6) months..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=hpwh_rebate_math_within_cap`.",
                    "GenAI `rule_key=hpwh_description_sufficient_for_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The fossil-fuel-removal supplement path is still not structured enough for deterministic validation."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Electrical Service Upgrade",
        "items": [
            {
                "quote": (
                    "Only homes that convert from a fossil fuel primary space and/or water heating system to a heat pump... are eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=esu_heat_pump_conversion_context_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "The electric service (new wire) must be upgraded by the participant's electrical utility... "
                    "The service upgrade... must be installed within six months of the heat pump installation."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=esu_utility_upgrade_evidence_present`.",
                    "GenAI `rule_key=esu_service_size_present`.",
                    "GenAI `rule_key=esu_timing_within_six_months_evidence`."
                ],
                "missing": [
                    "There is no persisted external/system validator that proves the utility actually performed the qualifying service upgrade."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Eligible expenses include utility connection fees, electrical panel or sub-panel upgrade, service mast alterations... labour."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=esu_description_sufficient_for_review`."
                ],
                "missing": [
                    "No persisted line-item classifier currently enforces the eligible-expense list deterministically."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Electrical panel or sub-panel upgrades or heat pump connections to the panel without an electric service upgrade by the utility are not eligible."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=esu_not_panel_only_or_connection_only`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "If the contractor is being billed by the utility for the line upgrade, then all work completed by the contractor and the utility must be on one invoice."
                ),
                "status": "Missing now",
                "implemented": [],
                "missing": [
                    "No persisted invoice-composition validator currently proves that contractor and utility work were combined on one invoice when required."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor... "
                    "All upgrades must be completed in accordance with applicable by-laws..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this registered-contractor requirement as its own explicit audit result.",
                    "No persisted AHJ/by-law validation currently enforces these sentences."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Electrical service upgrade... up to a maximum... Maximum of one electrical service upgrade per home... "
                    "Invoice... must show the itemized CleanBC rebate... within six (6) months..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=esu_rebate_math_within_cap`.",
                    "GenAI `rule_key=esu_one_per_home_manual_review`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [
                    "The one-per-home restriction is still manual-review oriented rather than a deterministic historical validator."
                ],
                "priority": "High",
            },
        ],
    },
    {
        "title": "Health And Safety",
        "items": [
            {
                "quote": (
                    "Remediation must be for existing health and safety issues... required to enable the safe installation and operation of a rebate-eligible upgrade... "
                    "completed in association with an eligible upgrade... Rebates will not be paid for health and safety remediation on its own... "
                    "confirmed as rebate-eligible prior to beginning remediation."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=hs_issue_type_present`.",
                    "GenAI `rule_key=hs_associated_upgrade_present`.",
                    "GenAI `rule_key=hs_not_standalone_flag`.",
                    "GenAI `rule_key=hs_pre_confirmation_evidence_present`."
                ],
                "missing": [
                    "The pre-confirmation step is still evidence/review oriented rather than a wired workflow integration."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be completed by a Registered Contractor who is approved to complete health and safety remediation..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this health-and-safety contractor-registration requirement as its own explicit audit result."
                ],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Must be used to remediate pest, asbestos, structural and/or mould issues... "
                    "Invoice... must show the itemized CleanBC rebate..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=hs_description_sufficient_for_review`.",
                    "GenAI `rule_key=hs_rebate_math_within_cap`.",
                    "GenAI `rule_key=hs_income_level_allows_rebate`.",
                    "GenAI `rule_key=rebate_line_evidence_present`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Before and after photos of the health and safety issue that was remediated."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=hs_before_after_photos_present`."
                ],
                "missing": [
                    "The supplement path does not yet do structured photo validation."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "The rebate application and supporting documentation must be submitted by the Registered Contractor within six (6) months of the invoice date."
                ),
                "status": "Implemented now",
                "implemented": [
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [],
                "priority": "Low",
            },
        ],
    },
    {
        "title": "Ventilation",
        "items": [
            {
                "quote": (
                    "Ventilation upgrades must be installed in association with a rebate-eligible heat pump, heat pump water heater, insulation, or windows/doors upgrade. "
                    "Rebates will not be paid for ventilation upgrades on their own."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=vent_associated_upgrade_present`.",
                    "GenAI `rule_key=vent_standalone_flag`."
                ],
                "missing": [],
                "priority": "Medium",
            },
            {
                "quote": (
                    "Heat/energy recovery ventilators must be ENERGY STAR certified and listed on Natural Resources Canada's searchable product list... "
                    "be installed in accordance with the BC Housing Heat Recovery Ventilation Guide..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=vent_system_type_present`.",
                    "GenAI `rule_key=vent_product_or_capacity_evidence_present`."
                ],
                "missing": [
                    "No persisted structured validator currently checks the HRV/ERV product list or ENERGY STAR status.",
                    "No persisted check currently proves the ventilation-guide installation requirement."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Bathroom fan systems must... be ENERGY STAR certified... be ducted directly to the outside... have a capacity of at least 85 cfm... "
                    "be rated for continuous duty... be equipped with self-closing backdraft damper... ducts must be sealed... ducts must be insulated to minimum R4..."
                ),
                "status": "Partial",
                "implemented": [
                    "GenAI `rule_key=vent_product_or_capacity_evidence_present`.",
                    "GenAI `rule_key=vent_not_generic_ductwork_only`."
                ],
                "missing": [
                    "Most bathroom-fan technical subrequirements are still review-oriented and not backed by a structured deterministic validator."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "All upgrades must be purchased, supplied and installed by a Registered Contractor who is approved to install ventilation upgrades... "
                    "Heat/energy recovery ventilators must be installed by a licensed HVAC contractor..."
                ),
                "status": "Partial",
                "implemented": [
                    "Legacy contractor onboarding/access controls already appear to gate baseline registered-contractor status outside the claims AI rulecheck layer."
                ],
                "missing": [
                    "No persisted claim-layer rulecheck currently traces this ventilation contractor-registration requirement as its own explicit audit result.",
                    "No persisted licensed-HVAC validator currently enforces these sentences."
                ],
                "priority": "High",
            },
            {
                "quote": (
                    "Ventilation... 95% or 60% of eligible upgrade costs... up to a maximum of $1,600 per home... "
                    "Invoice... must show the itemized CleanBC rebate... within six (6) months..."
                ),
                "status": "Implemented now",
                "implemented": [
                    "GenAI `rule_key=vent_income_level_allows_rebate`.",
                    "GenAI `rule_key=vent_rebate_math_within_cap`.",
                    "GenAI `rule_key=vent_description_sufficient_for_review`.",
                    "GenAI `rule_key=rebate_line_evidence_present`.",
                    "Code `rule_key=submission_within_six_months`."
                ],
                "missing": [],
                "priority": "Medium",
            },
        ],
    },
]

SECTION_PAGES = {
    "How To Read This Audit": ["N/A"],
    "General Eligibility Requirements": [1, 1, 2, 3, 3, 4, 4, 4, 4, 5],
    "Insulation": [6, 6, 6, 6, 6, 7],
    "Windows And Doors": [8, 8, 8, 8, 8, 8, 9],
    "Air Source Heat Pump (Convert From Electric)": [10, 10, 10, 10, 10, 11],
    "Air Source Heat Pump (Convert From Wood)": [12, 12, 12, 13, 12, 13],
    "Air Source Heat Pump (Convert From Natural Gas Or Propane)": [14, 14, 14, 14, 14, 16],
    "Air Source Heat Pump (Convert From Oil)": [17, 17, 17, 17, 17, 19],
    "Dual Fuel Ducted Heat Pump": [20, 20, 20, 20, 20, 21],
    "Air-To-Water Heat Pump": [23, 23, 23, 23, 23, 25],
    "Combined Space And Water Heat Pump": [23, 24, 23, 23, 23, 25],
    "Heat Pump Water Heater": [26, 26, 26, 26, 26, 27],
    "Electrical Service Upgrade": [28, 28, 28, 28, 28, 28, 29],
    "Health And Safety": [30, 30, 30, 30, 30],
    "Ventilation": [31, 31, 31, 31, 32],
}

EVIDENCE_SOURCE_ORDER = [
    "invoice_pdf",
    "supporting_document",
    "database",
    "external_list",
]

EVIDENCE_SOURCE_OVERRIDES = {
    ("General Eligibility Requirements", 1): ["invoice_pdf"],
    ("General Eligibility Requirements", 2): ["supporting_document", "database"],
    ("General Eligibility Requirements", 3): ["database"],
    ("General Eligibility Requirements", 4): ["database", "supporting_document"],
    ("General Eligibility Requirements", 5): ["database"],
    ("General Eligibility Requirements", 6): ["database"],
    ("General Eligibility Requirements", 7): ["database", "invoice_pdf"],
    ("General Eligibility Requirements", 8): ["database"],
    ("General Eligibility Requirements", 9): ["invoice_pdf"],
    ("General Eligibility Requirements", 10): ["database", "supporting_document"],
    ("Insulation", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Windows And Doors", 2): ["supporting_document", "database"],
    ("Windows And Doors", 3): ["invoice_pdf", "supporting_document", "external_list"],
    ("Windows And Doors", 6): ["invoice_pdf", "supporting_document", "database", "external_list"],
    ("Windows And Doors", 7): ["invoice_pdf", "supporting_document", "database"],
    ("Air Source Heat Pump (Convert From Electric)", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Air Source Heat Pump (Convert From Wood)", 4): ["supporting_document"],
    ("Air Source Heat Pump (Convert From Wood)", 7): ["invoice_pdf", "supporting_document", "database"],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 3): ["supporting_document", "database"],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Air Source Heat Pump (Convert From Oil)", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Air Source Heat Pump (Convert From Oil)", 3): ["supporting_document", "database"],
    ("Air Source Heat Pump (Convert From Oil)", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Dual Fuel Ducted Heat Pump", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Dual Fuel Ducted Heat Pump", 3): ["supporting_document"],
    ("Dual Fuel Ducted Heat Pump", 4): ["supporting_document", "database"],
    ("Dual Fuel Ducted Heat Pump", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Air-To-Water Heat Pump", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Air-To-Water Heat Pump", 3): ["supporting_document"],
    ("Air-To-Water Heat Pump", 4): ["invoice_pdf", "supporting_document", "database"],
    ("Air-To-Water Heat Pump", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Combined Space And Water Heat Pump", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Combined Space And Water Heat Pump", 3): ["supporting_document"],
    ("Combined Space And Water Heat Pump", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Heat Pump Water Heater", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Heat Pump Water Heater", 3): ["supporting_document", "database"],
    ("Heat Pump Water Heater", 6): ["invoice_pdf", "supporting_document", "database"],
    ("Electrical Service Upgrade", 2): ["invoice_pdf", "supporting_document"],
    ("Electrical Service Upgrade", 5): ["invoice_pdf", "supporting_document"],
    ("Health And Safety", 4): ["supporting_document"],
    ("Ventilation", 2): ["invoice_pdf", "supporting_document", "external_list"],
    ("Ventilation", 3): ["invoice_pdf", "supporting_document"],
}

CHECK_METHOD_OVERRIDES = {
    ("General Eligibility Requirements", 1): "code",
    ("General Eligibility Requirements", 2): "hybrid",
    ("General Eligibility Requirements", 3): "hybrid",
    ("General Eligibility Requirements", 4): "hybrid",
    ("General Eligibility Requirements", 5): "code",
    ("General Eligibility Requirements", 6): "code",
    ("General Eligibility Requirements", 7): "hybrid",
    ("General Eligibility Requirements", 8): "code",
    ("General Eligibility Requirements", 9): "hybrid",
    ("General Eligibility Requirements", 10): "hybrid",
    ("Insulation", 1): "code",
    ("Insulation", 2): "hybrid",
    ("Insulation", 3): "hybrid",
    ("Insulation", 4): "hybrid",
    ("Insulation", 5): "code",
    ("Insulation", 6): "hybrid",
    ("Windows And Doors", 1): "code",
    ("Windows And Doors", 2): "hybrid",
    ("Windows And Doors", 3): "hybrid",
    ("Windows And Doors", 4): "genai",
    ("Windows And Doors", 5): "code",
    ("Windows And Doors", 6): "hybrid",
    ("Windows And Doors", 7): "hybrid",
    ("Air Source Heat Pump (Convert From Electric)", 1): "code",
    ("Air Source Heat Pump (Convert From Electric)", 2): "hybrid",
    ("Air Source Heat Pump (Convert From Electric)", 3): "hybrid",
    ("Air Source Heat Pump (Convert From Electric)", 4): "hybrid",
    ("Air Source Heat Pump (Convert From Electric)", 5): "code",
    ("Air Source Heat Pump (Convert From Electric)", 6): "hybrid",
    ("Air Source Heat Pump (Convert From Wood)", 1): "code",
    ("Air Source Heat Pump (Convert From Wood)", 2): "hybrid",
    ("Air Source Heat Pump (Convert From Wood)", 3): "hybrid",
    ("Air Source Heat Pump (Convert From Wood)", 4): "hybrid",
    ("Air Source Heat Pump (Convert From Wood)", 5): "hybrid",
    ("Air Source Heat Pump (Convert From Wood)", 6): "code",
    ("Air Source Heat Pump (Convert From Wood)", 7): "hybrid",
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 1): "code",
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 2): "hybrid",
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 3): "hybrid",
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 4): "hybrid",
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 5): "code",
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 6): "hybrid",
    ("Air Source Heat Pump (Convert From Oil)", 1): "hybrid",
    ("Air Source Heat Pump (Convert From Oil)", 2): "hybrid",
    ("Air Source Heat Pump (Convert From Oil)", 3): "hybrid",
    ("Air Source Heat Pump (Convert From Oil)", 4): "hybrid",
    ("Air Source Heat Pump (Convert From Oil)", 5): "code",
    ("Air Source Heat Pump (Convert From Oil)", 6): "hybrid",
    ("Dual Fuel Ducted Heat Pump", 1): "code",
    ("Dual Fuel Ducted Heat Pump", 2): "hybrid",
    ("Dual Fuel Ducted Heat Pump", 3): "hybrid",
    ("Dual Fuel Ducted Heat Pump", 4): "hybrid",
    ("Dual Fuel Ducted Heat Pump", 5): "code",
    ("Dual Fuel Ducted Heat Pump", 6): "hybrid",
    ("Air-To-Water Heat Pump", 1): "code",
    ("Air-To-Water Heat Pump", 2): "hybrid",
    ("Air-To-Water Heat Pump", 3): "hybrid",
    ("Air-To-Water Heat Pump", 4): "hybrid",
    ("Air-To-Water Heat Pump", 5): "code",
    ("Air-To-Water Heat Pump", 6): "hybrid",
    ("Combined Space And Water Heat Pump", 1): "code",
    ("Combined Space And Water Heat Pump", 2): "hybrid",
    ("Combined Space And Water Heat Pump", 3): "hybrid",
    ("Combined Space And Water Heat Pump", 4): "hybrid",
    ("Combined Space And Water Heat Pump", 5): "code",
    ("Combined Space And Water Heat Pump", 6): "hybrid",
    ("Heat Pump Water Heater", 1): "code",
    ("Heat Pump Water Heater", 2): "hybrid",
    ("Heat Pump Water Heater", 3): "hybrid",
    ("Heat Pump Water Heater", 4): "hybrid",
    ("Heat Pump Water Heater", 5): "code",
    ("Heat Pump Water Heater", 6): "hybrid",
    ("Electrical Service Upgrade", 1): "code",
    ("Electrical Service Upgrade", 2): "hybrid",
    ("Electrical Service Upgrade", 3): "hybrid",
    ("Electrical Service Upgrade", 4): "code",
    ("Electrical Service Upgrade", 5): "hybrid",
    ("Electrical Service Upgrade", 6): "code",
    ("Electrical Service Upgrade", 7): "hybrid",
    ("Health And Safety", 1): "hybrid",
    ("Health And Safety", 2): "code",
    ("Health And Safety", 3): "hybrid",
    ("Health And Safety", 4): "hybrid",
    ("Health And Safety", 5): "code",
    ("Ventilation", 1): "code",
    ("Ventilation", 2): "hybrid",
    ("Ventilation", 3): "hybrid",
    ("Ventilation", 4): "code",
    ("Ventilation", 5): "hybrid",
}

LOCATED_FIELDS_OVERRIDES = {
    ("General Eligibility Requirements", 1): [],
    ("General Eligibility Requirements", 2): [],
    ("General Eligibility Requirements", 3): [],
    ("General Eligibility Requirements", 4): [],
    ("General Eligibility Requirements", 5): [],
    ("General Eligibility Requirements", 6): [],
    ("General Eligibility Requirements", 7): ["invoice_contractor_name", "invoice_contractor_address"],
    ("General Eligibility Requirements", 8): [],
    ("General Eligibility Requirements", 9): [
        "overall_rebate_line_amount",
        "overall_rebate_line_description",
        "amount_due_after_rebate",
        "customer_deposit",
    ],
    ("General Eligibility Requirements", 10): ["invoice_homeowner_name"],
    ("Insulation", 2): [
        "ins_material_type",
        "ins_upgrade_location",
        "ins_conditioned_boundary_evidence",
        "ins_new_r_value",
        "ins_existing_r_value",
        "ins_r_value_added",
    ],
    ("Insulation", 3): [
        "ins_new_r_value",
        "ins_existing_r_value",
        "ins_r_value_added",
        "ins_area_square_feet",
        "ins_line_amount",
        "upgrade_specific_rebate_line_amount",
        "ins_location_specific_rebate_amount",
        "ins_rebate_formula_or_rate_evidence",
    ],
    ("Insulation", 4): [
        "ins_removed_existing_insulation_evidence",
        "ins_health_safety_resolution_evidence",
    ],
    ("Insulation", 6): [
        "ins_before_after_photo_reference",
        "ins_floor_plan_reference",
        "ins_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Windows And Doors", 2): ["quote_preapproval_reference"],
    ("Windows And Doors", 3): [
        "certification_body_reference",
        "nrcan_number",
        "cpd_number",
        "brand_and_model",
        "envelope_replacement_evidence",
        "skylight_detected",
    ],
    ("Windows And Doors", 4): [
        "rough_opening_count",
        "window_or_door_quantity",
        "pane_count",
    ],
    ("Windows And Doors", 6): [
        "metric_u_factor",
        "window_or_door_line_amount",
        "hardware_per_unit",
        "labour_per_unit",
        "upgrade_specific_rebate_line_amount",
        "city_of_vancouver_evidence",
    ],
    ("Windows And Doors", 7): [
        "manufacturer_label_photo_reference",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Air Source Heat Pump (Convert From Electric)", 2): [
        "hp_existing_electric_heat_evidence",
        "hp_main_living_area_evidence",
        "hp_new_equipment_type",
    ],
    ("Air Source Heat Pump (Convert From Electric)", 3): [
        "hp_make_model",
        "hp_ahri_reference",
        "hp_product_list_reference",
        "hp_efficiency_and_capacity",
    ],
    ("Air Source Heat Pump (Convert From Electric)", 4): ["hp_existing_heat_pump_flag"],
    ("Air Source Heat Pump (Convert From Electric)", 6): [
        "hp_heat_load_calc_reference",
        "hp_line_amount",
        "upgrade_specific_rebate_line_amount",
        "hp_new_equipment_type",
    ],
    ("Air Source Heat Pump (Convert From Wood)", 2): [
        "hp_existing_wood_heat_evidence",
        "hp_backup_heat_evidence",
    ],
    ("Air Source Heat Pump (Convert From Wood)", 3): [
        "hp_make_model",
        "hp_ahri_reference",
        "hp_product_list_reference",
        "hp_efficiency_and_capacity",
        "hp_main_living_area_evidence",
    ],
    ("Air Source Heat Pump (Convert From Wood)", 4): ["hp_wood_system_removal_or_wett_evidence"],
    ("Air Source Heat Pump (Convert From Wood)", 5): ["hp_existing_heat_pump_flag"],
    ("Air Source Heat Pump (Convert From Wood)", 7): [
        "hp_heat_load_calc_reference",
        "hp_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 1): ["hp_existing_gas_propane_heat_evidence"],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 2): [
        "hp_make_model",
        "hp_ahri_reference",
        "hp_product_list_reference",
        "hp_efficiency_and_capacity",
        "hp_fossil_fuel_removal_evidence",
    ],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 3): ["hp_non_integrated_area_preapproval_reference"],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 4): [
        "hp_backup_heat_evidence",
        "hp_existing_heat_pump_flag",
    ],
    ("Air Source Heat Pump (Convert From Natural Gas Or Propane)", 6): [
        "hp_heat_load_calc_reference",
        "hp_fossil_fuel_removal_evidence",
        "hp_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Air Source Heat Pump (Convert From Oil)", 1): [
        "hp_existing_oil_heat_evidence",
        "hp_oil_consumption_baseline_evidence",
    ],
    ("Air Source Heat Pump (Convert From Oil)", 2): [
        "hp_make_model",
        "hp_ahri_reference",
        "hp_product_list_reference",
        "hp_efficiency_and_capacity",
        "hp_oil_system_removal_evidence",
    ],
    ("Air Source Heat Pump (Convert From Oil)", 3): ["hp_non_integrated_area_preapproval_reference"],
    ("Air Source Heat Pump (Convert From Oil)", 4): [
        "hp_backup_heat_evidence",
        "hp_existing_heat_pump_flag",
    ],
    ("Air Source Heat Pump (Convert From Oil)", 6): [
        "hp_heat_load_calc_reference",
        "hp_oil_system_removal_evidence",
        "hp_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Dual Fuel Ducted Heat Pump", 1): ["dfhp_existing_png_or_tank_propane_evidence"],
    ("Dual Fuel Ducted Heat Pump", 2): [
        "dfhp_equipment_type",
        "dfhp_switchover_setpoint_evidence",
        "hp_ahri_reference",
        "dfhp_fossil_modification_evidence",
    ],
    ("Dual Fuel Ducted Heat Pump", 3): ["dfhp_heat_load_calc_reference"],
    ("Dual Fuel Ducted Heat Pump", 4): [],
    ("Dual Fuel Ducted Heat Pump", 6): [
        "dfhp_heat_load_calc_reference",
        "dfhp_fossil_modification_evidence",
        "dfhp_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Air-To-Water Heat Pump", 1): ["atw_conversion_source_fuel_evidence"],
    ("Air-To-Water Heat Pump", 2): [
        "atw_make_model",
        "atw_product_list_reference",
    ],
    ("Air-To-Water Heat Pump", 3): [
        "atw_fossil_removal_evidence",
        "atw_wood_removal_or_wett_evidence",
    ],
    ("Air-To-Water Heat Pump", 4): [
        "atw_existing_heat_pump_flag",
        "atw_non_integrated_area_preapproval_reference",
    ],
    ("Air-To-Water Heat Pump", 6): [
        "atw_heat_load_calc_reference",
        "atw_fossil_removal_evidence",
        "atw_wood_removal_or_wett_evidence",
        "atw_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Combined Space And Water Heat Pump", 1): ["cshp_conversion_source_fuel_evidence"],
    ("Combined Space And Water Heat Pump", 2): [
        "cshp_make_model",
        "cshp_product_list_reference",
    ],
    ("Combined Space And Water Heat Pump", 3): [
        "cshp_fossil_removal_evidence",
        "cshp_wood_removal_or_wett_evidence",
        "cshp_domestic_hot_water_evidence",
    ],
    ("Combined Space And Water Heat Pump", 4): ["cshp_existing_heat_pump_flag"],
    ("Combined Space And Water Heat Pump", 6): [
        "cshp_heat_load_calc_reference",
        "cshp_fossil_removal_evidence",
        "cshp_wood_removal_or_wett_evidence",
        "cshp_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Heat Pump Water Heater", 1): ["hpwh_existing_water_heater_evidence"],
    ("Heat Pump Water Heater", 2): [
        "hpwh_manufacturer",
        "hpwh_model_number",
        "hpwh_model_components",
        "hpwh_neea_reference",
        "hpwh_tier_reference",
    ],
    ("Heat Pump Water Heater", 3): [
        "hpwh_existing_fuel_type",
        "hpwh_fossil_fuel_removal_evidence",
        "hpwh_non_integrated_area_preapproval_reference",
        "hpwh_fossil_removal_date_or_permit",
    ],
    ("Heat Pump Water Heater", 4): ["hpwh_secondary_system_flag", "hpwh_existing_hpwh_flag"],
    ("Heat Pump Water Heater", 6): [
        "hpwh_existing_fuel_type",
        "hpwh_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Electrical Service Upgrade", 1): ["esu_fossil_to_heat_pump_context"],
    ("Electrical Service Upgrade", 2): [
        "esu_utility_reference",
        "esu_previous_service_size",
        "esu_new_service_size",
        "esu_utility_bill_or_invoice_reference",
    ],
    ("Electrical Service Upgrade", 3): ["esu_eligible_expense_lines", "esu_line_amount"],
    ("Electrical Service Upgrade", 4): ["esu_ineligible_panel_only_evidence"],
    ("Electrical Service Upgrade", 5): ["esu_contractor_utility_management_evidence", "esu_utility_bill_or_invoice_reference"],
    ("Electrical Service Upgrade", 7): [
        "esu_line_amount",
        "upgrade_specific_rebate_line_amount",
        "esu_new_service_size",
    ],
    ("Health And Safety", 1): ["hs_issue_type", "hs_associated_upgrade_evidence", "hs_remediation_scope"],
    ("Health And Safety", 2): ["hs_registered_contractor_evidence"],
    ("Health And Safety", 3): [
        "hs_issue_type",
        "hs_remediation_scope",
        "hs_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
    ("Health And Safety", 4): ["hs_before_after_photo_reference"],
    ("Ventilation", 1): ["vent_associated_upgrade_evidence"],
    ("Ventilation", 2): [
        "vent_system_type",
        "vent_energy_star_reference",
        "vent_nrcan_or_product_list_reference",
    ],
    ("Ventilation", 3): [
        "vent_system_type",
        "vent_energy_star_reference",
        "vent_bathroom_fan_cfm",
        "vent_static_pressure",
        "vent_continuous_duty_motor_evidence",
        "vent_backdraft_damper_evidence",
        "vent_ducting_evidence",
        "vent_main_bathroom_evidence",
        "vent_direct_exterior_ducting_evidence",
    ],
    ("Ventilation", 5): [
        "vent_line_amount",
        "upgrade_specific_rebate_line_amount",
    ],
}


def add_runs(paragraph, text, color=None, bold=False, italic=False, size=None):
    run = paragraph.add_run(text)
    run.bold = bold
    run.italic = italic
    if color is not None:
        run.font.color.rgb = color
    if size is not None:
        run.font.size = size
    return run


def add_bookmark(paragraph, bookmark_name: str, bookmark_text: str):
    bookmark_id = str(abs(hash((bookmark_name, bookmark_text))) % 2_000_000_000)
    start = OxmlElement("w:bookmarkStart")
    start.set(qn("w:id"), bookmark_id)
    start.set(qn("w:name"), bookmark_name)

    end = OxmlElement("w:bookmarkEnd")
    end.set(qn("w:id"), bookmark_id)

    paragraph._p.append(start)
    run = paragraph.add_run(bookmark_text)
    paragraph._p.append(end)
    return run


def add_internal_hyperlink(paragraph, anchor: str, text: str, color="B00020", underline=True):
    hyperlink = OxmlElement("w:hyperlink")
    hyperlink.set(qn("w:anchor"), anchor)

    run = OxmlElement("w:r")
    r_pr = OxmlElement("w:rPr")

    if color:
        c = OxmlElement("w:color")
        c.set(qn("w:val"), color)
        r_pr.append(c)

    if underline:
        u = OxmlElement("w:u")
        u.set(qn("w:val"), "single")
        r_pr.append(u)

    t = OxmlElement("w:t")
    t.text = text

    run.append(r_pr)
    run.append(t)
    hyperlink.append(run)
    paragraph._p.append(hyperlink)


def extract_pdf_pages():
    reader = PdfReader(str(PDF_PATH))
    pages = []
    for i, page in enumerate(reader.pages, start=1):
        text = page.extract_text() or ""
        lines = [line.rstrip() for line in text.splitlines()]
        cleaned = "\n".join(line for line in lines if line.strip())
        pages.append({"page_number": i, "text": cleaned})
    return pages


def infer_evidence_sources(section_title: str, item_number: int, item: dict):
    override = EVIDENCE_SOURCE_OVERRIDES.get((section_title, item_number))
    if override:
        return override

    text_parts = [section_title, item.get("quote", "")]
    text_parts.extend(item.get("implemented", []))
    text_parts.extend(item.get("missing", []))
    text = " ".join(text_parts).lower()

    sources = set()

    invoice_keywords = [
        "invoice",
        "rebate",
        "rough opening",
        "u-factor",
        "model number",
        "description",
        "line item",
        "invoice date",
        "customer portion",
        "product reference",
        "visible invoice",
        "ocr text",
    ]
    supporting_keywords = [
        "supporting document",
        "supporting-document",
        "photo",
        "before and after",
        "before/after",
        "floor plan",
        "wett",
        "heat load",
        "f280",
        "permit",
        "inspection",
        "pre-approval",
        "preapproval",
        "manufacturer label",
        "removal proof",
        "removal evidence",
        "decommission",
        "technical safety",
        "ahj",
        "by-law",
        "bylaw",
        "quote",
    ]
    database_keywords = [
        "income",
        "eligibility code",
        "approved as income level",
        "pre-register",
        "pre-register",
        "residential account",
        "utility account",
        "assessed value",
        "bc assessment",
        "registered contractor",
        "contractor-approval",
        "contractor approval",
        "homeowner",
        "landlord",
        "duplicate-history",
        "cross-program",
        "submission date",
        "database",
        "vancouver",
        "non-integrated area",
        "resident",
        "primary heated",
        "primarily heated",
    ]
    external_keywords = [
        "ahri",
        "neea",
        "energy star",
        "product list",
        "qualifying system",
        "nfrc",
        "intertek",
        "csa",
        "qai",
        "nami",
        "certification",
    ]
    if "registered and approved as income level" in text or "income qualified household" in text:
        return ["database"]

    if "all upgrades must be purchased, supplied and installed by a registered contractor" in text:
        return ["database"]

    if "the rebate application" in text and "within six (6) months" in text:
        sources.update({"invoice_pdf", "database"})

    if "must be listed" in text or "listed on" in text:
        sources.update({"invoice_pdf", "external_list"})

    if "manufacturer label" in text or "before and after photos" in text or "wett" in text:
        sources.add("supporting_document")

    if "heat load calculation" in text or "f280" in text:
        sources.add("supporting_document")

    if "pre-approval" in text or "preapproval" in text or "non-integrated area" in text:
        sources.update({"supporting_document", "database"})

    if any(keyword in text for keyword in invoice_keywords):
        sources.add("invoice_pdf")
    if any(keyword in text for keyword in supporting_keywords):
        sources.add("supporting_document")
    if any(keyword in text for keyword in database_keywords):
        sources.add("database")
    if any(keyword in text for keyword in external_keywords):
        sources.add("external_list")

    if not sources:
        sources.add("invoice_pdf")

    ordered = [src for src in EVIDENCE_SOURCE_ORDER if src in sources]
    return ordered


def infer_check_method(section_title: str, item_number: int, item: dict):
    override = CHECK_METHOD_OVERRIDES.get((section_title, item_number))
    if override:
        return override

    text_parts = [section_title, item.get("quote", "")]
    text_parts.extend(item.get("implemented", []))
    text_parts.extend(item.get("missing", []))
    text = " ".join(text_parts).lower()

    if any(
        phrase in text
        for phrase in [
            "within six (6) months",
            "eligibility code",
            "income level",
            "assessed value",
            "duplicate-history",
            "one rebate payment",
            "vancouver",
            "registered contractor who is approved",
        ]
    ):
        return "code"

    if any(
        phrase in text
        for phrase in [
            "product list",
            "energy star",
            "u-factor",
            "capacity",
            "threshold",
            "heat load calculation",
            "wett",
            "photo",
            "removal proof",
            "pre-approval",
            "permit",
            "inspection",
        ]
    ):
        return "hybrid"

    if any(
        phrase in text
        for phrase in [
            "description sufficient",
            "reference present",
            "rough opening",
            "no skylights",
            "existing heat context",
        ]
    ):
        return "genai"

    if any(
        phrase in text
        for phrase in [
            "manual review",
            "admin review",
            "lawful authorities",
            "terms and conditions",
        ]
    ):
        return "out_of_scope"

    return "hybrid"


def infer_located_fields(section_title: str, item_number: int, item: dict):
    override = LOCATED_FIELDS_OVERRIDES.get((section_title, item_number))
    if override is not None:
        return override

    text_parts = [section_title, item.get("quote", "")]
    text_parts.extend(item.get("implemented", []))
    text_parts.extend(item.get("missing", []))
    text = " ".join(text_parts).lower()

    if any(
        phrase in text
        for phrase in [
            "within six (6) months",
            "income qualified household",
            "registered contractor who is approved",
            "assessed value",
            "duplicate-history",
            "one rebate payment",
            "landlord consent",
            "utility accounts must be in the name",
        ]
    ):
        return []

    if "rebate" in text and "invoice" in text:
        return ["upgrade_specific_rebate_line_amount"]

    return []


def render_check_method_label(check_method: str) -> str:
    labels = {
        "genai": "genai",
        "code": "code",
        "hybrid": "hybrid",
        "out_of_scope": "not a claims rule",
    }
    return labels.get(check_method, check_method)


def build_doc() -> Document:
    doc = Document()
    pdf_pages = extract_pdf_pages()

    for section in doc.sections:
        section.top_margin = Inches(0.7)
        section.bottom_margin = Inches(0.7)
        section.left_margin = Inches(0.8)
        section.right_margin = Inches(0.8)

    styles = doc.styles
    styles["Normal"].font.name = "Times New Roman"
    styles["Normal"].font.size = Pt(11)
    for style_name in ["Title", "Heading 1", "Heading 2"]:
        styles[style_name].font.name = "Times New Roman"

    doc.add_paragraph(
        "Energy Savings Program Requirements Traceability Audit",
        style="Title",
    )
    meta = doc.add_paragraph()
    add_runs(
        meta,
        "Source of truth: RebateEligibilityRequirements_ESP_1April2026.pdf. "
        "This version quotes source sentences, maps only to real persisted keys, and includes a full-source appendix at the end.",
        italic=True,
        size=Pt(10),
    )

    red = RGBColor(0xB0, 0x00, 0x20)

    for section in SECTIONS:
        doc.add_paragraph(section["title"], style="Heading 1")
        section_pages = SECTION_PAGES.get(section["title"], [])
        for idx, item in enumerate(section["items"]):
            page = item.get("page") or (section_pages[idx] if idx < len(section_pages) else None)
            p = doc.add_paragraph()
            quote_label = "Source quote"
            if page == "N/A":
                quote_label = "Source quote"
            elif page is not None:
                quote_label = f"Source quote (PDF p. {page})"
            add_runs(p, f"{quote_label}: ", bold=True)
            add_runs(p, item["quote"])
            if isinstance(page, int):
                add_runs(p, "  ")
                add_internal_hyperlink(
                    p,
                    anchor=f"appendix_page_{page}",
                    text=f"See full requirements appendix p. {page}",
                )

            status = doc.add_paragraph()
            add_runs(status, f"{item['status']}. ", color=red, bold=True)

            evidence_sources = infer_evidence_sources(section["title"], idx + 1, item)
            p_sources = doc.add_paragraph(style="List Bullet")
            add_runs(p_sources, "Evidence sources required: ", color=red, bold=True)
            add_runs(p_sources, ", ".join(evidence_sources), color=red)

            check_method = infer_check_method(section["title"], idx + 1, item)
            p_method = doc.add_paragraph(style="List Bullet")
            add_runs(p_method, "How this check should be done: ", color=red, bold=True)
            add_runs(p_method, render_check_method_label(check_method), color=red)

            located_fields = infer_located_fields(section["title"], idx + 1, item)
            p_fields = doc.add_paragraph(style="List Bullet")
            add_runs(p_fields, "Likely located fields required: ", color=red, bold=True)
            add_runs(p_fields, ", ".join(located_fields) if located_fields else "none", color=red)

            if item["implemented"]:
                p_impl = doc.add_paragraph(style="List Bullet")
                add_runs(p_impl, "Traceability keys in system: ", color=red, bold=True)
                add_runs(p_impl, " ".join(item["implemented"]), color=red)

            if item["missing"]:
                p_miss = doc.add_paragraph(style="List Bullet")
                add_runs(p_miss, "Missing now: ", color=red, bold=True)
                add_runs(p_miss, " ".join(item["missing"]), color=red)

            p_pri = doc.add_paragraph(style="List Bullet")
            add_runs(p_pri, "Priority: ", color=red, bold=True)
            add_runs(p_pri, item["priority"], color=red)

            doc.add_paragraph()

    doc.add_paragraph("Full Requirements Appendix", style="Heading 1")
    appendix_intro = doc.add_paragraph()
    add_runs(
        appendix_intro,
        "The pages below are extracted from the source PDF so each audit quote above can be traced back to the fuller surrounding source text.",
        italic=True,
        size=Pt(10),
    )

    for page in pdf_pages:
        heading = doc.add_paragraph(style="Heading 2")
        add_bookmark(
            heading,
            bookmark_name=f"appendix_page_{page['page_number']}",
            bookmark_text=f"Source PDF Page {page['page_number']}",
        )
        body = doc.add_paragraph()
        add_runs(body, page["text"])

    return doc


def save_doc():
    doc = build_doc()
    fd, tmpname = tempfile.mkstemp(suffix=".docx")
    os.close(fd)
    doc.save(tmpname)
    try:
        shutil.copyfile(tmpname, OUT_PATH)
        target = OUT_PATH
    except PermissionError:
        shutil.copyfile(tmpname, FALLBACK_OUT_PATH)
        target = FALLBACK_OUT_PATH
    Path(tmpname).unlink(missing_ok=True)
    return target


if __name__ == "__main__":
    print(save_doc())
