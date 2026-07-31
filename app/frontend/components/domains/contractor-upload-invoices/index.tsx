import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  Container,
  Flex,
  HStack,
  Modal,
  ModalBody,
  ModalContent,
  ModalFooter,
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
import { CheckCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useMst } from '../../../setup/root';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { CustomMessageBox } from '../../shared/base/custom-message-box';
import { ContractorProcessingGraphic } from '../../shared/claims/contractor-processing-graphic';
import {
  ClaimsUploadRequestError,
  claimsUploadCaughtErrorMessage,
  claimsUploadRequestError,
  contractorFacingClaimsFailureMessage,
} from '../../shared/claims/upload-error';

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
  invoice_id?: string | null;
  invoice_status?: string | null;
  invoice_status_subtype?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  can_continue?: boolean;
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
  const { sessionStore } = useMst();
  const runIdFromUrl = getParam(location.search, 'ingest_run_id');

  const [contractorError, setContractorError] = useState('');
  const [runId, setRunId] = useState(runIdFromUrl);
  const [uploadModalOpen, setUploadModalOpen] = useState(!!runIdFromUrl);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [submitErrorStatus, setSubmitErrorStatus] = useState<number | null>(null);
  const [failureMessage, setFailureMessage] = useState('');
  const [dismissedFailureRunId, setDismissedFailureRunId] = useState('');
  const [runHeader, setRunHeader] = useState<RunHeader | null>(null);
  const [runError, setRunError] = useState('');
  const [runErrorStatus, setRunErrorStatus] = useState<number | null>(null);

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
        if (!res.ok) throw claimsUploadRequestError(res, data, 'Unable to load your contractor account.');
        if (!cancelled) {
          setContractorError('');
        }
      } catch (error: unknown) {
        if (!cancelled) {
          const message = claimsUploadCaughtErrorMessage(error, 'Unable to load your contractor account.');
          const status = error instanceof ClaimsUploadRequestError ? error.status : null;
          setContractorError(message);
          if (status === 401) {
            sessionStore.setTokenExpired(true);
          }
        }
      }
    };

    void loadContractor();

    return () => {
      cancelled = true;
    };
  }, [sessionStore]);

  const loadRunHeader = async (id: string) => {
    if (!id) return;
    try {
      const res = await fetch(`/api/claims/contractor/ingest/runs/${encodeURIComponent(id)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
        cache: 'no-store',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw claimsUploadRequestError(res, data, 'We could not check the status of your upload.');
      setRunHeader(data as RunHeader);
      setRunError('');
      setRunErrorStatus(null);
      setFailureMessage(data?.failure_message ? String(data.failure_message) : '');
    } catch (error: unknown) {
      setRunError(claimsUploadCaughtErrorMessage(error, 'We could not check the status of your upload.'));
      setRunErrorStatus(error instanceof ClaimsUploadRequestError ? error.status : null);
      setRunHeader(null);
    }
  };

  const refreshRun = async (id = runId) => {
    if (!id) return;
    await loadRunHeader(id);
  };

  useEffect(() => {
    if (!runId) return;
    void refreshRun(runId);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runId]);

  const shouldPoll = useMemo(() => {
    const runStatus = String(runHeader?.status || '').toLowerCase();
    return runId && (runStatus === 'queued' || runStatus === 'running');
  }, [runHeader?.status, runId]);

  useEffect(() => {
    if (!shouldPoll) return;
    const id = window.setInterval(() => {
      void refreshRun();
    }, 3000);
    return () => window.clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shouldPoll, runId]);

  const clearUploadAttention = () => {
    setFailureMessage('');
    setSubmitError('');
    setSubmitErrorStatus(null);
    setRunError('');
    setRunErrorStatus(null);
    if (runId) setDismissedFailureRunId(runId);
  };

  const closeUploadModal = () => {
    if (submitLoading || isProcessing) return;
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
    setSubmitErrorStatus(null);
    setFailureMessage('');
    setDismissedFailureRunId('');
    setRunError('');
    setRunErrorStatus(null);
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
      if (!res.ok) throw claimsUploadRequestError(res, data, 'We could not upload your invoice package.');

      const nextRunId = String(data?.ingest_run_id || '').trim();
      const nextSessionId = String(data?.session_id || '').trim();
      if (!nextRunId) throw new Error('The upload response did not include an upload id.');

      setRunId(nextRunId);
      setParams(navigate, location, { ingest_run_id: nextRunId, session_id: nextSessionId });
      if (data?.failure_message) setFailureMessage(String(data.failure_message));
    } catch (error: unknown) {
      setSubmitError(claimsUploadCaughtErrorMessage(error, 'We could not upload your invoice package.'));
      setSubmitErrorStatus(error instanceof ClaimsUploadRequestError ? error.status : null);
    } finally {
      setSubmitLoading(false);
    }
  };

  const failureDismissedForCurrentRun = !!runId && dismissedFailureRunId === runId;
  const visibleFailureMessage = failureDismissedForCurrentRun ? '' : failureMessage;
  const invoiceStatus = String(runHeader?.invoice_status || '').toLowerCase();
  const hasFailedRows =
    !!visibleFailureMessage ||
    invoiceStatus.endsWith('_failed') ||
    invoiceStatus === 'package_needs_correction' ||
    invoiceStatus === 'technical_failure';
  const hasProcessingRows =
    invoiceStatus.includes('queued') || invoiceStatus.includes('progress') || invoiceStatus === 'ocr_complete';
  const canContinue = runHeader?.can_continue === true;
  const runStatus = String(runHeader?.status || '').toLowerCase();
  const runFailed = runStatus === 'failed';
  const runTerminal = runStatus === 'failed' || runStatus === 'succeeded' || runStatus === 'partial';
  const isProcessing =
    submitLoading ||
    (!failureMessage &&
      !!runId &&
      !canContinue &&
      !runTerminal &&
      (runStatus === 'queued' || runStatus === 'running' || hasProcessingRows || !runHeader?.invoice_id));
  const fallbackFailureMessage =
    !failureDismissedForCurrentRun && (hasFailedRows || runFailed)
      ? 'We could not prepare your AI advice right now. Please try uploading the same files again later.'
      : '';
  const displayFailureMessage = contractorFacingClaimsFailureMessage(
    submitError || runError || visibleFailureMessage || fallbackFailureMessage,
  );
  const authenticationExpired = [submitErrorStatus, runErrorStatus].includes(401);
  const uploadNeedsTechnicalHelp =
    runHeader?.failure_status === 'technical_failure' || invoiceStatus === 'technical_failure';
  const uploadErrorStatus = submitErrorStatus ?? runErrorStatus;
  const uploadMessageIsWarning =
    [413, 422, 429].includes(uploadErrorStatus || 0) || ((hasFailedRows || runFailed) && !uploadNeedsTechnicalHelp);
  const processingStoryLabel = (() => {
    if (submitLoading || runStatus === 'queued') return 'Uploading your files';
    if (!runHeader?.invoice_id) return 'Reading your files';

    if (invoiceStatus.startsWith('upload_')) return 'Uploading your files';
    if (invoiceStatus.startsWith('ocr_')) return 'Reading your files';
    if (invoiceStatus === 'ocr_complete') return 'Sorting invoice and support documents';
    if (invoiceStatus.startsWith('genai_')) return 'Preparing AI Advice';
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
    if (displayFailureMessage) {
      setUploadModalOpen(false);
      if (authenticationExpired) {
        sessionStore.setTokenExpired(true);
      }
      return;
    }

    if (submitLoading || isProcessing || canContinue) {
      setUploadModalOpen(true);
    }
  }, [authenticationExpired, canContinue, displayFailureMessage, isProcessing, sessionStore, submitLoading]);

  const continueToReview = () => {
    if (!canContinue) return;
    if (!runHeader?.invoice_id || !runHeader.session_id) return;

    navigate(
      `/contractor/sessions/${encodeURIComponent(runHeader.session_id)}/invoices/${encodeURIComponent(
        runHeader.invoice_id,
      )}/review?source=upload`,
    );
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Upload Invoice and Supporting Documents" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        {!authenticationExpired && (contractorError || displayFailureMessage) ? (
          <CustomMessageBox
            mb={4}
            status={contractorError || !uploadMessageIsWarning ? 'error' : 'warning'}
            title={
              contractorError
                ? 'Unable to load contractor account'
                : uploadMessageIsWarning
                  ? 'Upload needs attention'
                  : 'Upload could not be completed'
            }
            description={contractorError || displayFailureMessage}
          />
        ) : null}
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
              <Flex justify="flex-start" align="center" mb={3} wrap="wrap" gap={2}>
                <HStack spacing={2}>
                  <Button variant="secondary" onClick={() => fileInputRef.current?.click()} isDisabled={filesLocked}>
                    Add files
                  </Button>
                  <Button
                    variant="outline"
                    colorScheme="red"
                    onClick={() => setSelectedFiles([])}
                    isDisabled={!selectedFiles.length || filesLocked}
                  >
                    Remove all files
                  </Button>
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
                  variant="primary"
                  onClick={() => void handleRunSubmission()}
                  isLoading={submitLoading}
                  loadingText="Uploading..."
                  isDisabled={!selectedFiles.length || !!contractorError || filesLocked}
                >
                  Upload
                </Button>
              </Flex>
            </Box>

            <Modal
              isOpen={uploadModalOpen && (submitLoading || isProcessing || canContinue)}
              onClose={closeUploadModal}
              closeOnOverlayClick={false}
              closeOnEsc={false}
              size="2xl"
              isCentered
            >
              <ModalOverlay bg="rgba(15, 23, 42, 0.38)" backdropFilter="blur(5px)" />
              <ModalContent borderRadius="28px" overflow="hidden" boxShadow="0 28px 90px rgba(15, 23, 42, 0.28)">
                <ModalBody px={7} py={7}>
                  {submitLoading || isProcessing ? (
                    <ContractorProcessingGraphic label={processingStoryLabel} />
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
                          All files uploaded successfully
                        </Text>
                      </Box>
                    </Flex>
                  ) : null}
                </ModalBody>
                {canContinue ? (
                  <ModalFooter px={7} pt={0} pb={7}>
                    <Tooltip label={continueHelp} shouldWrapChildren>
                      <Button variant="primary" size="lg" onClick={continueToReview}>
                        Next
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
