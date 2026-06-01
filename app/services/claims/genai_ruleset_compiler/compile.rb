# frozen_string_literal: true

module Claims
  module GenaiRulesetCompiler
    class Compile
      def self.call(invoice_upgrade_type:)
        new(invoice_upgrade_type: invoice_upgrade_type).call
      end

      def initialize(invoice_upgrade_type:)
        @invoice_upgrade_type = invoice_upgrade_type
      end

      def call
        sections = []
        sections << header_text
        sections << located_fields_section
        sections << rulechecks_section
        sections.compact_blank.join("\n\n").strip
      end

      private

      attr_reader :invoice_upgrade_type

      def header_text
        common_upgrade_type? ? <<~TEXT.strip : <<~TEXT.strip
            Common ESP invoice evidence tasks.
            These common tasks run as the common invoice evidence ruleset before upgrade-type-specific rulesets.
          TEXT
            Upgrade type: #{display_name}.
            Source vintage: Better Homes BC Energy Savings Program requirements for invoices dated on or after 2026-04-01.
          TEXT
      end

      def located_fields_section
        body =
          located_field_mappings
            .map do |mapping|
              "#{mapping.field_number} [field_key: #{mapping.genai_located_field.genai_field_key}] #{mapping.genai_located_field.prompt_text.to_s.strip}"
            end
            .join("\n")

        [located_fields_heading, body.presence].compact.join("\n")
      end

      def rulechecks_section
        body_parts = [rule_intro_text.presence]
        body_parts.concat(
          rule_mappings.map do |mapping|
            [
              "rule #{mapping.rule_number} [rule_key: #{mapping.genai_rule.genai_rule_key}]",
              mapping.genai_rule.prompt_text.to_s.strip
            ].join("\n")
          end
        )

        [
          rulechecks_heading,
          body_parts.compact_blank.join("\n\n").presence
        ].compact.join("\n")
      end

      def located_fields_heading
        if common_upgrade_type?
          "Common located fields:"
        else
          "#{display_name} located fields:"
        end
      end

      def rulechecks_heading
        if common_upgrade_type?
          "Common GenAI rulecheck tasks:"
        else
          "#{display_name} GenAI rulecheck tasks:"
        end
      end

      def rule_intro_text
        common_upgrade_type? ? <<~TEXT.strip : <<~TEXT.strip
            For v1, create these rulechecks from the OCR/DI JSON and supplied database values.
            Use the supplied supporting-document summaries and located fields when a common rule asks about application attachments, utility/account documents, income documents, landlord consent, labels, photos, permits, or other non-invoice evidence.
            For shared database facts such as invoices.submitted_at, classifier.eligibility_code, and users_eligibilitycodes.*, use the supplied database values exactly as provided.
            For invoice dates, use the best-supported invoice date visible in the OCR/DI JSON.
            Show the date math in calculation when a date rule is evaluated.
          TEXT
            Use the OCR/DI JSON, supplied database values, and supporting_document_summary_for_upgrade_type for this upgrade type.
            When a rule asks about photos, labels, product specs, permits, preapproval, WETT reports, heat-load calculations, utility bills/invoices, fossil-fuel removal/modification, or other supporting documents, inspect configured_documents[].located_fields before warning or failing for missing evidence.
            For invoice dates, use the best-supported invoice date visible in the OCR/DI JSON.
            Show the date math in calculation when a date rule is evaluated.
          TEXT
      end

      def located_field_mappings
        @located_field_mappings ||=
          invoice_upgrade_type
            .genai_located_field_upgrade_types
            .joins(:genai_located_field)
            .merge(::Claims::GenaiLocatedField.where(enabled: true))
            .includes(:genai_located_field)
            .order(:field_number, "claims.genai_located_fields.genai_field_key")
      end

      def rule_mappings
        @rule_mappings ||=
          invoice_upgrade_type
            .genai_rule_upgrade_types
            .joins(:genai_rule)
            .merge(::Claims::GenaiRule.where(enabled: true))
            .includes(:genai_rule)
            .order(:rule_number, "claims.genai_rules.genai_rule_key")
      end

      def common_upgrade_type?
        invoice_upgrade_type.upgrade_type_key.to_s == "common"
      end

      def display_name
        invoice_upgrade_type.description.presence ||
          invoice_upgrade_type.upgrade_type_key.to_s.humanize
      end
    end
  end
end
