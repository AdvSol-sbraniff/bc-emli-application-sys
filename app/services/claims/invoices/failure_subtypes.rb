# frozen_string_literal: true

require "net/http"
require "timeout"

module Claims
  module Invoices
    module FailureSubtypes
      module_function

      def upload(error)
        message = error_message(error)

        return "configuration_missing" if configuration_error?(message)
        if malformed_json?(error, message)
          return "upload_service_malformed_response"
        end
        return "upload_storage_key_missing" if message.include?("storage_key")
        return "upload_storage_write_failure" if storage_write_error?(message)
        if no_response_error?(error, message)
          return "upload_service_no_response"
        end
        if service_error?(message, "node upload failed")
          return "upload_service_error"
        end

        "upload_unexpected_exception"
      end

      def ocr(error)
        message = error_message(error)

        return "configuration_missing" if configuration_error?(message)
        if malformed_json?(error, message)
          return "ocr_service_malformed_response"
        end
        return "ocr_storage_read_failure" if storage_read_error?(message)
        return "ocr_service_no_response" if no_response_error?(error, message)
        return "ocr_provider_timeout" if timeout_error?(error, message)
        return "ocr_service_error" if service_error?(message, "node ocr failed")
        return "db_persistence_failure" if persistence_error?(error)

        "ocr_unexpected_exception"
      end

      def genai(error)
        message = error_message(error)

        return "configuration_missing" if configuration_error?(message)
        if malformed_genai_response?(error, message)
          return "genai_service_malformed_response"
        end
        return "genai_service_no_response" if no_response_error?(error, message)
        return "genai_provider_timeout" if timeout_error?(error, message)
        if service_error?(message, "node genai failed")
          return "genai_service_error"
        end
        return "db_persistence_failure" if persistence_error?(error)

        "genai_unexpected_exception"
      end

      def runtime(error)
        message = error_message(error)

        return "configuration_missing" if configuration_error?(message)
        return "db_persistence_failure" if persistence_error?(error)

        "unknown_runtime_failure"
      end

      def payload(status:, status_subtype:, error: nil)
        normalized =
          ::Claims::Invoices::StatusSubtypes.normalize(status, status_subtype)
        {
          "failure_status" => status.to_s,
          "failure_status_subtype" => normalized || status_subtype.to_s,
          "error_class" => error&.class&.name,
          "error_message" => error&.message.to_s
        }.compact
      end

      def from_step(step, fallback:)
        payloads = [step&.genai_results_json, step&.di_results_json]
        payloads.each do |payload|
          next unless payload.is_a?(Hash)

          subtype =
            payload["failure_status_subtype"] ||
              payload[:failure_status_subtype] || payload["status_subtype"] ||
              payload[:status_subtype]
          normalized =
            ::Claims::Invoices::StatusSubtypes.normalize(
              "technical_failure",
              subtype
            )
          return normalized if normalized.present?
        end

        fallback
      end

      def error_message(error)
        if error.respond_to?(:message)
          error.message.to_s.downcase
        else
          error.to_s.downcase
        end
      end

      def configuration_error?(message)
        message.include?("missing env") ||
          message.include?("required runtime configuration") ||
          message.include?("validationgenai_config") ||
          message.include?("configuration missing") ||
          message.include?("config")
      end

      def malformed_json?(error, message)
        error.is_a?(JSON::ParserError) ||
          message.include?("json::parsererror") ||
          message.include?("unexpected token") ||
          message.include?("malformed response")
      end

      def malformed_genai_response?(error, message)
        malformed_json?(error, message) ||
          message.include?("applydocumenttriageresult failed") ||
          message.include?("applysupportingdocumenttypelocatedfields failed") ||
          message.include?("applygenairulechecks failed") ||
          message.include?("applygenailocatedfields failed")
      end

      def no_response_error?(error, message)
        if defined?(Net::OpenTimeout) && error.is_a?(Net::OpenTimeout)
          return true
        end
        return true if defined?(SocketError) && error.is_a?(SocketError)
        return true if defined?(EOFError) && error.is_a?(EOFError)
        if defined?(Errno::ECONNREFUSED) && error.is_a?(Errno::ECONNREFUSED)
          return true
        end
        if defined?(Errno::ECONNRESET) && error.is_a?(Errno::ECONNRESET)
          return true
        end
        if defined?(Errno::EHOSTUNREACH) && error.is_a?(Errno::EHOSTUNREACH)
          return true
        end
        if defined?(Errno::ENETUNREACH) && error.is_a?(Errno::ENETUNREACH)
          return true
        end

        message.include?("connection refused") ||
          message.include?("failed to open tcp connection") ||
          message.include?("getaddrinfo") ||
          message.include?("no route to host") ||
          message.include?("network is unreachable")
      end

      def timeout_error?(error, message)
        if defined?(Net::ReadTimeout) && error.is_a?(Net::ReadTimeout)
          return true
        end
        return true if defined?(Timeout::Error) && error.is_a?(Timeout::Error)

        message.include?("timeout") || message.include?("timed out")
      end

      def service_error?(message, marker)
        message.include?(marker) || message.include?("http=")
      end

      def storage_read_error?(message)
        message.include?("storage") || message.include?("blob")
      end

      def storage_write_error?(message)
        message.include?("storage write") ||
          message.include?("could not be saved") ||
          message.include?("write failure")
      end

      def persistence_error?(error)
        (
          defined?(ActiveRecord::StatementInvalid) &&
            error.is_a?(ActiveRecord::StatementInvalid)
        ) ||
          (
            defined?(ActiveRecord::RecordInvalid) &&
              error.is_a?(ActiveRecord::RecordInvalid)
          ) ||
          (
            defined?(ActiveRecord::RecordNotSaved) &&
              error.is_a?(ActiveRecord::RecordNotSaved)
          )
      end
    end
  end
end
