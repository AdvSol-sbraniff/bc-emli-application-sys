import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
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
  VStack,
} from '@chakra-ui/react';
import { FilePlus, Trash, UploadSimple, WarningCircle, XCircle } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { IngestRunMonitorTabs } from '../../shared/claims/ingest-run-monitor-tabs';

type CurrentReadPayload = {
  invoice?: {
    id?: string;
    session_id?: string | null;
    status?: string | null;
  };
  read?: {
    id?: string;
    invoice_id?: string;
    invoice_versionno?: number | null;
    original_filename?: string | null;
    content_type?: string | null;
    byte_size?: number | null;
    updated_at?: string | null;
    uploaded_supporting_documents?: SupportingDocumentRow[];
  };
};

type SupportingDocumentRow = {
  id: string;
  original_filename?: string | null;
  content_type?: string | null;
  mime_content_type?: string | null;
  byte_size?: number | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
};

type ProposedFileRow = {
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

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtBytes(n?: number | null) {
  if (n === null || n === undefined) return '-';
  if (n < 1024) return `${n} B`;
  if (n < 1024 * 1024) return `${(n / 1024).toFixed(1)} KB`;
  return `${(n / (1024 * 1024)).toFixed(2)} MB`;
}

function fileSizeMb(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

export default function ContractorFixSimulationAdminScreen() {
  const location = useLocation();
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const invoiceId = getParam(location.search, 'invoice_id');
  const contractorBusinessName = getParam(location.search, 'contractor_business_name');

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [readPayload, setReadPayload] = useState<CurrentReadPayload | null>(null);
  const [proposedRows, setProposedRows] = useState<ProposedFileRow[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitMessage, setSubmitMessage] = useState('');
  const [runId, setRunId] = useState('');

  const loadCurrentPackage = useCallback(async () => {
    if (!invoiceId.trim()) {
      setError('Missing invoice_id in URL.');
      setReadPayload(null);
      setProposedRows([]);
      return;
    }

    setLoading(true);
    setError('');
    try {
      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}/current_version/read`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = (await res.json().catch(() => ({}))) as CurrentReadPayload & { error?: string };
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      const invoiceClone: ProposedFileRow[] = data?.read?.id
        ? [
            {
              id: `clone-invoice-${data.read.id}`,
              sourceId: data.read.id,
              source: 'clone',
              fileRole: 'invoice',
              filename: data.read.original_filename || 'Current invoice PDF',
              contentType: data.read.content_type || 'application/pdf',
              byteSize: data.read.byte_size,
            },
          ]
        : [];

      const supportingClones = Array.isArray(data?.read?.uploaded_supporting_documents)
        ? data.read.uploaded_supporting_documents.map((doc) => ({
            id: `clone-support-${doc.id}`,
            sourceId: doc.id,
            source: 'clone' as const,
            fileRole: 'supporting_document' as const,
            filename: doc.original_filename || 'Supporting document',
            contentType: doc.mime_content_type || doc.content_type,
            byteSize: doc.byte_size,
            supportingType: doc.supporting_document_type_description || doc.supporting_document_type_key,
          }))
        : [];

      setReadPayload(data);
      setProposedRows([...invoiceClone, ...supportingClones]);
    } catch (e: any) {
      setError(e?.message || 'Failed to load current package.');
      setReadPayload(null);
      setProposedRows([]);
    } finally {
      setLoading(false);
    }
  }, [invoiceId]);

  useEffect(() => {
    void loadCurrentPackage();
  }, [loadCurrentPackage]);

  const currentRows = useMemo(() => proposedRows.filter((row) => row.source === 'clone'), [proposedRows]);
  const newRows = useMemo(() => proposedRows.filter((row) => row.source === 'new'), [proposedRows]);

  const validationMessage = useMemo(() => {
    if (!proposedRows.length) return 'The proposed package cannot be empty.';
    return '';
  }, [proposedRows.length]);

  const addFiles = (files: File[]) => {
    if (!files.length) return;
    setSubmitMessage('');
    setProposedRows((existing) => [
      ...existing,
      ...files.map((file) => ({
        id: `new-${crypto.randomUUID()}`,
        source: 'new' as const,
        fileRole: 'auto_detect' as const,
        filename: file.name,
        contentType: file.type || null,
        byteSize: file.size,
        file,
      })),
    ]);
  };

  const handleFilesPicked = (event: React.ChangeEvent<HTMLInputElement>) => {
    addFiles(Array.from(event.target.files || []));
    event.target.value = '';
  };

  const handleDropZoneDragOver = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    if (!isDragActive) setIsDragActive(true);
  };

  const handleDropZoneDragLeave = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    setIsDragActive(false);
  };

  const handleDropZoneDrop = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    setIsDragActive(false);
    addFiles(Array.from(event.dataTransfer?.files || []));
  };

  const removeProposedRow = (id: string) => {
    setSubmitMessage('');
    setProposedRows((existing) => existing.filter((row) => row.id !== id));
  };

  const handleSubmitFixPackage = async () => {
    if (validationMessage) {
      setSubmitMessage(validationMessage);
      return;
    }

    setIsSubmitting(true);
    setSubmitMessage('');
    setError('');

    try {
      const formData = new FormData();
      const cloneInvoiceRow = proposedRows.find((row) => row.source === 'clone' && row.fileRole === 'invoice');
      if (cloneInvoiceRow?.sourceId) {
        formData.append('clone_invoice_version_id', cloneInvoiceRow.sourceId);
      }

      proposedRows
        .filter((row) => row.source === 'clone' && row.fileRole === 'supporting_document' && row.sourceId)
        .forEach((row) => formData.append('clone_supporting_document_ids[]', row.sourceId || ''));

      proposedRows
        .filter((row) => row.source === 'new' && row.file)
        .forEach((row) => {
          formData.append('files[]', row.file as File);
        });

      const res = await fetch(`/api/claims/invoices/${encodeURIComponent(invoiceId)}/upload_fix_package`, {
        method: 'POST',
        body: formData,
        credentials: 'include',
        headers: { Accept: 'application/json' },
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data?.ok === false) throw new Error(data?.error || `HTTP ${res.status}`);

      const nextRunId = String(data?.ingest_run_id || '').trim();
      setRunId(nextRunId);
      setSubmitMessage(
        `Fix package accepted. Version ${data?.invoice_versionno ?? ''} is being prepared. Run ${nextRunId || '-'}`,
      );
    } catch (e: any) {
      setError(e?.message || 'Failed to submit fix package.');
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Contractor Fix Simulation" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <VStack align="stretch" spacing={5}>
          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <Flex justify="space-between" align="start" gap={4} wrap="wrap">
              <Box>
                <Text fontSize="lg" fontWeight="semibold">
                  Build the next package version
                </Text>
                <Text fontSize="sm" opacity={0.74} mt={1}>
                  Start with the current invoice package, remove anything that should not carry forward, then add
                  replacement or extra files.
                </Text>
              </Box>
              <Box textAlign="right">
                <Text fontSize="xs" opacity={0.68}>
                  contractor
                </Text>
                <Text fontSize="sm" fontWeight="semibold">
                  {contractorBusinessName || 'Unknown contractor'}
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  v{readPayload?.read?.invoice_versionno ?? '-'}
                </Text>
              </Box>
            </Flex>
          </Box>

          {error && (
            <Box p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 12px 34px rgba(15, 23, 42, 0.06)">
            <Flex justify="space-between" align="center" mb={3}>
              <Text fontSize="sm" fontWeight="bold">
                Current version files
              </Text>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm">
              <Thead bg="gray.50">
                <Tr>
                  <Th>filename</Th>
                  <Th>role</Th>
                  <Th>type</Th>
                  <Th isNumeric>size</Th>
                </Tr>
              </Thead>
              <Tbody>
                {currentRows.map((row) => (
                  <Tr key={`current-${row.id}`}>
                    <Td fontSize="sm">{row.filename}</Td>
                    <Td>
                      <Badge colorScheme={row.fileRole === 'invoice' ? 'blue' : 'gray'}>{row.fileRole}</Badge>
                    </Td>
                    <Td fontSize="xs">{row.supportingType || row.contentType || '-'}</Td>
                    <Td isNumeric fontSize="xs">
                      {fmtBytes(row.byteSize)}
                    </Td>
                  </Tr>
                ))}
                {!loading && currentRows.length === 0 && (
                  <Tr>
                    <Td colSpan={4}>
                      <Text fontSize="sm" opacity={0.7}>
                        No current files were found.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 12px 34px rgba(15, 23, 42, 0.06)">
            <input ref={fileInputRef} type="file" multiple style={{ display: 'none' }} onChange={handleFilesPicked} />

            <Flex justify="space-between" align="center" gap={3} wrap="wrap" mb={3}>
              <Box>
                <Text fontSize="sm" fontWeight="bold">
                  Add replacement or extra files
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  New files are staged as NEW ADDITION and classified from their contents by the AI pipeline.
                </Text>
              </Box>
              <Button
                leftIcon={<UploadSimple size={18} />}
                variant="outline"
                onClick={() => fileInputRef.current?.click()}
              >
                Choose files
              </Button>
            </Flex>

            <Box
              p={8}
              borderWidth="2px"
              borderStyle="dashed"
              borderColor={isDragActive ? 'blue.400' : 'gray.300'}
              bg={isDragActive ? 'blue.50' : 'linear-gradient(135deg, rgba(237, 242, 247, 0.9), white)'}
              borderRadius="xl"
              textAlign="center"
              transition="all 160ms ease"
              onDragOver={handleDropZoneDragOver}
              onDragEnter={handleDropZoneDragOver}
              onDragLeave={handleDropZoneDragLeave}
              onDrop={handleDropZoneDrop}
            >
              <FilePlus size={34} />
              <Text mt={2} fontSize="sm" fontWeight="semibold">
                Drag files here
              </Text>
              <Text fontSize="xs" opacity={0.68}>
                To replace a file, remove the CLONE row below and add the replacement as NEW ADDITION.
              </Text>
            </Box>

            {newRows.length > 0 && (
              <Text mt={3} fontSize="xs" opacity={0.72}>
                Added files:{' '}
                {newRows
                  .map((row) => `${row.filename} (${fileSizeMb(row.file?.size || row.byteSize || 0)})`)
                  .join(', ')}
              </Text>
            )}
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <Flex justify="space-between" align="center" gap={3} wrap="wrap" mb={3}>
              <Box>
                <Text fontSize="sm" fontWeight="bold">
                  Proposed next version
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  CLONE rows carry forward. NEW ADDITION rows will be treated as new evidence.
                </Text>
              </Box>
              <Button
                colorScheme="blue"
                onClick={handleSubmitFixPackage}
                isDisabled={loading || isSubmitting}
                isLoading={isSubmitting}
                leftIcon={validationMessage ? <WarningCircle size={18} /> : undefined}
              >
                Click me to fix
              </Button>
            </Flex>

            {validationMessage && (
              <Box mb={3} p={3} bg="orange.50" borderWidth="1px" borderColor="orange.200" borderRadius="md">
                <Text fontSize="sm" color="orange.800">
                  {validationMessage}
                </Text>
              </Box>
            )}

            {submitMessage && (
              <Box mb={3} p={3} bg="blue.50" borderWidth="1px" borderColor="blue.200" borderRadius="md">
                <Text fontSize="sm" color="blue.800">
                  {submitMessage}
                </Text>
              </Box>
            )}

            <Table size="sm">
              <Thead bg="gray.50">
                <Tr>
                  <Th>filename</Th>
                  <Th>status</Th>
                  <Th>classification</Th>
                  <Th>type</Th>
                  <Th isNumeric>size</Th>
                  <Th textAlign="right">actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {proposedRows.map((row) => (
                  <Tr key={row.id}>
                    <Td fontSize="sm">{row.filename}</Td>
                    <Td>
                      <Badge colorScheme={row.source === 'clone' ? 'purple' : 'green'}>
                        {row.source === 'clone' ? 'CLONE' : 'NEW ADDITION'}
                      </Badge>
                    </Td>
                    <Td>
                      <Badge
                        colorScheme={
                          row.fileRole === 'auto_detect' ? 'orange' : row.fileRole === 'invoice' ? 'blue' : 'gray'
                        }
                      >
                        {row.fileRole === 'auto_detect'
                          ? 'pending auto-detection'
                          : row.fileRole === 'invoice'
                            ? 'invoice'
                            : 'supporting doc'}
                      </Badge>
                    </Td>
                    <Td fontSize="xs">{row.supportingType || row.contentType || '-'}</Td>
                    <Td isNumeric fontSize="xs">
                      {fmtBytes(row.byteSize)}
                    </Td>
                    <Td>
                      <HStack justify="flex-end">
                        <Tooltip label="Remove from proposed next version">
                          <IconButton
                            aria-label="Remove from proposed next version"
                            size="xs"
                            variant="ghost"
                            colorScheme="red"
                            icon={row.source === 'clone' ? <Trash size={14} /> : <XCircle size={14} />}
                            onClick={() => removeProposedRow(row.id)}
                          />
                        </Tooltip>
                      </HStack>
                    </Td>
                  </Tr>
                ))}
                {proposedRows.length === 0 && (
                  <Tr>
                    <Td colSpan={6}>
                      <Text fontSize="sm" opacity={0.7}>
                        The proposed next version is empty.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <IngestRunMonitorTabs
              runId={runId}
              emptyMessage="Upload a fix package to see bundle invoices and step history."
            />
          </Box>
        </VStack>
      </Container>
    </Flex>
  );
}
