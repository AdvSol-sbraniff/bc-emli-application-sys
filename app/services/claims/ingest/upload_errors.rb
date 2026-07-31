# frozen_string_literal: true

module Claims
  module Ingest
    module UploadErrors
      SAFE_TECHNICAL_MESSAGE =
        "We could not complete the upload because of a technical problem. " \
          "Please try again. If the problem continues, contact support."

      class ValidationError < StandardError
        attr_reader :error_code

        def initialize(message, error_code: "upload_validation_error")
          @error_code = error_code
          super(message)
        end
      end

      class UnexpectedError < StandardError
        attr_reader :diagnostic_id,
                    :error_code,
                    :ingest_run_id,
                    :session_id,
                    :invoice_id

        def initialize(
          diagnostic_id:,
          error_code: "upload_unexpected_exception",
          ingest_run_id: nil,
          session_id: nil,
          invoice_id: nil
        )
          @diagnostic_id = diagnostic_id
          @error_code = error_code
          @ingest_run_id = ingest_run_id
          @session_id = session_id
          @invoice_id = invoice_id
          super(SAFE_TECHNICAL_MESSAGE)
        end
      end
    end
  end
end
