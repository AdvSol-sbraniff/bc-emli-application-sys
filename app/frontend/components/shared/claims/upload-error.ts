export type ClaimsUploadErrorPayload = {
  error?: unknown;
  message?: unknown;
  error_code?: unknown;
  failure_category?: unknown;
  failure_code?: unknown;
  retryable?: unknown;
  diagnostic_id?: unknown;
};

export class ClaimsUploadRequestError extends Error {
  status: number;
  errorCode: string;
  failureStatus: string;
  diagnosticId: string;

  constructor(status: number, message: string, payload: ClaimsUploadErrorPayload = {}) {
    super(message);
    this.name = 'ClaimsUploadRequestError';
    this.status = status;
    this.errorCode = typeof payload.error_code === 'string' ? payload.error_code : '';
    this.failureStatus = typeof payload.failure_category === 'string' ? payload.failure_category : '';
    this.diagnosticId = typeof payload.diagnostic_id === 'string' ? payload.diagnostic_id : '';
  }
}

const technicalErrorPattern =
  /\bHTTP(?:\s+|=)\d{3}\b|\b(?:Net|Faraday|OpenSSL|Aws)::|stack trace|connection refused|ECONN(?:REFUSED|RESET)|undefined method|NoMethodError/i;

function payloadErrorMessage(payload: ClaimsUploadErrorPayload): string {
  const value = payload?.error || payload?.message;
  return typeof value === 'string' ? value.trim() : '';
}

export function claimsUploadRequestError(
  response: Response,
  payload: ClaimsUploadErrorPayload,
  fallback: string,
): ClaimsUploadRequestError {
  const serverMessage = payloadErrorMessage(payload);
  let message = serverMessage || fallback;

  if (response.status === 401) {
    message = 'Your sign-in session has expired. Your files were not uploaded. Please sign in again and retry.';
  } else if (response.status === 403) {
    message =
      'Your account does not have permission to complete this upload. Please contact support if this is unexpected.';
  } else if (response.status === 413) {
    message = 'The selected files are too large to upload. Please reduce the package size and try again.';
  } else if (response.status === 429) {
    message = 'The upload service is busy right now. Please wait a moment and try again.';
  } else if (
    response.status >= 500 ||
    payload.failure_category === 'technical_failure' ||
    technicalErrorPattern.test(message)
  ) {
    message =
      'A processing service is temporarily unavailable. Please try again. If the problem continues, contact support.';
  }

  return new ClaimsUploadRequestError(response.status, message, payload);
}

export function claimsUploadCaughtErrorMessage(error: unknown, fallback: string): string {
  if (error instanceof ClaimsUploadRequestError) return error.message;
  if (error instanceof TypeError) {
    return 'We could not connect to the upload service. Check your connection and try again.';
  }

  const message = error instanceof Error ? error.message.trim() : '';
  if (technicalErrorPattern.test(message)) {
    return 'A processing service is temporarily unavailable. Please try again. If the problem continues, contact support.';
  }
  return message || fallback;
}

export function contractorFacingClaimsFailureMessage(message: string): string {
  const normalized = String(message || '').trim();
  if (!normalized) return '';
  if (technicalErrorPattern.test(normalized)) {
    return 'A processing service is temporarily unavailable. Please try again. If the problem continues, contact support.';
  }
  return normalized;
}
