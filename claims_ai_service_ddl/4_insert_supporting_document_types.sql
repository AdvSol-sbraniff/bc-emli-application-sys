BEGIN;

INSERT INTO claims.supporting_document_types (
  id,
  type_key,
  description,
  enabled,
  created_at,
  updated_at
)
VALUES
  ('0d67f495-bf0f-4aa4-8e63-1519d4200001'::uuid, 'approved_heat_load_calculation', 'Approved Heat Load Calculation', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200002'::uuid, 'before_after_photo_set', 'Before / After Photo Set', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200003'::uuid, 'certification_sheet', 'Certification Sheet', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200004'::uuid, 'commissioning_or_control_document', 'Commissioning / Control Document', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200005'::uuid, 'energy_performance_label', 'Energy Performance Label', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200006'::uuid, 'energy_star_label', 'ENERGY STAR Label', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200007'::uuid, 'f280_heat_load_calculation', 'F280 Heat Load Calculation', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200008'::uuid, 'floor_plan_document', 'Floor Plan Document', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200009'::uuid, 'fossil_fuel_removal_proof', 'Fossil Fuel Removal Proof', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200010'::uuid, 'fossil_modification_or_removal_proof', 'Fossil Modification / Removal Proof', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200011'::uuid, 'fossil_removal_proof', 'Fossil Removal Proof', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200012'::uuid, 'income_verification_document', 'Income Verification Document', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200013'::uuid, 'landlord_consent_form', 'Landlord Consent Form', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200014'::uuid, 'manufacturer_label_photo', 'Manufacturer Label Photo', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200015'::uuid, 'non_integrated_area_preapproval_notice', 'Non-Integrated Area Preapproval Notice', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200016'::uuid, 'oil_removal_proof', 'Oil Removal Proof', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200017'::uuid, 'permit_document', 'Permit Document', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200018'::uuid, 'preapproval_notice', 'Preapproval Notice', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200019'::uuid, 'preapproval_quote', 'Preapproval Quote', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200020'::uuid, 'product_spec_sheet', 'Product Spec Sheet', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200021'::uuid, 'utility_bill_or_account_document', 'Utility Bill or Account Document', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200022'::uuid, 'utility_bill_or_invoice', 'Utility Bill or Invoice', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200023'::uuid, 'utility_invoice', 'Utility Invoice', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200024'::uuid, 'utility_upgrade_document', 'Utility Upgrade Document', true, NOW(), NOW()),
  ('0d67f495-bf0f-4aa4-8e63-1519d4200025'::uuid, 'wett_report', 'WETT Report', true, NOW(), NOW())
ON CONFLICT (type_key) DO UPDATE SET
  description = EXCLUDED.description,
  enabled = EXCLUDED.enabled,
  updated_at = NOW();

COMMIT;
