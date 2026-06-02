-- Seed the stable source/type rows for Better Homes BC air-to-water and
-- combined heat pump qualifying product lists.
-- Rerunnable. Uses fixed IDs so these catalogue rows have stable FK targets.

BEGIN;

WITH sources (
  id,
  description,
  source_url
) AS (
  VALUES
  (
    '9b6b8e55-38b5-4fcb-9f3c-9a44a21cc101'::uuid,
    'Air-to-Water and Combination Heat Pump Qualifying Product List',
    'https://betterhomesbc.ca/qualified-product-list-air-to-water-heat-pumps-PDF'
  )
)
INSERT INTO claims.awhp_sources (
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
  description = COALESCE(NULLIF(claims.awhp_sources.description, ''), EXCLUDED.description),
  source_url = EXCLUDED.source_url,
  updated_at = now();

COMMIT;
