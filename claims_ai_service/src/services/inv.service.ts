// 2023 standard - old
// import { AzureKeyCredential, DocumentAnalysisClient } from '@azure/ai-form-recognizer';
import { HttpException, HttpStatus } from '@nestjs/common';

import { Injectable } from '@nestjs/common';
import DocumentIntelligence, {
  getLongRunningPoller,
  isUnexpected,
} from '@azure-rest/ai-document-intelligence';
import { AzureKeyCredential } from '@azure/core-auth';
import OpenAI, { toFile } from 'openai';

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
  isRetryableGenAiError,
  providerCode,
  providerStatus,
  sanitizedGenAiError,
} from './genai-error-policy';

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
    const blobContentType =
      args.contentType && args.contentType !== 'application/octet-stream'
        ? args.contentType
        : this.contentTypeFromStorageKey(filename) ||
          args.contentType ||
          'application/pdf';

    const uploadResp = await blobClient.uploadData(args.buffer, {
      blobHTTPHeaders: {
        blobContentType,
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
    const blobContentType =
      args.contentType && args.contentType !== 'application/octet-stream'
        ? args.contentType
        : this.contentTypeFromStorageKey(filename) ||
          args.contentType ||
          'application/pdf';

    const uploadResp = await blobClient.uploadData(args.buffer, {
      blobHTTPHeaders: {
        blobContentType,
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

  private async runDiAnalyzeFromBytes(
    fileBuffer: Buffer,
    modelId: string,
    contentType: string,
  ) {
    const initialResponse = await this.client
      .path('/documentModels/{modelId}:analyze', modelId)
      .post({
        body: fileBuffer as any,
        contentType: contentType as any,
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
    const [fileBuffer, properties] = await Promise.all([
      blobClient.downloadToBuffer(),
      blobClient.getProperties(),
    ]);
    const contentType =
      properties.contentType ||
      this.contentTypeFromStorageKey(storageKey) ||
      'application/pdf';

    // Send bytes directly so private-only storage does not need to be reachable by DI.
    const { di_raw_json } = await this.runDiAnalyzeFromBytes(
      fileBuffer,
      args.modelId,
      contentType,
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
      content_type:
        properties.contentType ||
        this.contentTypeFromStorageKey(storageKey) ||
        'application/pdf',
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

  private contentTypeFromStorageKey(storageKey: string): string | undefined {
    const lower = storageKey.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    return undefined;
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

  private async withGenAiRetries<T>(operation: () => Promise<T>): Promise<T> {
    const maxAttempts = Number(process.env.GENAI_MAX_ATTEMPTS || 2);
    const baseDelayMs = Number(process.env.GENAI_RETRY_BASE_MS || 5000);
    const maxDelayMs = Number(process.env.GENAI_RETRY_MAX_MS || 60000);

    for (let attempt = 1; ; attempt += 1) {
      try {
        return await operation();
      } catch (error: any) {
        error.genai_attempt_count = attempt;
        if (attempt >= maxAttempts || !isRetryableGenAiError(error)) {
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

  private genAiDiagnosticId(): string {
    const timestamp = new Date()
      .toISOString()
      .replace(/[-:.]/g, '')
      .replace('T', 'T')
      .replace('Z', 'Z');
    return `genai_${timestamp}_${crypto.randomBytes(4).toString('hex')}`;
  }

  private genAiEndpointHost(): string | undefined {
    try {
      return new URL(process.env.GENAI_BASE_URL || '').host || undefined;
    } catch {
      return undefined;
    }
  }

  private boundedString(value: any, maxLength = 500): string | undefined {
    if (value === undefined || value === null) return undefined;
    let text: string;
    try {
      text = typeof value === 'string' ? value : JSON.stringify(value, null, 0);
    } catch {
      text = String(value);
    }
    return text.length > maxLength ? `${text.slice(0, maxLength)}...` : text;
  }

  private safeDiagnosticContext(context: any): Record<string, any> {
    if (!context || typeof context !== 'object' || Array.isArray(context)) {
      return {};
    }

    const safeKeys = [
      'step_type',
      'ingest_run_id',
      'ingest_document_id',
      'invoice_version_id',
      'invoice_upgrade_type_id',
      'supporting_document_group_id',
      'original_filename',
      'content_type',
    ];

    const safe: Record<string, any> = {};
    for (const key of safeKeys) {
      const value = context[key];
      if (
        typeof value === 'string' ||
        typeof value === 'number' ||
        typeof value === 'boolean'
      ) {
        safe[key] =
          typeof value === 'string' ? this.boundedString(value, 200) : value;
      }
    }

    return safe;
  }

  private genAiAttachmentSummary(attachments: any[]): Record<string, any> {
    const safeAttachments = Array.isArray(attachments) ? attachments : [];
    return {
      attachment_count: safeAttachments.length,
      attachments: safeAttachments.slice(0, 20).map((attachment) => ({
        type: this.boundedString(attachment?.type, 80),
        filename: this.boundedString(attachment?.filename, 200),
        container: this.boundedString(attachment?.container, 120),
        storage_key: this.boundedString(attachment?.storageKey, 300),
      })),
    };
  }

  private genAiInputSummary(
    contextwindowjson: any,
    attachments: any[],
    diagnosticContext: Record<string, any>,
    diagnosticId: string,
  ): Record<string, any> {
    const contextText = this.boundedString(contextwindowjson, 200_000) || '';
    return {
      event_source: 'claims_ai_service',
      diagnostic_id: diagnosticId,
      api_style: this.genaiApiStyle,
      deployment: this.genaiDeployment,
      endpoint_host: this.genAiEndpointHost(),
      context_chars: contextText.length,
      diagnostic_context: this.safeDiagnosticContext(diagnosticContext),
      ...this.genAiAttachmentSummary(attachments),
    };
  }

  private providerStatus(error: any): number | string | undefined {
    return providerStatus(error);
  }

  private providerCode(error: any): string | undefined {
    return providerCode(error);
  }

  private providerRequestId(error: any): string | undefined {
    const headers = error?.headers || error?.response?.headers || {};
    return (
      headers?.get?.('x-request-id') ||
      headers?.get?.('apim-request-id') ||
      headers?.get?.('x-ms-request-id') ||
      headers?.['x-request-id'] ||
      headers?.['apim-request-id'] ||
      headers?.['x-ms-request-id']
    );
  }

  private providerRetryAfter(error: any): string | undefined {
    const headers = error?.headers || error?.response?.headers || {};
    return (
      headers?.get?.('retry-after') ||
      headers?.['retry-after'] ||
      error?.response?.headers?.['retry-after']
    );
  }

  private providerResponseSnippet(error: any): string | undefined {
    return this.boundedString(
      error?.response?.data ?? error?.error ?? error?.message,
      700,
    );
  }

  private logGenAiDiagnostic(
    event: string,
    payload: Record<string, any>,
  ): void {
    const line = JSON.stringify({ event, ...payload });
    if (event.endsWith('.failed')) {
      console.error(line);
    } else {
      console.log(line);
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

  async genai(
    contextwindowjson: any,
    attachments: any[] = [],
    diagnosticContext: Record<string, any> = {},
  ): Promise<any> {
    const diagnosticId = this.genAiDiagnosticId();
    const startedAt = Date.now();
    const diagnosticBase = this.genAiInputSummary(
      contextwindowjson,
      attachments,
      diagnosticContext,
      diagnosticId,
    );
    let raw = '';

    this.logGenAiDiagnostic('claims.genai.request.started', diagnosticBase);

    try {
      if (this.genaiApiStyle === 'responses') {
        const responsesPrompt =
          toResponsesInputAndInstructions(contextwindowjson);
        const preparedAttachments = await this.withInputFileAttachments(
          responsesPrompt.input,
          attachments,
        );
        try {
          const resp = await this.withGenAiRetries(() =>
            this.genaiClient.responses.create({
              model: this.genaiDeployment,
              instructions: responsesPrompt.instructions,
              input: preparedAttachments.input,
            }),
          );
          raw = resp.output_text ?? '';
        } finally {
          await this.deleteProviderFiles(
            preparedAttachments.providerFileIds,
            diagnosticId,
          );
        }
      } else {
        const resp = await this.withGenAiRetries(() =>
          this.genaiClient.chat.completions.create({
            model: this.genaiDeployment,
            messages: toChatMessages(contextwindowjson),
          }),
        );
        raw = extractChatCompletionText(resp);
      }
    } catch (error: any) {
      const elapsed_ms = Date.now() - startedAt;
      const safeError = sanitizedGenAiError({
        error,
        diagnosticId,
        elapsedMs: elapsed_ms,
        phase: diagnosticContext?.step_type,
      });

      this.logGenAiDiagnostic('claims.genai.request.failed', {
        ...diagnosticBase,
        elapsed_ms,
        category: safeError.category,
        error_code: safeError.code,
        retryable: safeError.retryable,
        provider_attempt_count: safeError.provider_attempt_count,
        provider_status: this.providerStatus(error),
        provider_code: this.providerCode(error),
        provider_request_id: this.providerRequestId(error),
        retry_after: this.providerRetryAfter(error),
        provider_response_snippet: this.providerResponseSnippet(error),
      });

      throw new HttpException(
        safeError,
        safeError.retryable
          ? HttpStatus.SERVICE_UNAVAILABLE
          : HttpStatus.UNPROCESSABLE_ENTITY,
      );
    }

    this.logGenAiDiagnostic('claims.genai.request.succeeded', {
      ...diagnosticBase,
      elapsed_ms: Date.now() - startedAt,
      output_chars: raw.length,
    });

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
  ): Promise<{ input: any[]; providerFileIds: string[] }> {
    if (!Array.isArray(attachments) || attachments.length === 0) {
      return { input, providerFileIds: [] };
    }

    const attachmentParts = [];
    const providerFileIds: string[] = [];
    try {
      for (const attachment of attachments) {
        if (!attachment || attachment.type !== 'input_file') continue;

        const storageKey = String(attachment.storageKey || '').trim();
        if (!storageKey) continue;

        const blob = await this.downloadBlob({
          container: attachment.container,
          storageKey,
        });
        const contentType =
          blob.content_type ||
          this.contentTypeFromStorageKey(storageKey) ||
          'application/pdf';
        const filename =
          String(
            attachment.filename || blob.filename || 'document.pdf',
          ).trim() || 'document.pdf';

        attachmentParts.push({
          type: 'input_text',
          text: `Attached supporting document file: ${filename}`,
        });
        if (contentType === 'image/jpeg' || contentType === 'image/png') {
          const providerFile = await this.withGenAiRetries(async () =>
            this.genaiClient.files.create({
              file: await toFile(blob.buffer, filename, {
                type: contentType,
              }),
              purpose: 'assistants',
            }),
          );
          providerFileIds.push(providerFile.id);
          attachmentParts.push({
            type: 'input_image',
            file_id: providerFile.id,
            detail: 'auto',
          });
        } else {
          attachmentParts.push({
            type: 'input_file',
            filename,
            file_data: `data:${contentType};base64,${blob.buffer.toString('base64')}`,
          });
        }
      }
    } catch (error) {
      await this.deleteProviderFiles(providerFileIds);
      throw error;
    }

    if (attachmentParts.length === 0) {
      return { input, providerFileIds };
    }

    return {
      input: [
        ...input,
        {
          type: 'message',
          role: 'user',
          content: attachmentParts,
        },
      ],
      providerFileIds,
    };
  }

  private async deleteProviderFiles(
    fileIds: string[],
    diagnosticId?: string,
  ): Promise<void> {
    const uniqueFileIds = [...new Set(fileIds.filter(Boolean))];
    if (uniqueFileIds.length === 0) return;

    const results = await Promise.allSettled(
      uniqueFileIds.map((fileId) => this.genaiClient.files.delete(fileId)),
    );
    const failedCount = results.filter(
      (result) => result.status === 'rejected',
    ).length;
    if (failedCount > 0) {
      console.warn(
        `[claims][genai] diagnostic_id=${diagnosticId || '-'} failed to delete ${failedCount} temporary provider image file(s).`,
      );
    }
  }

  // end service layer class
}
