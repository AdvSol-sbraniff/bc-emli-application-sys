# frozen_string_literal: true

require "bigdecimal"
require "date"
require "digest"
require "json"
require "net/http"
require "tempfile"
require "zlib"

module Claims
  module ExternalReferences
    class ImportNeeaHpwhProducts
      COLUMNS = {
        brand: 28.2,
        model_number: 148.7,
        storage_volume_gallons: 364.5,
        indoor_tier: 403.1,
        indoor_cce: 430.1,
        outdoor_tier: 459.3,
        outdoor_scop: 486.2,
        configuration: 544.6,
        flex_load_connectivity: 612.1,
        plug_in_endorsement: 624.3,
        qualified_date: 705.6,
        specification_version: 750.4
      }.freeze

      MODEL_COLUMN = :model_number
      ROW_Y_TOLERANCE = 1.1

      def self.call(neea_source_id:, publishing_date: nil, publishing_notes: nil, pdf_path: nil)
        new(
          neea_source_id: neea_source_id,
          publishing_date: publishing_date,
          publishing_notes: publishing_notes,
          pdf_path: pdf_path
        ).call
      end

      def initialize(neea_source_id:, publishing_date:, publishing_notes:, pdf_path:)
        @source = Claims::NeeaSource.find(neea_source_id)
        @neea_source_id = @source.id
        @publishing_date = publishing_date.presence
        @publishing_notes = publishing_notes.to_s.strip.presence
        @pdf_path = pdf_path.present? ? Pathname(pdf_path) : nil
        @downloaded_pdf = nil
      end

      def call
        now = Time.current
        ensure_pdf_file!
        run =
          Claims::NeeaImportRun.create!(
            neea_source_id: @neea_source_id,
            publishing_date: @publishing_date,
            publishing_notes: @publishing_notes,
            status: "running",
            started_at: now,
            created_at: now,
            updated_at: now,
            metadata_json: {
              parser: self.class.name,
              pdf_path: @pdf_path.to_s
            }
          )

        rows = parse_pdf_rows
        raise "No NEEA HPWH product rows were parsed from #{@pdf_path}" if rows.empty?

        node_resp = node_upload_source_pdf!(import_run_id: run.id)
        storage_key = node_resp.fetch("storage_key").to_s.strip
        raise "Node upload returned no storage_key" if storage_key.blank?

        product_rows =
          rows.map do |row|
            build_product_row(row, import_run_id: run.id, now: now)
          end

        Claims::NeeaProduct.transaction do
          Claims::NeeaProduct.insert_all!(product_rows)
          run.update!(
            status: "succeeded",
            completed_at: Time.current,
            records_imported: product_rows.size,
            storage_provider: "azure_blob",
            storage_key: storage_key,
            content_type: "application/pdf",
            byte_size: node_resp["byte_size"] || File.size(@pdf_path),
            file_sha256: Digest::SHA256.file(@pdf_path).hexdigest,
            updated_at: Time.current
          )
        end

        {
          ok: true,
          neea_source_id: @neea_source_id,
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
          neea_source_id: @neea_source_id,
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
        return if @pdf_path&.exist?

        @downloaded_pdf =
          Tempfile.new(["neea-#{@neea_source_id}-", ".pdf"], binmode: true)

        uri = URI(source_url)
        req = Net::HTTP::Get.new(uri)
        req["User-Agent"] =
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
          "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
        req["Accept"] = "application/pdf,application/octet-stream,*/*"
        req["Referer"] =
          "https://neea.org/resource/residential-hpwh-qualified-products-list/"

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "NEEA product-list download failed HTTP=#{res.code} body=#{body.first(500)}"
        end

        unless res["Content-Type"].to_s.downcase.include?("pdf") ||
                 body.start_with?("%PDF")
          raise "NEEA product-list download did not return a PDF for #{@source.description}"
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
          ["sessionId", "external-references/neea/#{@neea_source_id}"],
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
        raise "Node reference upload failed HTTP=#{res.code} body=#{body}" unless res.is_a?(Net::HTTPSuccess)

        JSON.parse(body)
      ensure
        io&.close
      end

      def parse_pdf_rows
        raise "PDF file not found: #{@pdf_path}" unless @pdf_path.exist?

        pdf_bytes = File.binread(@pdf_path)
        items = []

        pdf_bytes.scan(/stream\r?\n(.*?)\r?\nendstream/m).each_with_index do |match, stream_index|
          stream = inflate_stream(match.first)
          next if stream.nil?

          items.concat(extract_text_items(stream, stream_index: stream_index))
        end

        build_rows_from_items(items)
      end

      def inflate_stream(raw_stream)
        Zlib::Inflate.inflate(raw_stream)
      rescue Zlib::Error
        nil
      end

      def extract_text_items(stream, stream_index:)
        stream_text = stream.force_encoding(Encoding::BINARY)

        stream_text
          .scan(/1 0 0 1 ([0-9.]+) ([0-9.]+) Tm(.*?)(?:ET|Q)/m)
          .filter_map do |x, y, raw_block|
            text = extract_pdf_text(raw_block)
            next if text.blank?

            column = nearest_column(x.to_f)
            next if column.nil?

            {
              stream_index: stream_index,
              x: x.to_f,
              y: y.to_f,
              text: text,
              column: column
            }
          end
      end

      def extract_pdf_text(raw_block)
        parts = []

        raw_block.scan(/\[(.*?)\]\s*TJ/m) do |match|
          parts.concat(match.first.scan(/\((.*?)\)/m).map { |raw| clean_pdf_text(raw.first) })
        end

        raw_block.scan(/\((.*?)\)\s*Tj/m) do |match|
          parts << clean_pdf_text(match.first)
        end

        parts.join.squish
      end

      def clean_pdf_text(raw_text)
        raw_text
          .force_encoding("ISO-8859-1")
          .encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
          .gsub(/\\([\\()])/, "\\1")
          .gsub(/\\n|\\r|\\t/, " ")
          .squish
      end

      def nearest_column(x)
        column, column_x =
          COLUMNS.min_by { |_key, candidate_x| (candidate_x - x).abs }

        return nil if (column_x - x).abs > 24

        column
      end

      def build_rows_from_items(items)
        anchors =
          items.select do |item|
            item[:column] == MODEL_COLUMN &&
              item[:text].match?(/[A-Za-z0-9]/) &&
              item[:text].match?(/\d/) &&
              normalize_model(item[:text]) != "MODELNUMBER" &&
              !item[:text].match?(/\A(Asterisks|Entries)\b/i)
          end

        last_brand = nil

        anchors
          .sort_by { |anchor| [anchor[:y] * -1, anchor[:x]] }
          .filter_map do |anchor|
            row_items =
              items.select do |item|
                item[:stream_index] == anchor[:stream_index] &&
                  (item[:y] - anchor[:y]).abs <= ROW_Y_TOLERANCE
              end

            grouped = build_grouped_row(row_items)
            next if grouped[:model_number].blank?

            grouped[:brand] = grouped[:brand].presence || last_brand
            last_brand = grouped[:brand].presence || last_brand
            next if grouped[:brand].blank?

            grouped
          end
      end

      def build_grouped_row(row_items)
        row_items.group_by { |item| item[:column] }.transform_values do |items|
          items
            .sort_by { |item| [item[:x], -item[:y]] }
            .map { |item| item[:text] }
            .join(" ")
            .squish
            .gsub(/\s+\*\*\*/, "***")
        end
      end

      def build_product_row(row, import_run_id:, now:)
        model_number = row[:model_number].to_s.squish

        {
          import_run_id: import_run_id,
          brand: row[:brand],
          brand_normalized: normalize_text(row[:brand]),
          model_number: model_number,
          model_number_normalized: normalize_model(model_number),
          model_number_regex: model_regex(model_number),
          model_components: model_components(model_number),
          storage_volume_gallons: coerce_number(row[:storage_volume_gallons]),
          indoor_tier: coerce_integer(row[:indoor_tier]),
          indoor_cce: coerce_number(row[:indoor_cce]),
          outdoor_tier: coerce_integer(row[:outdoor_tier]),
          outdoor_scop: coerce_number(row[:outdoor_scop]),
          configuration: row[:configuration],
          flex_load_connectivity: row[:flex_load_connectivity],
          plug_in_endorsement: row[:plug_in_endorsement].present?,
          qualified_date: coerce_date(row[:qualified_date]),
          specification_version: row[:specification_version],
          eligibility_notes: nil,
          raw_row_json: row,
          created_at: now,
          updated_at: now
        }
      end

      def normalize_text(value)
        value.to_s.upcase.gsub(/[^A-Z0-9]+/, " ").squish.presence
      end

      def normalize_model(value)
        value.to_s.upcase.gsub(/\s+/, "").presence
      end

      def model_regex(value)
        normalized = normalize_model(value)
        return nil if normalized.blank?

        escaped = Regexp.escape(normalized).gsub("\\*", "[A-Z0-9]")
        "\\A#{escaped}\\z"
      end

      def model_components(value)
        components =
          value
            .to_s
            .split(/\s*&\s*/)
            .map(&:squish)
            .reject(&:blank?)

        components.size > 1 ? components : nil
      end

      def coerce_number(value)
        text = value.to_s.delete(",").strip
        return nil if text.blank?

        BigDecimal(text)
      rescue ArgumentError
        nil
      end

      def coerce_integer(value)
        text = value.to_s.strip
        return nil if text.blank?

        Integer(text)
      rescue ArgumentError
        nil
      end

      def coerce_date(value)
        text = value.to_s.strip
        return nil if text.blank?

        Date.strptime(text, "%m/%d/%y")
      rescue ArgumentError
        nil
      end
    end
  end
end
