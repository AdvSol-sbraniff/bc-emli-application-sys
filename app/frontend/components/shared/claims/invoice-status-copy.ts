export type InvoiceStatusCopy = {
  label: string;
  hint: string;
};

const STATUS_SUBTYPE_HINTS: Record<string, string> = {
  package_no_invoice_pdf: 'No invoice PDF was found. Upload exactly one invoice PDF.',
  package_multiple_invoice_pdfs: 'More than one invoice PDF was found. Upload exactly one invoice PDF.',
  package_invoice_not_pdf:
    'The invoice must be a PDF. Images can be supporting documents, but not the primary invoice.',
  package_replacement_not_invoice:
    'The replacement file was not recognized as an invoice. Upload one corrected invoice PDF.',
  package_replacement_multiple_files: 'Upload exactly one corrected invoice PDF for an invoice replacement.',
  package_unsupported_file_type:
    'One or more files use an unsupported file type. Upload PDFs or supported image files only.',
  package_unreadable_file:
    'One or more files could not be opened or read. Replace the unreadable file and upload again.',
  package_duplicate_file_conflict: 'Duplicate files were found and the package cannot be routed safely.',
  package_no_processable_files: 'No processable files were found in the upload.',
  package_invoice_classification_conflict:
    'The uploaded files could not be safely classified into one invoice and supporting documents.',
  package_no_supported_upgrade_type: 'The invoice was found, but no supported ESP rebate upgrade type was detected.',
  package_missing_required_fix_file: 'No corrected invoice file was provided.',
  package_file_too_large: 'One or more files are too large to process.',
  upload_service_no_response: 'The upload service did not respond.',
  upload_service_error: 'The upload service returned an error.',
  upload_service_malformed_response: 'The upload service returned a response the app could not read.',
  upload_storage_key_missing: 'The upload service did not return a storage key.',
  upload_storage_write_failure: 'The uploaded file could not be written to storage.',
  upload_unexpected_exception: 'Unexpected upload runtime failure.',
  ocr_service_no_response: 'The OCR service did not respond.',
  ocr_service_error: 'The OCR service returned an error.',
  ocr_service_malformed_response: 'The OCR service returned a response the app could not read.',
  ocr_storage_read_failure: 'The file could not be read from storage for OCR.',
  ocr_provider_timeout: 'The OCR provider timed out.',
  ocr_unexpected_exception: 'Unexpected OCR runtime failure.',
  genai_service_no_response: 'The GenAI service did not respond.',
  genai_service_error: 'The GenAI service returned an error.',
  genai_service_malformed_response: 'The GenAI service returned a response the app could not read.',
  genai_provider_timeout: 'The GenAI provider timed out.',
  genai_unexpected_exception: 'Unexpected GenAI runtime failure.',
  configuration_missing: 'Required runtime configuration is missing.',
  db_persistence_failure: 'The app could not save processing results.',
  worker_retry_exhausted: 'The background worker exhausted its retries.',
  unknown_runtime_failure: 'An unknown runtime failure stopped processing.',
};

