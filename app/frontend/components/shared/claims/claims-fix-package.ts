import { supportedClaimsEvidenceFiles } from './claims-evidence-files';

export type ClaimsSupportingDocument = {
  id: string;
  original_filename?: string | null;
  content_type?: string | null;
  mime_content_type?: string | null;
  byte_size?: number | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
};

export type ClaimsCurrentPackage = {
  read?: {
    id?: string;
    original_filename?: string | null;
    content_type?: string | null;
    byte_size?: number | null;
    uploaded_supporting_documents?: ClaimsSupportingDocument[];
  };
};

export type ClaimsFixPackageRow = {
  id: string;
  sourceId?: string | null;
  source: 'clone' | 'new';
  fileRole: 'invoice' | 'supporting_document' | 'auto_detect';
  filename: string;
  contentType?: string | null;
  byteSize?: number | null;
  file?: File;
  supportingType?: string | null;
};

export function buildClaimsFixPackageRows(payload: ClaimsCurrentPackage | null): ClaimsFixPackageRow[] {
  const read = payload?.read;
  const invoice: ClaimsFixPackageRow[] = read?.id
    ? [
        {
          id: `clone-invoice-${read.id}`,
          sourceId: read.id,
          source: 'clone',
          fileRole: 'invoice',
          filename: read.original_filename || 'Current invoice PDF',
          contentType: read.content_type || 'application/pdf',
          byteSize: read.byte_size,
        },
      ]
    : [];
  const supporting = (read?.uploaded_supporting_documents || []).map((document) => ({
    id: `clone-support-${document.id}`,
    sourceId: document.id,
    source: 'clone' as const,
    fileRole: 'supporting_document' as const,
    filename: document.original_filename || 'Supporting document',
    contentType: document.mime_content_type || document.content_type,
    byteSize: document.byte_size,
    supportingType: document.supporting_document_type_description || document.supporting_document_type_key,
  }));
  return [...invoice, ...supporting];
}

export function addFilesToClaimsFixPackage(existing: ClaimsFixPackageRow[], files: File[]): ClaimsFixPackageRow[] {
  const additions = supportedClaimsEvidenceFiles(files).filter(
    (file) =>
      !existing.some(
        (row) =>
          row.source === 'new' &&
          row.file?.name === file.name &&
          row.file.size === file.size &&
          row.file.lastModified === file.lastModified,
      ),
  );
  return [
    ...existing,
    ...additions.map((file) => ({
      id: makeClientId('new'),
      source: 'new' as const,
      fileRole: 'auto_detect' as const,
      filename: file.name,
      contentType: file.type || null,
      byteSize: file.size,
      file,
    })),
  ];
}

export function buildClaimsFixPackageFormData(rows: ClaimsFixPackageRow[]): FormData {
  const formData = new FormData();
  const invoice = rows.find((row) => row.source === 'clone' && row.fileRole === 'invoice');
  if (invoice?.sourceId) formData.append('clone_invoice_version_id', invoice.sourceId);

  rows
    .filter((row) => row.source === 'clone' && row.fileRole === 'supporting_document' && row.sourceId)
    .forEach((row) => formData.append('clone_supporting_document_ids[]', row.sourceId || ''));
  rows
    .filter((row) => row.source === 'new' && row.file)
    .forEach((row) => formData.append('files[]', row.file as File, row.filename));
  return formData;
}

function makeClientId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}
