BEGIN;

INSERT INTO claims.ingest_failure_subtypes (
  failure_category,
  failure_code,
  admin_label,
  contractor_message,
  retry_guidance,
  active,
  created_at,
  updated_at
)
VALUES
  ('package_needs_correction', 'package_no_invoice_pdf', 'No invoice PDF found', 'No invoice PDF was found. Upload exactly one invoice PDF.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_multiple_invoice_pdfs', 'Multiple invoice PDFs found', 'More than one invoice PDF was found. Upload exactly one invoice PDF.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_invoice_not_pdf', 'Invoice is not a PDF', 'The invoice must be a PDF. Images can be supporting documents, but not the primary invoice.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_replacement_not_invoice', 'Replacement file is not an invoice', 'The replacement file was not recognized as an invoice. Upload one corrected invoice PDF.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_replacement_multiple_files', 'Multiple replacement files uploaded', 'Upload exactly one corrected invoice PDF for an invoice replacement.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_replacement_upgrade_types_changed', 'Replacement changes claimed upgrades', 'The replacement invoice adds or removes a claimed upgrade type and was not applied.', 'Return to the invoice and use the Chat with admins button in the bottom-right corner for guidance.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_unsupported_file_type', 'Unsupported file type', 'One or more files use an unsupported file type. Upload PDFs, JPGs, or PNGs only.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_unreadable_file', 'Unreadable file', 'One or more files could not be opened or read. Replace the unreadable file and upload again.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_duplicate_file_conflict', 'Duplicate file conflict', 'Duplicate files were found and the package cannot be checked safely. Remove duplicates and upload again.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_no_processable_files', 'No processable files', 'No processable files were found. Upload one invoice PDF plus any supporting documents.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_invoice_classification_conflict', 'Invoice classification conflict', 'The uploaded files could not be safely sorted into one invoice and supporting documents. Upload a clearer package with exactly one invoice PDF.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_no_supported_upgrade_type', 'No supported rebate upgrade detected', 'The invoice was found, but no supported ESP rebate upgrade type was detected. Upload an invoice that includes a supported ESP rebate upgrade claim.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_missing_required_fix_file', 'Missing required fix file', 'No corrected invoice file was provided. Upload one corrected invoice PDF.', 'Upload a revised package.', true, NOW(), NOW()),
  ('package_needs_correction', 'package_file_too_large', 'File too large', 'One or more files are too large to process. Upload a smaller version of the file.', 'Upload a revised package.', true, NOW(), NOW()),

  ('technical_failure', 'upload_service_no_response', 'Upload service no response', 'We could not prepare your AI advice right now because the upload service did not respond.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'upload_service_error', 'Upload service error', 'We could not prepare your AI advice right now because the upload service returned an error.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'upload_service_malformed_response', 'Upload service response could not be read', 'We could not prepare your AI advice right now because the upload service returned a response the app could not read.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'upload_storage_key_missing', 'Upload storage key missing', 'We could not prepare your AI advice right now because the uploaded file could not be confirmed in storage.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'upload_storage_write_failure', 'Upload storage write failure', 'We could not prepare your AI advice right now because the uploaded file could not be saved.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'upload_unexpected_exception', 'Unexpected upload failure', 'We could not prepare your AI advice right now because the upload could not be completed.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'ocr_service_no_response', 'OCR service no response', 'We could not prepare your AI advice right now because the document reading service did not respond.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'ocr_service_error', 'OCR service error', 'We could not prepare your AI advice right now because the document reading service returned an error.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'ocr_service_malformed_response', 'OCR response could not be read', 'We could not prepare your AI advice right now because the document reading result could not be read.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'ocr_storage_read_failure', 'OCR storage read failure', 'We could not prepare your AI advice right now because the uploaded file could not be read from storage.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'ocr_provider_timeout', 'OCR provider timeout', 'We could not prepare your AI advice right now because the document reading service took too long to respond.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'ocr_unexpected_exception', 'Unexpected OCR failure', 'We could not prepare your AI advice right now because document reading could not be completed.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'genai_service_no_response', 'AI advice service no response', 'We could not prepare your AI advice right now because the AI advice service did not respond.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'genai_service_error', 'AI advice service error', 'We could not prepare your AI advice right now because the AI advice service returned an error.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'genai_service_malformed_response', 'AI advice response could not be read', 'We could not prepare your AI advice right now because the AI advice result could not be read.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'genai_provider_timeout', 'AI advice provider timeout', 'We could not prepare your AI advice right now because the AI advice service took too long to respond.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'genai_unexpected_exception', 'Unexpected AI advice failure', 'We could not prepare your AI advice right now because AI advice could not be completed.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'code_rule_runtime_failure', 'Code rule runtime failure', 'We could not prepare your AI advice right now because an internal program-rule check failed while processing the invoice.', 'Please contact support and include the invoice reference so the rule configuration can be corrected.', true, NOW(), NOW()),
  ('technical_failure', 'configuration_missing', 'Runtime configuration missing', 'We could not prepare your AI advice right now because a required system setting is missing.', 'Please try again later or contact support.', true, NOW(), NOW()),
  ('technical_failure', 'db_persistence_failure', 'Database persistence failure', 'We could not prepare your AI advice right now because the app could not save processing results.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'worker_retry_exhausted', 'Worker retry exhausted', 'We could not prepare your AI advice right now because background processing could not finish.', 'Please try uploading the same files again later.', true, NOW(), NOW()),
  ('technical_failure', 'unknown_runtime_failure', 'Unknown runtime failure', 'We could not prepare your AI advice right now because processing stopped unexpectedly.', 'Please try uploading the same files again later.', true, NOW(), NOW())
ON CONFLICT (failure_category, failure_code) DO UPDATE
SET
  admin_label = EXCLUDED.admin_label,
  contractor_message = EXCLUDED.contractor_message,
  retry_guidance = EXCLUDED.retry_guidance,
  active = EXCLUDED.active,
  updated_at = NOW();

COMMIT;