export const INVOICE_STATUS_COPY: Record<string, InvoiceStatusCopy> = {
  upload_queued: {
    label: 'Preparing AI Advice',
    hint: 'The package upload is queued.',
  },
  upload_in_progress: {
    label: 'Preparing AI Advice',
    hint: 'The uploaded package is being staged before evidence preparation starts.',
  },
  upload_failed: {
    label: 'Needs Technical Help',
    hint: 'Upload or package staging failed and needs troubleshooting.',
  },
  upload_complete: {
    label: 'Preparing AI Advice',
    hint: 'The package upload completed and the next processing step is starting.',
  },
  ocr_queued: {
    label: 'Preparing AI Advice',
    hint: 'Evidence preparation is queued.',
  },
  ocr_in_progress: {
    label: 'Preparing AI Advice',
    hint: 'OCR, document classification, invoice extraction, and supporting-document extraction are running.',
  },
  ocr_failed: {
    label: 'Needs Technical Help',
    hint: 'Evidence preparation failed and needs troubleshooting.',
  },
  ocr_complete: {
    label: 'Preparing AI Advice',
    hint: 'Evidence preparation completed and AI Advice is about to start.',
  },
  genai_queued: {
    label: 'Preparing AI Advice',
    hint: 'AI Advice generation is queued.',
  },
  genai_in_progress: {
    label: 'Preparing AI Advice',
    hint: 'AI Advice is being built: case facts, product lookup, GenAI advice, code checks, and final advice.',
  },
  genai_failed: {
    label: 'Needs Technical Help',
    hint: 'AI Advice failed and needs troubleshooting.',
  },
  genai_complete: {
    label: 'With Contractor for Pre-check',
    hint: 'AI Advice is complete. The contractor can pre-check the advice, revise if needed, and submit when ready.',
  },
  package_needs_correction: {
    label: 'Package Needs Correction',
    hint: 'The uploaded package cannot be reviewed yet. The contractor needs to correct the upload.',
  },
  technical_failure: {
    label: 'Needs Technical Help',
    hint: 'A system or service error stopped processing. Admin troubleshooting is required.',
  },
  admin_review_inbox: {
    label: 'With First Level Admin Review',
    hint: 'The claim is waiting for first level admin review.',
  },
  contractor_revision_inbox: {
    label: 'With Contractor for Revision',
    hint: 'Admin review sent the claim back to the contractor to revise the package or provide supporting information.',
  },
  in_review: {
    label: 'With Second Level Admin Review',
    hint: 'A second level admin review is underway.',
  },
  approved_pending: {
    label: 'Approved, Pending Payment',
    hint: 'The claim is approved, but payment or final closeout is not complete yet.',
  },
  approved_paid: {
    label: 'Approved and Paid',
    hint: 'The claim has been approved and paid or closed.',
  },
  ineligible: {
    label: 'Ineligible',
    hint: 'The claim has been marked ineligible.',
  },
  contractor_withdrawn: {
    label: 'Withdrawn by Contractor',
    hint: 'The contractor voluntarily withdrew this invoice before approval.',
  },
};

export const INVOICE_STATUS_FILTER_OPTIONS = [
  'upload_queued',
  'upload_in_progress',
  'upload_failed',
  'upload_complete',
  'ocr_queued',
  'ocr_in_progress',
  'ocr_failed',
  'ocr_complete',
  'genai_queued',
  'genai_in_progress',
  'genai_failed',
  'genai_complete',
  'package_needs_correction',
  'technical_failure',
  'admin_review_inbox',
  'contractor_revision_inbox',
  'in_review',
  'approved_pending',
  'approved_paid',
  'ineligible',
  'contractor_withdrawn',
];

const humanizeStatus = (status: string) =>
  status
    .split('_')
    .filter(Boolean)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');

export const invoiceStatusCopy = (status?: string | null, statusSubtype?: string | null): InvoiceStatusCopy => {
  const rawStatus = String(status || '').trim();
  const subtypeHint = STATUS_SUBTYPE_HINTS[String(statusSubtype || '').trim()];
  if (!rawStatus) {
    return {
      label: 'Unknown',
      hint: 'No invoice status is available yet.',
    };
  }

  const copy = INVOICE_STATUS_COPY[rawStatus] || {
    label: humanizeStatus(rawStatus),
    hint: 'This invoice is in a workflow status that does not have custom help text yet.',
  };

  return subtypeHint ? { ...copy, hint: subtypeHint } : copy;
};

export const INVOICE_STATUS_FILTER_GROUPS = INVOICE_STATUS_FILTER_OPTIONS.reduce<
  Array<{ label: string; statuses: string[] }>
>((groups, status) => {
  const label = invoiceStatusCopy(status).label;
  const existing = groups.find((group) => group.label === label);
  if (existing) existing.statuses.push(status);
  else groups.push({ label, statuses: [status] });
  return groups;
}, []);
