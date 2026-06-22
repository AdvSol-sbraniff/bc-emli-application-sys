# frozen_string_literal: true

module Claims
  module Ingest
    module EvidenceFile
      SUPPORTED_CONTENT_TYPES = %w[application/pdf image/jpeg image/png].freeze
      SUPPORTED_EXTENSIONS = %w[.pdf .jpg .jpeg .png].freeze

      module_function

      def original_filename(file, fallback:)
        safe_call(file, :original_filename).presence || fallback
      end

      def content_type(file, fallback: "application/octet-stream")
        safe_call(file, :content_type).presence || fallback
      end

      def byte_size(file)
        safe_call(file, :size)
      end

      def supported?(filename:, content_type:)
        supported_content_type?(content_type) ||
          SUPPORTED_EXTENSIONS.include?(File.extname(filename.to_s).downcase)
      end

      def storage_extension_for(filename:, content_type:)
        ext = File.extname(filename.to_s).downcase
        return ext if SUPPORTED_EXTENSIONS.include?(ext)

        case content_type.to_s.downcase
        when "application/pdf"
          ".pdf"
        when "image/jpeg"
          ".jpg"
        when "image/png"
          ".png"
        else
          ".bin"
        end
      end

      def safe_call(obj, method_name)
        return nil unless obj.respond_to?(method_name)

        obj.public_send(method_name)
      rescue StandardError
        nil
      end

      def supported_content_type?(content_type)
        SUPPORTED_CONTENT_TYPES.include?(content_type.to_s.downcase)
      end
    end
  end
end
