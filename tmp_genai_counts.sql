select status, count(*)
from claims.ingest_step_runs
where step_type = 'genai'
group by status
order by status;
