# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    # Invoice coverage is separate from event counts: versions, upgrades, rounds
    # and grouped complaint/request categories must not count an invoice twice.
    class InvoiceCoverageQuery
      SIGNAL_CONDITIONS = {
        "checks" => "TRUE",
        "versions" => "TRUE",
        "complaints" => "reason_complaint_code IS NOT NULL",
        "workflow_issues" => "revision_issue_id IS NOT NULL",
        "follow_up" => "revision_issue_id IS NOT NULL",
        "open" => "revision_issue_status IN ('pending_admin_review', 'open')",
        "closed" =>
          "revision_issue_status NOT IN ('pending_admin_review', 'open')",
        "sent_issues" => "sent_round_count > 0",
        "multi_round" => "sent_round_count > 1",
        "total_rounds" => "sent_round_count > 0",
        "repeat_rounds" => "sent_round_count > 1",
        "false_positive" =>
          "rule_result IN ('warn', 'fail') AND revision_issue_status = 'closed_no_contractor_action_required'",
        "false_negative" =>
          "rule_result IN ('pass', 'info') AND revision_issue_id IS NOT NULL",
        "explanation_complaints" =>
          "reason_complaint_code IN ('unclear_or_confusing', 'too_vague', 'missing_evidence_explanation', 'likely_causes_unhelpful', 'irrelevant_or_duplicative', 'too_verbose_or_repetitive', 'other')"
      }.freeze
      DOCUMENT_REQUESTS = %w[
        correct_and_reupload_invoice
        upload_supporting_document
      ].freeze

      def initialize(filters:, source_engine:, rule_key:)
        @filters = filters
        @source_engine = source_engine
        @rule_key = rule_key
      end

      def call
        conditions = SIGNAL_CONDITIONS.dup
        %w[pass info warn fail].each do |result|
          conditions["result:#{result}"] = "rule_result = '#{result}'"
        end
        Filters::CLOSED_DISPOSITIONS.each do |status|
          conditions[
            "closure:#{status}"
          ] = "revision_issue_status = '#{status}'"
        end
        values =
          scope.pluck(
            *conditions.values.map do |condition|
              Arel.sql(
                "COUNT(DISTINCT invoice_id) FILTER (WHERE #{condition})::integer"
              )
            end
          ).first
        counts = conditions.keys.zip(values).to_h

        ::Claims::InvoiceVersionRulecheck::REASON_COMPLAINT_CODES.each do |code|
          counts["complaint:#{code}"] = 0
        end
        scope
          .where.not(reason_complaint_code: nil)
          .group(:reason_complaint_code)
          .distinct
          .count(:invoice_id)
          .each { |code, count| counts["complaint:#{code}"] = count }

        requests =
          workflow_choices(author_type: "admin", sent_at: :admin_sent_at)
        responses =
          workflow_choices(
            author_type: "contractor",
            sent_at: :contractor_response_submitted_at
          )
        add_choice_counts(
          counts,
          requests,
          "admin_requests",
          :admin_recommended_remedy,
          ::Claims::RevisionIssueComment::ADMIN_REMEDIES
        )
        add_choice_counts(
          counts,
          responses,
          "contractor_responses",
          :contractor_response_method,
          ::Claims::RevisionIssueComment::CONTRACTOR_METHODS
        )
        counts["document_requests"] = requests
          .where(admin_recommended_remedy: DOCUMENT_REQUESTS)
          .distinct
          .count("claims.revision_issues.invoice_id")

        {
          total_invoice_count: counts.fetch("checks"),
          signal_invoice_counts: counts
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

      def workflow_choices(author_type:, sent_at:)
        ::Claims::RevisionIssueComment.joins(:revision_issue).where(
          revision_issue_id:
            scope.where.not(revision_issue_id: nil).select(:revision_issue_id),
          revision_round_id:
            ::Claims::RevisionRound.where.not(sent_at => nil).select(:id),
          author_type: author_type
        )
      end

      def add_choice_counts(counts, relation, prefix, field, choices)
        choices.each { |choice| counts["#{prefix}:#{choice}"] = 0 }
        relation
          .where.not(field => nil)
          .group(field)
          .distinct
          .count("claims.revision_issues.invoice_id")
          .each { |choice, count| counts["#{prefix}:#{choice}"] = count }
      end
    end
  end
end
