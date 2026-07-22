BEGIN;

ALTER TABLE claims.invoices
  DROP CONSTRAINT IF EXISTS invoices_status_chk;

ALTER TABLE claims.invoices
  ADD CONSTRAINT invoices_status_chk
  CHECK (status IN (
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
    'contractor_withdrawn'
  ));

COMMIT;
