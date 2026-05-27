-- Seed the stable source/type rows for BC Hydro heat-pump product lists.
-- Rerunnable. Uses fixed IDs so these catalogue rows have stable FK targets.

BEGIN;

WITH sources (
  id,
  description,
  source_url
) AS (
  VALUES
  (
    '1f61c7d9-9a17-4a45-bef3-bbc3b32651a1'::uuid,
    'Ductless mini-split heat pump',
    'https://app.bchydro.com/hero/HeatPumpLookup/DownloadMiniSplitSingleHeadListPDF'
  ),
  (
    '7a18e50a-fc3b-46bd-9e22-fd23d92db96f'::uuid,
    'Ductless multi-split heat pump',
    'https://app.bchydro.com/hero/HeatPumpLookup/DownloadMiniSplitMultiHeadListPDF'
  ),
  (
    'b27dfcf0-32e6-48ed-9778-72134cdf3a78'::uuid,
    'Central ducted heat pump (Tier 2)',
    'https://app.bchydro.com/hero/HeatPumpLookup/DownloadVariableSpeedCentralSystemListPDF'
  )
)
INSERT INTO claims.ahri_sources (
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
  description = COALESCE(NULLIF(claims.ahri_sources.description, ''), EXCLUDED.description),
  source_url = EXCLUDED.source_url,
  updated_at = now();

COMMIT;
