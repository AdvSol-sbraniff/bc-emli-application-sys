# frozen_string_literal: true

require "securerandom"

module Api
  module Claims
    module Concerns
      module UploadErrorRendering
        private

        def render_claims_upload_error(error, log_prefix:)
          if error.is_a?(::Claims::Ingest::UploadErrors::ValidationError)
            render(
              json: {
                ok: false,
                error: error.message,
                error_code: error.error_code,
                retryable: false
              },
              status: :unprocessable_entity
            )
            return
          end

          wrapped_error =
            if error.is_a?(::Claims::Ingest::UploadErrors::UnexpectedError)
              error
            else
              ::Claims::Ingest::UploadErrors::UnexpectedError.new(
                diagnostic_id: SecureRandom.uuid
              )
            end
          original_error = error.cause || error
          Rails.logger.error(
            "[claims][#{log_prefix}] diagnostic_id=#{wrapped_error.diagnostic_id} " \
              "ingest_run_id=#{wrapped_error.ingest_run_id || "-"} " \
              "ERROR: #{original_error.class}: #{original_error.message}"
          )
          Rails.logger.error(Array(original_error.backtrace).join("\n"))

          render(
            json: {
              ok: false,
              error: wrapped_error.message,
              failure_category: "technical_failure",
              failure_code: wrapped_error.error_code,
              error_code: wrapped_error.error_code,
              retryable: false,
              diagnostic_id: wrapped_error.diagnostic_id,
              ingest_run_id: wrapped_error.ingest_run_id,
              session_id: wrapped_error.session_id,
              invoice_id: wrapped_error.invoice_id
            }.compact,
            status: :internal_server_error
          )
        end
      end
    end
  end
end
