import { InvService } from './inv.service';

describe('InvService audit source admission', () => {
  let service: any;
  let getProperties: jest.Mock;
  let downloadToBuffer: jest.Mock;
  const source = {
    type: 'input_file',
    storageKey: 'authoritative/invoice.pdf',
  };

  beforeEach(() => {
    getProperties = jest.fn().mockResolvedValue({
      contentLength: 4,
      contentType: 'application/pdf',
      etag: 'version-etag',
    });
    downloadToBuffer = jest.fn().mockResolvedValue(Buffer.from('test'));
    service = Object.create(InvService.prototype);
    service.defaultContainer = 'invoices';
    service.blobSvc = {
      getContainerClient: jest.fn().mockReturnValue({
        getBlockBlobClient: jest
          .fn()
          .mockReturnValue({ getProperties, downloadToBuffer }),
      }),
    };
  });

  it('checks source size before downloading and pins its blob ETag', async () => {
    const signal = new AbortController().signal;
    const blob = await service.downloadAuditSource(source, 10, signal);
    expect(getProperties).toHaveBeenCalledWith({ abortSignal: signal });
    expect(downloadToBuffer).toHaveBeenCalledWith(0, 4, {
      abortSignal: signal,
      conditions: { ifMatch: 'version-etag' },
    });
    expect(blob.buffer.toString()).toBe('test');
  });

  it('does not allocate or download a source exceeding remaining admission budget', async () => {
    await expect(
      service.downloadAuditSource(source, 3, new AbortController().signal),
    ).rejects.toMatchObject({ status: 413 });
    expect(downloadToBuffer).not.toHaveBeenCalled();
  });

  it('fails closed when the storage service cannot establish a source size', async () => {
    getProperties.mockResolvedValue({ contentLength: undefined });
    await expect(
      service.downloadAuditSource(source, 10, new AbortController().signal),
    ).rejects.toMatchObject({ status: 422 });
    expect(downloadToBuffer).not.toHaveBeenCalled();
  });

  it('rejects a short source download rather than attaching partial evidence', async () => {
    downloadToBuffer.mockResolvedValue(Buffer.from('te'));
    await expect(
      service.downloadAuditSource(source, 10, new AbortController().signal),
    ).rejects.toMatchObject({ status: 422 });
  });
});
