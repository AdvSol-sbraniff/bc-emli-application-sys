select id,
       created_at,
       char_length(context_window_json::text) as input_chars,
       char_length(genai_results_json::text) as output_chars
from claims.ingest_step_runs
where step_type = 'genai'
  and status = 'succeeded'
order by created_at desc
limit 5;
