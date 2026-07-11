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

        RULE = { key: "hp_ahri_product_validation" }.freeze
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

          evidence = ahri_evidence_bundle
          product = product_for(evidence.fetch(:invoice_ahri))
          invoice_version.update!(ahri_product_id: product&.id)

          row = product_validation_row(evidence: evidence, product: product)
          replace_rulechecks!([row])

          { ok: true, skipped: false, matched: product.present?, rulechecks: 1 }
        rescue StandardError => e
          { ok: false, error: e.message, error_class: e.class.name }
        end

        private

        attr_reader :invoice_version, :upgrade_type

        def enabled_for_upgrade_type?
          unless AHRI_RELEVANT_UPGRADE_TYPES.include?(
                   upgrade_type.upgrade_type_key
                 )
            return false
          end

          ::Claims::CodeRules::Registry.enabled_for?(
            code_rule_key: RULE.fetch(:key),
            invoice_upgrade_type_id: upgrade_type.id,
            fallback: false
          )
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
                invoice_version_id: invoice_version.id
              }
            )
            .where(field_key: SUPPORTING_AHRI_FIELD_KEY)
            .where.not(value_text: [nil, ""])
            .order(confidence: :desc, created_at: :desc)
            .to_a
        end

        def product_for(raw_ahri)
          ahri = normalized_ahri(raw_ahri)
          return nil if ahri.blank?

          current_match =
            ::Claims::CurrentAhriProduct
              .where(ahri_reference_number: ahri)
              .order(:source_description, :id)
              .first
          return nil unless current_match

          ::Claims::AhriProduct.find_by(id: current_match.id)
        end

        def product_validation_row(evidence:, product:)
          subchecks =
            product_validation_subchecks(evidence: evidence, product: product)
          result = aggregate_subcheck_result(subchecks)

          base_rulecheck_row(
            rule_result: result,
            confidence: %w[pass fail].include?(result) ? 100 : 0,
            expected_text:
              "The invoice should show an AHRI reference, supporting product evidence should corroborate that same AHRI reference, and the AHRI reference should exist in the current imported BC Hydro heat-pump product list.",
            calculation:
              product_validation_calculation_text(
                evidence: evidence,
                product: product,
                subchecks: subchecks
              ),
            evidence_text: ahri_evidence_text(evidence),
            reason_and_likely_causes:
              product_validation_reason_text(
                product: product,
                subchecks: subchecks
              )
          )
        end

        def product_validation_subchecks(evidence:, product:)
          invoice_ahri = evidence.fetch(:invoice_ahri)
          supporting_ahris = evidence.fetch(:supporting_ahris)

          {
            invoice_ahri_reference_present:
              if invoice_ahri.present?
                subcheck(
                  "pass",
                  "Invoice GenAI field hp_ahri_reference=#{invoice_ahri}."
                )
              else
                subcheck(
                  "warn",
                  "No invoice GenAI field hp_ahri_reference was found."
                )
              end,
            supporting_document_ahri_matches_invoice:
              supporting_ahri_subcheck(
                invoice_ahri: invoice_ahri,
                supporting_ahris: supporting_ahris
              ),
            ahri_product_found_in_download:
              product_download_subcheck(
                invoice_ahri: invoice_ahri,
                product: product
              )
          }
        end

        def supporting_ahri_subcheck(invoice_ahri:, supporting_ahris:)
          if invoice_ahri.blank?
            return(
              subcheck(
                "warn",
                "Cannot compare supporting documents because invoice AHRI is missing."
              )
            )
          end
          if supporting_ahris.empty?
            return(
              subcheck(
                "warn",
                "No supporting-document AHRI reference was extracted."
              )
            )
          end
          if supporting_ahris.include?(invoice_ahri)
            return(
              subcheck(
                "pass",
                "Supporting-document AHRI values include #{invoice_ahri}."
              )
            )
          end

          subcheck(
            "fail",
            "Invoice AHRI #{invoice_ahri} does not match supporting-document AHRI values #{supporting_ahris.join(" / ")}."
          )
        end

        def product_download_subcheck(invoice_ahri:, product:)
          if invoice_ahri.blank?
            return(
              subcheck(
                "warn",
                "Download lookup could not run because invoice AHRI is missing."
              )
            )
          end
          unless current_heat_pump_products_available?
            return(
              subcheck(
                "warn",
                "No current imported BC Hydro heat-pump product-list rows were available."
              )
            )
          end
          if product
            return(
              subcheck(
                "pass",
                "AHRI #{invoice_ahri} matched ahri_products.id=#{product.id}."
              )
            )
          end

          subcheck(
            "fail",
            "AHRI #{invoice_ahri} was not found in the current imported BC Hydro heat-pump product list."
          )
        end

        def current_heat_pump_products_available?
          ::Claims::CurrentAhriProduct.exists?
        end

        def subcheck(status, reason)
          { status: status, reason: reason }
        end

        def aggregate_subcheck_result(subchecks)
          statuses = subchecks.values.map { |row| row.fetch(:status) }
          return "fail" if statuses.include?("fail")
          return "warn" if statuses.include?("warn")

          "pass"
        end

        def product_validation_calculation_text(evidence:, product:, subchecks:)
          [
            "invoice_product_identity: hp_ahri_reference=#{evidence.fetch(:invoice_ahri).presence || "(missing)"}",
            "supporting_document_product_identity: ahri_reference=#{evidence.fetch(:supporting_ahris).presence&.join(" / ") || "(none)"}",
            "download_lookup: table=claims.v_current_ahri_products; matched_product_id=#{product&.id || "(none)"}",
            subcheck_lines("subchecks", subchecks),
            subcheck_lines("failed_subchecks", subchecks, status: "fail"),
            subcheck_lines("warn_subchecks", subchecks, status: "warn")
          ].compact.join("\n")
        end

        def subcheck_lines(label, subchecks, status: nil)
          selected =
            subchecks.select do |_key, row|
              status.nil? || row.fetch(:status) == status
            end
          return nil if selected.empty? && status.present?

          lines =
            selected.map do |key, row|
              "- #{key}: #{row.fetch(:status)} - #{row.fetch(:reason)}"
            end
          "#{label}:\n#{lines.join("\n")}"
        end

        def product_validation_reason_text(product:, subchecks:)
          result = aggregate_subcheck_result(subchecks)
          if result == "pass"
            return(
              "The invoice AHRI reference, supporting-document AHRI evidence, and imported BC Hydro heat-pump product list all agree. " \
                "The stored invoice version points to ahri_products.id=#{product.id}."
            )
          end

          failed =
            subchecks
              .select { |_key, row| row.fetch(:status) == "fail" }
              .map { |key, row| "#{key}: #{row.fetch(:reason)}" }
          warned =
            subchecks
              .select { |_key, row| row.fetch(:status) == "warn" }
              .map { |key, row| "#{key}: #{row.fetch(:reason)}" }

          [
            "AHRI product validation did not fully pass.",
            ("Failed subchecks: #{failed.join(" | ")}" if failed.any?),
            ("Warning subchecks: #{warned.join(" | ")}" if warned.any?),
            "Admin should verify the invoice AHRI, supporting product evidence, and current AHRI product-list import."
          ].compact.join(" ")
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

        def replace_rulechecks!(rows)
          ::Claims::InvoiceVersionRulecheck.where(
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type.id,
            source_engine: "code",
            rule_key: RULE.fetch(:key)
          ).delete_all

          ::Claims::InvoiceVersionRulecheck.insert_all!(rows) if rows.any?
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

        def ahri_evidence_text(evidence)
          invoice_field = evidence.fetch(:invoice_field)
          supporting_fields = evidence.fetch(:supporting_fields)
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
