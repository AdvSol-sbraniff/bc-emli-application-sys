import { HttpException } from '@nestjs/common';
import { createHash } from 'crypto';
import {
  RULE_AUDIT_OUTPUT_SCHEMA,
  runRuleAudit,
  validateRuleAuditOutput,
} from './rule-audit';

describe('Rule package audit transport', () => {
  const output = {
    advice: 'The decision is supported; no change is justified.',
    proposed_rule_prompt: null,
    proposed_precheck_action: null,
    proposed_contractor_guidance: null,
  };
  const context = [
    {
      role: 'system',
      content: [{ type: 'input_text', text: 'Audit the supplied evidence.' }],
    },
    {
      role: 'user',
      content: [
        {
          type: 'input_text',
          text: JSON.stringify({
            record_type: 'workflow_history',
            comment: 'Please explain which supporting evidence is required.',
          }),
        },
      ],
    },
  ];
  const file = {
    type: 'input_file' as const,
    storageKey: 'evidence/source.pdf',
    filename: 'source_file_1_invoice.pdf',
    reference: 'source_file_1',
    occurrences: [
      { source_record_id: 'version-1', source_table: 'invoice_versions' },
    ],
  };
  let provider: jest.Mock;
  let download: jest.Mock;
  let deps: any;

  beforeEach(() => {
    provider = jest.fn().mockResolvedValue(completed(output));
    download = jest.fn().mockResolvedValue({
      buffer: Buffer.from('%PDF-real-test-bytes'),
      content_type: 'application/pdf',
      filename: 'source.pdf',
    });
    deps = {
      apiStyle: 'responses',
      defaultDeployment: 'fallback-model',
      downloadFile: download,
      createResponse: provider,
    };
    jest.spyOn(console, 'log').mockImplementation();
    jest.spyOn(console, 'error').mockImplementation();
  });

  afterEach(() => {
    jest.restoreAllMocks();
    for (const key of Object.keys(process.env)) {
      if (key.startsWith('RULE_AUDIT_')) delete process.env[key];
    }
  });

  it('sends strict structured output, complete faux records and the actual PDF bytes', async () => {
    const result = await runRuleAudit(
      {
        contextwindowjson: context,
        attachments: [file],
        deployment_name: 'comparison-model',
      },
      deps,
    );
    expect(result).toMatchObject(output);
    const [body, options] = provider.mock.calls[0];
    expect(body).toMatchObject({
      model: 'comparison-model',
      store: false,
      truncation: 'disabled',
      text: {
        format: {
          type: 'json_schema',
          name: 'rule_package_audit',
          strict: true,
          schema: RULE_AUDIT_OUTPUT_SCHEMA,
        },
      },
    });
    expect(JSON.stringify(body)).toContain(
      'Please explain which supporting evidence is required.',
    );
    const parts = body.input.flatMap((entry: any) => entry.content);
    const pdf = parts.find((part: any) => part.type === 'input_file');
    const decoded = Buffer.from(pdf.file_data.split(',')[1], 'base64');
    expect(decoded.toString()).toBe('%PDF-real-test-bytes');
    expect(result.transport).toMatchObject({
      deployment: 'comparison-model',
      attachment_count: 1,
      attachment_bytes: decoded.length,
      context_record_count: 2,
      context_sha256: digest(JSON.stringify(context)),
      provider_attempt_count: 1,
      provider_response_id: 'resp_test',
      input_tokens: 123,
      output_tokens: 45,
      omissions: [],
      attachments: [
        {
          filename: file.filename,
          sha256: digest(decoded),
          byte_size: decoded.length,
          reference: file.reference,
          occurrences: file.occurrences,
        },
      ],
    });
    expect(
      parts.find((part: any) => part.text?.includes('SOURCE FILE 1')).text,
    ).toContain(digest(decoded));
    expect(options.maxRetries).toBe(0);
    expect(options.timeout).toBeLessThanOrEqual(240_000);
    expect(options.signal).toBeInstanceOf(AbortSignal);
    expect(deps.defaultDeployment).toBe('fallback-model');
  });

  it('sends images as inline images and includes their exact-byte manifest', async () => {
    const buffer = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
    download.mockResolvedValue({
      buffer,
      content_type: 'image/jpeg',
      filename: 'photo.jpg',
    });
    const result = await audit([file]);
    const image = provider.mock.calls[0][0].input
      .flatMap((entry: any) => entry.content)
      .find((part: any) => part.type === 'input_image');
    expect(image.image_url).toBe('data:image/jpeg;base64,/9j/2Q==');
    expect(result.transport.attachments[0].sha256).toBe(digest(buffer));
  });

  it('verifies original evidence identity against known stored SHA and size', async () => {
    const bytes = Buffer.from('%PDF-real-test-bytes');
    const result = await audit([
      {
        ...file,
        expected_sha256: digest(bytes).toUpperCase(),
        expected_byte_size: bytes.length,
      },
    ]);
    expect(result.transport.attachments[0]).toMatchObject({
      expected_sha256: digest(bytes),
      expected_byte_size: bytes.length,
      sha256_verification: 'matched_stored_sha256',
      byte_size_verification: 'matched_stored_byte_size',
    });
  });

  it('explicitly marks historical identity as unverified when stored metadata is absent', async () => {
    const result = await audit([file]);
    expect(result.transport.attachments[0]).toMatchObject({
      expected_sha256: null,
      expected_byte_size: null,
      sha256_verification:
        'stored_sha256_unavailable_identity_verified_only_at_audit_read',
      byte_size_verification: 'stored_byte_size_unavailable',
    });
  });

  it.each([{ expected_sha256: '0'.repeat(64) }, { expected_byte_size: 12345 }])(
    'rejects changed evidence bytes before inference: %p',
    async (identity) => {
      await expectCode(
        audit([{ ...file, ...identity }]),
        'rule_audit_source_integrity_mismatch',
      );
      expect(provider).not.toHaveBeenCalled();
    },
  );

  it('allows missing-source cases without pretending files were attached', async () => {
    const result = await audit([]);
    expect(download).not.toHaveBeenCalled();
    expect(result.transport.attachment_count).toBe(0);
    expect(result.proposed_rule_prompt).toBeNull();
    expect(result.proposed_precheck_action).toBeNull();
    expect(result.proposed_contractor_guidance).toBeNull();
  });

  it('preserves multiple complementary proposals without applying any changes', async () => {
    const proposals = {
      ...output,
      proposed_rule_prompt: 'Complete replacement prompt.',
      proposed_precheck_action: 'Clear pre-check.',
      proposed_contractor_guidance: 'Prepare these documents.',
    };
    provider.mockResolvedValue(completed(proposals));
    expect(await audit([])).toMatchObject(proposals);
    expect(provider).toHaveBeenCalledTimes(1);
  });

  it('fails before inference if Responses is unavailable rather than dropping attachments', async () => {
    deps.apiStyle = 'chat_completions';
    await expectCode(audit([file]), 'rule_audit_responses_required');
    expect(download).not.toHaveBeenCalled();
    expect(provider).not.toHaveBeenCalled();
  });

  it.each([
    { type: 'input_file', storageKey: '' },
    { type: 'input_image', storageKey: 'some/file' },
    {
      type: 'input_file',
      storageKey: 'some/file',
      occurrences: 'not an array',
    },
    { type: 'input_file', storageKey: 'some/file', expected_sha256: 'invalid' },
    { type: 'input_file', storageKey: 'some/file', expected_byte_size: -1 },
  ])(
    'rejects malformed source references without omitting them: %p',
    async (attachment) => {
      await expectCode(audit([attachment]), 'rule_audit_invalid_attachment');
      expect(provider).not.toHaveBeenCalled();
    },
  );

  it('rejects a context over the UTF-8 byte limit before reading sources', async () => {
    process.env.RULE_AUDIT_MAX_CONTEXT_BYTES = '100';
    await expectCode(audit([file]), 'rule_audit_context_too_large');
    expect(download).not.toHaveBeenCalled();
    expect(provider).not.toHaveBeenCalled();
  });

  it('rejects unsupported message content rather than silently flattening it away', async () => {
    const input = [
      ...context,
      {
        role: 'user',
        content: [
          { type: 'input_file', file_url: 'https://example.com/invoice.pdf' },
        ],
      },
    ];
    await expectCode(
      runRuleAudit({ contextwindowjson: input }, deps),
      'rule_audit_invalid_context',
    );
    expect(provider).not.toHaveBeenCalled();
  });

  it('rejects too many files before any downloads', async () => {
    process.env.RULE_AUDIT_MAX_FILES = '1';
    await expectCode(audit([file, file]), 'rule_audit_attachment_limit');
    expect(download).not.toHaveBeenCalled();
  });

  it('rejects an individual oversized file and never invokes the model', async () => {
    process.env.RULE_AUDIT_MAX_FILE_BYTES = '5';
    await expectCode(audit([file]), 'rule_audit_files_too_large');
    expect(download.mock.calls[0][1]).toBe(5);
    expect(provider).not.toHaveBeenCalled();
  });

  it('checks total bytes as well as individual files and passes the remaining budget to downloads', async () => {
    process.env.RULE_AUDIT_MAX_TOTAL_FILE_BYTES = '30';
    await expectCode(audit([file, file]), 'rule_audit_files_too_large');
    expect(download.mock.calls[1][1]).toBe(
      30 - Buffer.byteLength('%PDF-real-test-bytes'),
    );
    expect(provider).not.toHaveBeenCalled();
  });

  it.each(['text/html', 'application/zip'])(
    'rejects unsupported source type %s',
    async (content_type) => {
      download.mockResolvedValue({
        buffer: Buffer.from('content'),
        filename: 'source',
        content_type,
      });
      await expectCode(audit([file]), 'rule_audit_unsupported_source');
      expect(provider).not.toHaveBeenCalled();
    },
  );

  it('stops at an unreadable file and sanitizes storage error details', async () => {
    download.mockRejectedValue(new Error('secret-sas-token provider detail'));
    await expectCode(audit([file]), 'rule_audit_source_unavailable');
    expect(provider).not.toHaveBeenCalled();
    expect(
      JSON.stringify((console.error as jest.Mock).mock.calls),
    ).not.toContain('secret-sas-token');
  });

  it('rejects partial advice even if it is valid JSON', async () => {
    provider.mockResolvedValue({
      ...completed(output),
      status: 'incomplete',
      incomplete_details: { reason: 'max_output_tokens' },
    });
    await expectCode(audit([]), 'rule_audit_incomplete');
  });

  it('recognises refusal separately from invalid JSON', async () => {
    provider.mockResolvedValue({
      status: 'completed',
      output: [
        {
          type: 'message',
          content: [{ type: 'refusal', refusal: 'private text' }],
        },
      ],
      output_text: '',
    });
    await expectCode(audit([]), 'rule_audit_refused');
    expect(
      JSON.stringify((console.error as jest.Mock).mock.calls),
    ).not.toContain('private text');
  });

  it.each([
    'not json',
    JSON.stringify({ ...output, advice: '' }),
    JSON.stringify({ ...output, proposed_rule_prompt: 42 }),
    JSON.stringify({ advice: 'missing nullable fields' }),
    JSON.stringify({ ...output, extra: 'unexpected field' }),
  ])('rejects malformed output %s', async (output_text) => {
    provider.mockResolvedValue({ ...completed(output), output_text });
    await expectCode(audit([]), 'rule_audit_invalid_output');
    expect(provider).toHaveBeenCalledTimes(1);
  });

  it('retries transient provider errors at most once with SDK retries disabled', async () => {
    provider.mockRejectedValueOnce(
      Object.assign(new Error('unavailable'), { status: 503 }),
    );
    const result = await audit([]);
    expect(provider).toHaveBeenCalledTimes(2);
    expect(result.transport.provider_attempt_count).toBe(2);
  });

  it('returns a sanitized provider error without exposing its response', async () => {
    provider.mockRejectedValue(
      Object.assign(new Error('secret-key provider failure'), {
        status: 401,
        code: 'invalid_api_key',
      }),
    );
    await expectCode(audit([]), 'genai_provider_auth_error');
    expect(provider).toHaveBeenCalledTimes(1);
    expect(
      JSON.stringify((console.error as jest.Mock).mock.calls),
    ).not.toContain('secret-key');
  });

  it('cancels the provider request and stops without waiting on a stalled dependency', async () => {
    const cancellation = new AbortController();
    provider.mockImplementation(() => {
      cancellation.abort();
      return new Promise(() => undefined);
    });
    await expectCode(
      runRuleAudit(
        { contextwindowjson: context, signal: cancellation.signal },
        deps,
      ),
      'rule_audit_cancelled',
    );
    expect(provider.mock.calls[0][1].signal.aborted).toBe(true);
  });

  it('bounds total runtime and aborts downloads as well as provider calls', async () => {
    process.env.RULE_AUDIT_TIMEOUT_MS = '10';
    download.mockImplementation(() => new Promise(() => undefined));
    await expectCode(audit([file]), 'rule_audit_timeout');
    expect(download.mock.calls[0][2].aborted).toBe(true);
    expect(provider).not.toHaveBeenCalled();
  });

  it('rejects invalid operator limits rather than unexpectedly lifting them', async () => {
    process.env.RULE_AUDIT_MAX_FILES = '999999';
    await expectCode(audit([]), 'rule_audit_invalid_configuration');
    expect(provider).not.toHaveBeenCalled();
  });

  it('runtime validation rejects a blank or unbounded proposal', () => {
    expect(() =>
      validateRuleAuditOutput({ ...output, proposed_rule_prompt: ' ' }),
    ).toThrow(HttpException);
    expect(() =>
      validateRuleAuditOutput({ ...output, advice: 'a'.repeat(60_001) }),
    ).toThrow(HttpException);
  });

  function audit(attachments: any[]) {
    return runRuleAudit({ contextwindowjson: context, attachments }, deps);
  }

  function completed(value: unknown) {
    return {
      id: 'resp_test',
      status: 'completed',
      output: [],
      output_text: JSON.stringify(value),
      usage: { input_tokens: 123, output_tokens: 45 },
    };
  }

  function digest(value: string | Buffer) {
    return createHash('sha256').update(value).digest('hex');
  }

  async function expectCode(promise: Promise<unknown>, code: string) {
    try {
      await promise;
      throw new Error(`Expected ${code}, but request succeeded`);
    } catch (error: any) {
      expect(error).toBeInstanceOf(HttpException);
      expect(error.getResponse()).toMatchObject({
        code,
        diagnostic_id: expect.stringMatching(/^rule_audit_/),
        provider_attempt_count: expect.any(Number),
      });
    }
  }
});
