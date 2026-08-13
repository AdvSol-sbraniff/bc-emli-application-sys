# frozen_string_literal: true

module Claims
  class RunGenaiRulesetJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai,
                    retry: ::Claims::Ingest::RetryPolicy.sidekiq_retries

    def perform(
      session_id,
      invoice_version_id,
      ingest_run_id,
      invoice_upgrade_type_id
    )
      raise "Missing ingest_run_id for GenAI ruleset." if ingest_run_id.blank?

      Claims::RunGenaiJob.new.run_genai_ruleset_child!(
        session_id: session_id,
        invoice_version_id: invoice_version_id,
        ingest_run_id: ingest_run_id,
        invoice_upgrade_type_id: invoice_upgrade_type_id,
        step_type: "evaluate_genai_ruleset"
      )
    end
  end
end
