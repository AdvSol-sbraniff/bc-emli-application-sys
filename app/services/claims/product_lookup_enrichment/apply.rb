# frozen_string_literal: true

module Claims
  module ProductLookupEnrichment
    class Apply
      AHRI_UPGRADE_TYPE_KEYS = %w[
        air_source_heat_pump_electric
        air_source_heat_pump_wood
        air_source_heat_pump_gas_propane
        dual_fuel_ducted_heat_pump
      ].freeze

      OIL_UPGRADE_TYPE_KEY = "air_source_heat_pump_oil"
      HPWH_UPGRADE_TYPE_KEY = "heat_pump_water_heater"

      CLASSIFIER_AHRI_FIELD_KEY = "classifier.ahri_reference"
      CLASSIFIER_MODEL_NUMBER_FIELD_KEY = "classifier.product_model_number"
      CLASSIFIER_MANUFACTURER_FIELD_KEY = "classifier.product_manufacturer"
      HPWH_MANUFACTURER_FIELD_KEY = "hpwh_manufacturer"
      HPWH_MODEL_NUMBER_FIELD_KEY = "hpwh_model_number"
      HPWH_MODEL_COMPONENTS_FIELD_KEY = "hpwh_model_components"
      HPWH_MAKE_MODEL_FIELD_KEY = "hpwh_make_model"

      HYDRONIC_INVOICE_FIELD_KEYS = {
        "air_to_water_heat_pump" => %w[
          hp_make_model
          atw_product_list_reference
        ],
        "combined_space_water_heat_pump" => %w[
          hp_make_model
          cshp_product_list_reference
        ]
      }.freeze
      def self.call(invoice_version_id:, invoice_upgrade_types:)
        new(
          invoice_version_id: invoice_version_id,
          invoice_upgrade_types: invoice_upgrade_types
        ).call
      end

      def initialize(invoice_version_id:, invoice_upgrade_types:)
        @invoice_version_id = invoice_version_id
        @invoice_upgrade_types = Array(invoice_upgrade_types).compact
      end

      def call
        @invoice_version = ::Claims::InvoiceVersion.find(@invoice_version_id)
        results = {}
        updates = {}

        if ahri_upgrade_types.any?
          results[:ahri] = lookup_ahri_product(ahri_upgrade_types)
          updates[:ahri_product_id] = results[:ahri][:product_id]
        end

        if oil_upgrade_type
          results[:ohpa] = lookup_ohpa_product(oil_upgrade_type)
          updates[:ohpa_product_id] = results[:ohpa][:product_id]
        end

        if hpwh_upgrade_type
          results[:neea] = lookup_neea_product(hpwh_upgrade_type)
          updates[:neea_product_id] = results[:neea][:product_id]
        end

        hydronic_upgrade_types.each do |upgrade_type|
          results[:awhp] = lookup_awhp_product(upgrade_type)
          updates[:awhp_product_id] = results[:awhp][:product_id]
          break if results[:awhp][:product_id].present?
        end

        invoice_version.update!(updates) if updates.any?

        {
          ok: true,
          skipped: updates.empty?,
          updated_columns: updates.keys.map(&:to_s),
          lookups: results
        }
      rescue StandardError => e
        { ok: false, error: e.message, error_class: e.class.name }
      end

      private

      attr_reader :invoice_version, :invoice_upgrade_types

      def ahri_upgrade_types
        @ahri_upgrade_types ||=
          invoice_upgrade_types.select do |upgrade_type|
            AHRI_UPGRADE_TYPE_KEYS.include?(upgrade_type.upgrade_type_key)
          end
      end

      def oil_upgrade_type
        @oil_upgrade_type ||=
          invoice_upgrade_types.find do |upgrade_type|
            upgrade_type.upgrade_type_key == OIL_UPGRADE_TYPE_KEY
          end
      end

      def hpwh_upgrade_type
        @hpwh_upgrade_type ||=
          invoice_upgrade_types.find do |upgrade_type|
            upgrade_type.upgrade_type_key == HPWH_UPGRADE_TYPE_KEY
          end
      end

      def hydronic_upgrade_types
        @hydronic_upgrade_types ||=
          invoice_upgrade_types.select do |upgrade_type|
            HYDRONIC_INVOICE_FIELD_KEYS.key?(upgrade_type.upgrade_type_key)
          end
      end

      def lookup_ahri_product(upgrade_types)
        field =
          best_invoice_field(
            field_keys: [CLASSIFIER_AHRI_FIELD_KEY],
            upgrade_type_ids: upgrade_types.map(&:id),
            source_engines: ["classifier"]
          )
        ahri = normalized_ahri(field&.value_text)
        product =
          if ahri.present?
            ::Claims::CurrentAhriProduct
              .where(ahri_reference_number: ahri)
              .order(:source_description, :id)
              .first
          end

        lookup_result(
          product_family: "ahri",
          evidence_kind: "invoice_ahri",
          evidence_value: ahri.presence,
          field: field,
          product: product,
          product_rows_available: ::Claims::CurrentAhriProduct.exists?
        )
      end

      def lookup_ohpa_product(upgrade_type)
        field =
          best_invoice_field(
            field_keys: [CLASSIFIER_AHRI_FIELD_KEY],
            upgrade_type_ids: [upgrade_type.id],
            source_engines: ["classifier"]
          )
        ahri = normalized_ahri(field&.value_text)
        product =
          if ahri.present?
            ::Claims::CurrentOhpaProduct
              .where(ahri_reference_number: ahri)
              .order(:source_description, :id)
              .first
          end

        lookup_result(
          product_family: "ohpa",
          evidence_kind: "invoice_ahri",
          evidence_value: ahri.presence,
          field: field,
          product: product,
          product_rows_available: ::Claims::CurrentOhpaProduct.exists?
        )
      end

      def lookup_neea_product(upgrade_type)
        fields = {
          manufacturer:
            invoice_fields(
              field_keys: [
                CLASSIFIER_MANUFACTURER_FIELD_KEY,
                HPWH_MANUFACTURER_FIELD_KEY
              ],
              upgrade_type_ids: [upgrade_type.id]
            ),
          model_number:
            invoice_fields(
              field_keys: [
                CLASSIFIER_MODEL_NUMBER_FIELD_KEY,
                HPWH_MODEL_NUMBER_FIELD_KEY
              ],
              upgrade_type_ids: [upgrade_type.id]
            ),
          model_components:
            invoice_fields(
              field_keys: [HPWH_MODEL_COMPONENTS_FIELD_KEY],
              upgrade_type_ids: [upgrade_type.id]
            ),
          make_model:
            invoice_fields(
              field_keys: [HPWH_MAKE_MODEL_FIELD_KEY],
              upgrade_type_ids: [upgrade_type.id]
            )
        }
        manufacturer_values = values_for(fields.fetch(:manufacturer))
        model_values =
          values_for(fields.fetch(:model_number)) +
            values_for(fields.fetch(:model_components)) +
            values_for(fields.fetch(:make_model))
        product =
          neea_product_for(
            model_values: model_values,
            manufacturer_values: manufacturer_values
          )

        lookup_result(
          product_family: "neea",
          evidence_kind: "invoice_model",
          evidence_value: model_values.first,
          field:
            (
              fields.fetch(:model_number).first ||
                fields.fetch(:model_components).first ||
                fields.fetch(:make_model).first
            ),
          product: product,
          product_rows_available: ::Claims::CurrentNeeaProduct.exists?,
          extra: {
            manufacturer_values: manufacturer_values,
            model_values: model_values
          }
        )
      end

      def lookup_awhp_product(upgrade_type)
        field_keys =
          HYDRONIC_INVOICE_FIELD_KEYS.fetch(upgrade_type.upgrade_type_key)
        fields =
          invoice_fields(
            field_keys: [
              CLASSIFIER_MODEL_NUMBER_FIELD_KEY,
              CLASSIFIER_AHRI_FIELD_KEY,
              *field_keys
            ],
            upgrade_type_ids: [upgrade_type.id]
          )
        model_values = model_values_for(fields)
        manufacturer_values = manufacturer_values_for(fields)
        product =
          awhp_product_for(
            model_values: model_values,
            manufacturer_values: manufacturer_values
          )

        lookup_result(
          product_family: "awhp",
          evidence_kind: "invoice_model",
          evidence_value: model_values.first,
          field: fields.first,
          product: product,
          product_rows_available: ::Claims::CurrentAwhpProduct.exists?,
          extra: {
            upgrade_type_key: upgrade_type.upgrade_type_key,
            manufacturer_values: manufacturer_values,
            model_values: model_values
          }
        )
      end

      def best_invoice_field(
        field_keys:,
        upgrade_type_ids:,
        source_engines: %w[classifier genai]
      )
        invoice_fields(
          field_keys: field_keys,
          upgrade_type_ids: upgrade_type_ids,
          source_engines: source_engines
        ).first
      end

      def invoice_fields(
        field_keys:,
        upgrade_type_ids:,
        source_engines: %w[classifier genai]
      )
        ::Claims::InvoiceVersionLocatedField
          .where(
            invoice_version_id: invoice_version.id,
            invoice_upgrade_type_id: upgrade_type_ids,
            source_engine: source_engines,
            field_key: field_keys
          )
          .where.not(value_text: [nil, ""])
          .order(
            Arel.sql("CASE source_engine WHEN 'classifier' THEN 0 ELSE 1 END"),
            confidence: :desc,
            created_at: :desc
          )
          .to_a
      end

      def lookup_result(
        product_family:,
        evidence_kind:,
        evidence_value:,
        field:,
        product:,
        product_rows_available:,
        extra: {}
      )
        {
          product_family: product_family,
          evidence_kind: evidence_kind,
          evidence_value: evidence_value,
          evidence_field_id: field&.id,
          evidence_field_key: field&.field_key,
          evidence_text: field&.evidence_text,
          product_rows_available: product_rows_available,
          matched: product.present?,
          product_id: product&.id,
          product_reference: product_reference(product)
        }.merge(extra)
      end

      def product_reference(product)
        return nil unless product

        if product.respond_to?(:ahri_reference_number)
          product.ahri_reference_number
        elsif product.respond_to?(:model_number)
          product.model_number
        end
      end

      def normalized_ahri(raw_ahri)
        text = raw_ahri.to_s.strip
        return "" if text.blank?

        digits = text.gsub(/\D/, "")
        digits.presence || text
      end

      def neea_product_for(model_values:, manufacturer_values:)
        return nil if model_values.empty?

        manufacturers =
          manufacturer_values.map { |value| normalize_text(value) }.compact
        scope = ::Claims::CurrentNeeaProduct.all
        candidates =
          if manufacturers.empty?
            scope.to_a
          else
            scope.where(brand_normalized: manufacturers).to_a.presence ||
              scope.to_a
          end

        product =
          best_model_product(
            candidates: candidates,
            model_values: model_values,
            manufacturer_values: manufacturers
          )
        product && ::Claims::NeeaProduct.find_by(id: product.id)
      end

      def awhp_product_for(model_values:, manufacturer_values:)
        return nil if model_values.empty?

        manufacturers =
          manufacturer_values.map { |value| normalize_text(value) }.compact
        candidates = ::Claims::CurrentAwhpProduct.all.to_a
        product =
          best_model_product(
            candidates: candidates,
            model_values: model_values,
            manufacturer_values: manufacturers
          )
        product && ::Claims::AwhpProduct.find_by(id: product.id)
      end

      def best_model_product(candidates:, model_values:, manufacturer_values:)
        matches =
          candidates.filter_map do |product|
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
            [
              score,
              product.try(:brand).to_s,
              product.model_number.to_s,
              product.id
            ]
          end
        match&.last
      end

      def manufacturer_match_score(product:, manufacturers:)
        return 0 if manufacturers.empty?

        product_brand = normalize_text(product.try(:brand))
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
          Array(product.try(:model_components))
            .map { |component| loose_model_key(component) }
            .reject(&:blank?)

        model_values.each do |value|
          strict_value = strict_model_key(value)
          loose_value = loose_model_key(value)

          if strict_model_matches_regex?(
               product.try(:model_number_regex),
               strict_value
             )
            return 100
          end

          if product.try(:model_number_normalized).present? &&
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

        product_components.all? { |component| loose_value.include?(component) }
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
