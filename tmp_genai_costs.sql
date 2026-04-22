with succeeded as (
  select char_length(context_window_json::text) as input_chars,
         char_length(genai_results_json::text) as output_chars
  from claims.ingest_step_runs
  where step_type = 'genai'
    and status = 'succeeded'
    and context_window_json is not null
    and genai_results_json is not null
)
select count(*) as succeeded_samples,
       round(avg(((input_chars::numeric / 4) * 1.75 / 1000000.0) + ((output_chars::numeric / 4) * 14.0 / 1000000.0)), 4) as avg_cost_usd,
       round(sum(((input_chars::numeric / 4) * 1.75 / 1000000.0) + ((output_chars::numeric / 4) * 14.0 / 1000000.0)), 4) as succeeded_cost_usd
from succeeded;
