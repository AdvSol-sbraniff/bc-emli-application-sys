# frozen_string_literal: true

module Claims
  module CodeRules
    module Dfhp
      class ApplyProductSpecs
        DFHP_UPGRADE_TYPE_KEY = "dual_fuel_ducted_heat_pump"
        INVOICE_AHRI_FIELD_KEY = "classifier.ahri_reference"

        MIN_CAPACITY_BTU = BigDecimal("12000")
        MIN_SEER = BigDecimal("16.0")
        MIN_HSPF = BigDecimal("10.0")
        MIN_SEER2 = BigDecimal("15.2")
        MIN_HSPF2 = BigDecimal("8.5")

        RULE = { number: 4, key: "dfhp_product_specs_meet_requirements" }.freeze

        def self.call(invoice_version_id:, invoice_upgrade_type_id:)
          new(
            invoice_version_id: invoice_version_id,
            invoice_upgrade_type_id: invoice_upgrade_type_id
          ).call
        end

        def self.implemented_rule_keys
          [RULE.fetch(:key)]
        end

        def initialize(invoice_version_id:, invoice_upgrade_type_id:)
          @invoice_version_id = invoice_version_id
          @invoice_upgrade_type_id = invoice_upgrade_type_id
        end

        def call
          @invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)
          @upgrade_type =
            ::Claims::InvoiceUpgradeType.find(@invoice_upgrade_type_id)

          return { ok: true, skipped: true } unless enabled_for_upgrade_type?

          row = product_specs_row(product: matched_ahri_product)
          replace_rulechecks!([row])

          { ok: true, skipped: false, rule_result: row.fetch(:rule_result) }
        rescue => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_for_upgrade_type?
          unless upgrade_type.upgrade_type_key == DFHP_UPGRADE_TYPE_KEY
            return false
          end

          ::Claims::CodeRules::Registry.enabled_for?(
            code_rule_key: RULE.fetch(:key),
            invoice_upgrade_type_id: upgrade_type.id,
            fallback: false
          )
        end

        def matched_ahri_product
          if invoice_version.ahri_product.present?
            return invoice_version.ahri_product
          end

          invoice_ahri = normalized_ahri(invoice_ahri_field&.value_text)
          return nil if invoice_ahri.blank?

          current_match =
            ::Claims::CurrentAhriProduct
              .where(ahri_reference_number: invoice_ahri)
              .order(:source_description, :id)
              .first

          ::Claims::AhriProduct.find_by(id: current_match.id) if current_match
        end

        def product_specs_row(product:)
          unless product
            return(
              base_rulecheck_row(
                rule_result: "info",
                confidence: 0,
                expected_text:
                  "The matched AHRI product row should show qualifying SEER/HSPF or SEER2/HSPF2 values and minimum capacity of 12,000 BTU for this dual-fuel ducted heat pump.",
                calculation:
                  "No matched AHRI product row was available from invoice_versions.ahri_product_id or classifier.ahri_reference.",
                evidence_text: field_evidence(invoice_ahri_field),
                reason_and_likely_causes:
                  "This DFHP product-spec rule depends on the AHRI product-list match. The AHRI product-list rule records whether the invoice AHRI reference was missing, not found, or matched; this dependent metric check is informational until that match exists."
              )
            )
          end

          evaluations = [
            efficiency_evaluation(product),
            capacity_evaluation(product)
          ]
          result = combined_result(evaluations)

          base_rulecheck_row(
            rule_result: result,
            confidence: result == "pass" || result == "fail" ? 100 : 0,
            expected_text:
              "Dual-fuel ducted heat pumps must meet SEER >= 16.0 and HSPF >= 10.0, or SEER2 >= 15.2 and HSPF2 >= 8.5 Region IV, and must have minimum capacity of 12,000 BTU. Variable speed compressor is not required for this upgrade type.",
            calculation:
              evaluations
                .map { |evaluation| evaluation.fetch(:calculation) }
                .join("; "),
            evidence_text: product_evidence(product),
            reason_and_likely_causes:
              product_specs_reason_text(
                result: result,
                evaluations: evaluations
              )
          )
        end

        def efficiency_evaluation(product)
          legacy_complete =
            metric_present?(product.seer) && metric_present?(product.hspf)
          current_complete =
            metric_present?(product.seer2) && metric_present?(product.hspf2)
          legacy_pass =
            legacy_complete && product.seer >= MIN_SEER &&
              product.hspf >= MIN_HSPF
          current_pass =
            current_complete && product.seer2 >= MIN_SEER2 &&
              product.hspf2 >= MIN_HSPF2

          if !legacy_complete && !current_complete
            return(
              {
                result: "warn",
                calculation:
                  "SEER/HSPF pair=(incomplete); SEER2/HSPF2 pair=(incomplete)",
                reason:
                  "The matched AHRI product row does not provide one complete efficiency pair for threshold comparison."
              }
            )
          end

          {
            result: legacy_pass || current_pass ? "pass" : "fail",
            calculation: efficiency_calculation_text(product),
            reason:
              if legacy_pass || current_pass
                "The matched AHRI product row meets one allowed DFHP efficiency threshold path."
              else
                "The matched AHRI product row does not meet either allowed DFHP efficiency threshold path."
              end
          }
        end

        def capacity_evaluation(product)
          capacity = product.rated_capacity_btu_at_minus_5c

          unless metric_present?(capacity)
            return(
              {
                result: "warn",
                calculation:
                  "capacity=#{format_decimal(capacity) || "(missing)"}; required_minimum=12000 BTU",
                reason:
                  "The matched AHRI product row does not provide a usable capacity value."
              }
            )
          end

          passed = BigDecimal(capacity.to_s) >= MIN_CAPACITY_BTU
          {
            result: passed ? "pass" : "fail",
            calculation:
              "capacity=#{format_decimal(capacity)} BTU; required_minimum=12000 BTU",
            reason:
              if passed
                "The matched AHRI product row meets the 12,000 BTU minimum capacity requirement."
              else
                "The matched AHRI product row is below the 12,000 BTU minimum capacity requirement."
              end
          }
        end

        def combined_result(evaluations)
          return "fail" if evaluations.any? { |e| e.fetch(:result) == "fail" }
          return "warn" if evaluations.any? { |e| e.fetch(:result) == "warn" }

          "pass"
        end

        def base_rulecheck_row(
          rule_result:,
          confidence:,
          expected_text:,
          calculation:,
          evidence_text:,
          reason_and_likely_causes:
        )
          now = Time.current

          {
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_number: RULE.fetch(:number),
            rule_key: RULE.fetch(:key),
            rule_result: rule_result,
            confidence: confidence,
            expected_text: expected_text,
            calculation: calculation,
            evidence_text: evidence_text,
            reason_and_likely_causes:
              append_admin_message(
                rule_result: rule_result,
                reason_text: reason_and_likely_causes
              ),
            created_at: now,
            updated_at: now
          }
        end

        def product_specs_reason_text(result:, evaluations:)
          details =
            evaluations.map { |evaluation| evaluation.fetch(:reason) }.join(" ")
          case result
          when "pass"
            "The matched product row satisfies the DFHP product specification checks. #{details}"
          when "fail"
            "One or more DFHP product specification checks failed. #{details}"
          else
            "One or more DFHP product specification checks could not be completed from the matched product row. #{details}"
          end
        end

        def invoice_ahri_field
          @invoice_ahri_field ||=
            ::Claims::InvoiceVersionLocatedField
              .where(
                invoice_version_id: invoice_version.id,
                invoice_upgrade_type_id: upgrade_type.id,
                source_engine: "classifier",
                field_key: INVOICE_AHRI_FIELD_KEY
              )
              .where.not(value_text: [nil, ""])
              .order(confidence: :desc, created_at: :desc)
              .first
        end

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.transaction do
            ::Claims::InvoiceVersionRulecheck.where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "code",
              rule_key: RULE.fetch(:key)
            ).delete_all

            ::Claims::InvoiceVersionRulecheck.insert_all!(rows)
          end
        end

        def append_admin_message(rule_result:, reason_text:)
          message =
            ::Claims::CodeRules::Registry.admin_message(
              code_rule_key: RULE.fetch(:key),
              rule_result: rule_result
            )
          return reason_text if message.blank?

          "#{reason_text}\n\nAdmin guidance: #{message}"
        end

        def field_evidence(*fields)
          fields
            .compact
            .map do |field|
              text = field.evidence_text.presence || field.value_text.presence
              next if text.blank?

              "#{field.field_key}: #{text}"
            end
            .compact
            .uniq
            .join("; ")
            .presence
        end

        def product_evidence(product)
          [
            "AHRI #{product.ahri_reference_number}",
            "ahri_products.id=#{product.id}",
            product.import_run&.ahri_source&.description,
            product.make,
            product.outdoor_model,
            product.indoor_model_or_air_handler,
            product.furnace_model,
            "capacity #{format_decimal(product.rated_capacity_btu_at_minus_5c)} BTU",
            efficiency_metric_summary(product)
          ].compact_blank.join("; ")
        end

        def efficiency_metric_summary(product)
          [
            (
              if metric_present?(product.seer)
                "SEER #{format_decimal(product.seer)}"
              end
            ),
            (
              if metric_present?(product.hspf)
                "HSPF #{format_decimal(product.hspf)}"
              end
            ),
            (
              if metric_present?(product.seer2)
                "SEER2 #{format_decimal(product.seer2)}"
              end
            ),
            (
              if metric_present?(product.hspf2)
                "HSPF2 #{format_decimal(product.hspf2)}"
              end
            )
          ].compact.join(", ")
        end

        def efficiency_calculation_text(product)
          legacy =
            if metric_present?(product.seer) || metric_present?(product.hspf)
              "SEER #{format_decimal(product.seer)} / HSPF #{format_decimal(product.hspf)} versus SEER >= 16.0 and HSPF >= 10.0"
            else
              "SEER/HSPF pair not provided"
            end

          current =
            if metric_present?(product.seer2) || metric_present?(product.hspf2)
              "SEER2 #{format_decimal(product.seer2)} / HSPF2 #{format_decimal(product.hspf2)} versus SEER2 >= 15.2 and HSPF2 >= 8.5"
            else
              "SEER2/HSPF2 pair not provided"
            end

          "#{legacy}; #{current}"
        end

        def metric_present?(value)
          value.present? && BigDecimal(value.to_s).positive?
        rescue ArgumentError
          false
        end

        def format_decimal(value)
          return nil if value.blank?

          decimal = BigDecimal(value.to_s)
          decimal.frac.zero? ? decimal.to_i.to_s : decimal.to_s("F")
        rescue ArgumentError
          nil
        end

        def normalized_ahri(raw_ahri)
          text = raw_ahri.to_s.strip
          return "" if text.blank?

          digits = text.gsub(/\D/, "")
          digits.presence || text
        end
      end
    end
  end
end
