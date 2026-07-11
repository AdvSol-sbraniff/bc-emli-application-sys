BEGIN;

-- First-pass tracker-derived supplement-type applicability seed.
-- This table expresses which supporting-document types are relevant to each
-- invoice upgrade type. It does not encode required/optional semantics; those
-- remain in the tracker and future runtime/admin rule layers.
WITH supporting_document_type_upgrade_types_seed (
  supporting_document_type_key,
  upgrade_type_key
) AS (
  VALUES
  ('utility_bill', 'common'),
  ('landlord_consent_form', 'common'),

  ('utility_bill', 'air_source_heat_pump_electric'),
  ('f280_heat_load_calculation', 'air_source_heat_pump_electric'),
  ('product_spec_sheet', 'air_source_heat_pump_electric'),
  ('manufacturer_label_photo', 'air_source_heat_pump_electric'),

  ('before_after_photo_set', 'air_source_heat_pump_wood'),
  ('wett_report', 'air_source_heat_pump_wood'),
  ('f280_heat_load_calculation', 'air_source_heat_pump_wood'),
  ('product_spec_sheet', 'air_source_heat_pump_wood'),
  ('manufacturer_label_photo', 'air_source_heat_pump_wood'),

  ('fossil_fuel_removal_proof', 'air_source_heat_pump_gas_propane'),
  ('permit_document', 'air_source_heat_pump_gas_propane'),
  ('preapproval_notice', 'air_source_heat_pump_gas_propane'),
  ('f280_heat_load_calculation', 'air_source_heat_pump_gas_propane'),
  ('product_spec_sheet', 'air_source_heat_pump_gas_propane'),
  ('manufacturer_label_photo', 'air_source_heat_pump_gas_propane'),

  ('oil_removal_proof', 'air_source_heat_pump_oil'),
  ('permit_document', 'air_source_heat_pump_oil'),
  ('utility_bill', 'air_source_heat_pump_oil'),
  ('preapproval_notice', 'air_source_heat_pump_oil'),
  ('f280_heat_load_calculation', 'air_source_heat_pump_oil'),
  ('product_spec_sheet', 'air_source_heat_pump_oil'),
  ('manufacturer_label_photo', 'air_source_heat_pump_oil'),

  ('dual_fuel_control_document', 'dual_fuel_ducted_heat_pump'),
  ('fossil_fuel_removal_proof', 'dual_fuel_ducted_heat_pump'),
  ('fossil_backup_system_document', 'dual_fuel_ducted_heat_pump'),
  ('permit_document', 'dual_fuel_ducted_heat_pump'),
  ('f280_heat_load_calculation', 'dual_fuel_ducted_heat_pump'),
  ('preapproval_notice', 'dual_fuel_ducted_heat_pump'),
  ('product_spec_sheet', 'dual_fuel_ducted_heat_pump'),
  ('manufacturer_label_photo', 'dual_fuel_ducted_heat_pump'),

  ('product_spec_sheet', 'air_to_water_heat_pump'),
  ('manufacturer_label_photo', 'air_to_water_heat_pump'),
  ('fossil_fuel_removal_proof', 'air_to_water_heat_pump'),
  ('permit_document', 'air_to_water_heat_pump'),
  ('before_after_photo_set', 'air_to_water_heat_pump'),
  ('wett_report', 'air_to_water_heat_pump'),
  ('preapproval_notice', 'air_to_water_heat_pump'),
  ('f280_heat_load_calculation', 'air_to_water_heat_pump'),

  ('product_spec_sheet', 'combined_space_water_heat_pump'),
  ('manufacturer_label_photo', 'combined_space_water_heat_pump'),
  ('fossil_fuel_removal_proof', 'combined_space_water_heat_pump'),
  ('permit_document', 'combined_space_water_heat_pump'),
  ('before_after_photo_set', 'combined_space_water_heat_pump'),
  ('wett_report', 'combined_space_water_heat_pump'),
  ('f280_heat_load_calculation', 'combined_space_water_heat_pump'),

  ('product_spec_sheet', 'heat_pump_water_heater'),
  ('manufacturer_label_photo', 'heat_pump_water_heater'),
  ('fossil_fuel_removal_proof', 'heat_pump_water_heater'),
  ('preapproval_notice', 'heat_pump_water_heater'),
  ('permit_document', 'heat_pump_water_heater'),

  ('utility_bill', 'electrical_service_upgrade'),
  ('electrical_utility_upgrade_document', 'electrical_service_upgrade'),

  ('before_after_photo_set', 'health_and_safety_remediation'),

  ('product_spec_sheet', 'ventilation'),
  ('energy_star_label', 'ventilation')
)
INSERT INTO claims.supporting_document_type_upgrade_types (
  supporting_document_type_id,
  invoice_upgrade_type_id,
  created_at
)
SELECT
  sdt.id,
  iut.id,
  NOW()
FROM supporting_document_type_upgrade_types_seed seed
JOIN claims.supporting_document_types sdt
  ON sdt.type_key = seed.supporting_document_type_key
JOIN claims.invoice_upgrade_types iut
  ON iut.upgrade_type_key = seed.upgrade_type_key
ON CONFLICT (supporting_document_type_id, invoice_upgrade_type_id) DO NOTHING;

COMMIT;
