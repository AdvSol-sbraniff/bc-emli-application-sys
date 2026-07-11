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
          failed_visible_quotes.map { |quote| markdown_quote_bullet(quote) }

        return nil if bullets.empty?

        [
          @config&.admin_advice_intro.to_s.strip.presence,
          bullets.join("\n"),
          @config&.admin_advice_closing.to_s.strip.presence
        ].compact.join("\n\n")
      end

      private

      def failed_visible_quotes
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
            .where(invoice_version_id: @invoice_version_id, rule_result: "fail")
            .where(
              "COALESCE(gr.contractor_visible_flag, cr.contractor_visible_flag, false) = true"
            )
            .select(
              "COALESCE(gr.source_quote, cr.source_quote) AS source_quote"
            )
            .order(:rule_key, :created_at)

        rows
          .map { |row| normalize_quote(row.read_attribute("source_quote")) }
          .compact_blank
          .uniq
      end

      def normalize_quote(value)
        lines = value.to_s.gsub(/\r\n?/, "\n").lines.map(&:rstrip)

        lines.shift while lines.first.to_s.strip.blank?
        lines.pop while lines.last.to_s.strip.blank?

        lines.join("\n").presence
      end

      def markdown_quote_bullet(quote)
        lines = quote.to_s.lines.map(&:rstrip)
        lines.shift while lines.first.to_s.strip.blank?
        lines.pop while lines.last.to_s.strip.blank?
        return nil if lines.empty?

        first, *rest = lines
        (
          ["- #{first.strip}"] +
            rest.map { |line| line.strip.blank? ? "  " : "  #{line}" }
        ).compact.join("\n")
      end
    end
  end
end
