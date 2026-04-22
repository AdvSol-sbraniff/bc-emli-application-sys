select created_at::date as day,
       count(*) as total_genai_rows,
       count(*) filter (where status = 'succeeded') as succeeded_rows,
       count(*) filter (where status = 'failed') as failed_rows,
       count(*) filter (where status = 'in_progress') as in_progress_rows
from claims.ingest_step_runs
where step_type = 'genai'
group by created_at::date
order by day;
