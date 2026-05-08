-- Rerunnable backfill for legacy permit applications that are missing
-- permit_type/activity even though their linked requirement template has them.

WITH source_data AS (
  SELECT
    pa.id AS permit_application_id,
    rt.permit_type_id,
    rt.activity_id
  FROM permit_applications pa
  JOIN template_versions tv
    ON tv.id = pa.template_version_id
  JOIN requirement_templates rt
    ON rt.id = tv.requirement_template_id
  WHERE (pa.permit_type_id IS NULL OR pa.activity_id IS NULL)
    AND (rt.permit_type_id IS NOT NULL OR rt.activity_id IS NOT NULL)
)
UPDATE permit_applications pa
SET
  permit_type_id = COALESCE(pa.permit_type_id, sd.permit_type_id),
  activity_id = COALESCE(pa.activity_id, sd.activity_id),
  updated_at = NOW()
FROM source_data sd
WHERE pa.id = sd.permit_application_id;
