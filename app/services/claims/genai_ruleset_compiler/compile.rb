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
              "rule_key: #{mapping.genai_rule.genai_rule_key}",
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
        result_rubric = <<~TEXT.strip
          Result rubric:
          Use rule_result="pass" when the requirement is satisfied and no correction or meaningful caveat is needed.
          Use rule_result="info" only when the requirement is satisfied enough that no contractor correction is requested, but the evidence is not fully squeaky clean. Info is blue: a pass with a meaningful non-blocking caveat or limitation. Do not use info for a clean pass, and do not use info for trivia or generic helpful context.
          Use rule_result="warn" when evidence is missing, ambiguous, incomplete, low-confidence, or requires admin verification before the requirement can be relied on.
          Use rule_result="fail" when visible evidence clearly contradicts the requirement or required evidence is clearly absent.
        TEXT

        common_upgrade_type? ? <<~TEXT.strip : <<~TEXT.strip
            For v1, create these rulechecks from the OCR/DI JSON and supplied database values.
            #{result_rubric}
            Use the supplied supporting-document summaries and located fields when a common rule asks about application attachments, utility/account documents, income documents, landlord consent, labels, photos, permits, or other non-invoice evidence.
            Use other_documents[] only as optional corroborating context for unusual or unclassified attachments; do not treat other_documents[] as a replacement for a clearly required configured supporting-document type unless its OCR excerpt or classification reason directly supports the rule.
            For shared database facts such as invoices.submitted_at, classifier.eligibility_code, and users_eligibilitycodes.*, use the supplied database values exactly as provided.
            For invoice dates, use the best-supported invoice date visible in the OCR/DI JSON.
            Show the date math in calculation when a date rule is evaluated.
          TEXT
            Use the OCR/DI JSON, supplied database values, and supporting_document_summary_for_upgrade_type for this upgrade type.
            #{result_rubric}
            When a rule asks about photos, labels, product specs, permits, preapproval, WETT reports, heat-load calculations, utility bills/invoices, fossil-fuel removal/modification, or other supporting documents, inspect configured_documents[].located_fields before warning or failing for missing evidence.
            Use other_documents[] only as optional corroborating context for unusual or unclassified attachments; do not treat other_documents[] as a replacement for a clearly required configured supporting-document type unless its OCR excerpt or classification reason directly supports the rule.
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
            .order("claims.genai_rules.genai_rule_key")
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
