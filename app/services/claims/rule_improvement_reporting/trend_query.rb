# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class TrendQuery
      GRAINS = %w[day week month].freeze

      def initialize(
        filters:,
        source_engine: nil,
        rule_key: nil,
        grain: "month"
      )
        @filters = filters
        @source_engine = source_engine
        @rule_key = rule_key
        @grain = GRAINS.include?(grain.to_s) ? grain.to_s : "month"
      end

      def call
        scope = filters.apply_events(::Claims::VRuleImprovementReporting.all)
        scope = scope.where(source_engine: source_engine) if source_engine
        scope = scope.where(rule_key: rule_key) if rule_key
        period_sql = "date_trunc('#{grain}', rulecheck_created_at)"

        rows =
          scope
            .group(Arel.sql(period_sql))
            .order(Arel.sql("#{period_sql} ASC"))
            .pluck(
              Arel.sql(period_sql),
              Arel.sql("COUNT(*)::integer"),
              Arel.sql(
                "COUNT(*) FILTER (WHERE reason_complaint_code IS NOT NULL)::integer"
              ),
              Arel.sql("COUNT(DISTINCT revision_issue_id)::integer"),
              Arel.sql(
                "COUNT(*) FILTER (WHERE revision_issue_status = 'closed_no_contractor_action_required')::integer"
              ),
              Arel.sql(
                "COALESCE(AVG(sent_round_count) FILTER (WHERE sent_round_count > 0), 0)::numeric"
              )
            )
            .map do |period, checks, complaints, issues, no_action, average_rounds|
              {
                period_start: period,
                check_count: checks,
                complaint_count: complaints,
                workflow_issue_count: issues,
                no_action_count: no_action,
                complaint_rate: rate(complaints, checks),
                average_rounds: average_rounds.to_f.round(2)
              }
            end

        { grain: grain, rows: rows }
      end

      private

      attr_reader :filters, :source_engine, :rule_key, :grain

      def rate(numerator, denominator)
        return if denominator.to_i.zero?

        (numerator.to_f / denominator.to_f).round(4)
      end
    end
  end
end
