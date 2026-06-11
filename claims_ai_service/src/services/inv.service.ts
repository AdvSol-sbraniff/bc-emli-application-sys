// 2023 standard - old
// import { AzureKeyCredential, DocumentAnalysisClient } from '@azure/ai-form-recognizer';
import { HttpException, HttpStatus } from '@nestjs/common';

import { Injectable } from '@nestjs/common';
import DocumentIntelligence, {
  getLongRunningPoller,
  isUnexpected,
} from '@azure-rest/ai-document-intelligence';
import { AzureKeyCredential } from '@azure/core-auth';
import OpenAI from 'openai';

import { BlobServiceClient } from '@azure/storage-blob';
import * as crypto from 'crypto';
import {
  GenAiApiStyle,
  extractChatCompletionText,
  extractJsonPayloadText,
  getGenAiApiStyleFromEnv,
  stripThinkBlocks,
  toChatMessages,
  toResponsesInputAndInstructions,
} from './genai-api';

import {
  BlobSASPermissions,
  generateBlobSASQueryParameters,
  SASProtocol,
  StorageSharedKeyCredential,
} from '@azure/storage-blob';

@Injectable()
export class InvService {
  //the constructor reserved def for build ONCE on nest load
  private readonly client: ReturnType<typeof DocumentIntelligence>;

  private readonly genaiClient: OpenAI;
  private readonly genaiDeployment: string;
  private readonly genaiApiStyle: GenAiApiStyle;

  private readonly blobSvc: BlobServiceClient;
  private readonly defaultContainer: string;

  constructor() {
    const endpoint = process.env.DOCINTEL_ENDPOINT;
    const key = process.env.DOCINTEL_KEY;

    if (!endpoint || !key) {
      throw new Error('Missing DOCINTEL_ENDPOINT or DOCINTEL_KEY');
    }

    // REST-style client (latest standard)
    // Note: the library defaults to apiVersion 2024-11-30, so you usually don't need to set it. :contentReference[oaicite:3]{index=3}
    this.client = DocumentIntelligence(endpoint, new AzureKeyCredential(key));

    // ---- GenAI (OpenAI SDK, Responses API) ----
    const genaiBaseUrl = process.env.GENAI_BASE_URL;
    const genaiKey = process.env.GENAI_KEY;
    const genaiDeployment = process.env.GENAI_DEPLOYMENT;

    if (!genaiBaseUrl || !genaiKey || !genaiDeployment) {
      throw new Error(
        'Missing GENAI_BASE_URL and/or GENAI_KEY and/or GENAI_DEPLOYMENT',
      );
    }

    this.genaiDeployment = genaiDeployment;
    this.genaiApiStyle = getGenAiApiStyleFromEnv();

    // build once at Nest load
    this.genaiClient = new OpenAI({
      apiKey: genaiKey,
      baseURL: genaiBaseUrl,
    });

    // ---- Azure Blob (Node owns Azure) ----
    const conn = process.env.AZURE_STORAGE_CONNECTION_STRING;
    const container = process.env.AZURE_BLOB_CONTAINER || 'inv-pdfs-dev';

    if (!conn) {
      throw new Error('Missing AZURE_STORAGE_CONNECTION_STRING');
    }

    this.blobSvc = BlobServiceClient.fromConnectionString(conn);
    this.defaultContainer = container;
  }

