-- Seed the stable source/type rows for NRCan ENERGY STAR heat/energy
-- recovery ventilator product lists.
-- Rerunnable. Uses fixed IDs so these catalogue rows have stable FK targets.

BEGIN;

WITH sources (
  id,
  description,
  source_url
) AS (
  VALUES
  (
    '9b6b8e55-38b5-4fcb-9f3c-9a44a21cc301'::uuid,
    'NRCan ENERGY STAR Heat/Energy Recovery Ventilators Product List',
    'https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ES.Ventilators.HeatEnergyRecovery'
  )
)
INSERT INTO claims.herv_sources (
  id,
  description,
  source_url,
  created_at,
  updated_at
)
SELECT
  id,
  description,
  source_url,
  now(),
  now()
FROM sources
ON CONFLICT (id) DO UPDATE SET
  description = COALESCE(NULLIF(claims.herv_sources.description, ''), EXCLUDED.description),
  source_url = EXCLUDED.source_url,
  updated_at = now();

COMMIT;
