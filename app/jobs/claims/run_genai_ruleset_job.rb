# frozen_string_literal: true

module Claims
  class RunGenaiRulesetJob
    include Sidekiq::Job
    sidekiq_options queue: :claims_genai, retry: 0

    def perform(
      session_id,
      invoice_version_id,
      ingest_run_id,
      invoice_upgrade_type_id,
      step_type
    )
      unless %w[genai_common genai_upgrade].include?(step_type.to_s)
        raise "Unsupported GenAI ruleset step_type=#{step_type.inspect}"
      end

      Claims::RunGenaiJob.new.run_genai_ruleset_child!(
        session_id: session_id,
        invoice_version_id: invoice_version_id,
        ingest_run_id: ingest_run_id,
        invoice_upgrade_type_id: invoice_upgrade_type_id,
        step_type: step_type.to_s
      )
    end
  end
end
