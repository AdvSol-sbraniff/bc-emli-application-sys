# frozen_string_literal: true

module Claims
  module CodeRules
    module HeatPumpAhri
      class ApplyProductListMatch
        INVOICE_AHRI_FIELD_KEY = "hp_ahri_reference"
        SUPPORTING_AHRI_FIELD_KEY = "ahri_reference"

        AHRI_RELEVANT_UPGRADE_TYPES = %w[
          air_source_heat_pump_electric
          air_source_heat_pump_wood
          air_source_heat_pump_gas_propane
          dual_fuel_ducted_heat_pump
        ].freeze

        MIN_CAPACITY_BTU_AT_MINUS_5C = BigDecimal("12000")
        MIN_SEER = BigDecimal("16.0")
        MIN_HSPF = BigDecimal("10.0")
        MIN_SEER2 = BigDecimal("15.2")
        MIN_HSPF2 = BigDecimal("8.5")

        RULES = {
          product_list_match: {
            number: 1,
            key: "hp_ahri_found_in_product_list"
          },
          minimum_capacity: {
            number: 2,
            key: "hp_product_minimum_capacity_at_minus_5c"
          },
          efficiency_threshold: {
            number: 3,
            key: "hp_product_efficiency_threshold"
          }
        }.freeze

        def self.call(invoice_version_id:, invoice_upgrade_type_id:)
          new(
            invoice_version_id: invoice_version_id,
            invoice_upgrade_type_id: invoice_upgrade_type_id
          ).call
        end

        def self.implemented_rule_keys
          RULES.values.map { |rule| rule.fetch(:key) }
        end

        def initialize(invoice_version_id:, invoice_upgrade_type_id:)
          @invoice_version_id = invoice_version_id
          @invoice_upgrade_type_id = invoice_upgrade_type_id
        end

        def call
          @invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)
          @upgrade_type =
            ::Claims::InvoiceUpgradeType.find(@invoice_upgrade_type_id)

          enabled_rules = enabled_rules_for_upgrade_type
          return { ok: true, skipped: true } if enabled_rules.empty?

          ahri_evidence = ahri_evidence_bundle
          product = product_for_ahri_evidence(ahri_evidence)
          rule_rows =
            rulecheck_rows(
              ahri_evidence: ahri_evidence,
              product: product,
              enabled_rules: enabled_rules
            )

          replace_rulechecks!(rule_rows)

          {
            ok: true,
            skipped: false,
            matched: product.present?,
            rulechecks: rule_rows.size
          }
        rescue => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_rules_for_upgrade_type
          RULES.select do |_rule_type, rule|
            ::Claims::CodeRules::Registry.enabled_for?(
              code_rule_key: rule.fetch(:key),
              invoice_upgrade_type_id: upgrade_type.id,
              fallback: legacy_ahri_relevant_upgrade_type?
            )
          end
        end

        def legacy_ahri_relevant_upgrade_type?
          AHRI_RELEVANT_UPGRADE_TYPES.include?(upgrade_type.upgrade_type_key)
        end

        def ahri_evidence_bundle
          invoice_field = best_invoice_ahri_located_field
          supporting_fields = supporting_document_ahri_located_fields
          invoice_ahri = normalized_ahri(invoice_field&.value_text)
          supporting_ahris =
            supporting_fields
              .map { |field| normalized_ahri(field.value_text) }
              .reject(&:blank?)
              .uniq

          {
            invoice_field: invoice_field,
            supporting_fields: supporting_fields,
            invoice_ahri: invoice_ahri.presence,
            supporting_ahris: supporting_ahris
          }
        end

        def best_invoice_ahri_located_field
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "genai",
              field_key: INVOICE_AHRI_FIELD_KEY
            )
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .first
        end

        def supporting_document_ahri_located_fields
          ::Claims::SupportingDocumentLocatedField
            .joins(:supporting_document)
            .where(
              ::Claims::SupportingDocument.table_name => {
                invoice_id: invoice_version.invoice_id
              }
            )
            .where(field_key: SUPPORTING_AHRI_FIELD_KEY)
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def product_for_ahri_evidence(ahri_evidence)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          return nil if invoice_ahri.blank?

          product_for(invoice_ahri)
        end

        def supporting_ahri_conflict?(ahri_evidence)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          supporting_ahris = ahri_evidence.fetch(:supporting_ahris)

          return false if invoice_ahri.blank? || supporting_ahris.empty?

          supporting_ahris.any? do |supporting_ahri|
            supporting_ahri != invoice_ahri
          end
        end

        def supporting_ahri_matches_invoice?(ahri_evidence)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          supporting_ahris = ahri_evidence.fetch(:supporting_ahris)

          invoice_ahri.present? && supporting_ahris.include?(invoice_ahri)
        end

        def product_for(raw_ahri)
          ahri = normalized_ahri(raw_ahri)
          return nil if ahri.blank?

          current_match =
            current_heat_pump_products
              .where(ahri_reference_number: ahri)
              .order(:source_description, :id)
              .first

          return nil unless current_match

          ::Claims::AhriProduct.find_by(id: current_match.id)
        end

        def current_heat_pump_products
          ::Claims::CurrentAhriProduct.all
        end

        def current_heat_pump_products_available?
          current_heat_pump_products.exists?
        end

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULES.values.map { |rule| rule.fetch(:key) }
          ).delete_all

          ::Claims::InvoiceVersionRulecheck.insert_all!(rows)
        end

        def rulecheck_rows(ahri_evidence:, product:, enabled_rules:)
          [
            (
              if enabled_rules.key?(:product_list_match)
                product_list_match_row(
                  ahri_evidence: ahri_evidence,
                  product: product
                )
              end
            ),
            (
              if enabled_rules.key?(:minimum_capacity)
                minimum_capacity_row(
                  ahri_evidence: ahri_evidence,
                  product: product
                )
              end
            ),
            (
              if enabled_rules.key?(:efficiency_threshold)
                efficiency_threshold_row(
                  ahri_evidence: ahri_evidence,
                  product: product
                )
              end
            )
          ].compact
        end

        def product_list_match_row(ahri_evidence:, product:)
          status =
            ahri_evidence_status(ahri_evidence: ahri_evidence, product: product)

          base_rulecheck_row(
            rule: RULES.fetch(:product_list_match),
            rule_result: product_list_rule_result(status),
            confidence: product_list_confidence(status),
            expected_text:
              "The invoice AHRI reference should match a row in the imported BC Hydro heat-pump product list; supporting-document AHRI evidence, when present, should not conflict.",
            calculation:
              product_list_calculation_text(
                ahri_evidence: ahri_evidence,
                status: status,
                product: product
              ),
            evidence_text: ahri_evidence_text(ahri_evidence),
            reason_and_likely_causes:
              product_list_reason_text(
                ahri_evidence: ahri_evidence,
                status: status,
                product: product
              )
          )
        end

        def minimum_capacity_row(ahri_evidence:, product:)
          ahri_text = display_ahri(ahri_evidence)

          if product.nil?
            return(
              dependent_info_row(
                rule: RULES.fetch(:minimum_capacity),
                ahri_text: ahri_text,
                expected_text:
                  "The matched heat-pump product-list row should show rated capacity at -5C of at least 12,000 BTU.",
                metric_name: "rated capacity at -5C"
              )
            )
          end

          capacity = product.rated_capacity_btu_at_minus_5c

          if capacity.nil?
            return(
              base_rulecheck_row(
                rule: RULES.fetch(:minimum_capacity),
                rule_result: "warn",
                confidence: 0,
                expected_text:
                  "The matched heat-pump product-list row should show rated capacity at -5C of at least 12,000 BTU.",
                calculation:
                  "AHRI #{ahri_text} matched a product-list row, but rated capacity at -5C was blank in the imported data.",
                evidence_text: product_evidence(product),
                reason_and_likely_causes:
                  "The AHRI product-list match succeeded, but the imported row did not provide a rated capacity at -5C value. " \
                    "The Energy Savings Program air-source heat-pump requirements include a minimum capacity requirement of 12,000 BTU. " \
                    "Because the value is missing, code cannot prove whether this product row meets that requirement. " \
                    "Admin should inspect the source product-list PDF or supporting product documents for the missing capacity value. " \
                    "If the source list has been parsed incorrectly, refresh or repair the heat-pump product-list import before relying on this code rule."
              )
            )
          end

          passed = capacity >= MIN_CAPACITY_BTU_AT_MINUS_5C
          base_rulecheck_row(
            rule: RULES.fetch(:minimum_capacity),
            rule_result: passed ? "pass" : "fail",
            confidence: 100,
            expected_text:
              "The matched heat-pump product-list row should show rated capacity at -5C of at least 12,000 BTU.",
            calculation:
              "Rated capacity at -5C = #{format_decimal(capacity)} BTU; required minimum = 12,000 BTU.",
            evidence_text: product_evidence(product),
            reason_and_likely_causes:
              minimum_capacity_reason_text(
                product: product,
                capacity: capacity,
                passed: passed
              )
          )
        end

        def efficiency_threshold_row(ahri_evidence:, product:)
          ahri_text = display_ahri(ahri_evidence)

          if product.nil?
            return(
              dependent_info_row(
                rule: RULES.fetch(:efficiency_threshold),
                ahri_text: ahri_text,
                expected_text:
                  "The matched heat-pump product-list row should meet either SEER >= 16.0 and HSPF >= 10.0, or SEER2 >= 15.2 and HSPF2 >= 8.5.",
                metric_name: "SEER/HSPF or SEER2/HSPF2"
              )
            )
          end

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
          passed = legacy_pass || current_pass

          if !legacy_complete && !current_complete
            return(
              base_rulecheck_row(
                rule: RULES.fetch(:efficiency_threshold),
                rule_result: "warn",
                confidence: 0,
                expected_text:
                  "The matched heat-pump product-list row should meet either SEER >= 16.0 and HSPF >= 10.0, or SEER2 >= 15.2 and HSPF2 >= 8.5.",
                calculation:
                  "AHRI #{ahri_text} matched a product-list row, but neither a complete SEER/HSPF pair nor a complete SEER2/HSPF2 pair was available.",
                evidence_text: product_evidence(product),
                reason_and_likely_causes:
                  "The AHRI product-list match succeeded, but the imported row did not include enough efficiency metrics for a deterministic threshold check. " \
                    "The Energy Savings Program allows the product to qualify using either the legacy SEER/HSPF pair or the newer SEER2/HSPF2 pair. " \
                    "Code needs one complete pair to evaluate the threshold safely. " \
                    "Admin should inspect the source product-list PDF or product documentation for the missing efficiency values. " \
                    "If the source values are visible but missing here, refresh or repair the heat-pump product-list import."
              )
            )
          end

          base_rulecheck_row(
            rule: RULES.fetch(:efficiency_threshold),
            rule_result: passed ? "pass" : "fail",
            confidence: 100,
            expected_text:
              "The matched heat-pump product-list row should meet either SEER >= 16.0 and HSPF >= 10.0, or SEER2 >= 15.2 and HSPF2 >= 8.5.",
            calculation: efficiency_calculation_text(product: product),
            evidence_text: product_evidence(product),
            reason_and_likely_causes:
              efficiency_reason_text(
                product: product,
                legacy_pass: legacy_pass,
                current_pass: current_pass,
                passed: passed
              )
          )
        end

        def base_rulecheck_row(
          rule:,
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
            rule_number: rule.fetch(:number),
            rule_key: rule.fetch(:key),
            rule_result: rule_result,
            confidence: confidence,
            expected_text: expected_text,
            calculation: calculation,
            evidence_text: evidence_text,
            reason_and_likely_causes:
              append_admin_message(
                rule: rule,
                rule_result: rule_result,
                reason_text: reason_and_likely_causes
              ),
            created_at: now,
            updated_at: now
          }
        end

        def dependent_info_row(rule:, ahri_text:, expected_text:, metric_name:)
          base_rulecheck_row(
            rule: rule,
            rule_result: "info",
            confidence: 0,
            expected_text: expected_text,
            calculation:
              "The #{metric_name} check was not run because no matching heat-pump product-list row was available for AHRI #{ahri_text.presence || "(missing)"}.",
            evidence_text: ahri_text.presence,
            reason_and_likely_causes:
              "This code rule depends on a successful AHRI product-list match before it can inspect product-list metrics. " \
                "Code Rule 1 records whether the AHRI reference was missing, not found, or matched. " \
                "Until a product row is matched, this dependent metric check cannot make a meaningful pass or fail decision. " \
                "This is shown as information rather than a second warning so the admin is not asked to resolve the same root issue twice. " \
                "After the AHRI match is corrected, rerun GenAI/code checks to evaluate this product-list metric."
          )
        end

        def append_admin_message(rule:, rule_result:, reason_text:)
          message =
            ::Claims::CodeRules::Registry.admin_message(
              code_rule_key: rule.fetch(:key),
              rule_result: rule_result
            )
          return reason_text if message.blank?

          "#{reason_text}\n\nAdmin guidance: #{message}"
        end

        def product_list_rule_result(status)
          if %i[
               source_unavailable
               missing_invoice
               matched_without_supporting
             ].include?(status)
            "warn"
          else
            (status == :matched_with_supporting ? "pass" : "fail")
          end
        end

        def product_list_confidence(status)
          case status
          when :matched_with_supporting, :matched_without_supporting, :conflict,
               :not_found
            100
          else
            0
          end
        end

        def ahri_evidence_status(ahri_evidence:, product:)
          return :missing_invoice if ahri_evidence.fetch(:invoice_ahri).blank?
          return :conflict if supporting_ahri_conflict?(ahri_evidence)
          unless current_heat_pump_products_available?
            return :source_unavailable
          end

          return :not_found if product.blank?
          if supporting_ahri_matches_invoice?(ahri_evidence)
            return :matched_with_supporting
          end

          :matched_without_supporting
        end

        def product_list_calculation_text(ahri_evidence:, status:, product:)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          supporting_ahris = ahri_evidence.fetch(:supporting_ahris)

          case status
          when :missing_invoice
            "No #{INVOICE_AHRI_FIELD_KEY} invoice located field was stored for this heat-pump upgrade call. Supporting-document AHRI values: #{supporting_ahris.presence&.join(", ") || "(none)"}."
          when :conflict
            "Invoice AHRI #{invoice_ahri} did not match supporting-document AHRI values #{supporting_ahris.join(", ")}."
          when :source_unavailable
            "Invoice AHRI #{invoice_ahri} was stored, but no current imported BC Hydro heat-pump product-list rows were available to search."
          when :matched_with_supporting
            "Invoice AHRI #{invoice_ahri} matched ahri_products.id=#{product.id} from source=#{product.import_run&.ahri_source&.description}; supporting-document AHRI evidence corroborates the same value."
          when :matched_without_supporting
            "Invoice AHRI #{invoice_ahri} matched ahri_products.id=#{product.id} from source=#{product.import_run&.ahri_source&.description}; no supporting-document #{SUPPORTING_AHRI_FIELD_KEY} located field corroborated the AHRI."
          else
            "Invoice AHRI #{invoice_ahri} was searched across the current imported BC Hydro heat-pump product lists, but no matching row was found."
          end
        end

        def product_list_reason_text(ahri_evidence:, status:, product:)
          invoice_ahri = ahri_evidence.fetch(:invoice_ahri)
          supporting_ahris = ahri_evidence.fetch(:supporting_ahris)

          case status
          when :missing_invoice
            "The invoice located fields did not include #{INVOICE_AHRI_FIELD_KEY}. " \
              "Supporting-document AHRI evidence is useful context, but this code rule uses the invoice AHRI as the product-list lookup key. " \
              "Without an invoice AHRI, code cannot confirm the billed equipment against the imported BC Hydro heat-pump product list. " \
              "Admin should verify whether the invoice visibly includes an AHRI reference and rerun extraction if needed."
          when :conflict
            "The invoice AHRI reference does not match the AHRI reference extracted from supporting documents. " \
              "Invoice AHRI is #{invoice_ahri}; supporting-document AHRI values are #{supporting_ahris.join(", ")}. " \
              "Because the two sources conflict, code cannot safely treat the supporting document as corroboration for the invoice product-list match. " \
              "Admin should verify whether the wrong supporting document was uploaded, the invoice references a different system, or extraction needs correction."
          when :source_unavailable
            "The invoice located fields show AHRI #{invoice_ahri}, but there are no current imported BC Hydro heat-pump product-list rows available for code to search. " \
              "This is an information-on-record problem, not a product failure. " \
              "Admin should refresh the heat-pump product-list imports and rerun GenAI/code checks."
          when :matched_with_supporting
            "The invoice AHRI #{invoice_ahri} was found in the current imported BC Hydro heat-pump product lists, and supporting-document AHRI evidence corroborates the same value. " \
              "The stored invoice version now points to the exact imported product-list row used for this check. " \
              "This is a code-owned pass because the match was made against local information on record, not by model judgment. " \
              "Admins can use the AHRI product-list section to inspect make, model, capacity, and efficiency details."
          when :matched_without_supporting
            "The invoice AHRI #{invoice_ahri} was found in the current imported BC Hydro heat-pump product lists, so the product-list lookup itself succeeded. " \
              "No processed supporting document supplied a matching #{SUPPORTING_AHRI_FIELD_KEY} located field, so this is shown as a warning for admin awareness rather than as a product-list failure. " \
              "Admin can use the AHRI product-list section to inspect the matched row and decide whether the evidence package needs follow-up."
          else
            "The invoice AHRI #{invoice_ahri} was not found across the current imported BC Hydro heat-pump product lists. " \
              "This is a product-list lookup failure, regardless of whether supporting-document AHRI evidence is present. " \
              "Admin should verify the AHRI was read correctly, confirm the product-list imports are current, and ask the contractor for corrected qualifying-product evidence if the AHRI still does not match."
          end
        end

        def display_ahri(ahri_evidence)
          ahri_evidence.fetch(:invoice_ahri).presence ||
            ahri_evidence.fetch(:supporting_ahris).first.presence
        end

        def ahri_evidence_text(ahri_evidence)
          invoice_field = ahri_evidence.fetch(:invoice_field)
          supporting_fields = ahri_evidence.fetch(:supporting_fields)
          parts = []

          if invoice_field
            parts << "invoice: #{invoice_field.evidence_text.presence || invoice_field.value_text}"
          end

          supporting_fields.each do |field|
            label =
              field.supporting_document&.original_filename.presence ||
                "supporting document"
            parts << "#{label}: #{field.evidence_text.presence || field.value_text}"
          end

          parts.uniq.join("; ").presence
        end

        def minimum_capacity_reason_text(product:, capacity:, passed:)
          if passed
            return(
              "The matched BC Hydro product-list row shows rated capacity at -5C of #{format_decimal(capacity)} BTU. " \
                "That is above the 12,000 BTU minimum used for these air-source heat-pump checks. " \
                "This is a code-owned pass because the value came from the imported product-list row linked to the AHRI reference. " \
                "The AHRI product-list section in the viewer shows the same matched row for admin inspection. " \
                "No follow-up is required for this product-list capacity threshold."
            )
          end

          "The matched BC Hydro product-list row shows rated capacity at -5C of #{format_decimal(capacity)} BTU. " \
            "That is below the 12,000 BTU minimum used for these air-source heat-pump checks. " \
            "Because this value comes from the imported product-list row, code can make a deterministic fail decision. " \
            "Admin should confirm the AHRI number and product-list row are the correct installed equipment combination. " \
            "If the AHRI match is correct, the contractor likely needs to provide different product evidence or correct the invoice."
        end

        def efficiency_calculation_text(product:)
          legacy_text =
            if metric_present?(product.seer) || metric_present?(product.hspf)
              "SEER #{format_decimal(product.seer)} / HSPF #{format_decimal(product.hspf)} versus required SEER >= 16.0 and HSPF >= 10.0"
            else
              "SEER/HSPF pair not provided"
            end

          current_text =
            if metric_present?(product.seer2) || metric_present?(product.hspf2)
              "SEER2 #{format_decimal(product.seer2)} / HSPF2 #{format_decimal(product.hspf2)} versus required SEER2 >= 15.2 and HSPF2 >= 8.5"
            else
              "SEER2/HSPF2 pair not provided"
            end

          "#{legacy_text}; #{current_text}."
        end

        def efficiency_reason_text(
          product:,
          legacy_pass:,
          current_pass:,
          passed:
        )
          if passed
            passing_path =
              if current_pass
                "SEER2/HSPF2"
              elsif legacy_pass
                "SEER/HSPF"
              end

            return(
              "The matched BC Hydro product-list row meets the Energy Savings Program efficiency threshold using the #{passing_path} metric pair. " \
                "The rule allows either the legacy SEER/HSPF path or the newer SEER2/HSPF2 path to satisfy the requirement. " \
                "The imported row values are #{efficiency_metric_summary(product)}. " \
                "This is a code-owned pass because the comparison is simple numeric threshold logic against the matched product-list row. " \
                "No follow-up is required for this product-list efficiency threshold."
            )
          end

          "The matched BC Hydro product-list row does not meet either allowed efficiency threshold path. " \
            "The rule allows either SEER >= 16.0 with HSPF >= 10.0, or SEER2 >= 15.2 with HSPF2 >= 8.5. " \
            "The imported row values are #{efficiency_metric_summary(product)}. " \
            "Because complete values are available and neither allowed path passes, code can make a deterministic fail decision. " \
            "Admin should confirm the AHRI number and product-list row are the correct installed equipment combination before asking the contractor for corrected product evidence."
        end

        def product_evidence(product)
          [
            "AHRI #{product.ahri_reference_number}",
            product.make,
            product.outdoor_model,
            product.indoor_model_or_air_handler,
            product.furnace_model,
            "capacity @ -5C #{format_decimal(product.rated_capacity_btu_at_minus_5c)} BTU",
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
