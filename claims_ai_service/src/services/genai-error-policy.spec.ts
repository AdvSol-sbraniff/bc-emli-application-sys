import {
  categorizeGenAiError,
  errorCodeForCategory,
  isRetryableGenAiError,
  sanitizedGenAiError,
} from './genai-error-policy';

describe('GenAI error policy', () => {
  it('classifies an invalid image as permanent and safe to report', () => {
    const error = {
      status: 400,
      code: 'invalid_value',
      message: 'Invalid image data: unsupported image format.',
      genai_attempt_count: 1,
    };

    expect(categorizeGenAiError(error)).toBe('provider_invalid_image');
    expect(isRetryableGenAiError(error)).toBe(false);
    expect(errorCodeForCategory('provider_invalid_image')).toBe(
      'genai_input_image_invalid',
    );
    expect(
      sanitizedGenAiError({
        error,
        diagnosticId: 'diag-123',
        elapsedMs: 42,
        phase: 'classifier_files',
      }),
    ).toEqual({
      message: 'GenAI provider request failed',
      code: 'genai_input_image_invalid',
      category: 'provider_invalid_image',
      retryable: false,
      diagnostic_id: 'diag-123',
      elapsed_ms: 42,
      provider_status: 400,
      provider_code: 'invalid_value',
      provider_attempt_count: 1,
      phase: 'classifier_files',
    });
  });

  it('marks throttling and provider outages as retryable', () => {
    expect(isRetryableGenAiError({ status: 429 })).toBe(true);
    expect(isRetryableGenAiError({ status: 503 })).toBe(true);
    expect(isRetryableGenAiError({ code: 'ECONNRESET' })).toBe(true);
  });

  it('does not expose the raw provider response in the safe envelope', () => {
    const safe = sanitizedGenAiError({
      error: {
        status: 400,
        response: {
          data: {
            message: 'Invalid image containing private raw details.',
          },
        },
      },
      diagnosticId: 'diag-private',
      elapsedMs: 10,
    });

    expect(JSON.stringify(safe)).not.toContain('private raw details');
  });
});
