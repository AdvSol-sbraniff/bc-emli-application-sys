# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class HistoryTimelineBuilder
      DISPLAY_FIELDS = {
        contractor_display_name: "Contractor-facing name",
        definition_text: "Rule definition",
        enabled: "Enabled",
        source_quote: "Source quote",
        contractor_action: "Contractor action",
        contractor_visibility: "Contractor visibility",
        contractor_blocking_policy: "Contractor blocking policy",
        admin_workflow_policy: "Admin workflow policy",
        pass_admin_message: "Pass message",
        info_admin_message: "Info message",
        warn_admin_message: "Warning message",
        fail_admin_message: "Failure message",
        admin_notes: "Admin notes"
      }.freeze

      def initialize(rule:, filters:)
        @rule = rule
        @filters = filters
      end

      def call
        snapshots = historical_snapshots
        states = snapshots.map { |row| state_from_history(row) }
        states << current_state

        {
          periods:
            (
              if code_rule?
                code_implementation_period
              else
                build_periods(snapshots, states)
              end
            ),
          milestones: build_milestones(snapshots, states),
          mapping_events: mapping_events,
          tracking_note: tracking_note
        }
      end

      private

      attr_reader :rule, :filters

      def code_rule?
        rule[:source_engine] == "code"
      end

      def tracking_note
        if code_rule?
          return(
            "Executable logic is maintained in source code. History here records database configuration changes only."
          )
        end

        "History stores the state before each saved change. The current rule completes the timeline."
      end

      def code_implementation_period
        [
          {
            sequence: 1,
            label: "Code implementation record",
            period_start: rule[:created_at],
            period_end: nil,
            state: current_state,
            metrics: metrics_for(rule[:created_at], nil)
          }
        ]
      end

      def historical_snapshots
        history_model
          .where(source_id: rule[:rule_id])
          .order(:history_created_at, :id)
          .to_a
      end

      def history_model
        if rule[:source_engine] == "genai"
          ::Claims::GenaiRuleHistory
        else
          ::Claims::CodeRuleHistory
        end
      end

      def state_from_history(row)
        common = {
          contractor_display_name: row.contractor_display_name,
          definition_text:
            rule[:source_engine] == "genai" ? row.prompt_text : row.description,
          enabled: row.enabled,
          source_quote: row.source_quote,
          contractor_action: row.contractor_action,
          contractor_visibility: row.contractor_visibility,
          contractor_blocking_policy: row.contractor_blocking_policy,
          admin_workflow_policy: row.admin_workflow_policy
        }

        return common if rule[:source_engine] == "genai"

        common.merge(
          pass_admin_message: row.pass_admin_message,
          info_admin_message: row.info_admin_message,
          warn_admin_message: row.warn_admin_message,
          fail_admin_message: row.fail_admin_message,
          admin_notes: row.admin_notes
        )
      end

      def current_state
        DISPLAY_FIELDS.keys.index_with { |field| rule[field] }
      end

      def build_periods(snapshots, states)
        states.each_with_index.map do |state, index|
          period_start =
            (
              if index.zero?
                rule[:created_at]
              else
                snapshots[index - 1].history_created_at
              end
            )
          period_end = snapshots[index]&.history_created_at

          {
            sequence: index + 1,
            label: period_label(index),
            period_start: period_start,
            period_end: period_end,
            state: state,
            metrics: metrics_for(period_start, period_end)
          }
        end
      end

      def period_label(index)
        return "Initial version" if index.zero?

        "Revision #{index}"
      end

      def metrics_for(period_start, period_end)
        MetricsRollup.new(filters).for_rule(
          source_engine: rule[:source_engine],
          rule_key: rule[:rule_key],
          period_start: period_start,
          period_end: period_end
        )
      end

      def build_milestones(snapshots, states)
        snapshots.each_with_index.map do |snapshot, index|
          changed_fields = changes_between(states[index], states[index + 1])
          {
            sequence: index + 1,
            changed_at: snapshot.history_created_at,
            label: milestone_label(changed_fields),
            changed_fields: changed_fields
          }
        end
      end

      def changes_between(before_state, after_state)
        DISPLAY_FIELDS.filter_map do |field, label|
          before_value = before_state[field]
          after_value = after_state[field]
          next if before_value == after_value

          {
            field: field,
            label: label,
            before: before_value,
            after: after_value
          }
        end
      end

      def milestone_label(changed_fields)
        return "Rule saved; no tracked field changed" if changed_fields.empty?

        labels = changed_fields.first(2).pluck(:label)
        suffix =
          (
            if changed_fields.length > 2
              " and #{changed_fields.length - 2} more"
            else
              ""
            end
          )
        "Changed #{labels.join(" and ")}#{suffix}"
      end

      def mapping_events
        model =
          (
            if rule[:source_engine] == "genai"
              ::Claims::GenaiRuleUpgradeTypeHistory
            else
              ::Claims::CodeRuleUpgradeTypeHistory
            end
          )
        foreign_key =
          rule[:source_engine] == "genai" ? :genai_rule_id : :code_rule_id

        upgrade_types = ::Claims::InvoiceUpgradeType.all.index_by(&:id)
        model
          .where(foreign_key => rule[:rule_id])
          .order(:history_created_at, :id)
          .map do |history|
            upgrade_type = upgrade_types[history.invoice_upgrade_type_id]
            {
              changed_at: history.history_created_at,
              upgrade_type_id: history.invoice_upgrade_type_id,
              upgrade_type_key: upgrade_type&.upgrade_type_key,
              description: upgrade_type&.description,
              note:
                "A pre-change mapping snapshot was recorded. The existing history does not identify whether the mapping was edited or removed."
            }
          end
      end
    end
  end
end
