with runs as (
  select id,
         created_at,
         char_length(context_window_json::text) as input_chars,
         char_length(genai_results_json::text) as output_chars
  from claims.ingest_step_runs
  where step_type = 'genai'
    and status = 'succeeded'
    and context_window_json is not null
    and genai_results_json is not null
  order by created_at desc
  limit 10
)
select id,
       created_at,
       input_chars,
       output_chars,
       round((input_chars::numeric / 4), 0) as est_input_tokens,
       round((output_chars::numeric / 4), 0) as est_output_tokens,
       round(((input_chars::numeric / 4) * 1.75 / 1000000.0) + ((output_chars::numeric / 4) * 14.0 / 1000000.0), 4) as est_cost_usd
from runs
order by created_at desc;
