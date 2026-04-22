select created_at::date as day,
       count(*) filter (
         where status = 'succeeded'
            or (status = 'failed' and error_text like 'RuntimeError: ApplyGenaiLocatedFields failed:%')
       ) as likely_model_calls,
       count(*) filter (where status = 'succeeded') as definite_model_calls,
       count(*) filter (where status = 'failed' and error_text like 'RuntimeError: ApplyGenaiLocatedFields failed:%') as post_model_failures,
       count(*) filter (where status = 'failed' and error_text like 'ArgumentError: No unique index found for invoice_version_located_fields_uniq%') as pre_model_failures_unique_index,
       count(*) filter (where status = 'failed' and error_text like 'ActiveRecord::StatementInvalid: PG::InvalidColumnReference:%') as pre_model_failures_on_conflict,
       count(*) filter (where status = 'in_progress') as ambiguous_in_progress
from claims.ingest_step_runs
where step_type = 'genai'
group by created_at::date
order by day;
