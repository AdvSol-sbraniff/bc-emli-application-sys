# frozen_string_literal: true

module Claims
  module RuleImprovementReporting
    class Filters
      class Invalid < StandardError
      end

      ENGINES = %w[code genai].freeze
      SIGNALS = %w[
        rule_review
        contractor_guidance
        explanation_tuning
        candidate_missed
        awaiting_sample
        none
      ].freeze
      CLOSED_DISPOSITIONS =
        (
          ::Claims::RevisionIssue::STATUSES -
            ::Claims::RevisionIssue::UNRESOLVED_STATUSES
        ).freeze

      attr_reader :q,
                  :date_from,
                  :date_to,
                  :invoice_upgrade_type_id,
                  :source_engine,
                  :enabled,
                  :contractor_id,
                  :reason_complaint_code,
                  :closure_disposition,
                  :minimum_sample_size,
                  :changed_within_days,
                  :signal

      def initialize(params)
        @q = params[:q].to_s.strip.presence
        @date_from = parse_date(params[:date_from], :date_from)
        @date_to = parse_date(params[:date_to], :date_to)
        if date_from && date_to && date_from > date_to
          raise Invalid, "date_from must be on or before date_to"
        end

        @invoice_upgrade_type_id =
          uuid_or_nil(
            params[:invoice_upgrade_type_id],
            :invoice_upgrade_type_id
          )
        @source_engine =
          enum_or_nil(params[:source_engine], ENGINES, :source_engine)
        @enabled = boolean_or_nil(params[:enabled], :enabled)
        @contractor_id = uuid_or_nil(params[:contractor_id], :contractor_id)
        @reason_complaint_code =
          enum_or_nil(
            params[:reason_complaint_code],
            ::Claims::InvoiceVersionRulecheck::REASON_COMPLAINT_CODES,
            :reason_complaint_code
          )
        @closure_disposition =
          enum_or_nil(
            params[:closure_disposition],
            CLOSED_DISPOSITIONS,
            :closure_disposition
          )
        @minimum_sample_size =
          integer_in_range(
            params[:minimum_sample_size],
            default: 5,
            min: 1,
            max: 1_000,
            name: :minimum_sample_size
          )
        @changed_within_days =
          integer_or_nil_in_range(
            params[:changed_within_days],
            min: 1,
            max: 3_650,
            name: :changed_within_days
          )
        @complaints_only =
          boolean_or_nil(params[:complaints_only], :complaints_only) || false
        @signal = enum_or_nil(params[:signal], SIGNALS, :signal)
      end

      def complaints_only?
        @complaints_only
      end

      def event_filtering?
        contractor_id.present? || reason_complaint_code.present? ||
          closure_disposition.present? || complaints_only?
      end

      def apply_events(scope)
        relation = scope
        relation = relation.where(source_engine: source_engine) if source_engine
        if date_from
          relation =
            relation.where(
              "rulecheck_created_at >= ?",
              date_from.beginning_of_day
            )
        end
        if date_to
          relation =
            relation.where("rulecheck_created_at <= ?", date_to.end_of_day)
        end
        if invoice_upgrade_type_id
          relation =
            relation.where(invoice_upgrade_type_id: invoice_upgrade_type_id)
        end
        relation = relation.where(contractor_id: contractor_id) if contractor_id
        if reason_complaint_code
          relation =
            relation.where(reason_complaint_code: reason_complaint_code)
        end
        if closure_disposition
          relation = relation.where(revision_issue_status: closure_disposition)
        end
        if complaints_only?
          relation = relation.where.not(reason_complaint_code: nil)
        end
        relation
      end

      def changed_since
        return if changed_within_days.nil?

        changed_within_days.days.ago
      end

      def as_json(*)
        {
          q: q,
          date_from: date_from&.iso8601,
          date_to: date_to&.iso8601,
          invoice_upgrade_type_id: invoice_upgrade_type_id,
          source_engine: source_engine,
          enabled: enabled,
          contractor_id: contractor_id,
          reason_complaint_code: reason_complaint_code,
          closure_disposition: closure_disposition,
          minimum_sample_size: minimum_sample_size,
          changed_within_days: changed_within_days,
          complaints_only: complaints_only?,
          signal: signal
        }
      end

      private

      def parse_date(value, name)
        return if value.blank?

        Date.iso8601(value.to_s)
      rescue Date::Error
        raise Invalid, "#{name} must be an ISO date"
      end

      def uuid_or_nil(value, name)
        return if value.blank?

        parsed = value.to_s
        unless parsed.match?(
                 /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i
               )
          raise Invalid, "#{name} must be a UUID"
        end
        parsed
      end

      def enum_or_nil(value, allowed, name)
        return if value.blank?

        parsed = value.to_s
        raise Invalid, "Invalid #{name}" unless allowed.include?(parsed)

        parsed
      end

      def boolean_or_nil(value, name)
        return if value.blank?
        return true if %w[true 1].include?(value.to_s.downcase)
        return false if %w[false 0].include?(value.to_s.downcase)

        raise Invalid, "#{name} must be true or false"
      end

      def integer_in_range(value, default:, min:, max:, name:)
        return default if value.blank?

        parsed = Integer(value)
        unless parsed.between?(min, max)
          raise Invalid, "#{name} must be between #{min} and #{max}"
        end
        parsed
      rescue ArgumentError, TypeError
        raise Invalid, "#{name} must be an integer"
      end

      def integer_or_nil_in_range(value, min:, max:, name:)
        return if value.blank?

        integer_in_range(value, default: nil, min: min, max: max, name: name)
      end
    end
  end
end
