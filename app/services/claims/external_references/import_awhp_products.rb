# frozen_string_literal: true

require "digest"
require "json"
require "net/http"
require "tempfile"
require "zlib"

module Claims
  module ExternalReferences
    class ImportAwhpProducts
      COLUMNS = { brand: 52.9, model_number: 216.1 }.freeze

      ROW_Y_TOLERANCE = 1.2
      COLUMN_X_TOLERANCE = 20.0

      def self.call(
        awhp_source_id:,
        publishing_date: nil,
        publishing_notes: nil,
        pdf_path: nil
      )
        new(
          awhp_source_id: awhp_source_id,
          publishing_date: publishing_date,
          publishing_notes: publishing_notes,
          pdf_path: pdf_path
        ).call
      end

      def initialize(
        awhp_source_id:,
        publishing_date:,
        publishing_notes:,
        pdf_path:
      )
        @source = Claims::AwhpSource.find(awhp_source_id)
        @awhp_source_id = @source.id
        @publishing_date = publishing_date.presence
        @publishing_notes = publishing_notes.to_s.strip.presence
        @pdf_path = pdf_path.present? ? Pathname(pdf_path) : nil
        @downloaded_pdf = nil
      end

      def call
        now = Time.current
        ensure_pdf_file!
        run =
          Claims::AwhpImportRun.create!(
            awhp_source_id: @awhp_source_id,
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
        if rows.empty?
          raise "No AWHP product rows were parsed from #{@pdf_path}"
        end

        node_resp = node_upload_source_pdf!(import_run_id: run.id)
        storage_key = node_resp.fetch("storage_key").to_s.strip
        raise "Node upload returned no storage_key" if storage_key.blank?

        product_rows =
          rows.map do |row|
            build_product_row(row, import_run_id: run.id, now: now)
          end

        Claims::AwhpProduct.transaction do
          Claims::AwhpProduct.insert_all!(product_rows)
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
          awhp_source_id: @awhp_source_id,
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
          awhp_source_id: @awhp_source_id,
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
          Tempfile.new(["awhp-#{@awhp_source_id}-", ".pdf"], binmode: true)

        uri = URI(source_url)
        res = http_get_follow_redirects(uri)

        body = res.body.to_s
        unless res.is_a?(Net::HTTPSuccess)
          raise "AWHP product-list download failed HTTP=#{res.code} body=#{body.first(500)}"
        end

        unless res["Content-Type"].to_s.downcase.include?("pdf") ||
                 body.start_with?("%PDF")
          raise "AWHP product-list download did not return a PDF for #{@source.description}"
        end

        @downloaded_pdf.binmode
        @downloaded_pdf.write(body)
        @downloaded_pdf.flush
        @pdf_path = Pathname(@downloaded_pdf.path)
      end

      def http_get_follow_redirects(uri, limit: 5)
        if limit <= 0
          raise "Too many redirects while downloading AWHP product list"
        end

        req = Net::HTTP::Get.new(uri)
        req[
          "User-Agent"
        ] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " \
          "(KHTML, like Gecko) Chrome/125.0 Safari/537.36"
        req["Accept"] = "application/pdf,application/octet-stream,*/*"
        req["Referer"] = "https://www.betterhomesbc.ca/qualifyingairtowaterhp/"

        res =
          Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: (uri.scheme == "https"),
            read_timeout: 120
          ) { |http| http.request(req) }

        if res.is_a?(Net::HTTPRedirection)
          location = res["location"].to_s
          if location.blank?
            raise "AWHP product-list redirect had no Location header"
          end

          return(
            http_get_follow_redirects(URI.join(uri, location), limit: limit - 1)
          )
        end

        res
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
          ["sessionId", "external-references/awhp/#{@awhp_source_id}"],
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
        items = []

        pdf_bytes
          .scan(/stream\r?\n(.*?)\r?\nendstream/m)
          .each_with_index do |match, stream_index|
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
          .scan(/1 0 0 1 ([0-9.-]+) ([0-9.-]+) Tm(.*?)(?:ET|Q)/m)
          .filter_map do |x, y, raw_block|
            text = clean_text(extract_pdf_text(raw_block))
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
        extract_pdf_strings(raw_block).join
      end

      def extract_pdf_strings(raw_block)
        strings = []
        i = 0
        raw = raw_block.to_s

        while i < raw.length
          if raw.getbyte(i) == 40 # (
            text, i = read_pdf_string(raw, i + 1)
            strings << text
          else
            i += 1
          end
        end

        strings
      end

      def read_pdf_string(raw, index)
        output = +""
        depth = 1
        i = index

        while i < raw.length && depth.positive?
          byte = raw.getbyte(i)

          if byte == 92 # backslash
            escaped, i = read_pdf_escape(raw, i)
            output << escaped
          elsif byte == 40 # (
            depth += 1
            output << "("
            i += 1
          elsif byte == 41 # )
            depth -= 1
            output << ")" if depth.positive?
            i += 1
          else
            output << byte.chr(Encoding::BINARY)
            i += 1
          end
        end

        [output.force_encoding(Encoding::UTF_8).scrub, i]
      end

      def read_pdf_escape(raw, index)
        next_byte = raw.getbyte(index + 1)
        return "", index + 1 if next_byte.nil?

        next_char = next_byte.chr
        simple =
          {
            "n" => "\n",
            "r" => "\r",
            "t" => "\t",
            "b" => "\b",
            "f" => "\f",
            "(" => "(",
            ")" => ")",
            "\\" => "\\"
          }[
            next_char
          ]
        return simple, index + 2 if simple

        if next_char.match?(/[0-7]/)
          octal = raw.byteslice(index + 1, 3).to_s[/\A[0-7]{1,3}/]
          if octal.present?
            return octal.to_i(8).chr(Encoding::BINARY), index + 1 + octal.length
          end
        end

        [next_char, index + 2]
      end

      def clean_text(value)
        value.to_s.tr("\u00A0", " ").gsub(/[[:space:]]+/, " ").strip
      end

      def nearest_column(x)
        column, expected_x =
          COLUMNS.min_by { |_name, column_x| (x - column_x).abs }
        return nil if (x - expected_x).abs > COLUMN_X_TOLERANCE

        column
      end

      def build_rows_from_items(items)
        groups = []

        items
          .sort_by do |item|
            [item.fetch(:stream_index), -item.fetch(:y), item.fetch(:x)]
          end
          .each do |item|
            group =
              groups.find do |candidate|
                candidate.fetch(:stream_index) == item.fetch(:stream_index) &&
                  (candidate.fetch(:y) - item.fetch(:y)).abs <= ROW_Y_TOLERANCE
              end

            unless group
              group = {
                stream_index: item.fetch(:stream_index),
                y: item.fetch(:y),
                brand: nil,
                model_number: nil
              }
              groups << group
            end

            column = item.fetch(:column)
            group[column] = [group[column], item.fetch(:text)].compact_blank
              .join(" ")
              .squish
          end

        groups
          .filter_map do |group|
            brand = group.fetch(:brand).to_s.squish
            model_number = group.fetch(:model_number).to_s.squish
            next if brand.blank? || model_number.blank?
            if brand.casecmp("Brand").zero? &&
                 model_number.casecmp("Model").zero?
              next
            end
            next if brand.match?(/\ACleanBC Better Homes/i)
            next if brand.match?(/\AIf you are considering/i)

            {
              brand: brand,
              model_number: model_number,
              stream_index: group.fetch(:stream_index),
              y: group.fetch(:y)
            }
          end
          .uniq do |row|
            [
              normalize_text(row.fetch(:brand)),
              strict_model_key(row.fetch(:model_number))
            ]
          end
      end

      def build_product_row(row, import_run_id:, now:)
        brand = row.fetch(:brand)
        model_number = row.fetch(:model_number)
        model_normalized = strict_model_key(model_number)

        {
          import_run_id: import_run_id,
          brand: brand,
          brand_normalized: normalize_text(brand),
          model_number: model_number,
          model_number_normalized: model_normalized,
          model_number_regex: model_regex(model_number),
          model_components: model_components(model_number),
          system_type: "air_to_water_or_combined",
          eligibility_notes: nil,
          raw_row_json: row,
          created_at: now,
          updated_at: now
        }
      end

      def model_regex(value)
        strict = strict_model_key(value)
        return nil if strict.blank?

        regex = Regexp.escape(strict)
        source_text = value.to_s

        if source_text.match?(/000\s*=\s*all sizes/i)
          regex = regex.gsub("000", "[A-Z0-9]{3,}")
        end

        regex = regex.gsub("XX", "[A-Z0-9]{2,}") if strict.include?("XX")

        "\\A#{regex}\\z"
      end

      def model_components(value)
        text = model_match_text(value)
        components =
          text
            .split(%r{\s+(?:with|and)\s+|/|\+|,}i)
            .map { |part| loose_model_key(part) }
            .reject { |part| part.blank? || part.length < 3 }
            .uniq

        components.presence
      end

      def model_match_text(value)
        value.to_s.gsub(/\([^)]*=\s*all sizes[^)]*\)/i, "").squish
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
    end
  end
end
