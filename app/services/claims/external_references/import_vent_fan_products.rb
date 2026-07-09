# frozen_string_literal: true

require "bigdecimal"
require "csv"
require "digest"
require "json"
require "net/http"
require "tempfile"

module Claims
  module ExternalReferences
    class ImportVentFanProducts
      DOWNLOAD_URL =
        "https://www.energystar.gov/productfinder/download/certified-ventilating-fans/"

      def self.call(
        vent_fan_source_id:,
        publishing_date: nil,
        publishing_notes: nil,
        csv_path: nil
      )
        new(
          vent_fan_source_id: vent_fan_source_id,
          publishing_date: publishing_date,
          publishing_notes: publishing_notes,
          csv_path: csv_path
        ).call
      end

      def initialize(
        vent_fan_source_id:,
        publishing_date:,
        publishing_notes:,
        csv_path:
      )
        @source = Claims::VentFanSource.find(vent_fan_source_id)
        @vent_fan_source_id = @source.id
        @publishing_date = publishing_date.presence
        @publishing_notes = publishing_notes.to_s.strip.presence
        @csv_path = csv_path.present? ? Pathname(csv_path) : nil
        @downloaded_csv = nil
      end

      def call
        now = Time.current
        run =
          Claims::VentFanImportRun.create!(
            vent_fan_source_id: @vent_fan_source_id,
            publishing_date: @publishing_date,
            publishing_notes: @publishing_notes,
            status: "running",
            started_at: now,
            created_at: now,
            updated_at: now,
            metadata_json: {
              parser: self.class.name,
              source_url: source_url,
              download_url: DOWNLOAD_URL
            }
          )

        download_csv_file! unless @csv_path&.exist?
        rows = parse_csv_rows
        if rows.empty?
          raise "No ENERGY STAR ventilating fan product rows were parsed from #{source_label}"
        end

        node_resp = node_upload_source_csv!(import_run_id: run.id)
        storage_key = node_resp.fetch("storage_key").to_s.strip
        raise "Node upload returned no storage_key" if storage_key.blank?

        product_rows =
          rows
            .filter_map do |row|
              build_product_row(row, import_run_id: run.id, now: now)
            end
            .uniq { |row| dedupe_key(row) }

        if product_rows.empty?
          raise "No matchable ENERGY STAR ventilating fan rows were parsed from #{source_label}"
        end

        Claims::VentFanProduct.transaction do
          Claims::VentFanProduct.insert_all!(product_rows)
          run.update!(
            status: "succeeded",
            completed_at: Time.current,
            records_imported: product_rows.size,
            storage_provider: "azure_blob",
            storage_key: storage_key,
            content_type: "text/csv",
            byte_size: node_resp["byte_size"] || File.size(@csv_path),
            file_sha256: Digest::SHA256.file(@csv_path).hexdigest,
            metadata_json:
              (run.metadata_json || {}).merge(
                csv_path: @csv_path.to_s,
                raw_rows_downloaded: rows.size
              ),
            updated_at: Time.current
          )
        end

        {
          ok: true,
          vent_fan_source_id: @vent_fan_source_id,
          import_run_id: run.id,
          records_imported: product_rows.size
        }
      rescue => e
        run&.update!(
          status: "failed",
          completed_at: Time.current,
          error_text: "#{e.class}: #{e.message}",
          updated_at: Time.current
        )

        {
          ok: false,
          vent_fan_source_id: @vent_fan_source_id,
          import_run_id: run&.id,
          error: e.message,
          error_class: e.class.name
        }
      ensure
        @downloaded_csv&.close!
      end

      private

      def source_url
        @source.source_url
      end

      def source_label
        @csv_path&.to_s.presence || DOWNLOAD_URL
      end

      def download_csv_file!
        response = http_get(URI(DOWNLOAD_URL))
        @downloaded_csv =
          Tempfile.new(
            ["vent-fan-#{@vent_fan_source_id}-", ".csv"],
            binmode: true
          )
        @downloaded_csv.write(response.body)
        @downloaded_csv.flush
        @csv_path = Pathname(@downloaded_csv.path)
      end

      def parse_csv_rows
        csv_text = utf8_file_text(@csv_path)
        CSV.parse(csv_text, headers: true).map { |row| row.to_h.compact }
      end

      def utf8_file_text(path)
        bytes = File.binread(path)
        text = bytes.dup.force_encoding("UTF-8")
        unless text.valid_encoding?
          text = bytes.force_encoding("ISO-8859-1").encode("UTF-8")
        end
        text.sub(/\A\uFEFF/, "")
      end

      def http_get(uri)
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = user_agent
        req["Accept"] = "text/csv,application/vnd.ms-excel,*/*"

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        unless res.is_a?(Net::HTTPSuccess)
          raise "ENERGY STAR fan CSV download failed HTTP=#{res.code} body=#{res.body.to_s.first(500)}"
        end

        res
      end

      def user_agent
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
          "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
      end

      def node_upload_source_csv!(import_run_id:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        base = base.sub(%r{/\z}, "")
        uri = URI("#{base}/inv/upload-pdf")

        req = Net::HTTP::Post.new(uri)
        io = File.open(@csv_path, "rb")
        filename = File.basename(@csv_path)

        form = [
          ["sessionId", "external-references/vent_fan/#{@vent_fan_source_id}"],
          ["invoiceVersionId", import_run_id.to_s],
          ["filename", filename],
          ["file", io, { filename: filename, content_type: "text/csv" }]
        ]

        req.set_form(form, "multipart/form-data")

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "Node reference upload failed HTTP=#{res.code} body=#{body}"
        end

        JSON.parse(body)
      ensure
        io&.close
      end

      def build_product_row(row, import_run_id:, now:)
        brand = clean_text(value(row, "Brand Name", "brand_name"))
        model_number = clean_text(value(row, "Model Number", "model_number"))
        brand_normalized = normalize_text(brand)
        model_normalized = strict_model_key(model_number)
        return nil if brand_normalized.blank? || model_normalized.blank?

        {
          import_run_id: import_run_id,
          energy_star_unique_id:
            clean_text(value(row, "ENERGY STAR Unique ID", "pd_id")),
          energy_star_partner:
            clean_text(
              value(row, "ENERGY STAR Partner", "energy_star_partner")
            ),
          brand: brand,
          brand_normalized: brand_normalized,
          product_model_name:
            clean_text(value(row, "Model Name", "model_name")),
          model_number: model_number,
          model_number_normalized: model_normalized,
          model_number_regex: model_regex(model_number),
          additional_model_information:
            clean_text(
              value(
                row,
                "Additional Model Information",
                "additional_model_information"
              )
            ),
          upc: clean_text(value(row, "UPC", "upc")),
          fan_type: clean_text(value(row, "Type", "unit_type")),
          merv_of_in_line_fan_filter:
            clean_text(
              value(
                row,
                "MERV of In-line Fan Filter",
                "merv_of_in_line_fan_filter"
              )
            ),
          number_of_speeds:
            clean_text(value(row, "Number of Speeds", "number_of_speeds")),
          duct_size: clean_text(value(row, "Duct Size", "duct_size")),
          sound_level_sones:
            decimal(value(row, "Sound Level (sones)", "sound_level_sones")),
          bathroom_utility_sound_level_sones_at_0_25_in_wg:
            decimal(
              value(
                row,
                "Bathroom and Utility Room Sound Level (sones) at 0.25 in. w.g.",
                "bathroom_and_utility_room_sound_level_sones_at_0_25_in_w_g"
              )
            ),
          bathroom_utility_airflow_at_0_25_in_wg:
            decimal(
              value(
                row,
                "Bathroom and Utility Room Airflow at 0.25 in. w.g.",
                "bathroom_and_utility_room_airflow_at_0_25_in_w_g"
              )
            ),
          lighting: clean_text(value(row, "Lighting", "lighting")),
          shipped_with_energy_star_lamps:
            clean_text(
              value(
                row,
                "Shipped with ENERGY STAR Lamp(s)",
                "shipped_with_energy_star_lamp_s"
              )
            ),
          energy_star_lamp_esuid:
            clean_text(
              value(row, "ENERGY STAR Lamp ESUID", "energy_star_lamp_esuid")
            ),
          alternate_energy_star_lamps_esuids:
            clean_text(
              value(
                row,
                "Alternate ENERGY STAR Lamps ESUIDs",
                "alternate_energy_star_lamps_esuids"
              )
            ),
          energy_star_lamp_partner:
            clean_text(
              value(row, "ENERGY STAR Lamp Partner", "energy_star_lamp_partner")
            ),
          lamp_model_number:
            clean_text(value(row, "Lamp Model Number", "lamp_model_number")),
          lighting_technology:
            clean_text(
              value(row, "Lighting Technology", "lighting_technology_used")
            ),
          total_light_output_lumens:
            decimal(
              value(row, "Total Light Output (lumens)", "light_output_lumens")
            ),
          total_input_power_watts:
            decimal(
              value(row, "Total Input Power (Watts)", "total_input_power_watts")
            ),
          luminaire_efficacy:
            decimal(
              value(
                row,
                "Energy Efficiency - Measured Outside the Fixture (lm/W)",
                "luminaire_efficacy"
              )
            ),
          power_factor: decimal(value(row, "Power Factor", "power_factor")),
          cct_kelvin:
            integer(
              value(
                row,
                "Light Color Appearance (CCT)",
                "correlated_color_temperature_kelvin"
              )
            ),
          cri:
            integer(
              value(
                row,
                "Light Color Quality (CRI)",
                "color_rendering_index_cri"
              )
            ),
          light_source_life_hours:
            integer(
              value(row, "Light Source Life (Hours)", "life_source_life_hours")
            ),
          special_features:
            clean_text(
              value(
                row,
                "Special Features (Dimming, Motion Sensing, etc.)",
                "special_features_dimming_motion_sensing_etc"
              )
            ),
          airflow_1_cfm:
            decimal(value(row, "Airflow 1 (cfm)", "airflow_1_cfm")),
          airflow_2_cfm:
            decimal(value(row, "Airflow 2 (cfm)", "airflow_2_cfm")),
          airflow_3_cfm:
            decimal(value(row, "Airflow 3 (cfm)", "airflow_3_cfm")),
          efficacy_1_cfm_watt:
            decimal(value(row, "Efficacy 1 (cfm/Watt)", "efficacy_1_cfm_w")),
          efficacy_2_cfm_watt:
            decimal(value(row, "Efficacy 2 (cfm/Watt)", "efficacy_2_cfm_w")),
          efficacy_3_cfm_watt:
            decimal(value(row, "Efficacy 3 (cfm/Watt)", "efficacy_3_cfm_w")),
          ventilating_fan_features:
            clean_text(
              value(row, "Ventilating Fan Features", "ventilating_fan_features")
            ),
          date_available_on_market:
            date(
              value(row, "Date Available On Market", "date_available_on_market")
            ),
          date_qualified: date(value(row, "Date Qualified", "date_qualified")),
          markets: clean_text(value(row, "Markets", "markets")),
          cb_model_identifier:
            clean_text(
              value(row, "CB Model Identifier", "energy_star_model_identifier")
            ),
          meets_most_efficient_criteria:
            clean_text(
              value(
                row,
                "Meets ENERGY STAR Most Efficient 2025 Criteria",
                "meets_most_efficient_criteria"
              )
            ),
          notes: clean_text(value(row, "Notes", "notes")),
          raw_row_json: row,
          created_at: now,
          updated_at: now
        }
      end

      def value(row, *keys)
        keys.each { |key| return row[key] if row.key?(key) }
        nil
      end

      def dedupe_key(row)
        if row[:energy_star_unique_id].present?
          ["energy_star_unique_id", row[:energy_star_unique_id]]
        else
          [
            "brand_model",
            row.fetch(:brand_normalized),
            row.fetch(:model_number_normalized),
            row[:cb_model_identifier].to_s
          ]
        end
      end

      def clean_text(value)
        text = value.to_s.tr("\u00A0", " ").gsub(/[[:space:]]+/, " ").strip
        return nil if text.blank? || text == "-"

        text
      end

      def decimal(value)
        text = value.to_s.gsub(/[,%]/, "").strip
        return nil if text.blank? || text == "-"

        BigDecimal(text)
      rescue ArgumentError
        nil
      end

      def integer(value)
        text = value.to_s.gsub(/[,%]/, "").strip
        return nil if text.blank? || text == "-"

        Integer(text)
      rescue ArgumentError
        nil
      end

      def date(value)
        text = value.to_s.strip
        return nil if text.blank? || text == "-"

        Date.parse(text)
      rescue ArgumentError
        nil
      end

      def model_regex(value)
        strict = strict_model_key(value)
        return nil if strict.blank?

        "\\A#{Regexp.escape(strict)}\\z"
      end

      def model_match_text(value)
        value.to_s.squish
      end

      def normalize_text(value)
        value.to_s.upcase.gsub(/[^A-Z0-9]+/, " ").squish.presence
      end

      def strict_model_key(value)
        model_match_text(value).upcase.gsub(/\s+/, "").presence
      end
    end
  end
end
