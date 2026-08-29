# frozen_string_literal: true

require "json"
require "net/http"

module Claims
  module Genai
    class NodeClient
      class Error < StandardError
        ANALYTICS_KEYS = %w[
          error_code
          error_category
          retryable
          diagnostic_id
          provider_status
          provider_code
          provider_attempt_count
          phase
        ].freeze

        attr_reader :http_status, :payload

        def initialize(http_status:, payload:)
          @http_status = http_status.to_i
          @payload = payload.is_a?(Hash) ? payload.stringify_keys : {}
          super(safe_message)
        end

        def error_code
          payload["code"].presence || fallback_error_code
        end

        def error_category
          payload["category"].presence || "node_service_error"
        end

        def retryable?
          if [true, false].include?(payload["retryable"])
            return payload["retryable"]
          end

          http_status == 408 || http_status == 429 || http_status >= 500
        end

        def analytics_payload
          {
            "error_code" => error_code,
            "error_category" => error_category,
            "retryable" => retryable?,
            "diagnostic_id" => bounded(payload["diagnostic_id"], 160),
            "provider_status" => payload["provider_status"],
            "provider_code" => bounded(payload["provider_code"], 160),
            "provider_attempt_count" =>
              positive_integer(payload["provider_attempt_count"]),
            "phase" => bounded(payload["phase"], 120)
          }.compact.slice(*ANALYTICS_KEYS)
        end

        private

        def fallback_error_code
          return "genai_node_throttled" if http_status == 429
          return "genai_node_service_error" if http_status >= 500

          "genai_node_request_error"
        end

        def safe_message
          parts = [error_code]
          diagnostic_id = bounded(payload["diagnostic_id"], 160)
          parts << "diagnostic_id=#{diagnostic_id}" if diagnostic_id.present?
          snippet = bounded(payload["snippet"], 1_000)
          if error_code == "genai_model_output_invalid_json" && snippet.present?
            parts << "snippet=#{snippet}"
          end
          "Node GenAI request failed (#{parts.join("; ")})"
        end

        def bounded(value, length)
          value.to_s.strip.presence&.slice(0, length)
        end

        def positive_integer(value)
          parsed = Integer(value)
          parsed.positive? ? parsed : nil
        rescue ArgumentError, TypeError
          nil
        end
      end

      def self.call(
        contextwindowjson:,
        attachments: [],
        diagnostic_context: {},
        deployment_name: nil
      )
        new.call(
          contextwindowjson: contextwindowjson,
          attachments: attachments,
          diagnostic_context: diagnostic_context,
          deployment_name: deployment_name
        )
      end

      def call(
        contextwindowjson:,
        attachments: [],
        diagnostic_context: {},
        deployment_name: nil
      )
        uri = URI("#{ENV.fetch("INV_NODE_BASE_URL")}/inv/genai")
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body =
          JSON.generate(
            contextwindowjson: contextwindowjson,
            attachments: attachments,
            diagnostic_context: diagnostic_context,
            deployment_name: deployment_name.to_s.strip.presence
          )

        http = Net::HTTP.new(uri.host, uri.port)
        http.open_timeout = 10
        http.read_timeout = 300
        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Error.new(
                  http_status: response.code,
                  payload: parse_error_payload(response.body)
                )
        end

        JSON.parse(response.body)
      end

      private

      def parse_error_payload(body)
        parsed = JSON.parse(body.to_s)
        return {} unless parsed.is_a?(Hash)

        nested =
          parsed["error"].presence ||
            (parsed["message"] if parsed["message"].is_a?(Hash))
        nested.is_a?(Hash) ? nested : parsed
      rescue JSON::ParserError, TypeError
        {}
      end
    end
  end
end
