# frozen_string_literal: true

module Claims
  module CodeRules
    module VentilationFan
      class ApplyProductListMatch
        VENTILATION_UPGRADE_TYPE_KEY = "ventilation"

        INVOICE_FIELD_KEYS = %w[
          vent_system_type
          vent_manufacturer
          vent_model_number
          vent_make_model
          vent_energy_star_reference
          vent_nrcan_or_product_list_reference
        ].freeze

        SUPPORTING_DOCUMENT_FIELD_KEYS = %w[
          brand_and_model
          model_number
          product_category_or_system_type
          energy_star_reference
          product_list_reference
        ].freeze

        SUPPORTING_DOCUMENT_CAPACITY_FIELD_KEYS = %w[
          bathroom_fan_cfm
          static_pressure
        ].freeze

        MINIMUM_CAPACITY_CFM = 85.0

        RULES = {
          product_list_match: {
            key: "vent_fan_energy_star_product_validation"
          },
          capacity_minimum: {
            key: "vent_fan_capacity_meets_minimum"
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

          field_bundle = located_field_bundle
          status = product_list_status(field_bundle)
          product =
            status == :matched ? product_for_field_bundle(field_bundle) : nil

          invoice_version.update!(vent_fan_product_id: product&.id)

          rule_rows =
            rulecheck_rows(
              field_bundle: field_bundle,
              product: product,
              status: status,
              enabled_rules: enabled_rules
            )

          replace_rulechecks!(rule_rows)

          {
            ok: true,
            skipped: false,
            matched: product.present?,
            status: status,
            rulechecks: rule_rows.size
          }
        rescue StandardError => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_rules_for_upgrade_type
          RULES.select do |_rule_type, rule|
            ::Claims::CodeRules::Registry.enabled_for?(
              code_rule_key: rule.fetch(:key),
              invoice_upgrade_type_id: upgrade_type.id,
              fallback: legacy_ventilation_relevant_upgrade_type?
            )
          end
        end

        def legacy_ventilation_relevant_upgrade_type?
          upgrade_type.upgrade_type_key == VENTILATION_UPGRADE_TYPE_KEY
        end

        def located_field_bundle
          invoice_fields =
            invoice_located_fields(field_keys: INVOICE_FIELD_KEYS)
          supporting_fields =
            supporting_document_located_fields(
              field_keys: SUPPORTING_DOCUMENT_FIELD_KEYS
            )
          supporting_capacity_fields =
            supporting_document_located_fields(
              field_keys: SUPPORTING_DOCUMENT_CAPACITY_FIELD_KEYS
            )
          all_fields =
            invoice_fields + supporting_fields + supporting_capacity_fields

          {
            fields: {
              invoice: invoice_fields,
              supporting_document:
                supporting_fields + supporting_capacity_fields
            },
            all_text: values_for(all_fields).join(" "),
            invoice_model_values: model_values_for(invoice_fields),
            supporting_model_values: model_values_for(supporting_fields),
            invoice_manufacturer_values:
              manufacturer_values_for(invoice_fields),
            supporting_manufacturer_values:
              manufacturer_values_for(supporting_fields),
            capacity_fields: {
              invoice: [],
              supporting_document: supporting_capacity_fields
            }
          }
        end

        def invoice_located_fields(field_keys:)
          ::Claims::InvoiceVersionLocatedField
            .where(
              invoice_version_id: invoice_version.id,
              invoice_upgrade_type_id: upgrade_type.id,
              source_engine: "genai",
              field_key: field_keys
            )
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def supporting_document_located_fields(field_keys:)
          ::Claims::SupportingDocumentLocatedField
            .joins(:supporting_document)
            .where(
              ::Claims::SupportingDocument.table_name => {
                invoice_version_id: invoice_version.id
              }
            )
            .where(field_key: field_keys)
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def values_for(fields)
          fields
            .flat_map { |field| split_field_value(field.value_text) }
            .map(&:squish)
            .reject(&:blank?)
            .uniq
        end

        def model_values_for(fields)
          values_for(fields).select { |value| model_like?(value) }
        end

        def manufacturer_values_for(fields)
          values_for(fields).map { |value| normalize_text(value) }.compact.uniq
        end

        def split_field_value(value)
          value.to_s.split(/\s*(?:\||,|;|\n|\r|&)\s*/).reject(&:blank?)
        end

        def model_like?(value)
          text = value.to_s
          loose = loose_model_key(text)
          loose.present? && loose.length >= 4 && text.match?(/[0-9]/)
        end

        def product_list_status(field_bundle)
          return :hrv_or_erv if hrv_or_erv_evidence?(field_bundle)
          return :unclear_system_type if fan_evidence?(field_bundle) == false
          if field_bundle.fetch(:invoice_model_values).empty?
            return :missing_invoice
          end
          if field_bundle.fetch(:supporting_model_values).empty?
            return :missing_supporting
          end
          return :source_unavailable unless current_vent_fan_products_available?

          invoice_product =
            product_for_values(
              model_values: field_bundle.fetch(:invoice_model_values),
              manufacturer_values:
                field_bundle.fetch(:invoice_manufacturer_values)
            )
          supporting_product =
            product_for_values(
              model_values: field_bundle.fetch(:supporting_model_values),
              manufacturer_values:
                field_bundle.fetch(:supporting_manufacturer_values)
            )

          if invoice_product.blank? || supporting_product.blank?
            return :not_found
          end
          return :conflict unless invoice_product.id == supporting_product.id

          :matched
        end

        def hrv_or_erv_evidence?(field_bundle)
          normalized_bundle_text(field_bundle).match?(
            /\b(hrv|erv)\b|heat recovery|energy recovery/
          )
        end

        def fan_evidence?(field_bundle)
          text = normalized_bundle_text(field_bundle)
          return nil if text.blank?

          text.match?(
            /bathroom fan|bath fan|utility fan|exhaust fan|ventilating fan|fan system/
          )
        end

        def normalized_bundle_text(field_bundle)
          normalize_text(field_bundle.fetch(:all_text)).to_s.downcase
        end

        def product_for_field_bundle(field_bundle)
          invoice_product =
            product_for_values(
              model_values: field_bundle.fetch(:invoice_model_values),
              manufacturer_values:
                field_bundle.fetch(:invoice_manufacturer_values)
            )
          supporting_product =
            product_for_values(
              model_values: field_bundle.fetch(:supporting_model_values),
              manufacturer_values:
                field_bundle.fetch(:supporting_manufacturer_values)
            )

          return nil if invoice_product.blank? || supporting_product.blank?
          return nil unless invoice_product.id == supporting_product.id

          invoice_product
        end

        def product_for_values(model_values:, manufacturer_values:)
          return nil if model_values.empty?

          matches =
            current_vent_fan_products.filter_map do |product|
              model_score =
                model_match_score(product: product, model_values: model_values)
              next if model_score.zero?

              manufacturer_score =
                manufacturer_match_score(
                  product: product,
                  manufacturers: manufacturer_values
                )

              [manufacturer_score + model_score, product]
            end

          match =
            matches.max_by do |score, product|
              [score, product.brand.to_s, product.model_number.to_s, product.id]
            end

          ::Claims::VentFanProduct.find_by(id: match.last.id) if match
        end

        def current_vent_fan_products
          ::Claims::CurrentVentFanProduct.all.to_a
        end

        def current_vent_fan_products_available?
          ::Claims::CurrentVentFanProduct.exists?
        end

        def manufacturer_match_score(product:, manufacturers:)
          return 0 if manufacturers.empty?

          product_brand = normalize_text(product.brand)
          return 0 if product_brand.blank?

          matched =
            manufacturers.any? do |manufacturer|
              manufacturer == product_brand ||
                manufacturer.include?(product_brand) ||
                product_brand.include?(manufacturer)
            end

          matched ? 20 : 0
        end

        def model_match_score(product:, model_values:)
          product_model = product.model_number.to_s
          product_strict = strict_model_key(product_model)
          product_loose = loose_model_key(product_model)

          model_values.each do |value|
            strict_value = strict_model_key(value)
            loose_value = loose_model_key(value)

            if strict_model_matches_regex?(
                 product.model_number_regex,
                 strict_value
               )
              return 100
            end

            if product.model_number_normalized.present? &&
                 product.model_number_normalized == strict_value
              return 95
            end

            return 90 if product_loose.present? && loose_value == product_loose

            if product_loose.present? && product_loose.length >= 5 &&
                 loose_value.to_s.include?(product_loose)
              return 85
            end

            if loose_value.present? && loose_value.length >= 5 &&
                 product_loose.to_s.include?(loose_value)
              return 75
            end

            next unless product_strict.present? && strict_value.present?
            if strict_value.include?(product_strict) ||
                 product_strict.include?(strict_value)
              return 60
            end
          end

          0
        end

        def strict_model_matches_regex?(regex_text, value)
          return false if regex_text.blank? || value.blank?

          Regexp.new(regex_text).match?(value)
        rescue RegexpError
          false
        end

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULES.values.map { |rule| rule.fetch(:key) }
          ).delete_all

          ::Claims::InvoiceVersionRulecheck.insert_all!(rows) if rows.any?
        end

        def rulecheck_rows(field_bundle:, product:, status:, enabled_rules:)
          [
            (
              if enabled_rules.key?(:product_list_match)
                product_list_match_row(
                  field_bundle: field_bundle,
                  product: product,
                  status: status
                )
              end
            ),
            (
              if enabled_rules.key?(:capacity_minimum)
                capacity_minimum_row(
                  field_bundle: field_bundle,
                  product: product,
                  status: status
                )
              end
            )
          ].compact
        end

        def product_list_match_row(field_bundle:, product:, status:)
          base_rulecheck_row(
            rule: RULES.fetch(:product_list_match),
            rule_result: product_list_rule_result(status),
            confidence: product.present? ? 100 : 0,
            expected_text:
              "For bathroom/utility/exhaust fan ventilation upgrades, the invoice and supporting document should both identify the same fan product, and that product should match a row in the imported ENERGY STAR certified ventilating fan product list.",
            calculation:
              product_list_calculation_text(
                field_bundle: field_bundle,
                status: status,
                product: product
              ),
            evidence_text: field_evidence(field_bundle),
            reason_and_likely_causes:
              product_list_reason_text(
                field_bundle: field_bundle,
                status: status,
                product: product
              )
          )
        end

        def capacity_minimum_row(field_bundle:, product:, status:)
          capacity_status =
            capacity_minimum_status(
              field_bundle: field_bundle,
              product: product,
              product_list_status: status
            )

          base_rulecheck_row(
            rule: RULES.fetch(:capacity_minimum),
            rule_result: capacity_rule_result(capacity_status),
            confidence: capacity_rule_confidence(capacity_status),
            expected_text:
              "For bathroom/utility/exhaust fan ventilation upgrades, visible or imported product evidence should support fan capacity of at least 85 cfm (40 L/s) at 50 Pa (0.2 in. w.c.). The imported ENERGY STAR fan list field bathroom_utility_airflow_at_0_25_in_wg is treated as conservative pass evidence when it is at least 85 cfm.",
            calculation:
              capacity_calculation_text(
                field_bundle: field_bundle,
                product: product,
                capacity_status: capacity_status,
                product_list_status: status
              ),
            evidence_text: field_evidence(field_bundle),
            reason_and_likely_causes:
              capacity_reason_text(
                field_bundle: field_bundle,
                product: product,
                capacity_status: capacity_status
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
          case status
          when :matched
            "pass"
          when :hrv_or_erv
            "info"
          when :missing_invoice, :missing_supporting, :source_unavailable,
               :unclear_system_type
            "warn"
          else
            "fail"
          end
        end

        def capacity_rule_result(status)
          case status
          when :matched_product_pass, :visible_exact_pass
            "pass"
          when :hrv_or_erv
            "info"
          when :visible_exact_fail
            "fail"
          else
            "warn"
          end
        end

        def capacity_rule_confidence(status)
          case status
          when :matched_product_pass, :visible_exact_pass, :visible_exact_fail
            100
          when :hrv_or_erv
            0
          else
            50
          end
        end

        def product_list_calculation_text(field_bundle:, status:, product:)
          base =
            case status
            when :hrv_or_erv
              "Named ventilation evidence indicates HRV/ERV rather than a bathroom/utility/exhaust fan. ENERGY STAR ventilating-fan lookup was not applicable."
            when :unclear_system_type
              "Named ventilation evidence did not clearly show bathroom/utility/exhaust fan wording. Invoice model evidence=#{field_bundle.fetch(:invoice_model_values).presence&.join(" / ") || "(none)"}; supporting-document model evidence=#{field_bundle.fetch(:supporting_model_values).presence&.join(" / ") || "(none)"}."
            when :missing_invoice
              "No usable fan model evidence was stored in invoice fields. Supporting-document model evidence=#{field_bundle.fetch(:supporting_model_values).presence&.join(" / ") || "(none)"}."
            when :missing_supporting
              "Invoice model evidence=#{field_bundle.fetch(:invoice_model_values).join(" / ")}; no usable fan model evidence was stored from supporting documents."
            when :source_unavailable
              "Invoice and supporting-document fan product evidence are present, but no current imported ENERGY STAR ventilating-fan product-list rows were available to search."
            when :conflict
              "Invoice product evidence #{field_bundle.fetch(:invoice_model_values).join(" / ")} did not resolve to the same imported fan product as supporting-document product evidence #{field_bundle.fetch(:supporting_model_values).join(" / ")}."
            when :matched
              "Invoice and supporting-document product evidence both matched vent_fan_products.id=#{product.id} from source=#{product.import_run&.vent_fan_source&.description}. #{field_summary(field_bundle)}; matched fan type=#{product.fan_type}; markets=#{product.markets}; ENERGY STAR Unique ID=#{product.energy_star_unique_id}; CB Model Identifier=#{product.cb_model_identifier}."
            else
              "Invoice model evidence #{field_bundle.fetch(:invoice_model_values).join(" / ")} and supporting-document model evidence #{field_bundle.fetch(:supporting_model_values).join(" / ")} were searched against the current imported ENERGY STAR certified ventilating-fan product list, but code could not confirm a shared matching row."
            end

          [
            base,
            "download_lookup: table=claims.v_current_vent_fan_products; matched_product_id=#{product&.id || "(none)"}",
            subcheck_lines(
              product_validation_subchecks(
                field_bundle: field_bundle,
                status: status,
                product: product
              )
            )
          ].join("\n")
        end

        def product_validation_subchecks(field_bundle:, status:, product:)
          {
            invoice_fan_product_identity_present:
              (
                if field_bundle.fetch(:invoice_model_values).empty?
                  ["warn", "No invoice fan product identity was extracted."]
                else
                  [
                    "pass",
                    "Invoice product evidence=#{field_bundle.fetch(:invoice_model_values).join(" / ")}."
                  ]
                end
              ),
            supporting_document_matches_invoice:
              case status
              when :missing_supporting
                [
                  "warn",
                  "No supporting-document fan product identity was extracted."
                ]
              when :conflict
                [
                  "fail",
                  "Invoice and supporting-document product evidence resolved to different fan rows."
                ]
              when :matched
                [
                  "pass",
                  "Invoice and supporting-document product evidence resolved to the same fan row."
                ]
              else
                if field_bundle.fetch(:supporting_model_values).empty?
                  [
                    "warn",
                    "No supporting-document fan product identity was extracted."
                  ]
                else
                  [
                    "warn",
                    "Supporting-document product identity could not be fully corroborated."
                  ]
                end
              end,
            vent_fan_product_found_in_download:
              case status
              when :matched
                ["pass", "Matched vent_fan_products.id=#{product.id}."]
              when :hrv_or_erv
                ["pass", "Not applicable because evidence indicates HRV/ERV."]
              when :source_unavailable
                [
                  "warn",
                  "No current imported ENERGY STAR fan rows were available."
                ]
              when :missing_invoice, :missing_supporting, :unclear_system_type
                [
                  "warn",
                  "Download lookup could not fully run because product identity or equipment type evidence is incomplete."
                ]
              else
                [
                  "fail",
                  "No shared matching ENERGY STAR fan product row was found."
                ]
              end
          }
        end

        def subcheck_lines(subchecks)
          all =
            subchecks.map do |key, (status, reason)|
              "- #{key}: #{status} - #{reason}"
            end
          failed =
            subchecks
              .select { |_key, (status, _reason)| status == "fail" }
              .map { |key, (_status, reason)| "- #{key}: #{reason}" }
          warned =
            subchecks
              .select { |_key, (status, _reason)| status == "warn" }
              .map { |key, (_status, reason)| "- #{key}: #{reason}" }

          [
            "subchecks:\n#{all.join("\n")}",
            ("failed_subchecks:\n#{failed.join("\n")}" if failed.any?),
            ("warn_subchecks:\n#{warned.join("\n")}" if warned.any?)
          ].compact.join("\n")
        end

        def product_list_reason_text(field_bundle:, status:, product:)
          case status
          when :hrv_or_erv
            "This ventilation upgrade evidence appears to describe an HRV/ERV, not a bathroom/utility/exhaust fan. The fan product-list requirement is not applicable to that equipment, so this code rule records information only."
          when :unclear_system_type
            "The ventilation evidence did not clearly identify the equipment as a bathroom, utility, exhaust, or ventilating fan. Code should not force a product-list failure when the triggering equipment type is unclear. Admin should review vent_system_type and supporting product evidence."
          when :missing_invoice
            "The supporting documents may include fan product evidence, but the invoice located fields did not include a usable model number. Because the invoice does not independently identify the installed fan product, code cannot confirm that the billed equipment matches the supporting product evidence."
          when :missing_supporting
            "The invoice includes fan model evidence, but processed supporting documents did not include usable product evidence. The code-owned lookup requires supporting product evidence such as a product specification sheet, ENERGY STAR label, or manufacturer label/photo."
          when :source_unavailable
            "The invoice and supporting documents both include fan product evidence, but there are no current imported ENERGY STAR ventilating-fan product-list rows available for code to search. Refresh the fan product-list download and rerun GenAI/code checks."
          when :conflict
            "The invoice product evidence does not match the product evidence extracted from supporting documents. Invoice evidence is #{field_bundle.fetch(:invoice_model_values).join(" / ")}; supporting-document evidence is #{field_bundle.fetch(:supporting_model_values).join(" / ")}. Admin should verify whether the wrong supporting document was uploaded, the invoice references a different product, or extraction needs correction."
          when :matched
            "The invoice and supporting document both identify the same fan product, and that product was found in the current imported ENERGY STAR certified ventilating-fan product list. The stored invoice version points to the exact imported product-list row used for this check."
          else
            "The invoice and supporting document both include fan model evidence, but code could not confirm a shared matching row in the current imported ENERGY STAR ventilating-fan product list. Admin should verify the model read, refresh the fan import if needed, or ask the contractor for corrected product evidence."
          end
        end

        def capacity_minimum_status(
          field_bundle:,
          product:,
          product_list_status:
        )
          return :hrv_or_erv if product_list_status == :hrv_or_erv

          visible = visible_capacity_evidence(field_bundle)
          if visible[:exact] && visible[:cfm] >= MINIMUM_CAPACITY_CFM
            return :visible_exact_pass
          end
          if visible[:exact] && visible[:cfm] < MINIMUM_CAPACITY_CFM
            return :visible_exact_fail
          end

          product_airflow = product_list_capacity_cfm(product)
          if product_airflow.present? && product_airflow >= MINIMUM_CAPACITY_CFM
            return :matched_product_pass
          end

          if product.present? && product_airflow.present?
            return :product_capacity_needs_review
          end

          return :visible_generic_capacity_only if visible[:cfm].present?
          unless product_list_status == :matched
            return :product_lookup_not_confirmed
          end

          :missing_capacity_evidence
        end

        def visible_capacity_evidence(field_bundle)
          texts = capacity_field_texts(field_bundle)
          joined = texts.join(" ")
          cfm = visible_capacity_cfm(joined)

          {
            cfm: cfm,
            exact: cfm.present? && required_static_pressure_evidence?(joined),
            text: joined.presence
          }
        end

        def capacity_field_texts(field_bundle)
          field_bundle
            .fetch(:capacity_fields)
            .values
            .flatten
            .filter_map do |field|
              [field.value_text.presence, field.evidence_text.presence].compact
            end
            .flatten
            .map(&:squish)
            .reject(&:blank?)
            .uniq
        end

        def visible_capacity_cfm(text)
          values = []

          text
            .to_s
            .scan(/(\d+(?:\.\d+)?)\s*(?:cfm|cubic feet)/i) do |match|
              values << match.first.to_f
            end

          text
            .to_s
            .scan(
              %r{(\d+(?:\.\d+)?)\s*(?:l\s*/\s*s|lps|litres?\s+per\s+second)}i
            ) { |match| values << (match.first.to_f * 2.11888) }

          values.max
        end

        def required_static_pressure_evidence?(text)
          normalized = text.to_s.downcase
          normalized.match?(/\b50\s*pa\b/) ||
            normalized.match?(/\b0\.2\s*(?:in|inch|["'”])/) ||
            normalized.match?(/\b0\.20\s*(?:in|inch|["'”])/)
        end

        def product_list_capacity_cfm(product)
          product&.bathroom_utility_airflow_at_0_25_in_wg&.to_f
        end

        def capacity_calculation_text(
          field_bundle:,
          product:,
          capacity_status:,
          product_list_status:
        )
          visible = visible_capacity_evidence(field_bundle)
          product_airflow = product_list_capacity_cfm(product)
          visible_text = visible[:text] || "(none)"
          product_text =
            (
              if product.present?
                "vent_fan_products.id=#{product.id}; bathroom_utility_airflow_at_0_25_in_wg=#{product_airflow || "(blank)"} cfm; airflow_1_cfm=#{product.airflow_1_cfm || "(blank)"}; airflow_2_cfm=#{product.airflow_2_cfm || "(blank)"}; airflow_3_cfm=#{product.airflow_3_cfm || "(blank)"}"
              else
                "(no matched product-list row)"
              end
            )

          case capacity_status
          when :matched_product_pass
            "Matched fan product has bathroom_utility_airflow_at_0_25_in_wg=#{product_airflow} cfm, which is at least #{MINIMUM_CAPACITY_CFM.to_i} cfm at a stricter listed pressure than 0.2 in. w.c. Product evidence: #{product_text}. Named visible capacity evidence: #{visible_text}."
          when :visible_exact_pass
            "Named visible capacity evidence shows #{visible[:cfm].round(1)} cfm at 50 Pa / 0.2 in. w.c., which is at least #{MINIMUM_CAPACITY_CFM.to_i} cfm. Product-list status=#{product_list_status}. Product evidence: #{product_text}. Named visible capacity evidence: #{visible_text}."
          when :visible_exact_fail
            "Named visible capacity evidence shows #{visible[:cfm].round(1)} cfm at 50 Pa / 0.2 in. w.c., which is below #{MINIMUM_CAPACITY_CFM.to_i} cfm. Product-list status=#{product_list_status}. Product evidence: #{product_text}. Named visible capacity evidence: #{visible_text}."
          when :product_capacity_needs_review
            "Matched fan product has bathroom_utility_airflow_at_0_25_in_wg=#{product_airflow} cfm, which does not independently confirm at least #{MINIMUM_CAPACITY_CFM.to_i} cfm at the required 0.2 in. w.c. pressure because the imported list uses 0.25 in. w.g. for this field. Product evidence: #{product_text}. Named visible capacity evidence: #{visible_text}."
          when :visible_generic_capacity_only
            "Named visible capacity evidence shows #{visible[:cfm].round(1)} cfm, but the named evidence did not clearly tie that capacity to 50 Pa / 0.2 in. w.c. Product-list status=#{product_list_status}. Product evidence: #{product_text}. Named visible capacity evidence: #{visible_text}."
          when :hrv_or_erv
            "Named ventilation evidence indicates HRV/ERV rather than a bathroom/utility/exhaust fan. Fan capacity minimum lookup was not applicable."
          else
            "Code could not confirm fan capacity from a matched ENERGY STAR fan row or named visible capacity fields. Product-list status=#{product_list_status}. Product evidence: #{product_text}. Named visible capacity evidence: #{visible_text}."
          end
        end

        def capacity_reason_text(field_bundle:, product:, capacity_status:)
          visible = visible_capacity_evidence(field_bundle)

          case capacity_status
          when :matched_product_pass
            "The matched imported ENERGY STAR fan row provides strong capacity evidence because its bathroom/utility airflow at 0.25 in. w.g. is at least 85 cfm. Since 0.25 in. w.g. is a stricter listed pressure than 0.2 in. w.c., this supports the fan capacity requirement."
          when :visible_exact_pass
            "The named capacity/static-pressure evidence itself supports at least 85 cfm at 50 Pa / 0.2 in. w.c."
          when :visible_exact_fail
            "The named capacity/static-pressure evidence appears to show the fan below 85 cfm at 50 Pa / 0.2 in. w.c. Admin should verify the product specification before approving this requirement."
          when :product_capacity_needs_review
            "The fan product was matched, but the imported product-list capacity field does not clearly prove the 85 cfm threshold at the required pressure. Admin should verify a product specification sheet or ENERGY STAR row detail before relying on the capacity requirement."
          when :visible_generic_capacity_only
            "Capacity evidence is present, but the named evidence does not clearly include the required static pressure. Admin should verify whether #{visible[:cfm]&.round(1)} cfm applies at 50 Pa / 0.2 in. w.c."
          when :product_lookup_not_confirmed
            "The fan product-list match was not confirmed, so code could not rely on imported product-list capacity evidence. Admin should resolve the product-list match first or verify named capacity evidence."
          when :hrv_or_erv
            "This evidence appears to describe an HRV/ERV, not a bathroom/utility/exhaust fan. The bathroom fan capacity minimum is not applicable to that equipment."
          else
            "No named capacity evidence was available and no matched fan product-list row supplied usable bathroom/utility airflow evidence. Admin should request or review a product specification sheet if this is a bathroom/utility/exhaust fan."
          end
        end

        def field_evidence(field_bundle)
          field_bundle
            .fetch(:fields)
            .values
            .flatten
            .filter_map do |field|
              field.evidence_text.presence || field.value_text.presence
            end
            .uniq
            .join("; ")
            .presence
        end

        def field_summary(field_bundle)
          [
            (
              if field_bundle.fetch(:invoice_model_values).any?
                "invoice model=#{field_bundle.fetch(:invoice_model_values).join(" / ")}"
              end
            ),
            (
              if field_bundle.fetch(:supporting_model_values).any?
                "supporting model=#{field_bundle.fetch(:supporting_model_values).join(" / ")}"
              end
            )
          ].compact.join("; ")
        end

        def normalize_text(value)
          value.to_s.upcase.gsub(/[^A-Z0-9]+/, " ").squish.presence
        end

        def strict_model_key(value)
          model_match_text(value).upcase.gsub(/\s+/, "").presence
        end

        def loose_model_key(value)
          model_match_text(value).upcase.gsub(/[^A-Z0-9]/, "").presence
        end

        def model_match_text(value)
          value.to_s.gsub(/\([^)]*=\s*all sizes[^)]*\)/i, "").squish
        end
      end
    end
  end
end
