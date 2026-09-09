# frozen_string_literal: true

module Api
  module Claims
    class ReportsRuleImprovementController < Api::ApplicationController
      include Api::Claims::Concerns::AdminAuthorization

      claims_function "claims.configuration"

      skip_before_action :require_confirmation
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped
      skip_forgery_protection

      # GET /api/claims/admin/reports/rule_improvement
      def index
        page = clamp_int(params[:page], 1, 1, 10_000)
        per = clamp_int(params[:per], 25, 1, 200)
        result = query.paginated(sort: params[:sort], page: page, per: per)

        render json: {
                 rows: result[:rows],
                 meta: result.except(:rows).merge(filters: filters.as_json)
               }
      end

      # GET /api/claims/admin/reports/rule_improvement/summary
      def summary
        render json: query.summary.merge(options: filter_options)
      end

      # GET /api/claims/admin/reports/rule_improvement/chart
      def chart
        lens =
          (
            if %w[attention workflow change].include?(params[:lens])
              params[:lens]
            else
              "attention"
            end
          )
        rows = chart_rows(lens)

        render json: { lens: lens, rows: rows, filters: filters.as_json }
      end

      # GET /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key
      def show
        rule = requested_rule
        breakdowns =
          ::Claims::RuleImprovementReporting::BreakdownQuery.new(
            filters: filters,
            source_engine: rule[:source_engine],
            rule_key: rule[:rule_key]
          ).call
        render json: {
                 rule: rule,
                 breakdowns: breakdowns,
                 metrics:
                   rule.slice(
                     *::Claims::RuleImprovementReporting::MetricsRollup::METRIC_KEYS
                   ),
                 rates:
                   rule.slice(
                     :pass_rate,
                     :info_rate,
                     :warn_rate,
                     :fail_rate,
                     :complaint_rate,
                     :no_action_rate,
                     :corrected_documentation_rate,
                     :attestation_rate,
                     :exception_rate,
                     :withdrawn_rate,
                     :multi_round_rate
                   )
               }
      end

      # GET /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key/timeline
      def timeline
        rule = requested_rule
        history =
          ::Claims::RuleImprovementReporting::HistoryTimelineBuilder.new(
            rule: rule,
            filters: filters
          ).call
        trend =
          ::Claims::RuleImprovementReporting::TrendQuery.new(
            filters: filters,
            source_engine: rule[:source_engine],
            rule_key: rule[:rule_key],
            grain: params[:grain]
          ).call

        render json: history.merge(trend: trend)
      end

      # GET /api/claims/admin/reports/rule_improvement/:source_engine/:rule_key/evidence
      def evidence
        requested_rule
        page = clamp_int(params[:page], 1, 1, 10_000)
        per = clamp_int(params[:per], 25, 1, 200)
        result =
          ::Claims::RuleImprovementReporting::EvidenceQuery.new(
            filters: filters,
            source_engine: params[:source_engine],
            rule_key: params[:rule_key],
            evidence_type: params[:evidence_type],
            evidence_complaint_code: params[:evidence_complaint_code],
            evidence_closure_outcome: params[:evidence_closure_outcome],
            minimum_sent_rounds: params[:minimum_sent_rounds]
          ).call(page: page, per: per)

        render json: result
      end

      rescue_from ::Claims::RuleImprovementReporting::Filters::Invalid do |error|
        render json: { error: error.message }, status: :unprocessable_entity
      end

      rescue_from ActiveRecord::RecordNotFound do |error|
        render json: { error: error.message }, status: :not_found
      end

      private

      def filters
        @filters ||= ::Claims::RuleImprovementReporting::Filters.new(params)
      end

      def query
        @query ||=
          ::Claims::RuleImprovementReporting::RuleGridQuery.new(filters)
      end

      def requested_rule
        @requested_rule ||=
          query.find_rule!(params[:source_engine].to_s, params[:rule_key].to_s)
      end

      def filter_options
        {
          source_engines: ::Claims::RuleImprovementReporting::Filters::ENGINES,
          complaint_codes:
            ::Claims::InvoiceVersionRulecheck::REASON_COMPLAINT_CODES,
          closure_dispositions:
            ::Claims::RuleImprovementReporting::Filters::CLOSED_DISPOSITIONS,
          upgrade_types:
            ::Claims::InvoiceUpgradeType
              .order(:description)
              .pluck(:id, :upgrade_type_key, :description)
              .map do |id, key, description|
                { id: id, key: key, description: description }
              end,
          contractors:
            ::Claims::VRuleImprovementReporting
              .where.not(contractor_id: nil)
              .distinct
              .order(:contractor_business_name)
              .pluck(:contractor_id, :contractor_business_name)
              .map { |id, name| { id: id, name: name } }
        }
      end

      def chart_rows(lens)
        rows = query.rows
        ordered =
          case lens
          when "workflow"
            rows
              .sort_by do |row|
                [row[:workflow_issue_count].to_i, row[:average_rounds].to_f]
              end
              .reverse
          when "change"
            rows
              .select { |row| row[:change_count].to_i.positive? }
              .sort_by { |row| row[:last_changed_at] || Time.at(0) }
              .reverse
          else
            rows.sort_by { |row| row[:attention_score].to_f }.reverse
          end

        ordered
          .first(15)
          .map do |row|
            row.slice(
              :source_engine,
              :rule_key,
              :contractor_display_name,
              :attention_signal,
              :attention_label,
              :attention_score,
              :check_count,
              :complaint_count,
              :complaint_rate,
              :workflow_issue_count,
              :average_rounds,
              :no_action_rate,
              :change_count,
              :last_changed_at
            )
          end
      end

      def clamp_int(value, default, minimum, maximum)
        parsed = Integer(value || default)
        [[parsed, minimum].max, maximum].min
      rescue ArgumentError, TypeError
        default
      end
    end
  end
end
