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

  it('uploads a JPEG for vision and references its file id', async () => {
    service.downloadBlob.mockResolvedValue({
      content_type: 'image/jpeg',
      filename: 'before.jpg',
      buffer: Buffer.from([0xff, 0xd8, 0xff, 0xd9]),
    });

    const result = await service.genai(prompt(), [
      attachment('before.jpg', 'evidence/before.jpg'),
    ]);

    expect(result).toEqual({ document_kind: 'photo' });
    expect(filesCreate).toHaveBeenCalledTimes(1);
    const upload = filesCreate.mock.calls[0][0];
    expect(upload).toMatchObject({ purpose: 'assistants' });
    expect(upload.file).toMatchObject({
      name: 'before.jpg',
      type: 'image/jpeg',
    });

    const request = responsesCreate.mock.calls[0][0];
    const imagePart = request.input
      .flatMap((item: any) => item.content || [])
      .find((part: any) => part.type === 'input_image');
    expect(imagePart).toEqual({
      type: 'input_image',
      file_id: 'file-image-123',
      detail: 'auto',
    });
    expect(JSON.stringify(request)).not.toContain('data:image/jpeg;base64');
    expect(filesDelete).toHaveBeenCalledWith('file-image-123');
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

  it('deletes the temporary image when the response request fails', async () => {
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

    expect(filesDelete).toHaveBeenCalledWith('file-image-123');
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
