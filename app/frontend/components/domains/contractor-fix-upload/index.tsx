import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  HStack,
  IconButton,
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalFooter,
  ModalHeader,
  ModalOverlay,
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
import { CheckCircle, FilePlus, Trash, UploadSimple, WarningCircle, XCircle } from '@phosphor-icons/react';
import { useNavigate, useParams } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { ContractorProcessingGraphic } from '../../shared/claims/contractor-processing-graphic';

type SupportingDocumentRow = {
  id: string;
  invoice_version_id?: string | null;
  original_filename?: string | null;
  content_type?: string | null;
  mime_content_type?: string | null;
  byte_size?: number | null;
  supporting_document_type_key?: string | null;
  supporting_document_type_description?: string | null;
};

type CurrentReadPayload = {
  read?: {
    id?: string;
    invoice_id?: string;
    session_id?: string | null;
    invoice_status?: string | null;
    invoice_status_subtype?: string | null;
    invoice_versionno?: number | null;
    original_filename?: string | null;
    content_type?: string | null;
    byte_size?: number | null;
    uploaded_supporting_documents?: SupportingDocumentRow[];
  };
  error?: string;
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

type RunHeader = {
  id: string;
  session_id: string;
  status: string;
  failure_status?: string | null;
  failure_status_subtype?: string | null;
  failure_message?: string | null;
  retry_guidance?: string | null;
  invoice_id?: string | null;
  invoice_status?: string | null;
  invoice_status_subtype?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  can_continue?: boolean;
};

function makeClientId(prefix: string) {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }

  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
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

function buildCloneRows(payload: CurrentReadPayload | null): ProposedFileRow[] {
  const read = payload?.read;
  const invoiceClone: ProposedFileRow[] = read?.id
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

  const supportingClones = Array.isArray(read?.uploaded_supporting_documents)
    ? read.uploaded_supporting_documents.map((doc) => ({
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

  return [...invoiceClone, ...supportingClones];
}

export default function ContractorFixUploadScreen() {
  const { sessionId = '', invoiceId = '' } = useParams();
  const navigate = useNavigate();
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [loading, setLoading] = useState(false);
  const [loadError, setLoadError] = useState('');
  const [readPayload, setReadPayload] = useState<CurrentReadPayload | null>(null);
  const [proposedRows, setProposedRows] = useState<ProposedFileRow[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);

  const [runId, setRunId] = useState('');
  const [uploadModalOpen, setUploadModalOpen] = useState(false);
  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [failureMessage, setFailureMessage] = useState('');
  const [dismissedFailureRunId, setDismissedFailureRunId] = useState('');
  const [runHeader, setRunHeader] = useState<RunHeader | null>(null);
  const [runError, setRunError] = useState('');

  const loadCurrentPackage = useCallback(async () => {
    if (!sessionId || !invoiceId) {
      setLoadError('Missing invoice information in the URL.');
      setReadPayload(null);
      setProposedRows([]);
      return;
    }

    setLoading(true);
    setLoadError('');
    try {
      const res = await fetch(
        `/api/claims/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
          cache: 'no-store',
        },
      );
      const data = (await res.json().catch(() => ({}))) as CurrentReadPayload;
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);

      setReadPayload(data);
      setProposedRows(buildCloneRows(data));
    } catch (error: any) {
      setLoadError(error?.message || 'Failed to load the current invoice package.');
      setReadPayload(null);
      setProposedRows([]);
    } finally {
      setLoading(false);
    }
  }, [invoiceId, sessionId]);

  useEffect(() => {
    void loadCurrentPackage();
  }, [loadCurrentPackage]);

  const currentVersionRows = useMemo(() => buildCloneRows(readPayload), [readPayload]);
  const newRows = useMemo(() => proposedRows.filter((row) => row.source === 'new'), [proposedRows]);
  const currentStatus = String(readPayload?.read?.invoice_status || '').trim();
  const canStartFix = currentStatus === 'genai_complete' || currentStatus === 'contractor_revision_inbox';
  const fixAvailabilityMessage =
    readPayload?.read && !canStartFix
      ? 'Fix upload is available after the pre-check finishes, or when the program team has requested a revision.'
      : '';

  const validationMessage = useMemo(() => {
    const originalCloneIds = new Set(currentVersionRows.map((row) => row.id));
    const proposedCloneIds = new Set(proposedRows.filter((row) => row.source === 'clone').map((row) => row.id));
    const removedClone = Array.from(originalCloneIds).some((id) => !proposedCloneIds.has(id));
    const hasPackageChange = removedClone || newRows.length > 0;

    if (fixAvailabilityMessage) return fixAvailabilityMessage;
    if (!proposedRows.length) return 'The proposed package cannot be empty.';
    if (!hasPackageChange) return 'Make at least one package change before uploading a fix.';
    return '';
  }, [currentVersionRows, fixAvailabilityMessage, newRows.length, proposedRows]);

  const loadRunHeader = useCallback(async (id: string) => {
    if (!id) return;
    try {
      const res = await fetch(`/api/claims/contractor/ingest/runs/${encodeURIComponent(id)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
        cache: 'no-store',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setRunHeader(data as RunHeader);
      setRunError('');
      setFailureMessage(data?.failure_message ? String(data.failure_message) : '');
    } catch (error: any) {
      setRunError(error?.message || 'Failed to check fix upload status.');
      setRunHeader(null);
    }
  }, []);

  const refreshRun = useCallback(
    async (id = runId) => {
      if (!id) return;
      await loadRunHeader(id);
    },
    [loadRunHeader, runId],
  );

  useEffect(() => {
    if (!runId) return;
    void refreshRun(runId);
  }, [refreshRun, runId]);

  const failureDismissedForCurrentRun = !!runId && dismissedFailureRunId === runId;
  const visibleFailureMessage = failureDismissedForCurrentRun ? '' : failureMessage;
  const runStatus = String(runHeader?.status || '').toLowerCase();
  const invoiceStatus = String(runHeader?.invoice_status || '').toLowerCase();
  const runFailed = runStatus === 'failed';
  const runTerminal = runStatus === 'failed' || runStatus === 'succeeded' || runStatus === 'partial';
  const hasFailedRows =
    !!visibleFailureMessage ||
    invoiceStatus.endsWith('_failed') ||
    invoiceStatus === 'package_needs_correction' ||
    invoiceStatus === 'technical_failure';
  const hasProcessingRows =
    invoiceStatus.includes('queued') || invoiceStatus.includes('progress') || invoiceStatus === 'ocr_complete';
  const canContinue = runHeader?.can_continue === true;
  const isProcessing =
    submitLoading ||
    (!failureMessage &&
      !!runId &&
      !canContinue &&
      !runTerminal &&
      (runStatus === 'queued' || runStatus === 'running' || hasProcessingRows || !runHeader?.invoice_id));
  const fallbackFailureMessage =
    !failureDismissedForCurrentRun && (hasFailedRows || runFailed)
      ? 'We could not prepare the updated AI Advice right now. Please try uploading the same fix again later.'
      : '';
  const displayFailureMessage = submitError || runError || visibleFailureMessage || fallbackFailureMessage;
  const filesLocked = submitLoading || isProcessing || canContinue;
  const controlsLocked = filesLocked || !!fixAvailabilityMessage;

  const shouldPoll = !!runId && (runStatus === 'queued' || runStatus === 'running');
  useEffect(() => {
    if (!shouldPoll) return;
    const id = window.setInterval(() => {
      void refreshRun();
    }, 3000);
    return () => window.clearInterval(id);
  }, [refreshRun, shouldPoll]);

  useEffect(() => {
    if (submitLoading || isProcessing || displayFailureMessage || canContinue) {
      setUploadModalOpen(true);
    }
  }, [canContinue, displayFailureMessage, isProcessing, submitLoading]);

  const processingStoryLabel = (() => {
    if (submitLoading || runStatus === 'queued') return 'Uploading revised package';
    if (!runHeader?.invoice_id) return 'Reading revised files';

    if (invoiceStatus.startsWith('upload_')) return 'Uploading revised package';
    if (invoiceStatus.startsWith('ocr_')) return 'Reading revised files';
    if (invoiceStatus === 'ocr_complete') return 'Extracting revised invoice evidence';
    if (invoiceStatus.startsWith('genai_')) return 'Refreshing AI Advice';
    if (runStatus === 'running') return 'Preparing updated review';

    return 'Refreshing AI Advice';
  })();

  const addFiles = (files: File[]) => {
    if (controlsLocked) return;

    const supportedEvidenceFiles = files.filter((file) => {
      const type = String(file.type || '').toLowerCase();
      const byType = type === 'application/pdf' || type === 'image/jpeg' || type === 'image/png';
      const byExt = /\.(pdf|jpe?g|png)$/.test(String(file.name || '').toLowerCase());
      return byType || byExt;
    });

    if (!supportedEvidenceFiles.length) return;
    setSubmitError('');
    setFailureMessage('');
    setRunError('');
    setProposedRows((existing) => [
      ...existing,
      ...supportedEvidenceFiles.map((file) => ({
        id: makeClientId('new'),
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
    if (controlsLocked) return;
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
    if (controlsLocked) return;
    addFiles(Array.from(event.dataTransfer?.files || []));
  };

  const removeProposedRow = (id: string) => {
    if (controlsLocked) return;
    setProposedRows((existing) => existing.filter((row) => row.id !== id));
  };

  const handleSubmitFixPackage = async () => {
    if (validationMessage) return;

    setUploadModalOpen(true);
    setSubmitLoading(true);
    setSubmitError('');
    setFailureMessage('');
    setDismissedFailureRunId('');
    setRunError('');
    setRunHeader(null);

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
          formData.append('files[]', row.file as File, row.filename);
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
      if (!nextRunId) throw new Error('The fix upload response did not include a processing id.');

      setRunId(nextRunId);
      if (data?.failure_message) setFailureMessage(String(data.failure_message));
    } catch (error: any) {
      setSubmitError(error?.message || 'Failed to upload the package fix.');
    } finally {
      setSubmitLoading(false);
    }
  };

  const closeUploadModal = () => {
    if (submitLoading || isProcessing) return;
    setUploadModalOpen(false);
  };

  const clearUploadModalAttention = () => {
    setSubmitError('');
    setFailureMessage('');
    setRunError('');
    if (runId) setDismissedFailureRunId(runId);
    setUploadModalOpen(false);
  };

  const continueToUpdatedReview = () => {
    if (!canContinue) return;
    navigate(
      `/contractor/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(
        invoiceId,
      )}/review?source=fix`,
    );
  };

  const resetToCurrentVersion = () => {
    if (controlsLocked) return;
    setProposedRows(buildCloneRows(readPayload));
    setSubmitError('');
    setFailureMessage('');
    setRunError('');
  };

  const isTechnicalFailure = runHeader?.failure_status === 'technical_failure' || invoiceStatus === 'technical_failure';

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Upload Package Fix" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <VStack align="stretch" spacing={5}>
          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <Flex justify="space-between" align="start" gap={4} wrap="wrap">
              <Box>
                <Text fontSize="lg" fontWeight="800">
                  Build the corrected package
                </Text>
                <Text fontSize="sm" opacity={0.75} mt={1}>
                  Keep the current files that still belong, remove anything that should not carry forward, then add the
                  corrected files.
                </Text>
              </Box>
              <Box textAlign="right">
                <Text fontSize="xs" opacity={0.68}>
                  current version
                </Text>
                <Text fontSize="sm" fontWeight="semibold">
                  v{readPayload?.read?.invoice_versionno ?? '-'}
                </Text>
              </Box>
            </Flex>
          </Box>

          {loadError ? (
            <Box p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {loadError}
              </Text>
            </Box>
          ) : null}

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 12px 34px rgba(15, 23, 42, 0.06)">
            <Flex justify="space-between" align="center" mb={3}>
              <Text fontSize="sm" fontWeight="bold">
                Current version files
              </Text>
              {loading ? <Spinner size="sm" /> : null}
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
                {currentVersionRows.map((row) => (
                  <Tr key={`current-${row.id}`}>
                    <Td fontSize="sm">{row.filename}</Td>
                    <Td>
                      <Badge colorScheme={row.fileRole === 'invoice' ? 'blue' : 'gray'}>
                        {row.fileRole === 'invoice' ? 'invoice' : 'supporting doc'}
                      </Badge>
                    </Td>
                    <Td fontSize="xs">{row.supportingType || row.contentType || '-'}</Td>
                    <Td isNumeric fontSize="xs">
                      {fmtBytes(row.byteSize)}
                    </Td>
                  </Tr>
                ))}
                {!loading && currentVersionRows.length === 0 ? (
                  <Tr>
                    <Td colSpan={4}>
                      <Text fontSize="sm" opacity={0.7}>
                        No current files were found.
                      </Text>
                    </Td>
                  </Tr>
                ) : null}
              </Tbody>
            </Table>
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 12px 34px rgba(15, 23, 42, 0.06)">
            <input
              ref={fileInputRef}
              type="file"
              multiple
              accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
              style={{ display: 'none' }}
              disabled={controlsLocked}
              onChange={handleFilesPicked}
            />

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
                isDisabled={controlsLocked || !!loadError}
              >
                Choose files
              </Button>
            </Flex>

            <Box
              p={8}
              borderWidth="2px"
              borderStyle="dashed"
              borderColor={isDragActive && !controlsLocked ? 'blue.400' : 'gray.300'}
              bg={
                isDragActive && !controlsLocked ? 'blue.50' : 'linear-gradient(135deg, rgba(237, 242, 247, 0.9), white)'
              }
              opacity={controlsLocked ? 0.72 : 1}
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
                Drag corrected files here
              </Text>
              <Text fontSize="xs" opacity={0.68}>
                To replace a file, remove the CLONE row below and add the replacement as NEW ADDITION.
              </Text>
            </Box>

            {newRows.length > 0 ? (
              <Text mt={3} fontSize="xs" opacity={0.72}>
                Added files:{' '}
                {newRows
                  .map((row) => `${row.filename} (${fileSizeMb(row.file?.size || row.byteSize || 0)})`)
                  .join(', ')}
              </Text>
            ) : null}
          </Box>

          <Box bg="white" p={5} borderRadius="xl" boxShadow="0 18px 45px rgba(15, 23, 42, 0.08)">
            <Flex justify="space-between" align="center" gap={3} wrap="wrap" mb={3}>
              <Box>
                <Text fontSize="sm" fontWeight="bold">
                  Proposed corrected package
                </Text>
                <Text fontSize="xs" opacity={0.68}>
                  CLONE rows carry forward. NEW ADDITION rows are uploaded into the corrected version.
                </Text>
              </Box>
              <HStack spacing={2}>
                <Tooltip label="Reset the proposed package back to the current version">
                  <IconButton
                    aria-label="Reset proposed package"
                    icon={<XCircle size={18} />}
                    variant="ghost"
                    onClick={resetToCurrentVersion}
                    isDisabled={controlsLocked || loading}
                  />
                </Tooltip>
                <Button
                  colorScheme="blue"
                  onClick={() => void handleSubmitFixPackage()}
                  isDisabled={loading || !!loadError || !!validationMessage || controlsLocked}
                  isLoading={submitLoading}
                  leftIcon={validationMessage ? <WarningCircle size={18} /> : undefined}
                >
                  Upload fix
                </Button>
              </HStack>
            </Flex>

            {validationMessage ? (
              <Box mb={3} p={3} bg="orange.50" borderWidth="1px" borderColor="orange.200" borderRadius="md">
                <Text fontSize="sm" color="orange.800">
                  {validationMessage}
                </Text>
              </Box>
            ) : null}

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
                      {row.fileRole === 'auto_detect' ? (
                        <Badge variant="subtle" colorScheme="orange">
                          pending auto-detection
                        </Badge>
                      ) : (
                        <Badge variant="subtle" colorScheme={row.fileRole === 'invoice' ? 'blue' : 'gray'}>
                          {row.fileRole === 'invoice' ? 'invoice' : 'supporting doc'}
                        </Badge>
                      )}
                    </Td>
                    <Td fontSize="xs">{row.supportingType || row.contentType || '-'}</Td>
                    <Td isNumeric fontSize="xs">
                      {fmtBytes(row.byteSize)}
                    </Td>
                    <Td>
                      <HStack justify="flex-end">
                        <Tooltip label="Remove from proposed corrected package">
                          <IconButton
                            aria-label="Remove from proposed corrected package"
                            size="xs"
                            variant="ghost"
                            colorScheme="red"
                            icon={row.source === 'clone' ? <Trash size={14} /> : <XCircle size={14} />}
                            onClick={() => removeProposedRow(row.id)}
                            isDisabled={controlsLocked}
                          />
                        </Tooltip>
                      </HStack>
                    </Td>
                  </Tr>
                ))}
                {proposedRows.length === 0 ? (
                  <Tr>
                    <Td colSpan={6}>
                      <Text fontSize="sm" opacity={0.7}>
                        The proposed corrected package is empty.
                      </Text>
                    </Td>
                  </Tr>
                ) : null}
              </Tbody>
            </Table>
          </Box>
        </VStack>

        <Modal
          isOpen={uploadModalOpen && (submitLoading || isProcessing || !!displayFailureMessage || canContinue)}
          onClose={closeUploadModal}
          closeOnOverlayClick={!!displayFailureMessage && !submitLoading && !isProcessing && !canContinue}
          closeOnEsc={!!displayFailureMessage && !submitLoading && !isProcessing && !canContinue}
          size="2xl"
          isCentered
        >
          <ModalOverlay bg="rgba(15, 23, 42, 0.38)" backdropFilter="blur(5px)" />
          <ModalContent borderRadius="28px" overflow="hidden" boxShadow="0 28px 90px rgba(15, 23, 42, 0.28)">
            <ModalHeader
              px={7}
              pt={6}
              pb={3}
              bg="linear-gradient(135deg, rgba(239,248,255,0.98), rgba(255,255,255,0.98))"
            >
              <Text fontSize="lg" fontWeight="800">
                Upload Package Fix
              </Text>
              <Text mt={1} fontSize="sm" color="gray.600" fontWeight="500">
                We are preparing the corrected package for updated AI Advice.
              </Text>
            </ModalHeader>
            {!!displayFailureMessage && !submitLoading && !isProcessing && !canContinue ? <ModalCloseButton /> : null}
            <ModalBody px={7} py={7}>
              {submitLoading || isProcessing ? (
                <ContractorProcessingGraphic label={processingStoryLabel} />
              ) : displayFailureMessage ? (
                <Flex
                  align="flex-start"
                  gap={4}
                  p={5}
                  borderRadius="22px"
                  bg="linear-gradient(135deg, rgba(255,245,240,0.96), rgba(255,255,255,0.98))"
                  border="1px solid rgba(194, 65, 12, 0.18)"
                  boxShadow="0 14px 38px rgba(124, 45, 18, 0.09)"
                >
                  <Box color="orange.600" pt="1px">
                    <WarningCircle size={30} weight="duotone" />
                  </Box>
                  <Box flex="1">
                    <Text fontWeight="800" color="gray.800">
                      {isTechnicalFailure ? 'Upload needs technical help' : 'Upload needs attention'}
                    </Text>
                    <Text mt={1} fontSize="sm" color="gray.700">
                      {displayFailureMessage}
                    </Text>
                  </Box>
                </Flex>
              ) : canContinue ? (
                <Flex direction="column" align="center" gap={4} py={8} textAlign="center">
                  <Box
                    color="green.500"
                    bg="green.50"
                    borderRadius="full"
                    p={4}
                    boxShadow="0 18px 44px rgba(47, 133, 90, 0.16)"
                  >
                    <CheckCircle size={72} weight="duotone" />
                  </Box>
                  <Box>
                    <Text fontSize="2xl" fontWeight="800" color="gray.800">
                      Updated AI Advice is ready
                    </Text>
                    <Text mt={2} fontSize="sm" color="gray.600" maxW="460px">
                      The corrected package has been processed. Continue to review the updated advice.
                    </Text>
                  </Box>
                </Flex>
              ) : null}
            </ModalBody>
            {displayFailureMessage && !submitLoading && !isProcessing ? (
              <ModalFooter px={7} pt={0} pb={7} gap={3}>
                <Button
                  leftIcon={<XCircle size={17} />}
                  colorScheme="orange"
                  borderRadius="full"
                  onClick={clearUploadModalAttention}
                >
                  Try Again
                </Button>
              </ModalFooter>
            ) : canContinue ? (
              <ModalFooter px={7} pt={0} pb={7}>
                <Button colorScheme="green" size="lg" borderRadius="full" onClick={continueToUpdatedReview}>
                  Continue to Updated Review
                </Button>
              </ModalFooter>
            ) : null}
          </ModalContent>
        </Modal>
      </Container>
    </Flex>
  );
}
