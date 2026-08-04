import { InvService } from './inv.service';

describe('InvService Responses API attachments', () => {
  let service: any;
  let filesCreate: jest.Mock;
  let filesDelete: jest.Mock;
  let responsesCreate: jest.Mock;

  beforeEach(() => {
    process.env.GENAI_MAX_ATTEMPTS = '1';
    filesCreate = jest.fn().mockResolvedValue({ id: 'file-image-123' });
    filesDelete = jest.fn().mockResolvedValue({
      id: 'file-image-123',
      deleted: true,
    });
    responsesCreate = jest
      .fn()
      .mockResolvedValue({ output_text: '{"document_kind":"photo"}' });

    service = Object.create(InvService.prototype);
    service.genaiApiStyle = 'responses';
    service.genaiDeployment = 'test-deployment';
    service.genaiClient = {
      files: {
        create: filesCreate,
        delete: filesDelete,
      },
      responses: {
        create: responsesCreate,
      },
    };
    service.downloadBlob = jest.fn();
    jest.spyOn(console, 'log').mockImplementation();
    jest.spyOn(console, 'error').mockImplementation();
    jest.spyOn(console, 'warn').mockImplementation();
  });

  afterEach(() => {
    jest.restoreAllMocks();
    delete process.env.GENAI_MAX_ATTEMPTS;
  });

  it('sends a JPEG as an inline Responses image', async () => {
    service.downloadBlob.mockResolvedValue({
      content_type: 'image/jpeg',
      filename: 'before.jpg',
      buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    });

    const result = await service.genai(prompt(), [
      attachment('before.jpg', 'evidence/before.jpg'),
    ]);

    expect(result).toEqual({ document_kind: 'photo' });
    expect(filesCreate).not.toHaveBeenCalled();
    expect(filesDelete).not.toHaveBeenCalled();

    const request = responsesCreate.mock.calls[0][0];
    const imagePart = request.input
      .flatMap((item: any) => item.content || [])
      .find((part: any) => part.type === 'input_image');
    expect(imagePart).toEqual({
      type: 'input_image',
      image_url: 'data:image/jpeg;base64,/9j/2Q==',
      detail: 'auto',
    });
    expect(JSON.stringify(request)).toContain('data:image/jpeg;base64');
  });

  it('keeps PDF attachments inline without a provider file upload', async () => {
    service.downloadBlob.mockResolvedValue({
      content_type: 'application/pdf',
      filename: 'invoice.pdf',
      buffer: Buffer.from('%PDF-test'),
    });

    await service.genai(prompt(), [
      attachment('invoice.pdf', 'evidence/invoice.pdf'),
    ]);

    expect(filesCreate).not.toHaveBeenCalled();
    expect(filesDelete).not.toHaveBeenCalled();
    const request = responsesCreate.mock.calls[0][0];
    const filePart = request.input
      .flatMap((item: any) => item.content || [])
      .find((part: any) => part.type === 'input_file');
    expect(filePart).toMatchObject({
      type: 'input_file',
      filename: 'invoice.pdf',
    });
    expect(filePart.file_data).toMatch(/^data:application\/pdf;base64,/);
  });

  it('does not create a provider file when the response request fails', async () => {
    service.downloadBlob.mockResolvedValue({
      content_type: 'image/jpeg',
      filename: 'after.jpg',
      buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    });
    responsesCreate.mockRejectedValue(
      Object.assign(new Error('provider unavailable'), {
        status: 503,
        code: 'service_unavailable',
      }),
    );

    await expect(
      service.genai(prompt(), [attachment('after.jpg', 'evidence/after.jpg')]),
    ).rejects.toBeDefined();

    expect(filesCreate).not.toHaveBeenCalled();
    expect(filesDelete).not.toHaveBeenCalled();
  });

  it('returns a structured retryable error when model output is not JSON', async () => {
    responsesCreate.mockResolvedValue({
      output_text: 'I found an invoice, but this is not JSON.',
    });

    await expect(service.genai(prompt())).rejects.toMatchObject({
      status: 503,
    });

    try {
      await service.genai(prompt(), [], { step_type: 'classifier_files' });
    } catch (error: any) {
      expect(error.getResponse()).toMatchObject({
        message: 'Model output was not valid JSON',
        code: 'genai_model_output_invalid_json',
        category: 'model_output_invalid_json',
        retryable: true,
        phase: 'classifier_files',
        output_chars: expect.any(Number),
        snippet: 'I found an invoice, but this is not JSON.',
      });
    }
  });

  function prompt() {
    return [
      {
        role: 'system',
        content: [
          {
            type: 'input_text',
            text: 'Return strict JSON.',
          },
        ],
      },
      {
        role: 'user',
        content: [
          {
            type: 'input_text',
            text: 'Classify the attached document.',
          },
        ],
      },
    ];
  }

  function attachment(filename: string, storageKey: string) {
    return {
      type: 'input_file',
      filename,
      storageKey,
    };
  }
});
