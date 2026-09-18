# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    # Package counts, not check counts. Report filters select the observations;
    # unfiltered checks on the exact first-submitted version establish outcomes.
    # Visibility is inferred from recorded settings, not proof of a page view.
    class PrecheckMetricsQuery
      COUNTS = %i[
        finding_package_count
        unresolved_package_count
        cleared_package_count
        unknown_outcome_package_count
        unknown_history_package_count
        no_visible_finding_package_count
        unsubmitted_package_count
        post_submission_only_package_count
      ].freeze
      FINDINGS = %w[warn fail].freeze
      CLEAR_RESULTS = %w[pass info].freeze

      def initialize(rule:, filters:)
        @rule = rule
        @filters = filters
      end

      def call
        counts = COUNTS.index_with { 0 }
        scoped_ids = Hash.new { |hash, key| hash[key] = Set.new }
        scoped_checks
          .distinct
          .pluck(:invoice_id, :rulecheck_id)
          .each { |invoice_id, check_id| scoped_ids[invoice_id].add(check_id) }

        scoped_ids
          .keys
          .each_slice(500) do |invoice_ids|
            versions =
              ::Claims::InvoiceVersion
                .where(invoice_id: invoice_ids)
                .select(:id, :invoice_id, :invoice_versionno, :created_at)
                .index_by(&:id)
            checks =
              ::Claims::InvoiceVersionRulecheck
                .where(
                  invoice_version_id: versions.keys,
                  source_engine: rule[:source_engine],
                  rule_key: rule[:rule_key]
                )
                .select(
                  :id,
                  :invoice_version_id,
                  :invoice_upgrade_type_id,
                  :rule_result,
                  :created_at
                )
                .group_by do |check|
                  versions.fetch(check.invoice_version_id).invoice_id
                end
            submissions =
              ::Claims::InvoiceStatusTransition
                .where(invoice_id: invoice_ids, to_status: "admin_review_inbox")
                .order(:created_at, :id)
                .group_by(&:invoice_id)

            ::Claims::Invoice
              .where(id: invoice_ids)
              .select(:id, :status, :submitted_at)
              .each do |invoice|
                classify_package(
                  invoice: invoice,
                  submission: submissions[invoice.id]&.first,
                  versions: versions,
                  checks: checks.fetch(invoice.id, []),
                  scoped_ids: scoped_ids.fetch(invoice.id),
                  counts: counts
                )
              end
          end

        counts.merge(
          unresolved_rate:
            MetricsRollup.rate(
              counts[:unresolved_package_count],
              counts[:finding_package_count]
            ),
          cleared_rate:
            MetricsRollup.rate(
              counts[:cleared_package_count],
              counts[:finding_package_count]
            )
        )
      end

      private

      attr_reader :rule, :filters

      def scoped_checks
        CurrentRulePeriod.apply(
          filters.apply_events(::Claims::VRuleImprovementReporting.all)
        ).where(source_engine: rule[:source_engine], rule_key: rule[:rule_key])
      end

      def classify_package(
        invoice:,
        submission:,
        versions:,
        checks:,
        scoped_ids:,
        counts:
      )
        unless submission
          key =
            if invoice.submitted_at.nil? &&
                 %w[contractor_precheck contractor_withdrawn].include?(
                   invoice.status
                 )
              :unsubmitted_package_count
            else
              :unknown_history_package_count
            end
          counts[key] += 1
          return
        end

        submitted_version = versions[submission.invoice_version_id]
        unless submission.from_status == "contractor_precheck" &&
                 submitted_version &&
                 submitted_version.invoice_id == invoice.id &&
                 submitted_version.created_at <= submission.created_at
          counts[:unknown_history_package_count] += 1
          return
        end

        before_submission =
          checks.select do |check|
            version = versions.fetch(check.invoice_version_id)
            check.created_at <= submission.created_at &&
              version.created_at <= submission.created_at &&
              version.invoice_versionno <= submitted_version.invoice_versionno
          end
        observations =
          before_submission.select { |check| scoped_ids.include?(check.id) }
        if observations.empty?
          counts[:post_submission_only_package_count] += 1
          return
        end

        unknown_visibility = false
        visible_findings =
          observations.select do |check|
            next false unless FINDINGS.include?(check.rule_result)
            # Keep findings visible at evaluation even if later hidden. Hiding a
            # finding does not clear it. Also consider settings at first submission.
            states = [policy_at(check.created_at)]
            if check.invoice_version_id == submitted_version.id
              states << policy_at(submission.created_at)
            end
            was_visible =
              states.any? { |policy| visible?(check.rule_result, policy) }
            unknown_visibility ||= !was_visible && states.any?(&:nil?)
            was_visible
          end
        if visible_findings.empty?
          counts[
            (
              if unknown_visibility
                :unknown_history_package_count
              else
                :no_visible_finding_package_count
              end
            )
          ] += 1
          return
        end

        counts[:finding_package_count] += 1
        submitted_checks =
          before_submission
            .select { |check| check.invoice_version_id == submitted_version.id }
            .group_by(&:invoice_upgrade_type_id)
        outcomes =
          visible_findings
            .group_by(&:invoice_upgrade_type_id)
            .map do |upgrade_id, findings|
              final = submitted_checks.fetch(upgrade_id, [])
              next :unknown unless final.one?
              classify_outcome(final.first, findings, submission.created_at)
            end

        # A package with several upgrades counts once. An unresolved finding
        # takes precedence; otherwise all observed findings must be proven clear.
        key =
          if outcomes.include?(:unresolved)
            :unresolved_package_count
          elsif unknown_visibility || outcomes.include?(:unknown)
            :unknown_outcome_package_count
          else
            :cleared_package_count
          end
        counts[key] += 1
      end

      def classify_outcome(final, findings, submitted_at)
        submission_policy = policy_at(submitted_at)
        return :unresolved if visible?(final.rule_result, submission_policy)
        return :unknown unless CLEAR_RESULTS.include?(final.rule_result)

        final_policy = policy_at(final.created_at)
        unless final_policy && submission_policy &&
                 final_policy[:id] == submission_policy[:id]
          return :unknown
        end
        comparable =
          findings.any? do |finding|
            earlier_policy = policy_at(finding.created_at)
            finding.invoice_version_id != final.invoice_version_id &&
              finding.created_at < final.created_at && earlier_policy &&
              earlier_policy[:id] == final_policy[:id]
          end
        comparable ? :cleared : :unknown
      end

      def visible?(result, policy)
        return false unless policy
        (policy[:visibility] == "warn_and_fail" && FINDINGS.include?(result)) ||
          (policy[:visibility] == "fail_only" && result == "fail")
      end

      def policy_at(time)
        state =
          policies.bsearch do |policy|
            policy[:ends_at] && policy[:ends_at] > time
          end || current_policy
        return unless state[:starts_at] && state[:starts_at] <= time
        unless %w[hidden fail_only warn_and_fail].include?(state[:visibility])
          return
        end
        state
      end

      def policies
        @policies ||=
          begin
            model =
              (
                if rule[:source_engine] == "genai"
                  ::Claims::GenaiRuleHistory
                else
                  ::Claims::CodeRuleHistory
                end
              )
            model
              .where(source_id: rule[:rule_id])
              .order(:history_created_at, :id)
              .map do |snapshot|
                {
                  id: snapshot.id,
                  starts_at:
                    snapshot.source_updated_at || snapshot.source_created_at,
                  ends_at: snapshot.history_created_at,
                  visibility: snapshot.contractor_visibility
                }
              end
          end
      end

      def current_policy
        @current_policy ||= {
          id: rule[:rule_id],
          starts_at: rule[:updated_at] || rule[:created_at],
          visibility: rule[:contractor_visibility]
        }
      end
    end
  end
end
