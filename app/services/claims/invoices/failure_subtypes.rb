# frozen_string_literal: true

require "net/http"
require "timeout"

module Claims
  module Invoices
    module FailureSubtypes
      STEP_DIAGNOSTIC_COLUMNS = %i[
        failure_status
        failure_status_subtype
        error_code
        error_category
        error_phase
        retryable
        diagnostic_id
        provider_status
        provider_code
        provider_attempt_count
      ].freeze

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

        if node_error_code(error) == "genai_input_image_invalid"
          return "package_unreadable_file"
        end
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

      def genai_status(error)
        if node_error_code(error) == "genai_input_image_invalid"
          return "package_needs_correction"
        end

        "technical_failure"
      end

      def runtime(error)
        message = error_message(error)

        return "configuration_missing" if configuration_error?(message)
        return "code_rule_runtime_failure" if code_rule_error?(message)
        return "db_persistence_failure" if persistence_error?(error)

        "unknown_runtime_failure"
      end

      def payload(status:, status_subtype:, error: nil)
        normalized =
          ::Claims::Invoices::StatusSubtypes.normalize(status, status_subtype)
        base = {
          "failure_status" => status.to_s,
          "failure_status_subtype" => normalized || status_subtype.to_s,
          "error_class" => error&.class&.name,
          "error_message" => error&.message.to_s
        }.compact
        analytics =
          if error.respond_to?(:analytics_payload)
            error.analytics_payload
          else
            {
              "error_code" => normalized || status_subtype.to_s,
              "retryable" => retryable?(error)
            }
          end

        base.merge(analytics)
      end

      def step_attributes(status:, status_subtype:, error: nil)
        values =
          payload(status: status, status_subtype: status_subtype, error: error)

        {
          failure_status: values["failure_status"],
          failure_status_subtype: values["failure_status_subtype"],
          error_code:
            values["error_code"].presence ||
              values["failure_status_subtype"].presence,
          error_category: values["error_category"],
          error_phase: values["phase"],
          retryable: values["retryable"],
          diagnostic_id: values["diagnostic_id"],
          provider_status: integer_or_nil(values["provider_status"]),
          provider_code: values["provider_code"],
          provider_attempt_count:
            positive_integer_or_nil(values["provider_attempt_count"])
        }
      end

      def clear_step_attributes
        STEP_DIAGNOSTIC_COLUMNS.index_with { nil }
      end

      def from_step(step, fallback:)
        scalar_subtype =
          normalized_step_value(step, :failure_status_subtype).presence
        scalar_status =
          normalized_step_value(step, :failure_status).presence ||
            "technical_failure"
        normalized =
          ::Claims::Invoices::StatusSubtypes.normalize(
            scalar_status,
            scalar_subtype
          )
        return normalized if normalized.present?

        payloads = [step&.genai_results_json, step&.di_results_json]
        payloads.each do |payload|
          next unless payload.is_a?(Hash)

          subtype =
            payload["failure_status_subtype"] ||
              payload[:failure_status_subtype] || payload["status_subtype"] ||
              payload[:status_subtype]
          status =
            payload["failure_status"] || payload[:failure_status] ||
              "technical_failure"
          normalized =
            ::Claims::Invoices::StatusSubtypes.normalize(status, subtype)
          return normalized if normalized.present?
        end

        fallback
      end

      def status_from_step(step, fallback: "technical_failure")
        scalar_status = normalized_step_value(step, :failure_status)
        if %w[package_needs_correction technical_failure].include?(
             scalar_status
           )
          return scalar_status
        end

        payloads = [step&.genai_results_json, step&.di_results_json]
        payloads.each do |payload|
          next unless payload.is_a?(Hash)

          status = payload["failure_status"] || payload[:failure_status]
          if %w[package_needs_correction technical_failure].include?(
               status.to_s
             )
            return status
          end
        end

        fallback
      end

      def analytics_from_step(step)
        scalar = {
          "error_code" => normalized_step_value(step, :error_code),
          "error_category" => normalized_step_value(step, :error_category),
          "retryable" => step_value(step, :retryable),
          "diagnostic_id" => normalized_step_value(step, :diagnostic_id),
          "provider_status" => step_value(step, :provider_status),
          "provider_code" => normalized_step_value(step, :provider_code),
          "provider_attempt_count" => step_value(step, :provider_attempt_count),
          "phase" => normalized_step_value(step, :error_phase),
          "failure_status" => normalized_step_value(step, :failure_status),
          "failure_status_subtype" =>
            normalized_step_value(step, :failure_status_subtype)
        }.compact
        return scalar if scalar["error_code"].present?

        payloads = [step&.genai_results_json, step&.di_results_json]
        payload =
          payloads.find do |candidate|
            candidate.is_a?(Hash) &&
              (
                candidate["error_code"].present? ||
                  candidate[:error_code].present?
              )
          end
        return {} unless payload

        payload
          .stringify_keys
          .slice(
            "error_code",
            "error_category",
            "retryable",
            "diagnostic_id",
            "provider_status",
            "provider_code",
            "provider_attempt_count",
            "phase",
            "failure_status",
            "failure_status_subtype"
          )
          .compact
      end

      def primary_failed_step(steps)
        Array(steps).min_by do |step|
          analytics = analytics_from_step(step)
          priority =
            if analytics["provider_status"].present?
              0
            elsif analytics["diagnostic_id"].present?
              1
            elsif analytics["error_code"].present? &&
                  analytics["error_category"] != "pipeline_cancelled"
              2
            else
              3
            end

          [priority, step.created_at || Time.at(0), step.id.to_s]
        end
      end

      def step_value(step, attribute)
        return if step.nil? || !step.respond_to?(attribute)

        step.public_send(attribute)
      end

      def normalized_step_value(step, attribute)
        step_value(step, attribute).to_s.strip
      end

      def integer_or_nil(value)
        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def positive_integer_or_nil(value)
        parsed = integer_or_nil(value)
        parsed&.positive? ? parsed : nil
      end

      def retryable?(error)
        return error.retryable? if error.respond_to?(:retryable?)
        return true if no_response_error?(error, error_message(error))
        return true if timeout_error?(error, error_message(error))
        if defined?(ActiveRecord::Deadlocked) &&
             error.is_a?(ActiveRecord::Deadlocked)
          return true
        end
        if defined?(ActiveRecord::ConnectionNotEstablished) &&
             error.is_a?(ActiveRecord::ConnectionNotEstablished)
          return true
        end

        false
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

      def node_error_code(error)
        return unless error.respond_to?(:error_code)

        error.error_code.to_s
      end

      def code_rule_error?(message)
        message.include?("code rules failed") ||
          message.include?("applycoderulechecks") ||
          message.include?("applyupgradecoderulechecks") ||
          message.include?("code_rule")
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
