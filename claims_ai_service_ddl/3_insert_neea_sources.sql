-- Seed the stable source/type rows for NEEA heat pump water heater product lists.
-- Rerunnable. Uses fixed IDs so these catalogue rows have stable FK targets.

BEGIN;

WITH sources (
  id,
  description,
  source_url
) AS (
  VALUES
  (
    '9b6b8e55-38b5-4fcb-9f3c-9a44a21cc001'::uuid,
    'Residential HPWH Qualified Products List',
    'https://neea.org/wp-content/uploads/2025/03/residential-HPWH-qualified-products-list.pdf'
  )
)
INSERT INTO claims.neea_sources (
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
  description = COALESCE(NULLIF(claims.neea_sources.description, ''), EXCLUDED.description),
  source_url = EXCLUDED.source_url,
  updated_at = now();

COMMIT;
