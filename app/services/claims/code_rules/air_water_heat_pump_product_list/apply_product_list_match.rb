# frozen_string_literal: true

module Claims
  module CodeRules
    module AirWaterHeatPumpProductList
      class ApplyProductListMatch
        RELEVANT_UPGRADE_FIELD_KEYS = {
          "air_to_water_heat_pump" => %w[
            hp_make_model
            atw_product_list_reference
          ],
          "combined_space_water_heat_pump" => %w[
            hp_make_model
            cshp_product_list_reference
          ]
        }.freeze

        SUPPORTING_DOCUMENT_FIELD_KEYS = %w[
          brand_and_model
          model_number
          product_list_reference
        ].freeze

        RELEVANT_UPGRADE_TYPE_KEYS = RELEVANT_UPGRADE_FIELD_KEYS.keys.freeze

        RULES = {
          product_list_match: {
            key: "hydronic_awhp_product_validation"
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
          product = product_for_field_bundle(field_bundle)
          invoice_version.update!(awhp_product_id: product&.id)
          rule_rows =
            rulecheck_rows(
              field_bundle: field_bundle,
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
              fallback: legacy_awhp_relevant_upgrade_type?
            )
          end
        end

        def legacy_awhp_relevant_upgrade_type?
          RELEVANT_UPGRADE_TYPE_KEYS.include?(upgrade_type.upgrade_type_key)
        end

        def located_field_bundle
          invoice_fields = hydronic_invoice_located_fields
          supporting_fields = supporting_document_located_fields
          all_fields = invoice_fields + supporting_fields

          {
            fields: {
              invoice: invoice_fields,
              supporting_document: supporting_fields
            },
            model_values: model_values_for(all_fields),
            manufacturer_values: manufacturer_values_for(all_fields),
            invoice_model_values: model_values_for(invoice_fields),
            supporting_model_values: model_values_for(supporting_fields),
            invoice_manufacturer_values:
              manufacturer_values_for(invoice_fields),
            supporting_manufacturer_values:
              manufacturer_values_for(supporting_fields)
          }
        end

        def hydronic_invoice_located_fields
          field_keys =
            RELEVANT_UPGRADE_FIELD_KEYS.fetch(upgrade_type.upgrade_type_key, [])
          return [] if field_keys.empty?

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

        def supporting_document_located_fields
          ::Claims::SupportingDocumentLocatedField
            .joins(:supporting_document)
            .where(
              ::Claims::SupportingDocument.table_name => {
                invoice_version_id: invoice_version.id
              }
            )
            .where(field_key: SUPPORTING_DOCUMENT_FIELD_KEYS)
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def model_values_for(fields)
          fields
            .flat_map { |field| split_field_value(field.value_text) }
            .map(&:squish)
            .select { |value| model_like?(value) }
            .uniq
        end

        def manufacturer_values_for(fields)
          fields
            .flat_map { |field| split_field_value(field.value_text) }
            .map { |value| normalize_text(value) }
            .compact
            .uniq
        end

        def split_field_value(value)
          value.to_s.split(/\s*(?:\||,|;|\n|\r)\s*/).reject(&:blank?)
        end

        def model_like?(value)
          text = value.to_s
          loose = loose_model_key(text)
          loose.present? && loose.length >= 4 && text.match?(/[0-9]/)
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
            current_awhp_products.filter_map do |product|
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

          ::Claims::AwhpProduct.find_by(id: match.last.id) if match
        end

        def current_awhp_products
          ::Claims::CurrentAwhpProduct.all.to_a
        end

        def current_awhp_products_available?
          ::Claims::CurrentAwhpProduct.exists?
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
          product_components =
            Array(product.model_components)
              .map { |component| loose_model_key(component) }
              .reject(&:blank?)

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
                 loose_value.include?(product_loose)
              return 85
            end

            if loose_value.present? && loose_value.length >= 5 &&
                 product_loose.to_s.include?(loose_value)
              return 75
            end

            if all_components_match?(
                 product_components: product_components,
                 loose_value: loose_value
               )
              return 70
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

        def all_components_match?(product_components:, loose_value:)
          return false if product_components.empty? || loose_value.blank?

          product_components.all? do |component|
            loose_value.include?(component)
          end
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

        def rulecheck_rows(field_bundle:, product:, enabled_rules:)
          [
            (
              if enabled_rules.key?(:product_list_match)
                product_list_match_row(
                  field_bundle: field_bundle,
                  product: product
                )
              end
            )
          ].compact
        end

        def product_list_match_row(field_bundle:, product:)
          matched = product.present?
          status =
            product_list_status(field_bundle: field_bundle, product: product)

          base_rulecheck_row(
            rule: RULES.fetch(:product_list_match),
            rule_result: product_list_rule_result(status),
            confidence: matched ? 100 : 0,
            expected_text:
              "The invoice and supporting document should both identify the same hydronic heat-pump product, and that product should match a row in the imported Better Homes BC qualifying product list.",
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
          if %i[missing_invoice missing_supporting source_unavailable].include?(
               status
             )
            "warn"
          else
            (status == :matched ? "pass" : "fail")
          end
        end

        def product_list_status(field_bundle:, product:)
          if field_bundle.fetch(:invoice_model_values).empty?
            return :missing_invoice
          end
          if field_bundle.fetch(:supporting_model_values).empty?
            return :missing_supporting
          end
          return :source_unavailable unless current_awhp_products_available?

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

          product.present? ? :matched : :not_found
        end

        def product_list_calculation_text(field_bundle:, status:, product:)
          base =
            case status
            when :missing_invoice
              "No usable hydronic heat-pump model/product evidence was stored in invoice located fields. Supporting-document product evidence: #{field_bundle.fetch(:supporting_model_values).presence&.join(" / ") || "(none)"}."
            when :missing_supporting
              "Invoice product evidence was stored as #{field_bundle.fetch(:invoice_model_values).join(" / ")}, but no usable supporting-document product evidence was stored."
            when :source_unavailable
              "Invoice and supporting-document product evidence are present, but no current imported Better Homes BC air-to-water / combined heat pump product-list rows were available to search."
            when :conflict
              "Invoice product evidence #{field_bundle.fetch(:invoice_model_values).join(" / ")} did not resolve to the same imported AWHP product as supporting-document product evidence #{field_bundle.fetch(:supporting_model_values).join(" / ")}."
            when :matched
              "Invoice and supporting-document product evidence both matched awhp_products.id=#{product.id} from source=#{product.import_run&.awhp_source&.description}. #{field_summary(field_bundle)}."
            else
              "Invoice product evidence #{field_bundle.fetch(:invoice_model_values).join(" / ")} and supporting-document product evidence #{field_bundle.fetch(:supporting_model_values).join(" / ")} were searched against the current imported Better Homes BC qualifying list, but code could not confirm a shared matching row."
            end

          [
            base,
            "download_lookup: table=claims.v_current_awhp_products; matched_product_id=#{product&.id || "(none)"}",
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
            invoice_product_identity_present:
              if field_bundle.fetch(:invoice_model_values).empty?
                ["warn", "No invoice hydronic product identity was extracted."]
              else
                [
                  "pass",
                  "Invoice product evidence=#{field_bundle.fetch(:invoice_model_values).join(" / ")}."
                ]
              end,
            supporting_document_matches_invoice:
              case status
              when :missing_supporting
                [
                  "warn",
                  "No supporting-document hydronic product identity was extracted."
                ]
              when :conflict
                [
                  "fail",
                  "Invoice and supporting-document product evidence resolved to different AWHP rows."
                ]
              when :matched
                [
                  "pass",
                  "Invoice and supporting-document product evidence resolved to the same AWHP row."
                ]
              else
                if field_bundle.fetch(:supporting_model_values).empty?
                  [
                    "warn",
                    "No supporting-document hydronic product identity was extracted."
                  ]
                else
                  [
                    "warn",
                    "Supporting-document product identity could not be fully corroborated."
                  ]
                end
              end,
            awhp_product_found_in_download:
              case status
              when :matched
                ["pass", "Matched awhp_products.id=#{product.id}."]
              when :source_unavailable
                ["warn", "No current imported AWHP rows were available."]
              when :missing_invoice, :missing_supporting
                [
                  "warn",
                  "Download lookup could not fully run because prerequisite product identity evidence is missing."
                ]
              else
                ["fail", "No shared matching AWHP product row was found."]
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
          when :missing_invoice
            "The product-list requirement now requires product evidence in both the invoice and a supporting product document. " \
              "The supporting documents may include hydronic product evidence, but the invoice located fields did not include a usable model number or product-list reference. " \
              "Because the invoice does not independently identify the installed product, code cannot confirm that the billed equipment matches the supporting product evidence. " \
              "Admin should ask for a corrected invoice or rerun extraction if the invoice visibly includes the product model/reference."
          when :missing_supporting
            "The invoice includes hydronic product evidence, but the processed supporting documents did not include usable product evidence. " \
              "The product-list requirement now requires the invoice product to be corroborated by a supporting product document such as a product specification sheet or manufacturer label/photo. " \
              "Admin should ask for supporting product evidence or rerun OCR/GenAI after the supporting document is added."
          when :source_unavailable
            "The invoice and supporting documents both include hydronic product evidence, but there are no current imported Better Homes BC qualifying-list rows available for code to search. " \
              "This is an information-on-record problem, not a product failure. " \
              "Admin should refresh the air-to-water product-list download and rerun GenAI/code checks."
          when :conflict
            "The invoice product evidence does not match the product evidence extracted from supporting documents. " \
              "Invoice evidence is #{field_bundle.fetch(:invoice_model_values).join(" / ")}; supporting-document evidence is #{field_bundle.fetch(:supporting_model_values).join(" / ")}. " \
              "Because the two sources resolve to different imported product-list rows, code cannot safely link the invoice to a single eligible hydronic product. " \
              "Admin should verify whether the wrong supporting document was uploaded, the invoice references a different system, or extraction needs correction."
          when :matched
            "The invoice and supporting document both identify the same hydronic heat-pump product, and that product was found in the current imported Better Homes BC Air-to-Water and Combination Heat Pump Qualifying Product List. " \
              "The stored invoice version now points to the exact imported product-list row used for this check. " \
              "This is a code-owned pass because the match was made against local information on record, not by model judgment. " \
              "Admins can inspect the matched row values in the AWHP product-list match section."
          else
            "The invoice and supporting document both include hydronic product evidence, but code could not confirm a shared matching row in the current imported Better Homes BC qualifying product list. " \
              "Admin should verify whether the product model/reference was read correctly, confirm the AWHP PDF import is current, and ask the contractor for corrected qualifying-product evidence if needed."
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

        def product_evidence(product)
          [
            product.brand,
            product.model_number,
            product.system_type,
            (
              if product.import_run&.awhp_source&.description.present?
                "source #{product.import_run&.awhp_source&.description}"
              end
            )
          ].compact_blank.join("; ")
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
