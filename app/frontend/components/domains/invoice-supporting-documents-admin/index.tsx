import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  Container,
  Flex,
  HStack,
  IconButton,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
} from '@chakra-ui/react';
import { FilePdf, Trash, UploadSimple } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ContextPayload = {
  invoice_id: string;
  session_id: string;
  session_created_at?: string | null;
  contractor_business_name?: string | null;
  invoice_created_at?: string | null;
  latest_invoice_version_id?: string | null;
  latest_ocr_invoice_number?: string | null;
};

type SupportingDocumentRow = {
  id: string;
  invoice_id: string;
  supporting_document_type_id?: string | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
  storage_provider?: string | null;
  storage_key?: string | null;
  original_filename?: string | null;
  content_type?: string | null;
  mime_content_type?: string | null;
  byte_size?: number | null;
  sha256?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '—';
}

function fmtDateOnly(s?: string | null) {
  if (!s) return '-';
  const d = new Date(s);
  if (Number.isNaN(d.getTime())) return '-';
  return d.toLocaleDateString('en-CA');
}

function fmtBytes(n?: number | null) {
  if (n === null || n === undefined) return '—';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

export default function InvoiceSupportingDocumentsAdminScreen() {
  const location = useLocation();
  const invoiceId = getParam(location.search, 'invoice_id');

  const [context, setContext] = useState<ContextPayload | null>(null);
  const [rows, setRows] = useState<SupportingDocumentRow[]>([]);
  const [loading, setLoading] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deletingId, setDeletingId] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);

  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const canUpload = useMemo(
    () => invoiceId.trim().length > 0 && selectedFiles.length > 0 && !uploading,
    [invoiceId, selectedFiles, uploading],
  );

  const loadData = async () => {
    if (!invoiceId.trim()) {
      setError('Missing invoice_id in URL.');
      setContext(null);
      setRows([]);
      return;
    }

    setLoading(true);
    setError('');

    try {
      const [contextRes, listRes] = await Promise.all([
        fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/supporting_documents/context`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        }),
        fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/supporting_documents`, {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        }),
      ]);

      const contextJson = await contextRes.json().catch(() => ({}));
      const listJson = await listRes.json().catch(() => ({ rows: [] }));

      if (!contextRes.ok) throw new Error(contextJson?.error || `HTTP ${contextRes.status}`);
      if (!listRes.ok) throw new Error(listJson?.error || `HTTP ${listRes.status}`);

      setContext(contextJson as ContextPayload);
      setRows(Array.isArray(listJson?.rows) ? listJson.rows : []);
    } catch (e: any) {
      setContext(null);
      setRows([]);
      setError(e?.message || 'Failed to load supporting-document screen.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void loadData();
  }, [invoiceId]);

  const mergeFiles = (incoming: File[]) => {
    const pdfsOnly = incoming.filter((f) => {
      const byType = String(f.type || '').toLowerCase() === 'application/pdf';
      const byExt = String(f.name || '')
        .toLowerCase()
        .endsWith('.pdf');
      return byType || byExt;
    });

    setSelectedFiles((prev) => {
      const seen = new Set(prev.map((f) => `${f.name}:${f.size}:${f.lastModified}`));
      const next = [...prev];
      pdfsOnly.forEach((f) => {
        const key = `${f.name}:${f.size}:${f.lastModified}`;
        if (!seen.has(key)) next.push(f);
      });
      return next;
    });
  };

  const handleUpload = async () => {
    if (!canUpload) return;

    setUploading(true);
    setError('');
    setSuccess('');

    try {
      const form = new FormData();
      selectedFiles.forEach((f) => form.append('pdfs[]', f, f.name));

      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/supporting_documents`, {
        method: 'POST',
        credentials: 'include',
        body: form,
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      setSelectedFiles([]);
      setSuccess(`Uploaded ${Number(data?.uploaded_count || 0)} supporting PDF(s).`);
      await loadData();
    } catch (e: any) {
      setError(e?.message || 'Failed to upload supporting PDFs.');
    } finally {
      setUploading(false);
    }
  };

  const handleOpenSupportingPdf = async (id: string) => {
    try {
      const res = await fetch(`/api/claims/admin/supporting_documents/${encodeURIComponent(id)}/pdf_url`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      if (!data?.sas_url) throw new Error('Supporting PDF URL not returned.');

      window.open(String(data.sas_url), '_blank', 'noopener,noreferrer');
    } catch (e: any) {
      setError(e?.message || 'Failed to open supporting PDF.');
    }
  };

  const handleDelete = async (id: string) => {
    const confirmed = window.confirm('Delete this supporting PDF? This cannot be undone.');
    if (!confirmed) return;

    setDeletingId(id);
    setError('');
    setSuccess('');

    try {
      const res = await fetch(`/api/claims/admin/supporting_documents/${encodeURIComponent(id)}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      setSuccess('Supporting PDF deleted.');
      await loadData();
    } catch (e: any) {
      setError(e?.message || 'Failed to delete supporting PDF.');
    } finally {
      setDeletingId('');
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoice Supporting Documents" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={5}>
          <Text fontSize="sm" fontWeight="bold" mb={4}>
            Invoice Context
          </Text>

          {loading && !context ? (
            <Spinner size="sm" />
          ) : (
            <Flex wrap="wrap" gap={6}>
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7}>
                  session_created_at
                </Text>
                <Text fontSize="sm">{fmtDateOnly(context?.session_created_at)}</Text>
              </Box>
              <Box minW="240px">
                <Text fontSize="xs" opacity={0.7}>
                  contractor
                </Text>
                <Text fontSize="sm">{context?.contractor_business_name || '—'}</Text>
              </Box>
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7}>
                  invoice_created_at
                </Text>
                <Text fontSize="sm">{fmtTs(context?.invoice_created_at)}</Text>
              </Box>
              <Box minW="220px">
                <Text fontSize="xs" opacity={0.7}>
                  latest OCR invoice number
                </Text>
                <Text fontSize="sm">{context?.latest_ocr_invoice_number || '—'}</Text>
              </Box>
            </Flex>
          )}
        </Box>

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={5}>
          <Text fontSize="sm" fontWeight="bold" mb={4}>
            Add Supporting PDFs
          </Text>

          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="application/pdf,.pdf"
            style={{ display: 'none' }}
            onChange={(e) => {
              mergeFiles(Array.from(e.target.files || []));
              e.target.value = '';
            }}
          />

          <Box
            borderWidth="2px"
            borderStyle="dashed"
            borderColor={isDragActive ? 'blue.400' : 'gray.200'}
            borderRadius="lg"
            p={8}
            textAlign="center"
            bg={isDragActive ? 'blue.50' : 'gray.50'}
            onDragEnter={(e) => {
              e.preventDefault();
              setIsDragActive(true);
            }}
            onDragOver={(e) => {
              e.preventDefault();
              setIsDragActive(true);
            }}
            onDragLeave={(e) => {
              e.preventDefault();
              setIsDragActive(false);
            }}
            onDrop={(e) => {
              e.preventDefault();
              setIsDragActive(false);
              mergeFiles(Array.from(e.dataTransfer.files || []));
            }}
          >
            <Text fontWeight="bold" mb={2}>
              Drag and drop PDF files here
            </Text>
            <Text fontSize="sm" opacity={0.8} mb={4}>
              Files upload directly to this invoice. No staging area is used.
            </Text>
            <Button
              variant="outline"
              leftIcon={<UploadSimple size={16} />}
              onClick={() => fileInputRef.current?.click()}
            >
              Select Files
            </Button>
          </Box>

          <Box mt={4}>
            <Text fontSize="xs" opacity={0.7} mb={2}>
              Selected files
            </Text>
            {selectedFiles.length ? (
              selectedFiles.map((file) => (
                <Flex
                  key={`${file.name}:${file.size}:${file.lastModified}`}
                  justify="space-between"
                  align="center"
                  py={1}
                >
                  <Text fontSize="sm">{file.name}</Text>
                  <Text fontSize="xs" opacity={0.7}>
                    {fmtBytes(file.size)}
                  </Text>
                </Flex>
              ))
            ) : (
              <Text fontSize="sm" opacity={0.7}>
                No files selected.
              </Text>
            )}
          </Box>

          <HStack mt={4} spacing={3}>
            <Button
              colorScheme="blue"
              onClick={() => void handleUpload()}
              isLoading={uploading}
              isDisabled={!canUpload}
            >
              Upload{' '}
              {selectedFiles.length ? `${selectedFiles.length} PDF${selectedFiles.length === 1 ? '' : 's'}` : 'PDFs'}
            </Button>
            {!!selectedFiles.length && (
              <Button variant="outline" onClick={() => setSelectedFiles([])} isDisabled={uploading}>
                Clear Selection
              </Button>
            )}
          </HStack>
        </Box>

        {error && (
          <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
            <Text fontSize="sm" color="red.700">
              {error}
            </Text>
          </Box>
        )}

        {success && (
          <Box mb={4} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
            <Text fontSize="sm" color="green.700">
              {success}
            </Text>
          </Box>
        )}

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="space-between" align="center" mb={3}>
            <Text fontSize="sm" fontWeight="bold">
              Supporting Documents For This Invoice
            </Text>
            {loading && <Spinner size="sm" />}
          </Flex>

          <Table size="sm">
            <Thead bg="gray.50">
              <Tr>
                <Th>created_at</Th>
                <Th>filename</Th>
                <Th>type</Th>
                <Th isNumeric>size</Th>
                <Th>actions</Th>
              </Tr>
            </Thead>
            <Tbody>
              {rows.map((row) => (
                <Tr key={row.id}>
                  <Td fontSize="xs" whiteSpace="nowrap">
                    {fmtTs(row.created_at)}
                  </Td>
                  <Td fontSize="sm">{row.original_filename || '—'}</Td>
                  <Td fontSize="xs">{row.content_type || '—'}</Td>
                  <Td isNumeric fontSize="xs">
                    {fmtBytes(row.byte_size)}
                  </Td>
                  <Td>
                    <HStack spacing={2}>
                      <Tooltip label="Open supporting PDF in a new browser tab">
                        <IconButton
                          aria-label="Open supporting PDF"
                          size="xs"
                          variant="outline"
                          icon={<FilePdf size={14} />}
                          onClick={() => void handleOpenSupportingPdf(row.id)}
                        />
                      </Tooltip>
                      <Tooltip label="Delete supporting PDF">
                        <IconButton
                          aria-label="Delete supporting PDF"
                          size="xs"
                          variant="outline"
                          colorScheme="red"
                          icon={<Trash size={14} />}
                          isLoading={deletingId === row.id}
                          onClick={() => void handleDelete(row.id)}
                        />
                      </Tooltip>
                    </HStack>
                  </Td>
                </Tr>
              ))}

              {!loading && rows.length === 0 && (
                <Tr>
                  <Td colSpan={5}>
                    <Text fontSize="sm" opacity={0.7}>
                      No supporting documents uploaded for this invoice yet.
                    </Text>
                  </Td>
                </Tr>
              )}
            </Tbody>
          </Table>
        </Box>
      </Container>
    </Flex>
  );
}
