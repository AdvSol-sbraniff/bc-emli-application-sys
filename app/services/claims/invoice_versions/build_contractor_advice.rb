# frozen_string_literal: true

module Claims
  module InvoiceVersions
    class BuildContractorAdvice
      def self.call(invoice_version_id:, config: nil)
        new(invoice_version_id: invoice_version_id, config: config).call
      end

      def initialize(invoice_version_id:, config: nil)
        @invoice_version_id = invoice_version_id
        @config =
          config || Claims::ValidationgenaiConfig.order(:created_at).first
      end

      def call
        bullets =
          contractor_actionable_rules.map do |rule|
            markdown_quote_bullet(
              rule.fetch(:source_quote),
              contractor_display_name: rule.fetch(:contractor_display_name),
              rule_key: rule.fetch(:rule_key)
            )
          end

        return nil if bullets.empty?

        [
          @config&.admin_advice_intro.to_s.strip.presence,
          bullets.join("\n"),
          @config&.admin_advice_closing.to_s.strip.presence
        ].compact.join("\n\n")
      end

      private

      def contractor_actionable_rules
        rows =
          Claims::InvoiceVersionRulecheck
            .joins(<<~SQL.squish)
              LEFT JOIN claims.genai_rules gr
                ON claims.invoice_version_rulechecks.source_engine = 'genai'
               AND gr.genai_rule_key = claims.invoice_version_rulechecks.rule_key
              LEFT JOIN claims.code_rules cr
                ON claims.invoice_version_rulechecks.source_engine = 'code'
               AND cr.code_rule_key = claims.invoice_version_rulechecks.rule_key
            SQL
            .where(invoice_version_id: @invoice_version_id)
            .contractor_actionable
            .select(
              "claims.invoice_version_rulechecks.rule_key AS rule_key",
              "claims.invoice_version_rulechecks.contractor_display_name AS contractor_display_name",
              "COALESCE(gr.source_quote, cr.source_quote) AS source_quote"
            )
            .order(:rule_key, :created_at)

        rows
          .filter_map do |row|
            source_quote = normalize_quote(row.read_attribute("source_quote"))
            next if source_quote.blank?

            {
              rule_key: row.rule_key.to_s,
              contractor_display_name:
                row
                  .read_attribute("contractor_display_name")
                  .to_s
                  .strip
                  .presence || row.rule_key.to_s.humanize,
              source_quote: source_quote
            }
          end
          .uniq
      end

      def normalize_quote(value)
        lines = value.to_s.gsub(/\r\n?/, "\n").lines.map(&:rstrip)

        lines.shift while lines.first.to_s.strip.blank?
        lines.pop while lines.last.to_s.strip.blank?

        lines.join("\n").presence
      end

      def markdown_quote_bullet(quote, contractor_display_name:, rule_key:)
        lines = quote.to_s.lines.map(&:rstrip)
        lines.shift while lines.first.to_s.strip.blank?
        lines.pop while lines.last.to_s.strip.blank?
        return nil if lines.empty?

        (
          ["- [**#{contractor_display_name}**](# \"Rule key: #{rule_key}\")"] +
            lines.map { |line| line.strip.blank? ? "  " : "  #{line}" }
        ).compact.join("\n")
      end
    end
  end
end
