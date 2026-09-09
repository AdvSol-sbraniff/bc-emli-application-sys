# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class MetricsRollup
      METRIC_EXPRESSIONS = [
        "COUNT(*)::integer",
        "COUNT(DISTINCT invoice_version_id)::integer",
        "COUNT(*) FILTER (WHERE rule_result = 'pass')::integer",
        "COUNT(*) FILTER (WHERE rule_result = 'info')::integer",
        "COUNT(*) FILTER (WHERE rule_result = 'warn')::integer",
        "COUNT(*) FILTER (WHERE rule_result = 'fail')::integer",
        "COUNT(*) FILTER (WHERE reason_complaint_code IS NOT NULL)::integer",
        "COUNT(DISTINCT revision_issue_id)::integer",
        "COUNT(DISTINCT invoice_version_id) FILTER (WHERE revision_issue_id IS NOT NULL)::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status IN ('pending_admin_review', 'open'))::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status IS NOT NULL AND revision_issue_status NOT IN ('pending_admin_review', 'open'))::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status = 'closed_no_contractor_action_required')::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status = 'closed_via_corrected_documentation')::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status = 'closed_via_attestation')::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status = 'closed_via_exception')::integer",
        "COUNT(*) FILTER (WHERE revision_issue_status = 'closed_as_withdrawn')::integer",
        "COUNT(*) FILTER (WHERE revision_issue_id IS NOT NULL AND sent_round_count > 0)::integer",
        "COALESCE(SUM(sent_round_count) FILTER (WHERE revision_issue_id IS NOT NULL), 0)::integer",
        "COALESCE(SUM(GREATEST(sent_round_count - 1, 0)) FILTER (WHERE revision_issue_id IS NOT NULL), 0)::integer",
        "COALESCE(AVG(sent_round_count) FILTER (WHERE revision_issue_id IS NOT NULL AND sent_round_count > 0), 0)::numeric",
        "COALESCE(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY sent_round_count) FILTER (WHERE revision_issue_id IS NOT NULL AND sent_round_count > 0), 0)::numeric",
        "COALESCE(MAX(sent_round_count) FILTER (WHERE revision_issue_id IS NOT NULL), 0)::integer",
        "COUNT(*) FILTER (WHERE revision_issue_id IS NOT NULL AND sent_round_count > 1)::integer",
        "COUNT(*) FILTER (WHERE rule_result IN ('warn', 'fail') AND revision_issue_status = 'closed_no_contractor_action_required')::integer",
        "COUNT(*) FILTER (WHERE rule_result IN ('pass', 'info') AND revision_issue_id IS NOT NULL AND COALESCE(revision_issue_status, '') NOT IN ('closed_no_contractor_action_required', 'closed_as_withdrawn'))::integer"
      ].freeze

      METRIC_KEYS = %i[
        check_count
        invoice_count
        pass_count
        info_count
        warn_count
        fail_count
        complaint_count
        workflow_issue_count
        follow_up_invoice_count
        open_issue_count
        closed_issue_count
        no_action_count
        corrected_documentation_count
        attestation_count
        exception_count
        withdrawn_count
        sent_issue_count
        total_round_count
        repeat_round_count
        average_rounds
        median_rounds
        maximum_rounds
        multi_round_issue_count
        candidate_false_positive_count
        candidate_false_negative_count
      ].freeze

      def initialize(filters)
        @filters = filters
      end

      def by_rule
        scope = @filters.apply_events(::Claims::VRuleImprovementReporting.all)
        scope = CurrentRulePeriod.apply(scope)
        expressions = METRIC_EXPRESSIONS.map { |sql| Arel.sql(sql) }

        scope
          .group(:source_engine, :rule_key)
          .pluck(:source_engine, :rule_key, *expressions)
          .to_h do |values|
            engine, key, *metrics = values
            [[engine, key], build_metrics(metrics)]
          end
      end

      def for_rule(
        source_engine:,
        rule_key:,
        period_start: nil,
        period_end: nil
      )
        scope = @filters.apply_events(::Claims::VRuleImprovementReporting.all)
        scope = scope.where(source_engine: source_engine, rule_key: rule_key)
        if period_start
          scope = scope.where("rulecheck_created_at >= ?", period_start)
        end
        if period_end
          scope = scope.where("rulecheck_created_at < ?", period_end)
        end

        values =
          scope.pluck(*METRIC_EXPRESSIONS.map { |sql| Arel.sql(sql) }).first
        build_metrics(values || Array.new(METRIC_KEYS.length, 0))
      end

      def self.empty_metrics
        new_metrics = METRIC_KEYS.index_with { 0 }
        add_rates(new_metrics)
      end

      def self.add_rates(metrics)
        checks = metrics[:check_count].to_i
        closed = metrics[:closed_issue_count].to_i
        sent = metrics[:sent_issue_count].to_i

        metrics.merge(
          pass_rate: rate(metrics[:pass_count], checks),
          info_rate: rate(metrics[:info_count], checks),
          warn_rate: rate(metrics[:warn_count], checks),
          fail_rate: rate(metrics[:fail_count], checks),
          complaint_rate: rate(metrics[:complaint_count], checks),
          no_action_rate: rate(metrics[:no_action_count], closed),
          corrected_documentation_rate:
            rate(metrics[:corrected_documentation_count], closed),
          attestation_rate: rate(metrics[:attestation_count], closed),
          exception_rate: rate(metrics[:exception_count], closed),
          withdrawn_rate: rate(metrics[:withdrawn_count], closed),
          multi_round_rate: rate(metrics[:multi_round_issue_count], sent)
        )
      end

      def self.rate(numerator, denominator)
        return nil if denominator.to_i.zero?

        (numerator.to_f / denominator.to_f).round(4)
      end

      private

      def build_metrics(values)
        metrics = METRIC_KEYS.zip(values).to_h
        metrics[:average_rounds] = metrics[:average_rounds].to_f.round(2)
        metrics[:median_rounds] = metrics[:median_rounds].to_f.round(2)
        self.class.add_rates(metrics)
      end
    end
  end
end
