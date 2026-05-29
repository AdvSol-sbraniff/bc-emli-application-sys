BEGIN;

-- First-pass supporting-document field extraction registry.
-- These rows define what the triage/classifier call should locate after it
-- classifies an uploaded file as a supporting document.
WITH field_seed (
  supporting_document_type_key,
  field_key,
  field_number,
  prompt_text,
  enabled
) AS (
  VALUES
  ('utility_bill_or_account_document', 'utility_provider', 1, 'Locate the utility provider name, such as BC Hydro, FortisBC, New Westminster, Penticton, Nelson Hydro, Summerland, Grand Forks, or Pacific Northern Gas.', true),
  ('utility_bill_or_account_document', 'account_holder_name', 2, 'Locate the utility account holder/customer name if visible.', true),
  ('utility_bill_or_account_document', 'service_address', 3, 'Locate the utility service address or premises address if visible.', true),
  ('utility_bill_or_account_document', 'account_or_bill_date', 4, 'Locate the bill date, statement date, account date, or service-period date if visible.', true),
  ('utility_bill_or_account_document', 'residential_account_evidence', 5, 'Locate text indicating this is a residential account, residential service, domestic service, or similar non-strata/non-landlord account evidence.', true),

  ('income_verification_document', 'document_holder_name', 1, 'Locate the person name shown on the income verification document.', true),
  ('income_verification_document', 'document_date_or_tax_year', 2, 'Locate the document date, benefit date, tax year, or effective date if visible.', true),
  ('income_verification_document', 'income_or_benefit_evidence', 3, 'Locate income line, line 15000, benefit program, or other income-qualification evidence if visible.', true),
  ('income_verification_document', 'redaction_or_legibility_concern', 4, 'Locate or summarize any visible redaction, cutoff, blur, or legibility issue affecting required income evidence.', true),

  ('landlord_consent_form', 'tenant_or_resident_name', 1, 'Locate the tenant, resident, or participant name if visible.', true),
  ('landlord_consent_form', 'property_owner_name', 2, 'Locate the landlord or registered property owner name if visible.', true),
  ('landlord_consent_form', 'property_address', 3, 'Locate the rental/home property address covered by the consent form.', true),
  ('landlord_consent_form', 'consent_signature_date', 4, 'Locate the landlord/property-owner consent signature date if visible.', true),

  ('wett_report', 'wett_inspection_date', 1, 'Locate the WETT inspection or report date.', true),
  ('wett_report', 'wett_inspector_certification_number', 2, 'Locate the WETT inspector certification number or inspector registration number.', true),
  ('wett_report', 'site_address', 3, 'Locate the inspected site address.', true),
  ('wett_report', 'compliance_or_removal_conclusion', 4, 'Locate the report conclusion about wood appliance compliance, removal, decommissioning, or not being in use.', true),

  ('fossil_fuel_removal_proof', 'removed_equipment_type', 1, 'Locate the fossil-fuel equipment type removed or decommissioned, such as gas furnace, propane furnace, boiler, or oil tank.', true),
  ('fossil_fuel_removal_proof', 'removal_date_or_permit_reference', 2, 'Locate the removal/decommissioning date, inspection date, permit number, or permit date.', true),
  ('fossil_fuel_removal_proof', 'site_address', 3, 'Locate the site address for the removal/decommissioning work.', true),
  ('fossil_fuel_removal_proof', 'contractor_or_authority_name', 4, 'Locate the contractor, fuel supplier, inspection authority, or permit authority name if visible.', true),

  ('oil_removal_proof', 'removed_equipment_type', 1, 'Locate evidence of oil system, oil tank, oil furnace, or oil boiler removal/decommissioning.', true),
  ('oil_removal_proof', 'removal_date_or_permit_reference', 2, 'Locate the oil removal/decommissioning date, inspection date, permit number, or permit date.', true),
  ('oil_removal_proof', 'site_address', 3, 'Locate the site address for the oil system removal/decommissioning work.', true),
  ('oil_removal_proof', 'contractor_or_authority_name', 4, 'Locate the contractor, fuel supplier, inspection authority, or permit authority name if visible.', true),

  ('fossil_removal_proof', 'removed_equipment_type', 1, 'Locate the fossil-fuel equipment type removed or decommissioned.', true),
  ('fossil_removal_proof', 'removal_date_or_permit_reference', 2, 'Locate the removal/decommissioning date, inspection date, permit number, or permit date.', true),
  ('fossil_removal_proof', 'site_address', 3, 'Locate the site address for the removal/decommissioning work.', true),
  ('fossil_removal_proof', 'contractor_or_authority_name', 4, 'Locate the contractor, fuel supplier, inspection authority, or permit authority name if visible.', true),

  ('utility_invoice', 'utility_provider', 1, 'Locate the utility provider name.', true),
  ('utility_invoice', 'previous_service_size', 2, 'Locate previous electrical service size if visible, such as 60 amp or 100 amp.', true),
  ('utility_invoice', 'new_service_size', 3, 'Locate new/upgraded electrical service size if visible, such as 100 amp, 200 amp, or 400 amp.', true),
  ('utility_invoice', 'service_address', 4, 'Locate the service address for the utility service upgrade.', true),
  ('utility_invoice', 'service_completion_or_invoice_date', 5, 'Locate utility invoice date, completion date, connection date, or service upgrade date.', true),
  ('utility_invoice', 'utility_upgrade_cost_or_reference', 6, 'Locate utility upgrade cost, connection fee, service upgrade reference, work order, or invoice number.', true),

  ('utility_upgrade_document', 'utility_provider', 1, 'Locate the utility provider name.', true),
  ('utility_upgrade_document', 'previous_service_size', 2, 'Locate previous electrical service size if visible.', true),
  ('utility_upgrade_document', 'new_service_size', 3, 'Locate new/upgraded electrical service size if visible.', true),
  ('utility_upgrade_document', 'service_address', 4, 'Locate the service address for the utility service upgrade.', true),
  ('utility_upgrade_document', 'service_completion_or_invoice_date', 5, 'Locate completion date, connection date, approval date, or utility document date.', true),
  ('utility_upgrade_document', 'utility_upgrade_cost_or_reference', 6, 'Locate utility upgrade cost, service upgrade reference, work order, permit, or approval number.', true),

  ('energy_performance_label', 'brand_and_model', 1, 'Locate brand, make, product name, and model reference visible on the label.', true),
  ('energy_performance_label', 'model_number', 2, 'Locate the model number or model identifier.', true),
  ('energy_performance_label', 'metric_u_factor', 3, 'Locate U-factor, metric U-factor, or equivalent energy-performance rating if visible.', true),
  ('energy_performance_label', 'nrcan_number', 4, 'Locate NRCan reference number if visible.', true),
  ('energy_performance_label', 'energy_star_reference', 5, 'Locate ENERGY STAR or qualified product-list reference if visible.', true),

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

  ('product_spec_sheet', 'brand_and_model', 1, 'Locate brand, make, product name, and model reference visible on the specification sheet.', true),
  ('product_spec_sheet', 'model_number', 2, 'Locate the model number or model identifier.', true),
  ('product_spec_sheet', 'efficiency_or_capacity_rating', 3, 'Locate relevant efficiency, capacity, CFM, U-factor, NEEA, AHRI, NRCan, or ENERGY STAR rating evidence if visible.', true),
  ('product_spec_sheet', 'product_list_reference', 4, 'Locate AHRI, NEEA, NRCan, ENERGY STAR, CPD, or other product-list/certification reference if visible.', true),

  ('energy_star_label', 'energy_star_reference', 1, 'Locate ENERGY STAR evidence, logo text, certification wording, or qualified product reference.', true),
  ('energy_star_label', 'brand_and_model', 2, 'Locate brand, make, product name, and model reference visible on the label.', true),
  ('energy_star_label', 'model_number', 3, 'Locate the model number or model identifier.', true),

  ('f280_heat_load_calculation', 'calculation_date', 1, 'Locate the heat-load calculation date or report date.', true),
  ('f280_heat_load_calculation', 'site_address', 2, 'Locate the home/site address for the heat-load calculation.', true),
  ('f280_heat_load_calculation', 'design_heat_load_value', 3, 'Locate design heat load, capacity sizing, or calculated heating load value if visible.', true),
  ('f280_heat_load_calculation', 'professional_or_company_name', 4, 'Locate the designer, professional, contractor, or company name associated with the calculation.', true),

  ('approved_heat_load_calculation', 'calculation_date', 1, 'Locate the heat-load calculation date or approval date.', true),
  ('approved_heat_load_calculation', 'site_address', 2, 'Locate the home/site address for the heat-load calculation.', true),
  ('approved_heat_load_calculation', 'design_heat_load_value', 3, 'Locate design heat load, capacity sizing, or calculated heating load value if visible.', true),
  ('approved_heat_load_calculation', 'approval_or_professional_reference', 4, 'Locate approval, designer, professional, contractor, or company reference if visible.', true),

  ('commissioning_or_control_document', 'commissioning_date', 1, 'Locate commissioning date, setup date, or control document date if visible.', true),
  ('commissioning_or_control_document', 'equipment_reference', 2, 'Locate equipment make/model, heat pump reference, or control equipment reference.', true),
  ('commissioning_or_control_document', 'switchover_setpoint', 3, 'Locate switchover setpoint, lockout temperature, control setting, or dual-fuel control evidence if visible.', true),

  ('permit_document', 'permit_number', 1, 'Locate permit number, authorization number, or inspection number.', true),
  ('permit_document', 'permit_date', 2, 'Locate permit issue date, inspection date, completion date, or approval date.', true),
  ('permit_document', 'permit_address', 3, 'Locate the property/site address on the permit.', true),
  ('permit_document', 'authority_name', 4, 'Locate the authority having jurisdiction, municipality, Technical Safety BC, or other issuing authority.', true),

  ('before_after_photo_set', 'before_photo_evidence', 1, 'Locate text, captions, filenames, or page labels indicating before-photo evidence.', true),
  ('before_after_photo_set', 'after_photo_evidence', 2, 'Locate text, captions, filenames, or page labels indicating after-photo evidence.', true),
  ('before_after_photo_set', 'subject_area_evidence', 3, 'Locate text or captions identifying the photographed subject or area, such as insulation, remediation, attic, wall, crawlspace, or label.', true),
  ('before_after_photo_set', 'visual_review_limitation', 4, 'Summarize whether text-only DI is insufficient and visual review is required to confirm the photo content.', true)
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
