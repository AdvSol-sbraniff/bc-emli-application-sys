select count(*) as total_genai_rows,
       count(*) filter (where status = 'succeeded') as succeeded_rows,
       count(*) filter (where status = 'failed') as failed_rows,
       count(*) filter (where status = 'in_progress') as in_progress_rows,
       count(*) filter (where status = 'queued') as queued_rows,
       count(*) filter (where status = 'succeeded' and context_window_json is not null and genai_results_json is not null) as succeeded_with_payloads,
       count(*) filter (where status = 'failed' and error_text like 'RuntimeError: ApplyGenaiLocatedFields failed:%') as failed_after_model_apply_located,
       count(*) filter (where status = 'failed' and error_text like 'ArgumentError: No unique index found for invoice_version_located_fields_uniq%') as failed_before_model_unique_index,
       count(*) filter (where status = 'failed' and error_text like 'ActiveRecord::StatementInvalid: PG::InvalidColumnReference:%') as failed_before_model_on_conflict
from claims.ingest_step_runs
where step_type = 'genai';
