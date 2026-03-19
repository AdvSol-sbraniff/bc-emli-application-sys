select id, invoice_version_id, step_type, status, validationgenai_ruleset_id, created_at, updated_at, coalesce(left(error_text, 120), '') as error_text
from claims.ingest_step_runs
where session_id = 'd87003dd-51d3-4389-affa-ed36cc186bb8'
order by created_at desc
limit 20;
