export type GenAiErrorCategory =
  | 'provider_timeout'
  | 'provider_throttled'
  | 'provider_auth_error'
  | 'provider_invalid_image'
  | 'provider_bad_request'
  | 'provider_gateway_error'
  | 'provider_content_filter'
  | 'provider_network_error'
  | 'provider_unknown_error';

export type SanitizedGenAiError = {
  message: string;
  code: string;
  category: GenAiErrorCategory;
  retryable: boolean;
  diagnostic_id: string;
  elapsed_ms: number;
  provider_status?: number | string;
  provider_code?: string;
  provider_attempt_count?: number;
  phase?: string;
};

export function providerStatus(error: any): number | string | undefined {
  return error?.status ?? error?.response?.status;
}

export function providerCode(error: any): string | undefined {
  const value = error?.code ?? error?.error?.code;
  if (value === undefined || value === null) return undefined;

  return String(value).slice(0, 120);
}

function providerErrorText(error: any): string {
  const value = error?.response?.data ?? error?.error ?? error?.message ?? '';

  try {
    return (
      typeof value === 'string' ? value : JSON.stringify(value)
    ).toLowerCase();
  } catch {
    return String(error?.message || '').toLowerCase();
  }
}

export function isRetryableGenAiError(error: any): boolean {
  const status = Number(providerStatus(error));
  const code = String(providerCode(error) || '').toLowerCase();
  const message = String(error?.message || '').toLowerCase();

  if ([408, 429, 500, 502, 503, 504].includes(status)) return true;
  if (['econnreset', 'enotfound', 'econnrefused', 'eai_again'].includes(code)) {
    return true;
  }

  return (
    code.includes('timeout') ||
    message.includes('timeout') ||
    message.includes('timed out')
  );
}

export function categorizeGenAiError(error: any): GenAiErrorCategory {
  const status = Number(providerStatus(error));
  const code = String(providerCode(error) || '').toLowerCase();
  const message = providerErrorText(error);

  if (
    status === 408 ||
    code.includes('timeout') ||
    message.includes('timeout') ||
    message.includes('timed out')
  ) {
    return 'provider_timeout';
  }
  if (status === 429 || code.includes('rate') || message.includes('throttl')) {
    return 'provider_throttled';
  }
  if (status === 401 || status === 403) return 'provider_auth_error';
  if (message.includes('content') && message.includes('filter')) {
    return 'provider_content_filter';
  }
  if (
    status === 400 &&
    message.includes('image') &&
    ['invalid', 'format', 'unsupported', 'decode', 'corrupt'].some((marker) =>
      message.includes(marker),
    )
  ) {
    return 'provider_invalid_image';
  }
  if (status === 400 || status === 422) return 'provider_bad_request';
  if ([502, 503, 504].includes(status) || status >= 500) {
    return 'provider_gateway_error';
  }
  if (['econnreset', 'enotfound', 'econnrefused', 'eai_again'].includes(code)) {
    return 'provider_network_error';
  }

  return 'provider_unknown_error';
}

export function errorCodeForCategory(category: GenAiErrorCategory): string {
  const codes: Record<GenAiErrorCategory, string> = {
    provider_timeout: 'genai_provider_timeout',
    provider_throttled: 'genai_provider_throttled',
    provider_auth_error: 'genai_provider_auth_error',
    provider_invalid_image: 'genai_input_image_invalid',
    provider_bad_request: 'genai_provider_bad_request',
    provider_gateway_error: 'genai_provider_gateway_error',
    provider_content_filter: 'genai_provider_content_filter',
    provider_network_error: 'genai_provider_network_error',
    provider_unknown_error: 'genai_provider_unknown_error',
  };

  return codes[category];
}

export function sanitizedGenAiError(args: {
  error: any;
  diagnosticId: string;
  elapsedMs: number;
  phase?: string;
}): SanitizedGenAiError {
  const category = categorizeGenAiError(args.error);
  const attempts = Number(args.error?.genai_attempt_count);

  return {
    message: 'GenAI provider request failed',
    code: errorCodeForCategory(category),
    category,
    retryable: isRetryableGenAiError(args.error),
    diagnostic_id: args.diagnosticId,
    elapsed_ms: args.elapsedMs,
    provider_status: providerStatus(args.error),
    provider_code: providerCode(args.error),
    provider_attempt_count:
      Number.isFinite(attempts) && attempts > 0 ? attempts : undefined,
    phase: args.phase ? String(args.phase).slice(0, 120) : undefined,
  };
}
