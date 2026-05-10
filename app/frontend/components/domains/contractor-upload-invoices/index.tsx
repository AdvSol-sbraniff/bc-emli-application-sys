import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  HStack,
  IconButton,
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
import { ArrowsClockwise, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

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
};

type RunInvoiceRow = {
  invoice_id: string;
  invoice_status?: string | null;
  invoice_status_updated_at?: string | null;
  invoice_version_id: string;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
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

function fmtTs(value?: string | null) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);

  return date.toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  });
}

function fileSizeMb(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function contractorUploadStatusLabel(status?: string | null) {
  const value = String(status || '').toLowerCase();

  if (value === 'genai_complete') return 'Ready to review';
  if (value.endsWith('_failed')) return 'Needs help';
  if (value.includes('queued') || value.includes('progress') || value === 'ocr_complete') return 'Checking invoice...';
  if (value === 'admin_review_inbox') return 'Submitted to admin';
  if (value === 'contractor_revision_inbox') return 'Update requested';
  if (value === 'in_review') return 'With admin';
  if (value === 'approved_pending' || value === 'approved_paid') return 'Approved';

  return value || 'Waiting';
}

function contractorUploadStatusColor(status?: string | null) {
  const value = String(status || '').toLowerCase();

  if (value === 'genai_complete') return 'green';
  if (value.endsWith('_failed')) return 'red';
  if (value.includes('queued') || value.includes('progress') || value === 'ocr_complete') return 'yellow';
  if (value === 'contractor_revision_inbox') return 'orange';
  if (value === 'approved_pending' || value === 'approved_paid') return 'green';

  return 'gray';
}

export default function ContractorUploadInvoicesScreen() {
  const location = useLocation();
  const navigate = useNavigate();
  const runIdFromUrl = getParam(location.search, 'ingest_run_id');

  const [contractorName, setContractorName] = useState('');
  const [contractorError, setContractorError] = useState('');
  const [runId, setRunId] = useState(runIdFromUrl);
  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const [isDragActive, setIsDragActive] = useState(false);
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [submitOk, setSubmitOk] = useState('');
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
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setRunHeader(data as RunHeader);
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
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setInvoiceRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (error: any) {
      setRowsError(error?.message || 'Failed to load uploaded invoices.');
      setInvoiceRows([]);
    }
  };

  const refreshAll = async () => {
    if (!runId) return;
    await Promise.all([loadRunHeader(runId), loadRunInvoices(runId)]);
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

  const mergeStagedFiles = (files: File[]) => {
    const pdfsOnly = files.filter((file) => {
      const byType = String(file.type || '').toLowerCase() === 'application/pdf';
      const byExt = String(file.name || '')
        .toLowerCase()
        .endsWith('.pdf');
      return byType || byExt;
    });

    if (!pdfsOnly.length) return;

    setSelectedFiles((prev) => {
      const next = [...prev];
      pdfsOnly.forEach((file) => {
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
    mergeStagedFiles(Array.from(event.dataTransfer?.files || []));
  };

  const handleRunSubmission = async () => {
    setSubmitLoading(true);
    setSubmitError('');
    setSubmitOk('');
    try {
      if (!selectedFiles.length) throw new Error('Select one or more PDF files.');

      const form = new FormData();
      selectedFiles.forEach((file) => form.append('pdfs[]', file, file.name));

      const res = await fetch('/api/claims/contractor/invoices/upload_batch', {
        method: 'POST',
        credentials: 'include',
        body: form,
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const nextRunId = String(data?.ingest_run_id || '').trim();
      const nextSessionId = String(data?.session_id || '').trim();
      if (!nextRunId) throw new Error('Upload started but no upload id returned.');

      setRunId(nextRunId);
      setSelectedFiles([]);
      setParams(navigate, location, { ingest_run_id: nextRunId, session_id: nextSessionId });
      setSubmitOk('Upload started. We are checking your invoice now.');
      await refreshAll();
    } catch (error: any) {
      setSubmitError(error?.message || 'Failed to upload invoices.');
    } finally {
      setSubmitLoading(false);
    }
  };

  const readyRows = invoiceRows.filter((row) => String(row.invoice_status || '').toLowerCase() === 'genai_complete');
  const hasFailedRows = invoiceRows.some((row) =>
    String(row.invoice_status || '')
      .toLowerCase()
      .endsWith('_failed'),
  );
  const hasProcessingRows = invoiceRows.some((row) => {
    const status = String(row.invoice_status || '').toLowerCase();
    return status.includes('queued') || status.includes('progress') || status === 'ocr_complete';
  });
  const canContinue = invoiceRows.length > 0 && readyRows.length === invoiceRows.length;
  const continueHelp = canContinue
    ? 'Your upload is ready. Continue to review the invoice checks.'
    : hasFailedRows
      ? 'We could not finish checking one or more invoices. Please contact support if this keeps happening.'
      : hasProcessingRows
        ? 'Please wait a few minutes, then click Check upload status. If it still does not finish, contact support.'
        : 'Upload invoice PDFs first, then wait until checks are complete.';

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
      <BlueTitleBar title="Upload Invoice(s)" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="application/pdf,.pdf"
            style={{ display: 'none' }}
            onChange={handleFilesPicked}
          />

          <VStack spacing={4} align="stretch" mb={5}>
            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
              <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={2}>
                <Box>
                  <Text fontSize="lg" fontWeight="bold">
                    Step 1: Upload invoices
                  </Text>
                  <Text fontSize="sm" opacity={0.75}>
                    These invoices will be uploaded for {contractorName || 'your company'} and checked automatically.
                  </Text>
                  {contractorError ? (
                    <Text fontSize="sm" color="red.700" mt={2}>
                      {contractorError}
                    </Text>
                  ) : null}
                </Box>
                <HStack spacing={2}>
                  <Button variant="outline" onClick={() => fileInputRef.current?.click()}>
                    Add PDFs
                  </Button>
                  <Tooltip label="Clear selected files">
                    <IconButton
                      aria-label="Clear selected files"
                      icon={<XCircle size={18} />}
                      variant="ghost"
                      colorScheme="red"
                      onClick={() => setSelectedFiles([])}
                      isDisabled={!selectedFiles.length}
                    />
                  </Tooltip>
                </HStack>
              </Flex>

              <Box
                mb={3}
                p={6}
                borderWidth="2px"
                borderStyle="dashed"
                borderColor={isDragActive ? 'blue.400' : 'gray.300'}
                bg={isDragActive ? 'blue.50' : 'gray.50'}
                borderRadius="md"
                textAlign="center"
                transition="all 0.15s ease"
                onDragOver={handleDropZoneDragOver}
                onDragEnter={handleDropZoneDragOver}
                onDragLeave={handleDropZoneDragLeave}
                onDrop={handleDropZoneDrop}
              >
                <Text fontSize="sm" fontWeight="bold">
                  Drag PDF invoices here
                </Text>
                <Text fontSize="xs" opacity={0.75} mt={1}>
                  or use Add PDFs to browse from your device
                </Text>
              </Box>

              <Box borderWidth="1px" borderRadius="md" overflow="auto">
                <Table size="sm" minW="680px">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th>#</Th>
                      <Th>selected PDF</Th>
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
                            No PDFs selected yet.
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
                  isDisabled={!selectedFiles.length || !!contractorError}
                >
                  Upload invoice(s)
                </Button>
                <Tooltip label="Check whether the automatic invoice checks are finished">
                  <Button
                    variant="outline"
                    leftIcon={<ArrowsClockwise size={18} />}
                    onClick={refreshAll}
                    isDisabled={!runId}
                  >
                    Check upload status
                  </Button>
                </Tooltip>
              </Flex>
            </Box>

            {(submitError || submitOk || runError || rowsError) && (
              <Box p={3} borderWidth="1px" borderRadius="md" bg="gray.50">
                {submitError ? <Text color="red.700">{submitError}</Text> : null}
                {submitOk ? <Text color="green.700">{submitOk}</Text> : null}
                {runError ? <Text color="red.700">{runError}</Text> : null}
                {rowsError ? <Text color="red.700">{rowsError}</Text> : null}
              </Box>
            )}
          </VStack>

          <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={3}>
            <Box>
              <Text fontSize="lg" fontWeight="bold">
                Uploaded invoices
              </Text>
              <Text fontSize="sm" opacity={0.75}>
                When all uploaded invoices say Ready to review, continue to step 2.
              </Text>
            </Box>
            <Tooltip label={continueHelp} shouldWrapChildren>
              <Button colorScheme="green" isDisabled={!canContinue} onClick={continueToReview}>
                Continue to Step 2: Review uploads
              </Button>
            </Tooltip>
          </Flex>

          {!canContinue && invoiceRows.length > 0 ? (
            <Text fontSize="sm" color={hasFailedRows ? 'red.700' : 'gray.700'} mb={3}>
              {continueHelp}
            </Text>
          ) : null}

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="760px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>invoice</Th>
                  <Th>status</Th>
                  <Th>last checked</Th>
                  <Th>uploaded</Th>
                </Tr>
              </Thead>
              <Tbody>
                {invoiceRows.map((row) => (
                  <Tr key={`${row.invoice_version_id}-${row.invoice_id}`}>
                    <Td fontSize="sm">{row.original_filename || `Invoice ${row.invoice_versionno ?? ''}`}</Td>
                    <Td>
                      <Badge colorScheme={contractorUploadStatusColor(row.invoice_status)}>
                        {contractorUploadStatusLabel(row.invoice_status)}
                      </Badge>
                    </Td>
                    <Td fontSize="sm">{fmtTs(row.invoice_status_updated_at || row.updated_at)}</Td>
                    <Td fontSize="sm">{fmtTs(row.created_at)}</Td>
                  </Tr>
                ))}
                {invoiceRows.length === 0 && (
                  <Tr>
                    <Td colSpan={4}>
                      <Text fontSize="sm" opacity={0.7}>
                        Uploaded invoices will appear here after you click Upload invoice(s).
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
        </Box>
      </Container>
    </Flex>
  );
}
