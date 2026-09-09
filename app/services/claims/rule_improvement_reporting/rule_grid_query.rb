# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class RuleGridQuery
      SORT_FIELDS = %w[
        attention_score
        contractor_display_name
        source_engine
        enabled
        check_count
        invoice_count
        complaint_count
        candidate_false_positive_count
        candidate_false_negative_count
        total_round_count
        repeat_round_count
        workflow_issue_count
        average_rounds
        no_action_rate
        corrected_documentation_rate
        complaint_rate
        last_changed_at
      ].freeze

      HIGH_NO_ACTION_RATE = 0.25
      HIGH_COMPLAINT_RATE = 0.10
      HIGH_AVERAGE_ROUNDS = 1.5

      attr_reader :filters

      def initialize(filters)
        @filters = filters
      end

      def rows
        @rows ||=
          begin
            metrics_by_rule = MetricsRollup.new(filters).by_rule
            history_by_rule = history_summaries

            current_rules.filter_map do |rule|
              next unless inventory_match?(rule)

              metrics =
                metrics_by_rule.fetch(
                  [rule[:source_engine], rule[:rule_key]],
                  MetricsRollup.empty_metrics
                )
              if filters.event_filtering? && metrics[:check_count].to_i.zero?
                next
              end

              history =
                history_by_rule.fetch(
                  [rule[:source_engine], rule[:rule_id]],
                  { change_count: 0, last_history_at: nil }
                )
              last_changed_at = history[:last_history_at] || rule[:created_at]
              attention =
                attention_for(
                  metrics,
                  history,
                  last_changed_at,
                  source_engine: rule[:source_engine]
                )
              next if filters.signal && attention[:key] != filters.signal
              if filters.changed_since &&
                   last_changed_at < filters.changed_since
                next
              end

              rule
                .merge(metrics)
                .merge(history)
                .merge(
                  last_changed_at: last_changed_at,
                  current_effective_at:
                    (
                      if rule[:source_engine] == "genai"
                        last_changed_at
                      else
                        rule[:created_at]
                      end
                    ),
                  attention_signal: attention[:key],
                  attention_label: attention[:label],
                  attention_score: attention[:score],
                  meets_minimum_sample:
                    metrics[:check_count].to_i >= filters.minimum_sample_size
                )
            end
          end
      end

      def sorted_rows(sort: "attention_score:desc")
        field, direction = parse_sort(sort)
        sorted =
          rows.sort_by do |row|
            value = row[field.to_sym]
            normalized =
              case value
              when Time, DateTime, ActiveSupport::TimeWithZone
                value.to_f
              when TrueClass
                1
              when FalseClass, NilClass
                0
              when Numeric
                value
              else
                value.to_s.downcase
              end
            [normalized, row[:contractor_display_name].to_s.downcase]
          end
        direction == "desc" ? sorted.reverse : sorted
      end

      def paginated(sort:, page:, per:)
        ordered = sorted_rows(sort: sort)
        {
          rows: ordered.slice((page - 1) * per, per) || [],
          total: ordered.length,
          page: page,
          per: per,
          sort: normalize_sort(sort)
        }
      end

      def summary
        {
          rule_count: rows.length,
          check_count: rows.sum { |row| row[:check_count].to_i },
          workflow_issue_count:
            rows.sum { |row| row[:workflow_issue_count].to_i },
          complaint_count: rows.sum { |row| row[:complaint_count].to_i },
          signal_counts:
            Filters::SIGNALS.index_with do |signal|
              rows.count { |row| row[:attention_signal] == signal }
            end
        }
      end

      def find_rule!(source_engine, rule_key)
        row =
          rows.find do |candidate|
            candidate[:source_engine] == source_engine &&
              candidate[:rule_key] == rule_key
          end
        return row if row

        raise ActiveRecord::RecordNotFound, "Rule not found"
      end

      private

      def current_rules
        genai_rules + code_rules
      end

      def genai_rules
        ::Claims::GenaiRule
          .includes(:invoice_upgrade_types)
          .map do |rule|
            {
              rule_id: rule.id,
              record_type: "genai_rule",
              source_engine: "genai",
              rule_key: rule.genai_rule_key,
              contractor_display_name: rule.contractor_display_name,
              enabled: rule.enabled,
              created_at: rule.created_at,
              updated_at: rule.updated_at,
              definition_text: rule.prompt_text,
              source_quote: rule.source_quote,
              contractor_action: rule.contractor_action,
              contractor_visibility: rule.contractor_visibility,
              contractor_blocking_policy: rule.contractor_blocking_policy,
              admin_workflow_policy: rule.admin_workflow_policy,
              upgrade_types: serialize_upgrade_types(rule.invoice_upgrade_types)
            }
          end
      end

      def code_rules
        ::Claims::CodeRule
          .includes(:invoice_upgrade_types)
          .map do |rule|
            {
              rule_id: rule.id,
              record_type: "code_rule",
              source_engine: "code",
              rule_key: rule.code_rule_key,
              contractor_display_name: rule.contractor_display_name,
              enabled: rule.enabled,
              created_at: rule.created_at,
              updated_at: rule.updated_at,
              definition_text: rule.description,
              source_quote: rule.source_quote,
              contractor_action: rule.contractor_action,
              contractor_visibility: rule.contractor_visibility,
              contractor_blocking_policy: rule.contractor_blocking_policy,
              admin_workflow_policy: rule.admin_workflow_policy,
              pass_admin_message: rule.pass_admin_message,
              info_admin_message: rule.info_admin_message,
              warn_admin_message: rule.warn_admin_message,
              fail_admin_message: rule.fail_admin_message,
              admin_notes: rule.admin_notes,
              upgrade_types: serialize_upgrade_types(rule.invoice_upgrade_types)
            }
          end
      end

      def serialize_upgrade_types(upgrade_types)
        upgrade_types
          .sort_by(&:upgrade_type_key)
          .map do |upgrade_type|
            {
              id: upgrade_type.id,
              key: upgrade_type.upgrade_type_key,
              description: upgrade_type.description
            }
          end
      end

      def history_summaries
        summaries = {}
        ::Claims::GenaiRuleHistory
          .group(:source_id)
          .pluck(
            :source_id,
            Arel.sql("COUNT(*)"),
            Arel.sql("MAX(history_created_at)")
          )
          .each do |source_id, count, last_at|
            summaries[["genai", source_id]] = {
              change_count: count.to_i,
              last_history_at: last_at
            }
          end
        ::Claims::CodeRuleHistory
          .group(:source_id)
          .pluck(
            :source_id,
            Arel.sql("COUNT(*)"),
            Arel.sql("MAX(history_created_at)")
          )
          .each do |source_id, count, last_at|
            summaries[["code", source_id]] = {
              change_count: count.to_i,
              last_history_at: last_at
            }
          end
        summaries
      end

      def inventory_match?(rule)
        if filters.source_engine &&
             rule[:source_engine] != filters.source_engine
          return false
        end
        return false unless enabled_match?(rule)
        return false unless query_match?(rule)
        return false unless upgrade_type_match?(rule)

        true
      end

      def enabled_match?(rule)
        filters.enabled.nil? || rule[:enabled] == filters.enabled
      end

      def query_match?(rule)
        return true if filters.q.blank?

        haystack = [rule[:rule_key], rule[:contractor_display_name]].join(
          " "
        ).downcase
        haystack.include?(filters.q.downcase)
      end

      def upgrade_type_match?(rule)
        return true unless filters.invoice_upgrade_type_id

        rule[:upgrade_types].any? do |upgrade_type|
          upgrade_type[:id].to_s == filters.invoice_upgrade_type_id
        end
      end

      def attention_for(metrics, history, last_changed_at, source_engine:)
        min = filters.minimum_sample_size
        closed = metrics[:closed_issue_count].to_i
        checks = metrics[:check_count].to_i
        sent = metrics[:sent_issue_count].to_i

        if closed >= min && metrics[:no_action_rate].to_f >= HIGH_NO_ACTION_RATE
          return(
            attention(
              "rule_review",
              "Review rule applicability",
              500 + metrics[:no_action_rate].to_f
            )
          )
        end
        if checks >= min &&
             metrics[:candidate_false_negative_count].to_i >= [2, min / 2].max
          return(
            attention(
              "candidate_missed",
              "Review possible missed issues",
              450 + metrics[:candidate_false_negative_count].to_i
            )
          )
        end
        if checks >= min && metrics[:complaint_rate].to_f >= HIGH_COMPLAINT_RATE
          return(
            attention(
              "explanation_tuning",
              "Improve reason quality",
              400 + metrics[:complaint_rate].to_f
            )
          )
        end
        if sent >= min && metrics[:average_rounds].to_f >= HIGH_AVERAGE_ROUNDS
          return(
            attention(
              "contractor_guidance",
              "Improve contractor guidance",
              350 + metrics[:average_rounds].to_f
            )
          )
        end
        if source_engine == "genai" && history[:change_count].to_i.positive? &&
             last_changed_at >= 90.days.ago && checks < min
          return(
            attention("awaiting_sample", "Awaiting post-change sample", 200)
          )
        end

        attention(
          "none",
          checks.zero? ? "No processed sample" : "No strong signal",
          0
        )
      end

      def attention(key, label, score)
        { key: key, label: label, score: score }
      end

      def normalize_sort(raw)
        field, direction = parse_sort(raw)
        "#{field}:#{direction}"
      end

      def parse_sort(raw)
        field, direction = raw.to_s.split(":", 2)
        field = "attention_score" unless SORT_FIELDS.include?(field)
        direction = direction == "asc" ? "asc" : "desc"
        [field, direction]
      end
    end
  end
end
