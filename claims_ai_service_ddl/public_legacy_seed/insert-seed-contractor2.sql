BEGIN;

-- Seed contractor(s) found in local invoice test data.
-- Source invoices:
-- - claims_ai_service_documentation/Test Data/Electric Service Upgrade/test001/CANADA~1.PDF
-- - claims_ai_service_documentation/Test Data/lookheredude/Invoice 9 - Heat Pump, Ventilation, Electrical Service Upgrade.pdf
--
-- Mapping notes:
-- - public.contractors.id is a deterministic UUIDv5 generated from the business name + GST number.
-- - public.contractors.number uses the GST account number root because no legacy workbook UID is present.
-- - contact_id is left NULL because this seed only creates the contractor company record.

INSERT INTO public.contractors (
  id,
  contact_id,
  business_name,
  website,
  phone_number,
  email,
  onboarded,
  number,
  cellphone_number,
  street_address,
  city,
  postal_code,
  created_at,
  updated_at
) VALUES
  (
    'ae8cce51-21a1-59aa-af2a-e23161455518',
    NULL,
    'SASQUATCH HEAT PUMPS LTD',
    NULL,
    '(236) 917-2033',
    'installs@sasquatchheatpumps.com',
    true,
    '782662001',
    NULL,
    '2C-6631 Sooke Road',
    'Sooke',
    NULL,
    NOW(),
    NOW()
  ),
  (
    'a7f62339-5685-53a3-9363-e8bd0cdd1a5d',
    NULL,
    'Fox Plumbing Heating Cooling Electrical',
    'https://www.foxandsons.ca',
    '1-844-739-0804',
    'admin@foxandsons.ca',
    true,
    '857158976',
    NULL,
    'PO Box 20115',
    'Vernon',
    'V1T 9L4',
    NOW(),
    NOW()
  )
ON CONFLICT (id) DO UPDATE SET
  business_name = EXCLUDED.business_name,
  website = EXCLUDED.website,
  phone_number = EXCLUDED.phone_number,
  email = EXCLUDED.email,
  onboarded = EXCLUDED.onboarded,
  number = EXCLUDED.number,
  cellphone_number = EXCLUDED.cellphone_number,
  street_address = EXCLUDED.street_address,
  city = EXCLUDED.city,
  postal_code = EXCLUDED.postal_code,
  updated_at = NOW();

INSERT INTO public.contractor_infos (
  id,
  contractor_id,
  gst_number,
  created_at,
  updated_at
) VALUES
  (
    '3044c0c7-db08-5cc3-9b13-34731dc5416d',
    'ae8cce51-21a1-59aa-af2a-e23161455518',
    '782662001 RT0001',
    NOW(),
    NOW()
  ),
  (
    'ca1090c7-0dd8-5668-96ec-34af17effdba',
    'a7f62339-5685-53a3-9363-e8bd0cdd1a5d',
    '857158976 RT0001',
    NOW(),
    NOW()
  )
ON CONFLICT (contractor_id) DO UPDATE SET
  gst_number = EXCLUDED.gst_number,
  updated_at = NOW();

COMMIT;
