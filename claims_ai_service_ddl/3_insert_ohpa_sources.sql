-- Seed the stable source/type rows for NRCan Oil to Heat Pump Affordability
-- qualified product lists.
-- Rerunnable. Uses fixed IDs so these catalogue rows have stable FK targets.

BEGIN;

WITH sources (
  id,
  description,
  source_url
) AS (
  VALUES
  (
    '9b6b8e55-38b5-4fcb-9f3c-9a44a21cc201'::uuid,
    'NRCan OHPA BC Air Source Heat Pump Qualified Product List',
    'https://spl-lpi.nrcan-rncan.gc.ca/en-US/product/?product=ASHP3_OHPA'
  )
)
INSERT INTO claims.ohpa_sources (
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
  description = COALESCE(NULLIF(claims.ohpa_sources.description, ''), EXCLUDED.description),
  source_url = EXCLUDED.source_url,
  updated_at = now();

COMMIT;
