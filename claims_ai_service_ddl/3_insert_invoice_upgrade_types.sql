BEGIN;

WITH upgrade_types (
  id,
  upgrade_type_key,
  description,
  created_at,
  updated_at
) AS (
  VALUES
  (
    'd5eaa9f3-342f-4f30-b444-d54ca0c142f2'::uuid,
    'common',
    'Common invoice evidence',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '7a2a72db-3b8f-4d7d-bfa4-263e1b52b4f6'::uuid,
    'air_source_heat_pump_electric',
    'Air source heat pump - convert from electric',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '5b81d92f-3a16-43d9-b5f8-6cdd47c63311'::uuid,
    'air_source_heat_pump_wood',
    'Air source heat pump - convert from wood',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'f29716a1-5b15-4e34-ae37-7f9d6c7e9ab2'::uuid,
    'air_source_heat_pump_gas_propane',
    'Air source heat pump - convert from natural gas or propane',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '0e8042e2-e3d8-4987-90d6-8fffb8f18405'::uuid,
    'air_source_heat_pump_oil',
    'Air source heat pump - convert from oil',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'f7c47e34-f7c5-46b1-9f75-4e47d0d8c2f1'::uuid,
    'dual_fuel_ducted_heat_pump',
    'Dual fuel ducted heat pump',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'ac27dc8f-74d3-4781-bf4f-a742561ddf1c'::uuid,
    'air_to_water_heat_pump',
    'Air-to-water heat pump',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'aa5f8868-a612-4b6f-8fb3-cc06f94ef0a1'::uuid,
    'combined_space_water_heat_pump',
    'Combined space and water heat pump',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'f43113db-6c9a-4d88-8fe5-db195c1a8ca9'::uuid,
    'heat_pump_water_heater',
    'Heat pump water heater',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '0d0efe3e-f66b-42f4-a097-d0d74f32cb4b'::uuid,
    'electrical_service_upgrade',
    'Electrical service upgrade',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    'c7599fa5-c56f-413a-9fd6-a4e7c5ebde24'::uuid,
    'ventilation',
    'Ventilation',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  ),
  (
    '2011d143-8003-4f30-b444-d54ca0c142f2'::uuid,
    'health_and_safety_remediation',
    'Health and safety remediation',
    TIMESTAMP '2026-05-06 00:00:00',
    NOW()
  )
)
INSERT INTO claims.invoice_upgrade_types (
  id,
  upgrade_type_key,
  description,
  created_at,
  updated_at
)
SELECT
  id,
  upgrade_type_key,
  description,
  created_at,
  updated_at
FROM upgrade_types
ON CONFLICT (upgrade_type_key) DO UPDATE SET
  description = EXCLUDED.description,
  updated_at = NOW();

-- Local/dev cleanup: remove retired seed upgrade types when no history protects them.
DELETE FROM claims.invoice_upgrade_types ut
WHERE ut.upgrade_type_key NOT IN (
  'common',
  'air_source_heat_pump_electric',
  'air_source_heat_pump_wood',
  'air_source_heat_pump_gas_propane',
  'air_source_heat_pump_oil',
  'dual_fuel_ducted_heat_pump',
  'air_to_water_heat_pump',
  'combined_space_water_heat_pump',
  'heat_pump_water_heater',
  'electrical_service_upgrade',
  'ventilation',
  'health_and_safety_remediation'
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
  SELECT 1 FROM claims.ingest_step_runs s
  WHERE s.invoice_upgrade_type_id = ut.id
);

COMMIT;
