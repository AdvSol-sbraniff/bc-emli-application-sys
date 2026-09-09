# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class BreakdownQuery
      def initialize(filters:, source_engine:, rule_key:)
        @filters = filters
        @source_engine = source_engine
        @rule_key = rule_key
      end

      def call
        {
          complaint_types: grouped_counts(:reason_complaint_code),
          closure_types: grouped_counts(:revision_issue_status),
          admin_requests:
            workflow_choice_counts(
              field: :admin_recommended_remedy,
              author_type: "admin",
              round_ids: sent_round_ids
            ),
          contractor_responses:
            workflow_choice_counts(
              field: :contractor_response_method,
              author_type: "contractor",
              round_ids: responded_round_ids
            ),
          round_distribution:
            scope
              .where.not(revision_issue_id: nil)
              .group(:sent_round_count)
              .count
              .sort_by { |rounds, _count| rounds.to_i }
              .map { |rounds, count| { rounds: rounds.to_i, count: count } }
        }
      end

      private

      attr_reader :filters, :source_engine, :rule_key

      def scope
        @scope ||=
          CurrentRulePeriod.apply(
            filters.apply_events(::Claims::VRuleImprovementReporting.all)
          ).where(source_engine: source_engine, rule_key: rule_key)
      end

      def grouped_counts(field)
        scope
          .where.not(field => nil)
          .group(field)
          .count
          .sort_by { |_value, count| -count }
          .map { |value, count| { value: value, count: count } }
      end

      def workflow_choice_counts(field:, author_type:, round_ids:)
        ::Claims::RevisionIssueComment
          .where(
            revision_issue_id: current_issue_ids,
            revision_round_id: round_ids,
            author_type: author_type
          )
          .where.not(field => nil)
          .group(field)
          .count
          .sort_by { |_value, count| -count }
          .map { |value, count| { value: value, count: count } }
      end

      def current_issue_ids
        scope.where.not(revision_issue_id: nil).select(:revision_issue_id)
      end

      def sent_round_ids
        ::Claims::RevisionRound.where.not(admin_sent_at: nil).select(:id)
      end

      def responded_round_ids
        ::Claims::RevisionRound
          .where.not(contractor_response_submitted_at: nil)
          .select(:id)
      end
    end
  end
end
