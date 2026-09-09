# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class EvidenceQuery
      TYPES = %w[
        all
        complaints
        workflow
        false_positives
        false_negatives
        contractor_follow_up
        closure_outcomes
      ].freeze

      def initialize(
        filters:,
        source_engine:,
        rule_key:,
        evidence_type: "all",
        evidence_complaint_code: nil,
        evidence_closure_outcome: nil,
        minimum_sent_rounds: nil
      )
        @filters = filters
        @source_engine = source_engine
        @rule_key = rule_key
        @evidence_type =
          TYPES.include?(evidence_type.to_s) ? evidence_type.to_s : "all"
        @evidence_complaint_code =
          enum_or_nil(
            evidence_complaint_code,
            ::Claims::InvoiceVersionRulecheck::REASON_COMPLAINT_CODES,
            :evidence_complaint_code
          )
        @evidence_closure_outcome =
          enum_or_nil(
            evidence_closure_outcome,
            Filters::CLOSED_DISPOSITIONS,
            :evidence_closure_outcome
          )
        @minimum_sent_rounds =
          integer_or_nil_in_range(
            minimum_sent_rounds,
            min: 1,
            max: 100,
            name: :minimum_sent_rounds
          )
      end

      def call(page:, per:)
        scope = filters.apply_events(::Claims::VRuleImprovementReporting.all)
        scope = CurrentRulePeriod.apply(scope)
        scope = scope.where(source_engine: source_engine, rule_key: rule_key)
        scope = evidence_scope(scope)

        total = scope.count
        rows =
          ordered_scope(scope)
            .offset((page - 1) * per)
            .limit(per)
            .map { |row| serialize(row) }

        {
          rows: rows,
          meta: {
            total: total,
            page: page,
            per: per,
            evidence_type: evidence_type,
            evidence_complaint_code: evidence_complaint_code,
            evidence_closure_outcome: evidence_closure_outcome,
            minimum_sent_rounds: minimum_sent_rounds
          }
        }
      end

      private

      attr_reader :filters,
                  :source_engine,
                  :rule_key,
                  :evidence_type,
                  :evidence_complaint_code,
                  :evidence_closure_outcome,
                  :minimum_sent_rounds

      def evidence_scope(scope)
        case evidence_type
        when "complaints"
          relation = scope.where.not(reason_complaint_code: nil)
          if evidence_complaint_code
            relation =
              relation.where(reason_complaint_code: evidence_complaint_code)
          end
          relation
        when "workflow"
          scope.where.not(revision_issue_id: nil)
        when "contractor_follow_up"
          relation = scope.where.not(revision_issue_id: nil)
          if minimum_sent_rounds
            relation =
              relation.where("sent_round_count >= ?", minimum_sent_rounds)
          end
          relation
        when "closure_outcomes"
          relation =
            scope.where(revision_issue_status: Filters::CLOSED_DISPOSITIONS)
          if evidence_closure_outcome
            relation =
              relation.where(revision_issue_status: evidence_closure_outcome)
          end
          relation
        when "false_positives"
          scope.where(
            rule_result: %w[warn fail],
            revision_issue_status: "closed_no_contractor_action_required"
          )
        when "false_negatives"
          scope
            .where(rule_result: %w[pass info])
            .where.not(revision_issue_id: nil)
            .where.not(
              revision_issue_status: %w[
                closed_no_contractor_action_required
                closed_as_withdrawn
              ]
            )
        else
          scope
        end
      end

      def ordered_scope(scope)
        if evidence_type == "contractor_follow_up"
          return(
            scope.order(
              sent_round_count: :desc,
              rulecheck_created_at: :desc,
              rulecheck_id: :desc
            )
          )
        end

        scope.order(rulecheck_created_at: :desc, rulecheck_id: :desc)
      end

      def enum_or_nil(value, allowed, name)
        return if value.blank?

        parsed = value.to_s
        unless allowed.include?(parsed)
          raise Filters::Invalid, "Invalid #{name}"
        end

        parsed
      end

      def integer_or_nil_in_range(value, min:, max:, name:)
        return if value.blank?

        parsed = Integer(value)
        unless parsed.between?(min, max)
          raise Filters::Invalid, "#{name} must be between #{min} and #{max}"
        end
        parsed
      rescue ArgumentError, TypeError
        raise Filters::Invalid, "#{name} must be an integer"
      end

      def serialize(row)
        {
          rulecheck_id: row.rulecheck_id,
          rulecheck_created_at: row.rulecheck_created_at,
          invoice_id: row.invoice_id,
          invoice_version_id: row.invoice_version_id,
          version_number: row.version_number,
          invoice_reference_number: row.invoice_reference_number,
          invoice_status: row.invoice_status,
          contractor_id: row.contractor_id,
          contractor_business_name: row.contractor_business_name,
          invoice_upgrade_type_id: row.invoice_upgrade_type_id,
          upgrade_type_key: row.upgrade_type_key,
          rule_result: row.rule_result,
          reason: row.reason_and_likely_causes,
          reason_complaint_code: row.reason_complaint_code,
          reason_complaint_text: row.reason_complaint_text,
          revision_issue_id: row.revision_issue_id,
          revision_issue_status: row.revision_issue_status,
          disposition_comment: row.disposition_comment,
          sent_round_count: row.sent_round_count,
          first_admin_sent_at: row.first_admin_sent_at,
          latest_contractor_response_at: row.latest_contractor_response_at
        }
      end
    end
  end
end
