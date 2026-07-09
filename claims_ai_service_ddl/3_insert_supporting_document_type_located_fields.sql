BEGIN;

-- Supporting-document field extraction registry.
-- These rows define what the separate supporting-document extraction call
-- should locate after triage classifies an uploaded file as a supporting document.
DELETE FROM claims.supporting_document_type_located_fields
WHERE field_key = 'non_integrated_area_evidence'
  AND supporting_document_type_id IN (
    SELECT id
    FROM claims.supporting_document_types
    WHERE type_key = 'preapproval_notice'
  );

WITH field_seed (
  supporting_document_type_key,
  field_key,
  field_number,
  prompt_text,
  enabled
) AS (
  VALUES
  ('utility_bill', 'utility_provider', 1, 'Locate the utility provider name, such as BC Hydro, FortisBC, New Westminster, Penticton, Nelson Hydro, Summerland, Grand Forks, or Pacific Northern Gas.', true),
  ('utility_bill', 'account_holder_name', 2, 'Locate the utility account holder/customer name if visible.', true),
  ('utility_bill', 'service_address', 3, 'Locate the utility service address or premises address if visible.', true),
  ('utility_bill', 'account_or_bill_date', 4, 'Locate the bill date, statement date, account date, or service-period date if visible.', true),
  ('utility_bill', 'residential_account_evidence', 5, 'Locate text indicating this is a residential account, residential service, domestic service, or similar non-strata/non-landlord account evidence.', true),
  ('utility_bill', 'strata_or_landlord_account_evidence', 6, 'Locate any text indicating the utility account is held by a strata corporation, landlord, property manager, or other non-resident/non-homeowner account holder.', true),
  ('utility_bill', 'utility_service_type_or_fuel_evidence', 7, 'Locate utility service type or fuel evidence, such as electric service, natural gas, propane, oil delivery, or other account/service wording.', true),
  ('utility_bill', 'account_number_or_reference', 8, 'Locate the account number, customer number, meter number, premise ID, service ID, or similar utility account reference if visible.', true),
  ('utility_bill', 'fuel_consumption_quantity_or_period', 9, 'Locate fuel or utility consumption quantities and service periods if visible, such as litres of oil delivered, kWh, GJ, cubic metres, billing period, annual consumption, or delivery period.', true),
  ('utility_bill', 'previous_service_size', 10, 'Locate previous electrical service size if visible, such as 60 amp or 100 amp.', true),
  ('utility_bill', 'new_service_size', 11, 'Locate new/upgraded electrical service size if visible, such as 100 amp, 200 amp, or 400 amp.', true),
  ('utility_bill', 'service_completion_or_invoice_date', 12, 'Locate utility invoice date, completion date, connection date, service-upgrade date, or service-period date if visible.', true),
  ('utility_bill', 'utility_upgrade_cost_or_reference', 13, 'Locate utility upgrade cost, connection fee, service upgrade reference, work order, invoice number, account reference, or similar billing reference if visible.', true),

  ('landlord_consent_form', 'tenant_or_resident_name', 1, 'Locate the tenant, resident, or participant name if visible.', true),
  ('landlord_consent_form', 'property_owner_name', 2, 'Locate the landlord or registered property owner name if visible.', true),
  ('landlord_consent_form', 'property_address', 3, 'Locate the rental/home property address covered by the consent form.', true),
  ('landlord_consent_form', 'consent_signature_date', 4, 'Locate the landlord/property-owner consent signature date if visible.', true),
  ('landlord_consent_form', 'owner_signature_evidence', 5, 'Locate evidence that the landlord or registered property owner signed or completed the consent form.', true),
  ('landlord_consent_form', 'consented_upgrade_scope', 6, 'Locate the upgrade scope or program work the landlord/property owner consented to, if visible.', true),

  ('wett_report', 'wett_inspection_date', 1, 'Locate the WETT inspection or report date.', true),
  ('wett_report', 'wett_inspector_certification_number', 2, 'Locate the WETT inspector certification number or inspector registration number.', true),
  ('wett_report', 'site_address', 3, 'Locate the inspected site address.', true),
  ('wett_report', 'compliance_or_removal_conclusion', 4, 'Locate the report conclusion about wood appliance compliance, removal, decommissioning, or not being in use.', true),
  ('wett_report', 'wett_inspector_or_company_name', 5, 'Locate the WETT inspector name, inspection company, or certifying organization if visible.', true),
  ('wett_report', 'wett_appliance_or_system_reference', 6, 'Locate the wood or solid-fuel appliance/system reference covered by the WETT report, such as stove, fireplace, insert, boiler, furnace, or chimney.', true),

  ('fossil_fuel_removal_proof', 'removed_equipment_type', 1, 'Locate the fossil-fuel equipment type removed or decommissioned, such as gas furnace, propane furnace, boiler, or oil tank.', true),
  ('fossil_fuel_removal_proof', 'removal_date_or_permit_reference', 2, 'Locate the removal/decommissioning date, inspection date, permit number, or permit date.', true),
  ('fossil_fuel_removal_proof', 'site_address', 3, 'Locate the site address for the removal/decommissioning work.', true),
  ('fossil_fuel_removal_proof', 'contractor_or_authority_name', 4, 'Locate the contractor, fuel supplier, inspection authority, or permit authority name if visible.', true),
  ('fossil_fuel_removal_proof', 'removal_scope_or_description', 5, 'Locate the description of removal/decommissioning work completed, including appliance, piping, vent, fuel container, tank, capping, disconnection, or by-law/compliance wording.', true),

  ('oil_removal_proof', 'removed_equipment_type', 1, 'Locate evidence of oil system, oil tank, oil furnace, or oil boiler removal/decommissioning.', true),
  ('oil_removal_proof', 'removal_date_or_permit_reference', 2, 'Locate the oil removal/decommissioning date, inspection date, permit number, or permit date.', true),
  ('oil_removal_proof', 'site_address', 3, 'Locate the site address for the oil system removal/decommissioning work.', true),
  ('oil_removal_proof', 'contractor_or_authority_name', 4, 'Locate the contractor, fuel supplier, inspection authority, or permit authority name if visible.', true),
  ('oil_removal_proof', 'removal_scope_or_description', 5, 'Locate the description of oil system or oil tank removal/decommissioning work completed, including capping, disconnection, tank removal, appliance removal, or by-law/compliance wording.', true),

  ('fossil_backup_system_document', 'backup_equipment_type', 1, 'Locate the fossil-fuel backup, retained, removed, or modified equipment type, such as gas furnace, propane furnace, boiler, piping, vent, fuel container, or other backup heat source.', true),
  ('fossil_backup_system_document', 'backup_system_document_date_or_permit_reference', 2, 'Locate the document date, commissioning date, modification date, removal date, inspection date, permit number, or permit date for the fossil backup/removal/modification work.', true),
  ('fossil_backup_system_document', 'site_address', 3, 'Locate the site address for the retained, removed, or modified fossil backup system.', true),
  ('fossil_backup_system_document', 'contractor_or_authority_name', 4, 'Locate the contractor, fuel supplier, inspection authority, permit authority, or heat-pump installation company name if visible.', true),
  ('fossil_backup_system_document', 'backup_system_scope_or_description', 5, 'Locate the description of fossil-fuel system removal, modification, retained/limited backup setup, controls, switchover, capping, disconnection, piping, appliance, vent, fuel container, tank, or by-law/compliance wording.', true),

  ('electrical_utility_upgrade_document', 'utility_provider', 1, 'Locate the electrical utility provider name, especially BC Hydro or FortisBC, if visible.', true),
  ('electrical_utility_upgrade_document', 'previous_service_size', 2, 'Locate previous electrical service size if visible.', true),
  ('electrical_utility_upgrade_document', 'new_service_size', 3, 'Locate new/upgraded electrical service size if visible.', true),
  ('electrical_utility_upgrade_document', 'service_address', 4, 'Locate the service address for the electrical utility service upgrade.', true),
  ('electrical_utility_upgrade_document', 'service_completion_or_invoice_date', 5, 'Locate completion date, connection date, approval date, or utility document date.', true),
  ('electrical_utility_upgrade_document', 'utility_upgrade_cost_or_reference', 6, 'Locate utility upgrade cost, service upgrade reference, work order, permit, or approval number.', true),

  ('fenestration_energy_performance_label', 'brand_and_model', 1, 'Locate brand, make, product name, and model reference visible on the fenestration label.', true),
  ('fenestration_energy_performance_label', 'model_number', 2, 'Locate the window/door model number or model identifier.', true),
  ('fenestration_energy_performance_label', 'metric_u_factor', 3, 'Locate U-factor, metric U-factor, or equivalent fenestration energy-performance rating if visible.', true),
  ('fenestration_energy_performance_label', 'nrcan_number', 4, 'Locate NRCan fenestration reference number if visible.', true),
  ('fenestration_energy_performance_label', 'energy_star_reference', 5, 'Locate ENERGY STAR, qualified product-list, or fenestration-rating reference if visible.', true),
  ('fenestration_energy_performance_label', 'product_category_or_system_type', 6, 'Locate the fenestration product category shown on the label, such as window, door, sliding door, or patio door.', true),
  ('fenestration_energy_performance_label', 'label_legibility_concern', 7, 'Locate or summarize any visible blur, cutoff, glare, low resolution, or other fenestration label legibility issue.', true),

  ('certification_sheet', 'certification_body_reference', 1, 'Locate the certification body or certification program reference.', true),
  ('certification_sheet', 'brand_and_model', 2, 'Locate brand, make, product name, and model reference visible on the certification sheet.', true),
  ('certification_sheet', 'model_number', 3, 'Locate the model number or model identifier.', true),
  ('certification_sheet', 'metric_u_factor', 4, 'Locate U-factor, metric U-factor, or equivalent performance rating if visible.', true),
  ('certification_sheet', 'cpd_number', 5, 'Locate CPD number or certification product directory number if visible.', true),
  ('certification_sheet', 'nrcan_number', 6, 'Locate NRCan reference number if visible.', true),

  ('manufacturer_label_photo', 'brand_and_model', 1, 'Locate brand, make, product name, and model reference visible on the label/photo.', true),
  ('manufacturer_label_photo', 'model_number', 2, 'Locate the model number or model identifier visible on the label/photo.', true),
  ('manufacturer_label_photo', 'serial_number', 3, 'Locate serial number if visible.', true),
  ('manufacturer_label_photo', 'label_legibility_concern', 4, 'Locate or summarize any visible blur, cutoff, glare, low resolution, or other label legibility issue.', true),
  ('manufacturer_label_photo', 'equipment_type_or_product_category', 5, 'Locate the equipment or product category visible on the label/photo, such as window, door, heat pump, water heater, HRV, ERV, or bathroom fan.', true),
  ('manufacturer_label_photo', 'certification_or_listing_reference', 6, 'Locate ENERGY STAR, NRCan, AHRI, NEEA, CPD, NFRC, or other certification/listing reference visible on the label/photo.', true),
  ('manufacturer_label_photo', 'metric_u_factor', 7, 'Locate U-factor, metric U-factor, or equivalent fenestration energy-performance rating if visible on the label/photo.', true),
  ('manufacturer_label_photo', 'nrcan_number', 8, 'Locate NRCan reference number if visible on the label/photo.', true),
  ('manufacturer_label_photo', 'cpd_number', 9, 'Locate CPD, NFRC Certified Products Directory, or similar fenestration product-directory number if visible on the label/photo.', true),
  ('manufacturer_label_photo', 'installed_unit_location_or_count_evidence', 10, 'Locate labels, filenames, captions, room/location names, unit numbers, or counts that help determine whether label photos cover each installed unit.', true),
  ('manufacturer_label_photo', 'ahri_reference', 11, 'Locate AHRI reference number, AHRI certificate number, or AHRI certified reference evidence if visible on the label/photo.', true),

  ('product_spec_sheet', 'brand_and_model', 1, 'Locate brand, make, product name, and model reference visible on the specification sheet.', true),
  ('product_spec_sheet', 'model_number', 2, 'Locate the model number or model identifier.', true),
  ('product_spec_sheet', 'efficiency_or_capacity_rating', 3, 'Locate relevant efficiency, capacity, CFM, U-factor, NEEA, AHRI, NRCan, or ENERGY STAR rating evidence if visible.', true),
  ('product_spec_sheet', 'product_list_reference', 4, 'Locate AHRI, NEEA, NRCan, ENERGY STAR, CPD, or other product-list/certification reference if visible.', true),
  ('product_spec_sheet', 'energy_star_reference', 5, 'Locate ENERGY STAR certification, ENERGY STAR product list, logo text, or qualified product wording if visible.', true),
  ('product_spec_sheet', 'nrcan_reference', 6, 'Locate Natural Resources Canada, NRCan searchable product list, or Canadian product-list reference if visible.', true),
  ('product_spec_sheet', 'neea_reference', 7, 'Locate NEEA Advanced Water Heater Specification, NEEA qualified product list, or similar water-heater product-list reference if visible.', true),
  ('product_spec_sheet', 'tier_reference', 8, 'Locate Tier 2 or higher evidence if visible.', true),
  ('product_spec_sheet', 'bathroom_fan_cfm', 9, 'Locate bathroom fan capacity in cfm or L/s if visible.', true),
  ('product_spec_sheet', 'static_pressure', 10, 'Locate static pressure rating evidence, such as 50 Pa, 0.2 in. w.c., 0.6 in. WC, or similar.', true),
  ('product_spec_sheet', 'direct_exterior_ducting_evidence', 13, 'Locate direct-to-outdoors ducting, exterior exhaust, sealed ducting, insulated ducting, duct hood, or screened hood evidence if visible.', true),
  ('product_spec_sheet', 'main_bathroom_evidence', 14, 'Locate main bathroom, bathtub, shower, or similar bathroom-location evidence if visible.', true),
  ('product_spec_sheet', 'product_spec_legibility_concern', 15, 'Locate or summarize any visible cutoff, blur, missing page, table ambiguity, or other legibility issue affecting required product specification evidence.', true),
  ('product_spec_sheet', 'ahri_reference', 16, 'Locate AHRI reference number, AHRI certificate number, or AHRI certified reference evidence if visible.', true),
  ('product_spec_sheet', 'capacity_btu_or_kw', 17, 'Locate heating, cooling, ventilation, or water-heating capacity values if visible, including BTU/h, kW, CFM, or L/s.', true),
  ('product_spec_sheet', 'seer_or_seer2_rating', 18, 'Locate SEER, SEER2, cooling efficiency, or related seasonal cooling-efficiency rating if visible.', true),
  ('product_spec_sheet', 'hspf_or_hspf2_rating', 19, 'Locate HSPF, HSPF2, Region V HSPF, or related seasonal heating-efficiency rating if visible.', true),
  ('product_spec_sheet', 'duct_sealing_evidence', 20, 'Locate duct sealing, sealed joints, sealed ducting, tape/mastic, airtight duct, or similar bathroom-fan duct-sealing evidence if visible.', true),
  ('product_spec_sheet', 'duct_insulation_r_value', 21, 'Locate duct insulation evidence and R-value if visible, especially R4 or higher for bathroom-fan ducting.', true),
  ('product_spec_sheet', 'installation_standard_or_guide_reference', 22, 'Locate installation-standard, manufacturer-installation, BC Housing guide, ventilation guide, code, or similar installation-compliance reference if visible.', true),

  ('energy_star_label', 'energy_star_reference', 1, 'Locate ENERGY STAR evidence, logo text, certification wording, or qualified product reference.', true),
  ('energy_star_label', 'brand_and_model', 2, 'Locate brand, make, product name, and model reference visible on the label.', true),
  ('energy_star_label', 'model_number', 3, 'Locate the model number or model identifier.', true),
  ('energy_star_label', 'product_category_or_system_type', 4, 'Locate the product category or system type shown with the ENERGY STAR evidence, such as HRV, ERV, bathroom fan, window, door, or water heater.', true),
  ('energy_star_label', 'product_list_reference', 5, 'Locate product-list, certification number, or qualified-product reference associated with the ENERGY STAR label if visible.', true),
  ('energy_star_label', 'nrcan_reference', 6, 'Locate Natural Resources Canada, NRCan searchable product list, Canadian ENERGY STAR listing, or related Canadian product-list reference if visible.', true),
  ('energy_star_label', 'label_legibility_concern', 7, 'Locate or summarize any visible blur, cutoff, glare, low resolution, or other ENERGY STAR label legibility issue.', true),

  ('f280_heat_load_calculation', 'calculation_date', 1, 'Locate the heat-load calculation date or report date.', true),
  ('f280_heat_load_calculation', 'site_address', 2, 'Locate the home/site address for the heat-load calculation.', true),
  ('f280_heat_load_calculation', 'design_heat_load_value', 3, 'Locate design heat load, capacity sizing, or calculated heating load value if visible.', true),
  ('f280_heat_load_calculation', 'professional_or_company_name', 4, 'Locate the designer, professional, contractor, or company name associated with the calculation.', true),
  ('f280_heat_load_calculation', 'calculation_standard_reference', 5, 'Locate CSA-F280-12, F280, heat-load standard, software, or methodology reference if visible.', true),
  ('f280_heat_load_calculation', 'approval_or_professional_reference', 6, 'Locate approval, designer, professional, contractor, program acceptance, or company reference if visible.', true),
  ('f280_heat_load_calculation', 'approval_status_or_condition', 7, 'Locate approval status, approval condition, limitation, revision requirement, or program acceptance wording if visible.', true),
  ('f280_heat_load_calculation', 'sizing_method_or_rule_of_thumb_evidence', 8, 'Locate sizing-method evidence, calculated-sizing evidence, equipment-sizing method, or wording that indicates rule-of-thumb sizing was used or rejected.', true),
  ('f280_heat_load_calculation', 'supplemental_heat_source_assumptions', 9, 'Locate supplemental heat sources considered, included, excluded, or disallowed in the heat-load calculation, including electric heat, non-fossil heat, fossil fuel heat, gas fireplace, propane, natural gas, oil, or wood.', true),

  ('dual_fuel_control_document', 'control_setup_date', 1, 'Locate control setup date, commissioning date, or control document date if visible.', true),
  ('dual_fuel_control_document', 'equipment_reference', 2, 'Locate equipment make/model, heat pump reference, thermostat, outdoor-temperature switch-over control, or equipment control board reference.', true),
  ('dual_fuel_control_document', 'switchover_setpoint', 3, 'Locate switchover setpoint, lockout temperature, control setting, or dual-fuel control evidence if visible.', true),
  ('dual_fuel_control_document', 'backup_fuel_or_integration_evidence', 4, 'Locate fossil-backup fuel, propane/natural-gas integration, dual-fuel wiring/control integration, or retained backup-system evidence if visible.', true),
  ('dual_fuel_control_document', 'region_or_temperature_threshold_evidence', 5, 'Locate region, climate zone, outdoor-temperature threshold, or region-specific switchover threshold evidence if visible.', true),

  ('permit_document', 'permit_number', 1, 'Locate permit number, authorization number, or inspection number.', true),
  ('permit_document', 'permit_date', 2, 'Locate permit issue date, inspection date, completion date, or approval date.', true),
  ('permit_document', 'permit_address', 3, 'Locate the property/site address on the permit.', true),
  ('permit_document', 'authority_name', 4, 'Locate the authority having jurisdiction, municipality, Technical Safety BC, or other issuing authority.', true),
  ('permit_document', 'permit_scope_or_equipment_reference', 5, 'Locate the permitted work scope or equipment reference, such as electrical service, gas/oil removal, water heater, heat pump, venting, tank, panel, or inspection scope.', true),
  ('permit_document', 'permit_status_or_completion_evidence', 6, 'Locate permit status, final inspection, passed inspection, closed permit, completion, approval, deficiency, or correction evidence if visible.', true),

  ('preapproval_quote', 'quote_date', 1, 'Locate the quote date, estimate date, submission date, or revision date if visible.', true),
  ('preapproval_quote', 'quote_reference', 2, 'Locate quote number, estimate number, email subject/reference, contractor reference, or application/reference number if visible.', true),
  ('preapproval_quote', 'quoted_upgrade_scope', 3, 'Locate the quoted upgrade scope, such as windows/doors, ductless-to-ducted conversion, hydronic removal, or other preapproval scope.', true),
  ('preapproval_quote', 'property_or_participant_reference', 4, 'Locate property address, participant/customer name, or other case reference visible on the quote.', true),
  ('preapproval_quote', 'approval_submission_evidence', 5, 'Locate evidence that the quote was submitted for program preapproval or approval before installation, such as submitted, approved, pre-approved, ESP contractor support, or email approval wording.', true),
  ('preapproval_quote', 'quoted_cost_or_amount', 6, 'Locate quoted cost, estimate amount, rebate amount, or amount subject to preapproval if visible.', true),

  ('preapproval_notice', 'preapproval_date', 1, 'Locate the preapproval, approval, email, notice, or decision date if visible.', true),
  ('preapproval_notice', 'approval_reference', 2, 'Locate approval number, application/reference number, email subject/reference, case number, or program reference if visible.', true),
  ('preapproval_notice', 'approved_upgrade_scope', 3, 'Locate the approved upgrade scope covered by the preapproval notice.', true),
  ('preapproval_notice', 'property_or_participant_reference', 4, 'Locate property address, participant/customer name, eligibility code, or other case reference visible on the notice.', true),
  ('preapproval_notice', 'preapproval_condition_or_expiry', 5, 'Locate any approval condition, expiry, required next step, or limitation visible on the preapproval notice.', true),
  ('preapproval_notice', 'approval_status_or_decision', 6, 'Locate the approval decision/status, such as approved, pre-approved, conditional approval, rejected, expired, or pending if visible.', true),

  ('floor_plan_document', 'floor_plan_area_reference', 1, 'Locate text or markings showing the area of new insulation added or the insulation upgrade area.', true),
  ('floor_plan_document', 'floor_plan_location_or_scope', 2, 'Locate the floor, room, attic, wall, crawlspace, basement, exposed floor, or other location/scope shown on the floor plan.', true),
  ('floor_plan_document', 'floor_plan_dimensions_or_square_feet', 3, 'Locate dimensions, square footage, measurements, takeoff values, or other area-calculation evidence shown on the floor plan.', true),
  ('floor_plan_document', 'floor_plan_address_or_project_reference', 4, 'Locate property address, project name, participant/customer name, or other case reference visible on the floor plan.', true),
  ('floor_plan_document', 'floor_plan_legibility_concern', 5, 'Locate or summarize any visible cutoff, missing scale, unreadable measurements, unclear room labels, or other legibility issue affecting floor-plan review.', true),

  ('before_after_photo_set', 'photo_role', 1, 'For this single uploaded file, identify whether the visible evidence appears to be a before photo, after photo, unknown, or not applicable.', true),
  ('before_after_photo_set', 'visible_subject_or_area', 2, 'For this single uploaded file, summarize the visible photographed subject or area, such as insulation, remediation, attic, wall, crawlspace, window label, equipment label, or unknown.', true),
  ('before_after_photo_set', 'visible_condition_summary', 3, 'For this single uploaded file, summarize the visible condition or work state shown in the image.', true),
  ('before_after_photo_set', 'image_quality_or_legibility', 4, 'For this single uploaded file, summarize whether the image is clear enough for review and whether any visible text is legible.', true),
  ('before_after_photo_set', 'visible_text_or_label_values', 5, 'For this single uploaded file, locate any visible text, captions, labels, or label values in the image.', true)
)
INSERT INTO claims.supporting_document_type_located_fields (
  supporting_document_type_id,
  field_key,
  field_number,
  prompt_text,
  enabled,
  created_at,
  updated_at
)
SELECT
  sdt.id,
  seed.field_key,
  seed.field_number,
  seed.prompt_text,
  seed.enabled,
  NOW(),
  NOW()
FROM field_seed seed
JOIN claims.supporting_document_types sdt
  ON sdt.type_key = seed.supporting_document_type_key
ON CONFLICT (supporting_document_type_id, field_key) DO UPDATE SET
  field_number = EXCLUDED.field_number,
  prompt_text = EXCLUDED.prompt_text,
  enabled = EXCLUDED.enabled,
  updated_at = NOW();

COMMIT;
