# frozen_string_literal: true

module Claims
  module Invoices
    module StatusSubtypes
      PACKAGE_NEEDS_CORRECTION = "package_needs_correction"
      TECHNICAL_FAILURE = "technical_failure"

      PACKAGE_SUBTYPES = %w[
        package_no_invoice_pdf
        package_multiple_invoice_pdfs
        package_invoice_not_pdf
        package_replacement_not_invoice
        package_replacement_multiple_files
        package_unsupported_file_type
        package_unreadable_file
        package_duplicate_file_conflict
        package_no_processable_files
        package_invoice_classification_conflict
        package_no_supported_upgrade_type
        package_missing_required_fix_file
        package_file_too_large
      ].freeze

      TECHNICAL_SUBTYPES = %w[
        upload_service_no_response
        upload_service_error
        upload_service_malformed_response
        upload_storage_key_missing
        upload_storage_write_failure
        upload_unexpected_exception
        ocr_service_no_response
        ocr_service_error
        ocr_service_malformed_response
        ocr_storage_read_failure
        ocr_provider_timeout
        ocr_unexpected_exception
        genai_service_no_response
        genai_service_error
        genai_service_malformed_response
        genai_provider_timeout
        genai_unexpected_exception
        configuration_missing
        db_persistence_failure
        worker_retry_exhausted
        unknown_runtime_failure
      ].freeze

      ALLOWED_BY_STATUS = {
        PACKAGE_NEEDS_CORRECTION => PACKAGE_SUBTYPES,
        TECHNICAL_FAILURE => TECHNICAL_SUBTYPES
      }.freeze

      SUBTYPE_COPY = {
        "package_no_invoice_pdf" =>
          "No invoice PDF was found. Upload exactly one invoice PDF.",
        "package_multiple_invoice_pdfs" =>
          "More than one invoice PDF was found. Upload exactly one invoice PDF.",
        "package_invoice_not_pdf" =>
          "The invoice must be a PDF. Images can be supporting documents, but not the primary invoice.",
        "package_replacement_not_invoice" =>
          "The replacement file was not recognized as an invoice. Upload one corrected invoice PDF.",
        "package_replacement_multiple_files" =>
          "Upload exactly one corrected invoice PDF for an invoice replacement.",
        "package_unsupported_file_type" =>
          "One or more files use an unsupported file type. Upload PDFs or supported image files only.",
        "package_unreadable_file" =>
          "One or more files could not be opened or read. Replace the unreadable file and upload again.",
        "package_duplicate_file_conflict" =>
          "Duplicate files were found and the package cannot be routed safely.",
        "package_no_processable_files" =>
          "No processable files were found in the upload.",
        "package_invoice_classification_conflict" =>
          "The uploaded files could not be safely classified into one invoice and supporting documents.",
        "package_no_supported_upgrade_type" =>
          "The invoice was found, but no supported ESP rebate upgrade type was detected.",
        "package_missing_required_fix_file" =>
          "No corrected invoice file was provided.",
        "package_file_too_large" =>
          "One or more files are too large to process.",
        "upload_service_no_response" => "The upload service did not respond.",
        "upload_service_error" => "The upload service returned an error.",
        "upload_service_malformed_response" =>
          "The upload service returned a response the app could not read.",
        "upload_storage_key_missing" =>
          "The upload service did not return a storage key.",
        "upload_storage_write_failure" =>
          "The uploaded file could not be written to storage.",
        "upload_unexpected_exception" => "Unexpected upload runtime failure.",
        "ocr_service_no_response" => "The OCR service did not respond.",
        "ocr_service_error" => "The OCR service returned an error.",
        "ocr_service_malformed_response" =>
          "The OCR service returned a response the app could not read.",
        "ocr_storage_read_failure" =>
          "The file could not be read from storage for OCR.",
        "ocr_provider_timeout" => "The OCR provider timed out.",
        "ocr_unexpected_exception" => "Unexpected OCR runtime failure.",
        "genai_service_no_response" => "The GenAI service did not respond.",
        "genai_service_error" => "The GenAI service returned an error.",
        "genai_service_malformed_response" =>
          "The GenAI service returned a response the app could not read.",
        "genai_provider_timeout" => "The GenAI provider timed out.",
        "genai_unexpected_exception" => "Unexpected GenAI runtime failure.",
        "configuration_missing" => "Required runtime configuration is missing.",
        "db_persistence_failure" =>
          "The app could not save processing results.",
        "worker_retry_exhausted" =>
          "The background worker exhausted its retries.",
        "unknown_runtime_failure" =>
          "An unknown runtime failure stopped processing."
      }.freeze

      def self.valid?(status, subtype)
        return true if subtype.blank?

        ALLOWED_BY_STATUS.fetch(status.to_s, []).include?(subtype.to_s)
      end

      def self.normalize(status, subtype)
        subtype = subtype.to_s.strip
        return nil if subtype.empty?

        valid?(status, subtype) ? subtype : nil
      end

      def self.hint(subtype)
        SUBTYPE_COPY[subtype.to_s]
      end

      def self.contractor_message(status, subtype)
        subtype = normalize(status, subtype)
        return nil if subtype.blank?

        subtype_record(status, subtype)&.contractor_message.presence ||
          SUBTYPE_COPY[subtype]
      end

      def self.retry_guidance(status, subtype)
        subtype = normalize(status, subtype)
        return nil if subtype.blank?

        subtype_record(status, subtype)&.retry_guidance.presence
      end

      def self.admin_label(status, subtype)
        subtype = normalize(status, subtype)
        return nil if subtype.blank?

        subtype_record(status, subtype)&.admin_label.presence ||
          subtype.tr("_", " ").titleize
      end

      def self.contractor_failure_message(status, subtype)
        status = status.to_s
        subtype = normalize(status, subtype)
        message = contractor_message(status, subtype)

        case status
        when PACKAGE_NEEDS_CORRECTION
          detail =
            message.presence ||
              "Upload a revised package with exactly one invoice PDF."
          "We could not prepare your AI advice because the upload package needs a change: #{detail}"
        when TECHNICAL_FAILURE
          guidance =
            retry_guidance(status, subtype).presence ||
              "Please try uploading the same files again later."
          base =
            message.presence || "We could not prepare your AI advice right now."
          "#{base} #{guidance}".squish
        end
      end

      def self.invoice_row_copy(status, subtype)
        subtype = subtype.to_s.strip
        return {} if subtype.blank?

        record = subtype_record(status, subtype)
        return {} if record.nil?

        hint_parts = [
          record.contractor_message.presence,
          record.retry_guidance.presence
        ].compact

        {
          invoice_status_subtype_admin_label: record.admin_label.presence,
          invoice_status_subtype_hint: hint_parts.join(" ").presence,
          invoice_status_subtype_retry_guidance: record.retry_guidance.presence
        }.compact
      end

      def self.subtype_record(status, subtype)
        return nil if subtype.blank?

        ::Claims::InvoiceStatusSubtype.active.find_by(
          status: status.to_s,
          status_subtype: subtype.to_s
        )
      rescue ActiveRecord::StatementInvalid,
             ActiveRecord::ConnectionNotEstablished
        nil
      end
    end
  end
end
