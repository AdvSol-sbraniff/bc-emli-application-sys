# frozen_string_literal: true

module Claims
  module InvoiceVersionRulechecks
    class ApplyUpgradeCodeRulechecks
      SERVICE_CLASSES = [
        ::Claims::CodeRules::AirWaterHeatPumpProductList::ApplyProductListMatch,
        ::Claims::CodeRules::AshpGasPropane::ApplyRebateCap,
        ::Claims::CodeRules::AshpFossil::ApplyNorthernTopUp,
        ::Claims::CodeRules::AshpOil::ApplyRebateCap,
        ::Claims::CodeRules::AshpProductRequirements::ApplyProductRequirements,
        ::Claims::CodeRules::Dfhp::ApplyProductSpecs,
        ::Claims::CodeRules::Dfhp::ApplyRebateCap,
        ::Claims::CodeRules::HeatPump::ApplyNorthernTopUp3000,
        ::Claims::CodeRules::Hpwh::ApplyRebateCap,
        ::Claims::CodeRules::Hydronic::ApplyRebateCap,
        ::Claims::CodeRules::OilHeatPumpOhpa::ApplyProductListMatch,
        ::Claims::CodeRules::HeatPumpAhri::ApplyProductListMatch,
        ::Claims::CodeRules::HeatPumpWaterHeaterNeea::ApplyProductListMatch,
        ::Claims::CodeRules::IncomeLevel::ApplyLevelOneOrTwoRequired,
        ::Claims::CodeRules::WindowsDoorsUFactor::ApplyThresholdCheck
      ].freeze

      def self.call(invoice_version_id:, invoice_upgrade_type_id:)
        new(
          invoice_version_id: invoice_version_id,
          invoice_upgrade_type_id: invoice_upgrade_type_id
        ).call
      end

      def initialize(invoice_version_id:, invoice_upgrade_type_id:)
        @invoice_version_id = invoice_version_id
        @invoice_upgrade_type_id = invoice_upgrade_type_id
      end

      def call
        validate_rule_coverage!

        results =
          SERVICE_CLASSES.map do |service_class|
            service_class.call(
              invoice_version_id: @invoice_version_id,
              invoice_upgrade_type_id: @invoice_upgrade_type_id
            )
          end

        failure = results.find { |result| !result[:ok] }
        return failure if failure

        applied_results = results.reject { |result| result[:skipped] }

        {
          ok: true,
          skipped: applied_results.empty?,
          applied_service_count: applied_results.size,
          services: results
        }
      end

      private

      def enabled_rule_keys_for_upgrade_type
        @enabled_rule_keys_for_upgrade_type ||=
          ::Claims::CodeRule
            .joins(:code_rule_upgrade_types)
            .where(enabled: true)
            .where(
              ::Claims::CodeRuleUpgradeType.table_name => {
                invoice_upgrade_type_id: @invoice_upgrade_type_id
              }
            )
            .order(:code_rule_key)
            .pluck(:code_rule_key)
      end

      def implemented_rule_keys
        SERVICE_CLASSES.flat_map(&:implemented_rule_keys).uniq
      end

      def validate_rule_coverage!
        missing_keys =
          enabled_rule_keys_for_upgrade_type - implemented_rule_keys
        return if missing_keys.empty?

        raise(
          "Enabled upgrade code rules have no executor implementation for invoice_upgrade_type_id=#{@invoice_upgrade_type_id}: #{missing_keys.join(", ")}"
        )
      end
    end
  end
end
