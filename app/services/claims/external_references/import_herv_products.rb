# frozen_string_literal: true

require "csv"
require "bigdecimal"
require "digest"
require "json"
require "net/http"
require "tempfile"

module Claims
  module ExternalReferences
    class ImportHervProducts
      PRODUCT_QUERY_PARAM = "product"
      DEFAULT_PRODUCT_SEGMENT = "ES.Ventilators.HeatEnergyRecovery"
      DEFAULT_LANG = "en-US"
      DOWNLOAD_TAKE = 100_000

      def self.call(
        herv_source_id:,
        publishing_date: nil,
        publishing_notes: nil,
        csv_path: nil
      )
        new(
          herv_source_id: herv_source_id,
          publishing_date: publishing_date,
          publishing_notes: publishing_notes,
          csv_path: csv_path
        ).call
      end

      def initialize(
        herv_source_id:,
        publishing_date:,
        publishing_notes:,
        csv_path:
      )
        @source = Claims::HervSource.find(herv_source_id)
        @herv_source_id = @source.id
        @publishing_date = publishing_date.presence
        @publishing_notes = publishing_notes.to_s.strip.presence
        @csv_path = csv_path.present? ? Pathname(csv_path) : nil
        @downloaded_csv = nil
      end

      def call
        now = Time.current
        run =
          Claims::HervImportRun.create!(
            herv_source_id: @herv_source_id,
            publishing_date: @publishing_date,
            publishing_notes: @publishing_notes,
            status: "running",
            started_at: now,
            created_at: now,
            updated_at: now,
            metadata_json: {
              parser: self.class.name,
              source_url: source_url,
              product_segment: product_segment
            }
          )

        rows = load_rows
        if rows.empty?
          raise "No HERV product rows were parsed from #{source_label}"
        end

        write_csv_file!(rows) unless @csv_path&.exist?
        node_resp = node_upload_source_csv!(import_run_id: run.id)
        storage_key = node_resp.fetch("storage_key").to_s.strip
        raise "Node upload returned no storage_key" if storage_key.blank?

        product_rows =
          rows
            .filter_map do |row|
              build_product_row(row, import_run_id: run.id, now: now)
            end
            .uniq do |row|
              [
                row.fetch(:brand_normalized),
                row.fetch(:model_number_normalized),
                row[:model_type],
                row[:sensible_heat_recovery_efficiency_sre_at_0c]&.to_s,
                row[:associated_net_supply_airflow_at_0c_cfm]&.to_s,
                row[:power_consumption_at_0c_w]&.to_s
              ]
            end

        if product_rows.empty?
          raise "No matchable HERV product rows were parsed from #{source_label}"
        end

        Claims::HervProduct.transaction do
          Claims::HervProduct.insert_all!(product_rows)
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
          herv_source_id: @herv_source_id,
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
          herv_source_id: @herv_source_id,
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
        @csv_path&.to_s.presence || source_url
      end

      def product_segment
        uri = URI(source_url)
        query = URI.decode_www_form(uri.query.to_s).to_h
        query.fetch(PRODUCT_QUERY_PARAM, DEFAULT_PRODUCT_SEGMENT).presence ||
          DEFAULT_PRODUCT_SEGMENT
      rescue URI::InvalidURIError
        DEFAULT_PRODUCT_SEGMENT
      end

      def lang
        source_url.include?("/fr-") ? "fr-CA" : DEFAULT_LANG
      end

      def load_rows
        return parse_csv_rows if @csv_path&.exist?

        download_nrcan_rows
      end

      def parse_csv_rows
        CSV
          .read(@csv_path, headers: true, encoding: "bom|utf-8")
          .map { |row| row.to_h.compact }
      end

      def download_nrcan_rows
        api_url = resolve_csv_api_url
        skip = 0
        all_rows = []

        loop do
          body = {
            product: product_segment,
            lang: lang,
            skip: skip,
            take: DOWNLOAD_TAKE,
            filters: {
            }
          }

          response = http_post_json(URI(api_url), body)
          data = JSON.parse(response.body)
          rows = Array(data["data"])
          all_rows.concat(rows)

          break if rows.length < DOWNLOAD_TAKE

          skip += DOWNLOAD_TAKE
        end

        all_rows
      end

      def resolve_csv_api_url
        response = http_get(URI(source_url))
        html = response.body.to_s
        match =
          html.match(
            /const\s+defaultCSVAPI\s*=\s*isProdTest\s*\?\s*'[^']+'\s*:\s*isUAT\s*\?\s*'[^']+'\s*:\s*'([^']+)'/m
          )

        return match[1] if match

        urls =
          html.scan(
            %r{https://[^'"]+powerautomate/automations/direct/workflows/[^'"]+}
          )
        api_url =
          urls
            .reject { |url| url.include?("149afcaf") || url.include?("106fbd") }
            .last
        return api_url if api_url.present?

        raise "Could not locate NRCan CSV API endpoint on #{source_url}"
      end

      def http_get(uri)
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] = user_agent
        req["Accept"] = "text/html,application/xhtml+xml,application/json,*/*"

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        unless res.is_a?(Net::HTTPSuccess)
          raise "HERV page download failed HTTP=#{res.code} body=#{res.body.to_s.first(500)}"
        end

        res
      end

      def http_post_json(uri, body)
        req = Net::HTTP::Post.new(uri)
        req["User-Agent"] = user_agent
        req["Accept"] = "application/json,*/*"
        req["Content-Type"] = "application/json"
        req.body = JSON.generate(body)

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        unless res.is_a?(Net::HTTPSuccess)
          raise "HERV CSV API failed HTTP=#{res.code} body=#{res.body.to_s.first(500)}"
        end

        res
      end

      def user_agent
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
          "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
      end

      def write_csv_file!(rows)
        @downloaded_csv =
          Tempfile.new(["herv-#{@herv_source_id}-", ".csv"], binmode: true)

        headers = rows.flat_map(&:keys).uniq
        csv =
          CSV.generate(write_headers: true, headers: headers) do |out|
            rows.each { |row| out << headers.map { |header| row[header] } }
          end

        @downloaded_csv.write("\uFEFF#{csv}")
        @downloaded_csv.flush
        @csv_path = Pathname(@downloaded_csv.path)
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
          ["sessionId", "external-references/herv/#{@herv_source_id}"],
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
        brand = clean_text(row["BrandName"])
        model_number = clean_text(row["ModelNumber"])
        model_normalized = strict_model_key(model_number)
        return nil if model_normalized.blank?

        {
          import_run_id: import_run_id,
          brand: brand,
          brand_normalized: normalize_text(brand),
          model_number: model_number,
          model_number_normalized: model_normalized,
          model_number_regex: model_regex(model_number),
          model_type: clean_text(row["ModelType"]),
          sensible_heat_recovery_efficiency_sre_at_0c:
            decimal(row["SensibleHeatRecoveryEfficiencySREAt0C"]),
          sensible_heat_recovery_efficiency_sre_at_minus_25c:
            decimal(row["IfNotMarkedForOutdoorMinus25CREG"]),
          associated_net_supply_airflow_at_0c_cfm:
            decimal(row["AssociatedNetSupplyAirflowAt0CCFM"]),
          associated_net_supply_airflow_at_minus_25c_cfm:
            decimal(row["IfNotMarkedForOutdoorMinus25CFM"]),
          associated_power_consumption_at_0c_w:
            decimal(row["AssociatedPowerConsumptionAt0CW"]),
          associated_power_consumption_at_minus_25c_w:
            decimal(row["AssociatedPowerConsumptionAtMinus25CW"]),
          associated_net_supply_airflow_at_0c_ls:
            decimal(row["AssociatedNetSupplyAirflowAt0CLS"]),
          associated_net_supply_airflow_at_minus_25c_ls:
            decimal(row["IfNotMarkedForOutdoorMinus25CLS"]),
          marked_for_outdoor_use_at_minus_10c_or_higher:
            boolean(row["MarkedForOutdoorUseAtMinus10COrHigher"]),
          max_rated_airflow_at_0c_cfm: decimal(row["MaxRatedAirflowAt0CCFM"]),
          max_rated_airflow_at_0c_ls: decimal(row["MaxRatedAirflowAt0CLS"]),
          power_consumption_at_0c_w: decimal(row["PowerConsumptionAt0CW"]),
          eligibility_notes: nil,
          raw_row_json: row,
          created_at: now,
          updated_at: now
        }
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

      def boolean(value)
        text = value.to_s.strip.downcase
        return true if %w[1 true yes y].include?(text)
        return false if %w[0 false no n].include?(text)

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
