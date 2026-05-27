# frozen_string_literal: true

module Claims
  module GenaiRulesetPublisher
    class Publish
      def self.call(invoice_upgrade_type_ids:)
        new(invoice_upgrade_type_ids: invoice_upgrade_type_ids).call
      end

      def initialize(invoice_upgrade_type_ids:)
        @invoice_upgrade_type_ids = Array.wrap(invoice_upgrade_type_ids).map(&:to_s).reject(&:blank?).uniq
      end

      def call
        upgrade_types.map { |upgrade_type| publish_one!(upgrade_type) }
      end

      private

      attr_reader :invoice_upgrade_type_ids

      def upgrade_types
        @upgrade_types ||=
          ::Claims::InvoiceUpgradeType.where(id: invoice_upgrade_type_ids).order(:upgrade_type_key)
      end

      def publish_one!(upgrade_type)
        compiled_user_record1 =
          ::Claims::GenaiRulesetCompiler::Compile.call(
            invoice_upgrade_type: upgrade_type
          )

        latest =
          ::Claims::ValidationgenaiRuleset
            .where(invoice_upgrade_type_id: upgrade_type.id)
            .order(Arel.sql("updated_at DESC, created_at DESC, id DESC"))
            .first

        return latest if latest&.user_record1.to_s == compiled_user_record1

        ::Claims::ValidationgenaiRuleset.create!(
          invoice_upgrade_type_id: upgrade_type.id,
          ruleset_shortname: ruleset_shortname_for(upgrade_type),
          user_record1: compiled_user_record1
        )
      end

      def ruleset_shortname_for(upgrade_type)
        stamp = Time.current.utc.strftime("%Y%m%d%H%M%S")
        "normalized_#{upgrade_type.upgrade_type_key}_#{stamp}"
      end
    end
  end
end
