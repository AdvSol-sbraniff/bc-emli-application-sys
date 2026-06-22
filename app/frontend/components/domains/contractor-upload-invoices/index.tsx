import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
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
import { CheckCircle, WarningCircle, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { ContractorProcessingGraphic } from '../../shared/claims/contractor-processing-graphic';

type ContractorPortalResponse = {
  contractor?: {
    id: string;
    business_name?: string | null;
    number?: string | null;
  };
  error?: string;
};

type RunHeader = {
  id: string;
  session_id: string;
  status: string;
  failure_status?: string | null;
  failure_status_subtype?: string | null;
  failure_message?: string | null;
  retry_guidance?: string | null;
};

type RunInvoiceRow = {
  invoice_id: string;
  invoice_status?: string | null;
  invoice_status_subtype?: string | null;
  invoice_version_id: string;
  invoice_versionno?: number | null;
  original_filename?: string | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function setParams(
  navigate: ReturnType<typeof useNavigate>,
  location: ReturnType<typeof useLocation>,
  patch: Record<string, string>,
) {
  const params = new URLSearchParams(location.search);
  Object.entries(patch).forEach(([key, value]) => {
    if (!value) params.delete(key);
    else params.set(key, value);
  });
  const qs = params.toString();
  navigate(`${location.pathname}${qs ? `?${qs}` : ''}`, { replace: true });
}

function fileSizeMb(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

export default function ContractorUploadInvoicesScreen() {
  const location = useLocation();
  const navigate = useNavigate();
  const runIdFromUrl = getParam(location.search, 'ingest_run_id');

  const [contractorName, setContractorName] = useState('');
  const [contractorError, setContractorError] = useState('');
  const [runId, setRunId] = useState(runIdFromUrl);
  const [uploadModalOpen, setUploadModalOpen] = useState(!!runIdFromUrl);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [failureMessage, setFailureMessage] = useState('');
  const [dismissedFailureRunId, setDismissedFailureRunId] = useState('');
  const [runHeader, setRunHeader] = useState<RunHeader | null>(null);
  const [runError, setRunError] = useState('');
  const [invoiceRows, setInvoiceRows] = useState<RunInvoiceRow[]>([]);
  const [rowsError, setRowsError] = useState('');

  useEffect(() => setRunId(runIdFromUrl), [runIdFromUrl]);

  useEffect(() => {
    let cancelled = false;

    const loadContractor = async () => {
      try {
        const res = await fetch('/api/claims/contractor/invoices', {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
          cache: 'no-store',
        });
        const data: ContractorPortalResponse = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
        if (!cancelled) {
          setContractorName(data?.contractor?.business_name || data?.contractor?.number || 'your company');
        }
      } catch (error: any) {
        if (!cancelled) setContractorError(error?.message || 'Unable to load contractor account.');
      }
    };

    void loadContractor();

    return () => {
      cancelled = true;
    };
  }, []);

  const loadRunHeader = async (id: string) => {
    if (!id) return;
    setRunError('');
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
      if (data?.failure_message) setFailureMessage(String(data.failure_message));
    } catch (error: any) {
      setRunError(error?.message || 'Failed to check upload status.');
      setRunHeader(null);
    }
  };

  const loadRunInvoices = async (id: string) => {
    if (!id) return;
    setRowsError('');
    try {
      const res = await fetch(`/api/claims/contractor/ingest/runs/${encodeURIComponent(id)}/invoices`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
        cache: 'no-store',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setInvoiceRows(Array.isArray(data?.rows) ? data.rows : []);
      if (data?.failure_message) setFailureMessage(String(data.failure_message));
    } catch (error: any) {
      setRowsError(error?.message || 'Failed to load uploaded invoices.');
      setInvoiceRows([]);
    }
  };

  const refreshAll = async (id = runId) => {
    if (!id) return;
    await Promise.all([loadRunHeader(id), loadRunInvoices(id)]);
  };

  useEffect(() => {
    if (!runId) return;
    void loadRunHeader(runId);
    void loadRunInvoices(runId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runId]);

  const shouldPoll = useMemo(() => {
    const runStatus = String(runHeader?.status || '').toLowerCase();
    return runId && (runStatus === 'queued' || runStatus === 'running');
  }, [runHeader?.status, runId]);

  useEffect(() => {
    if (!shouldPoll) return;
    const id = window.setInterval(() => {
      void refreshAll();
    }, 3000);
    return () => window.clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shouldPoll, runId]);

  const clearUploadAttention = () => {
    setFailureMessage('');
    setSubmitError('');
    setRunError('');
    setRowsError('');
    if (runId) setDismissedFailureRunId(runId);
  };

  const closeUploadModal = () => {
    if (submitLoading || isProcessing) return;
    setUploadModalOpen(false);
  };

  const clearUploadModalAttention = () => {
    clearUploadAttention();
    setUploadModalOpen(false);
  };

  const mergeStagedFiles = (files: File[]) => {
    if (filesLocked) return;

    const supportedEvidenceFiles = files.filter((file) => {
      const type = String(file.type || '').toLowerCase();
      const byType = type === 'application/pdf' || type === 'image/jpeg' || type === 'image/png';
      const byExt = /\.(pdf|jpe?g|png)$/.test(String(file.name || '').toLowerCase());
      return byType || byExt;
    });

    if (!supportedEvidenceFiles.length) return;

    const startingFreshBatch = runTerminal || canContinue;
    clearUploadAttention();
    if (startingFreshBatch) {
      setRunId('');
      setRunHeader(null);
      setInvoiceRows([]);
      setParams(navigate, location, { ingest_run_id: '', session_id: '' });
    }
    setSelectedFiles((prev) => {
      const next = startingFreshBatch ? [] : [...prev];
      supportedEvidenceFiles.forEach((file) => {
        const exists = next.some(
          (item) => item.name === file.name && item.size === file.size && item.lastModified === file.lastModified,
        );
        if (!exists) next.push(file);
      });
      return next;
    });
  };

  const handleFilesPicked = (event: React.ChangeEvent<HTMLInputElement>) => {
    mergeStagedFiles(Array.from(event.target.files || []));
    event.target.value = '';
  };

  const handleDropZoneDragOver = (event: React.DragEvent<HTMLDivElement>) => {
    event.preventDefault();
    event.stopPropagation();
    if (filesLocked) return;
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
    if (filesLocked) return;
    mergeStagedFiles(Array.from(event.dataTransfer?.files || []));
  };

  const handleRunSubmission = async () => {
    setUploadModalOpen(true);
    setSubmitLoading(true);
    setSubmitError('');
    setFailureMessage('');
    setDismissedFailureRunId('');
    setRunError('');
    setRowsError('');
    try {
      if (!selectedFiles.length) throw new Error('Select an invoice package first.');

      const form = new FormData();
      selectedFiles.forEach((file) => form.append('files[]', file, file.name));

      const res = await fetch('/api/claims/contractor/invoices/upload_batch', {
        method: 'POST',
        credentials: 'include',
        body: form,
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const nextRunId = String(data?.ingest_run_id || '').trim();
      const nextSessionId = String(data?.session_id || '').trim();
      if (!nextRunId) throw new Error('The upload response did not include an upload id.');

      setRunId(nextRunId);
      setParams(navigate, location, { ingest_run_id: nextRunId, session_id: nextSessionId });
      if (data?.failure_message) setFailureMessage(String(data.failure_message));
      await refreshAll(nextRunId);
    } catch (error: any) {
      setSubmitError(error?.message || 'Failed to upload invoice package.');
    } finally {
      setSubmitLoading(false);
    }
  };

  const readyRows = invoiceRows.filter((row) => String(row.invoice_status || '').toLowerCase() === 'genai_complete');
  const failureDismissedForCurrentRun = !!runId && dismissedFailureRunId === runId;
  const visibleFailureMessage = failureDismissedForCurrentRun ? '' : failureMessage;
  const hasFailedRows =
    !!visibleFailureMessage ||
    invoiceRows.some((row) => {
      const status = String(row.invoice_status || '').toLowerCase();
      return status.endsWith('_failed') || status === 'package_needs_correction' || status === 'technical_failure';
    });
  const hasProcessingRows = invoiceRows.some((row) => {
    const status = String(row.invoice_status || '').toLowerCase();
    return status.includes('queued') || status.includes('progress') || status === 'ocr_complete';
  });
  const canContinue = invoiceRows.length > 0 && readyRows.length === invoiceRows.length;
  const runStatus = String(runHeader?.status || '').toLowerCase();
  const runFailed = runStatus === 'failed';
  const runTerminal = runStatus === 'failed' || runStatus === 'succeeded' || runStatus === 'partial';
  const isProcessing =
    submitLoading ||
    (!failureMessage &&
      !!runId &&
      !canContinue &&
      !runTerminal &&
      (runStatus === 'queued' || runStatus === 'running' || hasProcessingRows || invoiceRows.length === 0));
  const fallbackFailureMessage =
    !failureDismissedForCurrentRun && (hasFailedRows || runFailed)
      ? 'We could not prepare your AI advice right now. Please try uploading the same files again later.'
      : '';
  const displayFailureMessage = submitError || runError || rowsError || visibleFailureMessage || fallbackFailureMessage;
  const processingStoryLabel = (() => {
    if (submitLoading || runStatus === 'queued') return 'Uploading your package';
    if (!invoiceRows.length) return 'Reading your files';

    const statuses = invoiceRows.map((row) => String(row.invoice_status || '').toLowerCase());
    if (statuses.some((status) => status.startsWith('upload_'))) return 'Uploading your package';
    if (statuses.some((status) => status.startsWith('ocr_'))) return 'Reading your files';
    if (statuses.some((status) => status === 'ocr_complete')) return 'Sorting invoice and support documents';
    if (statuses.some((status) => status.startsWith('genai_'))) return 'Preparing AI Advice';
    if (runStatus === 'running') return 'Extracting invoice evidence';

    return 'Preparing AI Advice';
  })();
  const continueHelp = canContinue
    ? 'Your upload is ready. Continue to review the invoice checks.'
    : hasFailedRows || runFailed
      ? displayFailureMessage
      : hasProcessingRows
        ? 'Preparing AI Advice'
        : 'Upload a package first.';
  const filesLocked = submitLoading || isProcessing || canContinue;

  useEffect(() => {
    if (submitLoading || isProcessing || displayFailureMessage || canContinue) {
      setUploadModalOpen(true);
    }
  }, [canContinue, displayFailureMessage, isProcessing, submitLoading]);

  const continueToReview = () => {
    if (!canContinue) return;
    const firstInvoice = readyRows[0];
    if (!firstInvoice || !runHeader?.session_id) return;

    navigate(
      `/contractor/sessions/${encodeURIComponent(runHeader.session_id)}/invoices/${encodeURIComponent(
        firstInvoice.invoice_id,
      )}/review?source=upload`,
    );
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Upload Invoice Package" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="application/pdf,image/jpeg,image/png,.pdf,.jpg,.jpeg,.png"
            style={{ display: 'none' }}
            disabled={filesLocked}
            onChange={handleFilesPicked}
          />

          <VStack spacing={4} align="stretch" mb={5}>
            <Box p={0} bg="transparent">
              <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={2}>
                <Box>
                  <Text fontSize="lg" fontWeight="bold">
                    Step 1: Upload invoice package
                  </Text>
                  <Text fontSize="sm" opacity={0.75}>
                    Upload one invoice plus any supporting documents for {contractorName || 'your company'}.
                  </Text>
                  {contractorError ? (
                    <Text fontSize="sm" color="red.700" mt={2}>
                      {contractorError}
                    </Text>
                  ) : null}
                </Box>
                <HStack spacing={2}>
                  <Button variant="outline" onClick={() => fileInputRef.current?.click()} isDisabled={filesLocked}>
                    Add files
                  </Button>
                  <Tooltip label="Clear selected files">
                    <IconButton
                      aria-label="Clear selected files"
                      icon={<XCircle size={18} />}
                      variant="ghost"
                      colorScheme="red"
                      onClick={() => setSelectedFiles([])}
                      isDisabled={!selectedFiles.length || filesLocked}
                    />
                  </Tooltip>
                </HStack>
              </Flex>

              <Box
                mb={3}
                p={6}
                borderWidth="2px"
                borderStyle="dashed"
                borderColor={isDragActive && !filesLocked ? 'blue.400' : 'gray.300'}
                bg={isDragActive && !filesLocked ? 'blue.50' : 'gray.50'}
                opacity={filesLocked ? 0.72 : 1}
                borderRadius="md"
                textAlign="center"
                transition="all 0.15s ease"
                onDragOver={handleDropZoneDragOver}
                onDragEnter={handleDropZoneDragOver}
                onDragLeave={handleDropZoneDragLeave}
                onDrop={handleDropZoneDrop}
              >
                <Text fontSize="sm" fontWeight="bold">
                  Drag invoice and support files here
                </Text>
                <Text fontSize="xs" opacity={0.75} mt={1}>
                  PDF, JPG, JPEG, and PNG files are supported.
                </Text>
              </Box>

              <Box borderWidth="1px" borderRadius="md" overflow="auto">
                <Table size="sm" minW="680px">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th>#</Th>
                      <Th>selected file</Th>
                      <Th>size</Th>
                      <Th>action</Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {selectedFiles.map((file, index) => (
                      <Tr key={`${file.name}-${file.size}-${file.lastModified}`}>
                        <Td fontSize="xs">{index + 1}</Td>
                        <Td fontSize="xs">{file.name}</Td>
                        <Td fontSize="xs">{fileSizeMb(file.size)}</Td>
                        <Td>
                          <Button
                            size="xs"
                            variant="ghost"
                            colorScheme="red"
                            onClick={() => setSelectedFiles((prev) => prev.filter((_, i) => i !== index))}
                            isDisabled={filesLocked}
                          >
                            Remove
                          </Button>
                        </Td>
                      </Tr>
                    ))}
                    {selectedFiles.length === 0 && (
                      <Tr>
                        <Td colSpan={4}>
                          <Text fontSize="sm" opacity={0.7}>
                            No files selected yet.
                          </Text>
                        </Td>
                      </Tr>
                    )}
                  </Tbody>
                </Table>
              </Box>

              <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
                <Button
                  colorScheme="blue"
                  onClick={() => void handleRunSubmission()}
                  isLoading={submitLoading}
                  loadingText="Uploading..."
                  isDisabled={!selectedFiles.length || !!contractorError || filesLocked}
                >
                  Upload package
                </Button>
              </Flex>
            </Box>

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
                    Upload Invoice Package
                  </Text>
                  <Text mt={1} fontSize="sm" color="gray.600" fontWeight="500">
                    We are preparing the package for AI Advice.
                  </Text>
                </ModalHeader>
                {!!displayFailureMessage && !submitLoading && !isProcessing && !canContinue ? (
                  <ModalCloseButton />
                ) : null}
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
                          {runHeader?.failure_status === 'technical_failure' ||
                          invoiceRows.some(
                            (row) => String(row.invoice_status || '').toLowerCase() === 'technical_failure',
                          )
                            ? 'Upload needs technical help'
                            : 'Upload needs attention'}
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
                          AI Advice is ready
                        </Text>
                        <Text mt={2} fontSize="sm" color="gray.600" maxW="460px">
                          Your package has been processed. Continue to pre-check the invoice before submitting it.
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
                    <Tooltip label={continueHelp} shouldWrapChildren>
                      <Button colorScheme="green" size="lg" borderRadius="full" onClick={continueToReview}>
                        Continue to Step 2: Pre-check
                      </Button>
                    </Tooltip>
                  </ModalFooter>
                ) : null}
              </ModalContent>
            </Modal>
          </VStack>
        </Box>
      </Container>
    </Flex>
  );
}