  async uploadPdfToBlob(args: {
    sessionId: string;
    invoiceVersionId: string;
    container?: string;
    filename?: string;
    buffer: Buffer;
    contentType: string;
    originalName?: string;
  }) {
    const containerName = (args.container || this.defaultContainer).trim();
    const filename = (args.filename || 'original.PDF').trim();

    // enforce your convention exactly
    const storageKey = `sessions/${args.sessionId}/pdfs/${args.invoiceVersionId}/${filename}`;

    const sha256 = crypto
      .createHash('sha256')
      .update(args.buffer)
      .digest('hex');

    const containerClient = this.blobSvc.getContainerClient(containerName);
    // optional: ensure container exists (safe for dev; you can remove later)
    await containerClient.createIfNotExists();

    const blobClient = containerClient.getBlockBlobClient(storageKey);

    const uploadResp = await blobClient.uploadData(args.buffer, {
      blobHTTPHeaders: {
        blobContentType: args.contentType || 'application/pdf',
      },
      metadata: {
        original_name: (args.originalName || '').slice(0, 200),
        sha256,
      },
    });

    // eTag is usually quoted; normalize
    const etag = (uploadResp.etag || '').replace(/"/g, '');

    return {
      ok: true,
      container: containerName,
      storage_key: storageKey,
      byte_size: args.buffer.length,
      sha256,
      etag,
      url: blobClient.url, // NOTE: this is NOT a SAS url; just the base blob URL
    };
  }

  async uploadSupportingPdfToBlob(args: {
    sessionId: string;
    invoiceId: string;
    supportingDocumentId: string;
    container?: string;
    filename?: string;
    buffer: Buffer;
    contentType: string;
    originalName?: string;
  }) {
    const containerName = (args.container || this.defaultContainer).trim();
    const filename = (
      args.filename ||
      args.originalName ||
      'supporting-document.PDF'
    ).trim();
    const storageKey = `sessions/${args.sessionId}/invoices/${args.invoiceId}/supporting-documents/${args.supportingDocumentId}/${filename}`;

    const sha256 = crypto
      .createHash('sha256')
      .update(args.buffer)
      .digest('hex');

    const containerClient = this.blobSvc.getContainerClient(containerName);
    await containerClient.createIfNotExists();

    const blobClient = containerClient.getBlockBlobClient(storageKey);

    const uploadResp = await blobClient.uploadData(args.buffer, {
      blobHTTPHeaders: {
        blobContentType: args.contentType || 'application/pdf',
      },
      metadata: {
        original_name: (args.originalName || '').slice(0, 200),
        sha256,
      },
    });

    const etag = (uploadResp.etag || '').replace(/"/g, '');

    return {
      ok: true,
      container: containerName,
      storage_key: storageKey,
      byte_size: args.buffer.length,
      sha256,
      etag,
      url: blobClient.url,
    };
  }

  async deleteBlob(args: { container?: string; storageKey: string }) {
    const containerName = (args.container || this.defaultContainer).trim();
    const storageKey = (args.storageKey || '').trim();
    if (!storageKey) throw new Error('Missing storageKey');

    const containerClient = this.blobSvc.getContainerClient(containerName);
    const blobClient = containerClient.getBlockBlobClient(storageKey);
    await blobClient.deleteIfExists();

    return {
      ok: true,
      container: containerName,
      storage_key: storageKey,
    };
  }

  // ============================================================
  // SECTION 30 - Azure Blob helpers (NO SAS INPUT FROM CLIENT)
  // PURPOSE:
  // - Mint a short-lived read-only SAS URL for a blob
  // - Download blob bytes for Document Intelligence
  // ============================================================

  // ============================================================
  // SECTION 30.01 - Parse connection string for shared key cred
  // NOTES:
  // - We already require AZURE_STORAGE_CONNECTION_STRING
  // - DI needs a SAS URL; easiest is shared key SAS
  // ============================================================

  private parseConnStringForSharedKey(conn: string): {
    accountName: string;
    accountKey: string;
  } {
    const parts = conn
      .split(';')
      .map((s) => s.trim())
      .filter(Boolean);
    const map: Record<string, string> = {};
    for (const p of parts) {
      const idx = p.indexOf('=');
      if (idx > 0) map[p.slice(0, idx)] = p.slice(idx + 1);
    }

    const accountName = map['AccountName'];
    const accountKey = map['AccountKey'];

    if (!accountName || !accountKey) {
      throw new Error(
        'AZURE_STORAGE_CONNECTION_STRING missing AccountName/AccountKey (required for SAS minting)',
      );
    }

    return { accountName, accountKey };
  }

  // ============================================================
  // SECTION 30.02 - Mint SAS URL for a blob
  // DEFAULTS:
  // - read-only permissions
  // - short TTL (10 minutes)
  // ============================================================

  private async buildBlobSasUrl(
    container: string,
    storageKey: string,
  ): Promise<string> {
    const conn = process.env.AZURE_STORAGE_CONNECTION_STRING;
    if (!conn) throw new Error('Missing AZURE_STORAGE_CONNECTION_STRING');

    const { accountName, accountKey } = this.parseConnStringForSharedKey(conn);
    const sharedKey = new StorageSharedKeyCredential(accountName, accountKey);

    // Use existing client to build blob URL reliably
    const containerClient = this.blobSvc.getContainerClient(container);
    const blobClient = containerClient.getBlockBlobClient(storageKey);

    const startsOn = new Date(Date.now() - 2 * 60 * 1000); // backdate 2 min (clock skew)
    const expiresOn = new Date(Date.now() + 10 * 60 * 1000); // 10 min TTL

    const sas = generateBlobSASQueryParameters(
      {
        containerName: container,
        blobName: storageKey,
        permissions: BlobSASPermissions.parse('r'), // read-only
        startsOn,
        expiresOn,
        protocol: SASProtocol.Https,
      },
      sharedKey,
    ).toString();

    return `${blobClient.url}?${sas}`;
  }

  private async runDiAnalyzeFromUrl(sasUrl: string, modelId: string) {
    const initialResponse = await this.client
      .path('/documentModels/{modelId}:analyze', modelId)
      .post({
        body: { urlSource: sasUrl },
        contentType: 'application/json',
      });

    if (isUnexpected(initialResponse)) {
      throw new Error(
        `Document Intelligence error: ${JSON.stringify(initialResponse.body)}`,
      );
    }

    const poller = getLongRunningPoller(this.client, initialResponse);
    const finalResponse = await poller.pollUntilDone();

    const di_raw_json =
      (finalResponse as any)?.body?.analyzeResult ??
      (finalResponse as any)?.body;
    return { di_raw_json };
  }

  private async runDiAnalyzeFromBytes(pdfBuffer: Buffer, modelId: string) {
    const initialResponse = await this.client
      .path('/documentModels/{modelId}:analyze', modelId)
      .post({
        body: pdfBuffer as any,
        contentType: 'application/pdf',
      });

    if (isUnexpected(initialResponse)) {
      throw new Error(
        `Document Intelligence error: ${JSON.stringify(initialResponse.body)}`,
      );
    }

    const poller = getLongRunningPoller(this.client, initialResponse);
    const finalResponse = await poller.pollUntilDone();

    const di_raw_json =
      (finalResponse as any)?.body?.analyzeResult ??
      (finalResponse as any)?.body;
    return { di_raw_json };
  }

  async ocrByBlob(args: {
    container?: string;
    storageKey: string;
    modelId: string;
  }) {
    const container = (
      args.container ??
      process.env.AZURE_BLOB_CONTAINER ??
      this.defaultContainer ??
      'inv-pdfs-dev'
    ).trim();

    const storageKey = (args.storageKey ?? '').trim();
    if (!storageKey) throw new Error('Missing storageKey');

    const containerClient = this.blobSvc.getContainerClient(container);
    const blobClient = containerClient.getBlockBlobClient(storageKey);
    const pdfBuffer = await blobClient.downloadToBuffer();

    // Send bytes directly so private-only storage does not need to be reachable by DI.
    const { di_raw_json } = await this.runDiAnalyzeFromBytes(
      pdfBuffer,
      args.modelId,
    );

    return {
      ok: true,
      container,
      storage_key: storageKey,
      di_raw_json,
    };
  }

  async mintSasUrl(args: { container?: string; storageKey: string }) {
    const container = (
      args.container ??
      process.env.AZURE_BLOB_CONTAINER ??
      this.defaultContainer ??
      'inv-pdfs-dev'
    ).trim();

    const storageKey = (args.storageKey ?? '').trim();
    if (!storageKey) throw new Error('Missing storageKey');

    const sasUrl = await this.buildBlobSasUrl(container, storageKey);

    return {
      ok: true,
      container,
      storage_key: storageKey,
      sas_url: sasUrl,
    };
  }

  async downloadBlob(args: { container?: string; storageKey: string }) {
    const container = (
      args.container ??
      process.env.AZURE_BLOB_CONTAINER ??
      this.defaultContainer ??
      'inv-pdfs-dev'
    ).trim();

    const storageKey = (args.storageKey ?? '').trim();
    if (!storageKey) throw new Error('Missing storageKey');

    const containerClient = this.blobSvc.getContainerClient(container);
    const blobClient = containerClient.getBlockBlobClient(storageKey);
    const [properties, buffer] = await Promise.all([
      blobClient.getProperties(),
      blobClient.downloadToBuffer(),
    ]);

    return {
      container,
      storage_key: storageKey,
      content_type: properties.contentType || 'application/pdf',
      byte_size: buffer.length,
      filename: storageKey.split('/').pop() || 'document.pdf',
      buffer,
    };
  }

  // start HelloWorld
  async HelloWorld(): Promise<{ message: string }> {
    console.log('service.HelloWorld: exiting');
    return { message: 'hello from InvService' };
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
  }

  private retryAfterMs(error: any): number | undefined {
    const retryAfter =
      error?.headers?.get?.('retry-after') ??
      error?.headers?.['retry-after'] ??
      error?.response?.headers?.['retry-after'];

    if (!retryAfter) return undefined;

    const seconds = Number(retryAfter);
    if (Number.isFinite(seconds)) return Math.max(0, seconds * 1000);

    const dateMs = Date.parse(String(retryAfter));
    if (Number.isFinite(dateMs)) return Math.max(0, dateMs - Date.now());

    return undefined;
  }

  private isRetryableGenAiError(error: any): boolean {
    const status = error?.status ?? error?.response?.status;
    return (
      status === 429 ||
      status === 500 ||
      status === 502 ||
      status === 503 ||
      status === 504
    );
  }

  private async withGenAiRetries<T>(operation: () => Promise<T>): Promise<T> {
    const maxAttempts = Number(process.env.GENAI_MAX_ATTEMPTS || 6);
    const baseDelayMs = Number(process.env.GENAI_RETRY_BASE_MS || 5000);
    const maxDelayMs = Number(process.env.GENAI_RETRY_MAX_MS || 60000);

    for (let attempt = 1; ; attempt += 1) {
      try {
        return await operation();
      } catch (error: any) {
        if (attempt >= maxAttempts || !this.isRetryableGenAiError(error)) {
          throw error;
        }

        const retryAfterMs = this.retryAfterMs(error);
        const backoffMs = Math.min(
          maxDelayMs,
          baseDelayMs * Math.pow(2, attempt - 1),
        );
        const jitterMs = Math.floor(Math.random() * 1000);
        const delayMs = retryAfterMs ?? backoffMs + jitterMs;
        const status = error?.status ?? error?.response?.status ?? 'unknown';

        console.warn(
          `GenAI request failed with status ${status}; retrying attempt ${attempt + 1}/${maxAttempts} in ${delayMs}ms`,
        );
        await this.sleep(delayMs);
      }
    }
  }

  // called from curl for troubleshooting
  async genaiHelloWorld(): Promise<{ message: string }> {
    const arrConversation: any[] = [];

    const recConversationSystem = {
      role: 'system',
      content: [
        {
          type: 'input_text',
          text: 'You are a helpful assistant. Keep it short.',
        },
      ],
    };
    arrConversation.push(recConversationSystem);

    const recConversationUser = {
      role: 'user',
      content: [{ type: 'input_text', text: 'Say hello to Stephen.' }],
    };
    arrConversation.push(recConversationUser);

    let message = '';

    if (this.genaiApiStyle === 'responses') {
      const resp = await this.withGenAiRetries(() =>
        this.genaiClient.responses.create({
          model: this.genaiDeployment,
          input: arrConversation,
        }),
      );
      message = resp.output_text ?? '';
    } else {
      const resp = await this.withGenAiRetries(() =>
        this.genaiClient.chat.completions.create({
          model: this.genaiDeployment,
          messages: [
            {
              role: 'system',
              content: 'You are a helpful assistant. Keep it short.',
            },
            {
              role: 'user',
              content: 'Say hello to Stephen.',
            },
          ],
        }),
      );
      message = extractChatCompletionText(resp);
    }
    console.log('genaiDeployment was', this.genaiDeployment);
    console.log('service.genaiHelloWorld: exiting');
    return { message: stripThinkBlocks(message).trim() };
  }

  async genai(contextwindowjson: any, attachments: any[] = []): Promise<any> {
    let raw = '';

    if (this.genaiApiStyle === 'responses') {
      const responsesPrompt =
        toResponsesInputAndInstructions(contextwindowjson);
      const responsesInput = await this.withInputFileAttachments(
        responsesPrompt.input,
        attachments,
      );
      const resp = await this.withGenAiRetries(() =>
        this.genaiClient.responses.create({
          model: this.genaiDeployment,
          instructions: responsesPrompt.instructions,
          input: responsesInput,
        }),
      );
      raw = resp.output_text ?? '';
    } else {
      const resp = await this.withGenAiRetries(() =>
        this.genaiClient.chat.completions.create({
          model: this.genaiDeployment,
          messages: toChatMessages(contextwindowjson),
        }),
      );
      raw = extractChatCompletionText(resp);
    }

    const candidate = extractJsonPayloadText(raw);

    // Return the model JSON verbatim
    try {
      return JSON.parse(candidate);
    } catch {
      // Thin, but not silent: tell Rails exactly what happened
      throw new HttpException(
        {
          message: 'Model output was not valid JSON',
          snippet: stripThinkBlocks(raw).slice(0, 2000), // keep it bounded
        },
        HttpStatus.UNPROCESSABLE_ENTITY, // 422
      );
    }
  }

  private async withInputFileAttachments(
    input: any[],
    attachments: any[],
  ): Promise<any[]> {
    if (!Array.isArray(attachments) || attachments.length === 0) return input;

    const attachmentParts = [];
    for (const attachment of attachments) {
      if (!attachment || attachment.type !== 'input_file') continue;

      const storageKey = String(attachment.storageKey || '').trim();
      if (!storageKey) continue;

      const blob = await this.downloadBlob({
        container: attachment.container,
        storageKey,
      });
      const contentType = blob.content_type || 'application/pdf';
      const filename =
        String(attachment.filename || blob.filename || 'document.pdf').trim() ||
        'document.pdf';

      attachmentParts.push({
        type: 'input_text',
        text: `Attached supporting document PDF: ${filename}`,
      });
      attachmentParts.push({
        type: 'input_file',
        filename,
        file_data: `data:${contentType};base64,${blob.buffer.toString('base64')}`,
      });
    }

    if (attachmentParts.length === 0) return input;

    return [
      ...input,
      {
        type: 'message',
        role: 'user',
        content: attachmentParts,
      },
    ];
  }

  // end service layer class
}
