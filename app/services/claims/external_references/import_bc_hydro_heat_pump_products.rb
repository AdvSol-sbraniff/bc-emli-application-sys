# frozen_string_literal: true

require "digest"
require "bigdecimal"
require "json"
require "net/http"
require "tempfile"
require "zlib"

module Claims
  module ExternalReferences
    class ImportBcHydroHeatPumpProducts
      COLUMNS = {
        ahri_reference_number: 47.68,
        heat_pump_type: 108.4,
        make: 183.8,
        outdoor_model: 259.2,
        indoor_model_or_air_handler: 334.6,
        furnace_model: 407.0,
        rated_capacity_btu_at_minus_5c: 509.0,
        seer: 586.0,
        seer2: 661.0,
        hspf: 737.0,
        hspf2: 812.0,
        cop: 889.0,
        capacity_maintenance_percent: 964.0,
        eligibility_notes: 1013.2,
        cold_climate_rated: 1116.41
      }.freeze

      NUMERIC_COLUMNS = %i[
        rated_capacity_btu_at_minus_5c
        seer
        seer2
        hspf
        hspf2
        cop
        capacity_maintenance_percent
      ].freeze

      def self.call(
        ahri_source_id:,
        publishing_date: nil,
        publishing_notes: nil,
        pdf_path: nil
      )
        new(
          ahri_source_id: ahri_source_id,
          publishing_date: publishing_date,
          publishing_notes: publishing_notes,
          pdf_path: pdf_path
        ).call
      end

      def self.sources
        Claims::AhriSource
          .order(:description, :id)
          .map do |source|
            {
              id: source.id,
              description: source.description,
              source_url: source.source_url
            }
          end
      end

      def initialize(
        ahri_source_id:,
        publishing_date:,
        publishing_notes:,
        pdf_path:
      )
        @source = Claims::AhriSource.find(ahri_source_id)
        @ahri_source_id = @source.id
        @publishing_date = publishing_date.presence
        @publishing_notes = publishing_notes.to_s.strip.presence
        @pdf_path = pdf_path.present? ? Pathname(pdf_path) : nil
        @downloaded_pdf = nil
      end

      def call
        now = Time.current
        run =
          Claims::AhriImportRun.create!(
            ahri_source_id: @ahri_source_id,
            publishing_date: @publishing_date,
            publishing_notes: @publishing_notes,
            status: "running",
            started_at: now,
            created_at: now,
            updated_at: now,
            metadata_json: {
              parser: self.class.name,
              source_url: source_url,
              input_mode:
                @pdf_path.present? ? "explicit_pdf_path" : "remote_source_url",
              requested_pdf_path: @pdf_path&.to_s
            }
          )

        ensure_pdf_file!

        rows = parse_pdf_rows
        if rows.empty?
          raise "No heat pump product rows were parsed from #{@pdf_path}"
        end

        node_resp = node_upload_source_pdf!(import_run_id: run.id)
        storage_key = node_resp.fetch("storage_key").to_s.strip
        raise "Node upload returned no storage_key" if storage_key.blank?

        product_rows =
          rows.map do |row|
            build_product_row(row, import_run_id: run.id, now: now)
          end

        Claims::AhriProduct.transaction do
          Claims::AhriProduct.insert_all!(product_rows)
          run.update!(
            status: "succeeded",
            completed_at: Time.current,
            records_imported: product_rows.size,
            storage_provider: "azure_blob",
            storage_key: storage_key,
            content_type: "application/pdf",
            byte_size: node_resp["byte_size"] || File.size(@pdf_path),
            file_sha256: Digest::SHA256.file(@pdf_path).hexdigest,
            metadata_json:
              (run.metadata_json || {}).merge(
                resolved_pdf_path: @pdf_path.to_s
              ),
            updated_at: Time.current
          )
        end

        {
          ok: true,
          ahri_source_id: @ahri_source_id,
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
          ahri_source_id: @ahri_source_id,
          import_run_id: run&.id,
          error: e.message,
          error_class: e.class.name
        }
      ensure
        @downloaded_pdf&.close!
      end

      private

      def source_url
        @source.source_url
      end

      def ensure_pdf_file!
        if @pdf_path.present?
          return if @pdf_path.exist?

          raise "Explicit AHRI product-list PDF path does not exist: #{@pdf_path}"
        end

        @downloaded_pdf =
          Tempfile.new(["ahri-#{@ahri_source_id}-", ".pdf"], binmode: true)

        uri =
          begin
            URI.parse(source_url.to_s)
          rescue URI::InvalidURIError => e
            raise "BC Hydro product-list source URL is invalid for #{@source.description}: #{e.message}"
          end

        unless uri.host.present?
          raise "BC Hydro product-list source URL is missing or invalid for #{@source.description}"
        end

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.get(uri.request_uri) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "BC Hydro product-list download failed HTTP=#{res.code} body=#{body.first(500)}"
        end

        unless res["Content-Type"].to_s.downcase.include?("pdf") ||
                 body.start_with?("%PDF")
          raise "BC Hydro product-list download did not return a PDF for #{@source.description}"
        end

        @downloaded_pdf.binmode
        @downloaded_pdf.write(body)
        @downloaded_pdf.flush
        @pdf_path = Pathname(@downloaded_pdf.path)
      end

      def node_upload_source_pdf!(import_run_id:)
        base = ENV["INV_NODE_BASE_URL"].to_s.strip
        raise "Missing ENV INV_NODE_BASE_URL" if base.empty?

        base = base.sub(%r{/\z}, "")
        uri = URI("#{base}/inv/upload-pdf")

        req = Net::HTTP::Post.new(uri)
        io = File.open(@pdf_path, "rb")
        filename = File.basename(@pdf_path)

        form = [
          ["sessionId", "external-references/ahri/#{@ahri_source_id}"],
          ["invoiceVersionId", import_run_id.to_s],
          ["filename", filename],
          ["file", io, { filename: filename, content_type: "application/pdf" }]
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

      def parse_pdf_rows
        raise "PDF file not found: #{@pdf_path}" unless @pdf_path.exist?

        pdf_bytes = File.binread(@pdf_path)
        rows = []

        pdf_bytes.scan(/stream\r?\n(.*?)\r?\nendstream/m) do |match|
          stream = inflate_stream(match.first)
          next if stream.nil?

          rows.concat(parse_stream_rows(stream))
        end

        rows
      end

      def inflate_stream(raw_stream)
        Zlib::Inflate.inflate(raw_stream)
      rescue Zlib::Error
        nil
      end

      def parse_stream_rows(stream)
        items = extract_text_items(stream)
        anchors =
          items.select do |item|
            item[:column] == :ahri_reference_number &&
              item[:text].match?(/\A\d{8,10}\z/)
          end

        return [] if anchors.empty?

        anchors
          .sort_by { |anchor| -anchor[:y] }
          .each_with_index
          .filter_map do |anchor, index|
            next_anchor = anchors.sort_by { |a| -a[:y] }[index + 1]
            lower_y = next_anchor ? next_anchor[:y] + 1.5 : -Float::INFINITY
            upper_y = anchor[:y] + 1.5

            row_items =
              items.select { |item| item[:y] <= upper_y && item[:y] > lower_y }

            build_parsed_row(row_items)
          end
      end

      def extract_text_items(stream)
        stream
          .force_encoding(Encoding::BINARY)
          .scan(
            %r{1 0 0 1 ([0-9.]+) ([0-9.]+) Tm\s*(?:/F\d+ [0-9.]+ Tf\s*)?\((.*?)\)Tj}m
          )
          .filter_map do |x, y, raw_text|
            text = clean_pdf_text(raw_text)
            next if text.blank?

            column = nearest_column(x.to_f)
            next if column.nil?

            { x: x.to_f, y: y.to_f, text: text, column: column }
          end
      end

      def nearest_column(x)
        column, column_x =
          COLUMNS.min_by { |_key, candidate_x| (candidate_x - x).abs }

        return nil if (column_x - x).abs > 35

        column
      end

      def build_parsed_row(row_items)
        grouped =
          row_items
            .group_by { |item| item[:column] }
            .transform_values do |items|
              items
                .sort_by { |item| [-item[:y], item[:x]] }
                .map { |item| item[:text] }
                .join(" ")
                .squish
                .gsub(/-\s+/, "-")
            end

        ahri = grouped[:ahri_reference_number].to_s.strip
        return nil unless ahri.match?(/\A\d{8,10}\z/)

        grouped
      end

      def clean_pdf_text(raw_text)
        raw_text
          .force_encoding("ISO-8859-1")
          .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          .gsub(/\\([\\()])/, "\\1")
          .gsub(/\\n|\\r|\\t/, " ")
          .squish
      end

      def build_product_row(row, import_run_id:, now:)
        attrs = {
          import_run_id: import_run_id,
          ahri_reference_number: row[:ahri_reference_number],
          heat_pump_type: row[:heat_pump_type],
          make: row[:make],
          outdoor_model: row[:outdoor_model],
          indoor_model_or_air_handler: row[:indoor_model_or_air_handler],
          furnace_model: row[:furnace_model],
          rated_capacity_btu_at_minus_5c:
            coerce_number(row[:rated_capacity_btu_at_minus_5c]),
          seer: coerce_number(row[:seer]),
          seer2: coerce_number(row[:seer2]),
          hspf: coerce_number(row[:hspf]),
          hspf2: coerce_number(row[:hspf2]),
          cop: coerce_number(row[:cop]),
          capacity_maintenance_percent:
            coerce_number(row[:capacity_maintenance_percent]),
          cold_climate_rated: coerce_bool(row[:cold_climate_rated]),
          eligibility_notes: row[:eligibility_notes],
          raw_row_json: row,
          created_at: now,
          updated_at: now
        }

        attrs
      end

      def coerce_number(value)
        text = value.to_s.delete(",").delete("%").strip
        return nil if text.blank?

        BigDecimal(text)
      rescue ArgumentError
        nil
      end

      def coerce_bool(value)
        case value.to_s.strip.downcase
        when "yes", "y", "true"
          true
        when "no", "n", "false"
          false
        end
      end
    end
  end
end
