import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  HStack,
  IconButton,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Table,
  Tabs,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  VStack,
} from '@chakra-ui/react';
import { ArrowsClockwise, Question, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type RunHeader = {
  id: string;
  session_id: string;
  status: string;
  total_files: number;
  completed_files: number;
  failed_files: number;
  created_at?: string | null;
  updated_at?: string | null;
  completed_at?: string | null;
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

type StepRow = {
  id: string;
  ingest_run_id?: string | null;
  invoice_id?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  invoice_status?: string | null;
  step_type?: string | null;
  status?: string | null;
  error_text?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type ClassifierResultRow = {
  id: string;
  invoice_version_id?: string | null;
  upgrade_type_key?: string | null;
  upgrade_type_description?: string | null;
  call_status?: string | null;
  confidence?: number | null;
  evidence_text?: string | null;
  classifier_notes?: string | null;
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
  Object.entries(patch).forEach(([k, v]) => {
    if (!v) params.delete(k);
    else params.set(k, v);
  });
  const qs = params.toString();
  navigate(`${location.pathname}${qs ? `?${qs}` : ''}`, { replace: true });
}

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '—';
}

function statusColor(status?: string | null) {
  const v = String(status || '').toLowerCase();
  if (v.includes('fail')) return 'red';
  if (v.includes('complete') || v.includes('succeed')) return 'green';
  if (v.includes('progress') || v === 'running' || v === 'queued') return 'yellow';
  return 'gray';
}

function progressIndicator(status?: string | null) {
  const v = String(status || '').toLowerCase();

  if (v === 'genai_complete' || v === 'admin_review_inbox' || v === 'approved_pending' || v === 'approved_paid') {
    return <Box w="10px" h="10px" borderRadius="full" bg="green.400" />;
  }

  if (v.endsWith('_failed') || v === 'ineligible') {
    return <Box w="10px" h="10px" borderRadius="full" bg="red.400" />;
  }

  if (v === 'contractor_revision_inbox') {
    return <Box w="10px" h="10px" borderRadius="full" bg="orange.400" />;
  }

  if (v === 'in_review') {
    return <Box w="10px" h="10px" borderRadius="full" bg="blue.400" />;
  }

  return <Spinner size="xs" color="blue.500" />;
}

function pipelineStage(status?: string | null) {
  const v = String(status || '').toLowerCase();
  if (v.startsWith('upload_')) return 'Upload';
  if (v.startsWith('ocr_')) return 'OCR';
  if (v.startsWith('genai_')) return 'GenAI';
  if (v === 'admin_review_inbox') return 'Admin Review';
  if (v === 'contractor_revision_inbox') return 'Contractor Revision';
  if (v === 'in_review') return 'Review';
  if (v === 'approved_pending' || v === 'approved_paid') return 'Approved';
  if (v === 'ineligible') return 'Closed';
  return 'Pending';
}

function fileSizeMb(bytes: number) {
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function renderStepState(step: StepRow) {
  const stepStatus = String(step.status || '').toLowerCase();

  if (stepStatus === 'succeeded') return <Badge colorScheme="green">succeeded</Badge>;
  if (stepStatus === 'failed') return <Badge colorScheme="red">failed</Badge>;
  if (stepStatus === 'queued') return <Badge colorScheme="yellow">queued</Badge>;
  if (stepStatus === 'in_progress') {
    return (
      <HStack spacing={2}>
        <Spinner size="xs" color="blue.500" />
        <Text fontSize="xs">in progress</Text>
      </HStack>
    );
  }

  return <Badge colorScheme="gray">pending</Badge>;
}

export default function UploadInvoiceFixAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();
  const fileInputRef = useRef<HTMLInputElement | null>(null);

  const invoiceId = getParam(location.search, 'invoice_id');
  const contractorBusinessName = getParam(location.search, 'contractor_business_name');
  const runIdFromUrl = getParam(location.search, 'ingest_run_id');

  const [runId, setRunId] = useState(runIdFromUrl);
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [isDragActive, setIsDragActive] = useState(false);
  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [submitOk, setSubmitOk] = useState('');

  const [runHeader, setRunHeader] = useState<RunHeader | null>(null);
  const [runError, setRunError] = useState('');
  const [rowsLoading, setRowsLoading] = useState(false);
  const [rowsError, setRowsError] = useState('');
  const [invoiceRows, setInvoiceRows] = useState<RunInvoiceRow[]>([]);
  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const [steps, setSteps] = useState<StepRow[]>([]);
  const [classifierResults, setClassifierResults] = useState<ClassifierResultRow[]>([]);

  useEffect(() => setRunId(runIdFromUrl), [runIdFromUrl]);

  const loadRunHeader = async (id: string) => {
    if (!id) return;
    setRunError('');
    try {
      const res = await fetch(`/api/claims/ingest/runs/${encodeURIComponent(id)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      setRunHeader((data?.run ?? data) as RunHeader);
    } catch (e: any) {
      setRunHeader(null);
      setRunError(e?.message || 'Could not load ingest run.');
    }
  };

  const loadRunInvoices = async (id: string) => {
    if (!id) return;
    setRowsLoading(true);
    setRowsError('');
    try {
      const res = await fetch(`/api/claims/ingest/runs/${encodeURIComponent(id)}/invoices`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      setInvoiceRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setRowsError(e?.message || 'Could not load run invoices.');
      setInvoiceRows([]);
    } finally {
      setRowsLoading(false);
    }
  };

  const loadInvoiceSteps = async (runIdOverride?: string) => {
    if (!invoiceId) return;
    setStepsLoading(true);
    setStepsError('');
    try {
      const params = new URLSearchParams({ limit: '200' });
      const effectiveRunId = runIdOverride ?? runId;
      if (effectiveRunId) params.set('ingest_run_id', effectiveRunId);
      const res = await fetch(
        `/api/claims/ingest/invoices/${encodeURIComponent(invoiceId)}/steps?${params.toString()}`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
        },
      );
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      setSteps(Array.isArray(data?.rows) ? data.rows : []);
      setClassifierResults(Array.isArray(data?.classifier_results) ? data.classifier_results : []);
    } catch (e: any) {
      setStepsError(e?.message || 'Could not load invoice steps.');
      setSteps([]);
      setClassifierResults([]);
    } finally {
      setStepsLoading(false);
    }
  };

  const refreshAll = async () => {
    if (runId) {
      await Promise.all([loadRunHeader(runId), loadRunInvoices(runId)]);
    }
    await loadInvoiceSteps();
  };

  useEffect(() => {
    void refreshAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [runId, invoiceId]);

  const shouldPoll = useMemo(() => {
    const status = String(runHeader?.status || '').toLowerCase();
    return runId && (status === 'queued' || status === 'running');
  }, [runHeader?.status, runId]);

  useEffect(() => {
    if (!shouldPoll) return;
    const id = window.setInterval(() => {
      void refreshAll();
    }, 3000);
    return () => window.clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shouldPoll, runId, invoiceId]);

  const mergeFile = (file?: File | null) => {
    if (!file) return;
    const byType = String(file.type || '').toLowerCase() === 'application/pdf';
    const byExt = String(file.name || '')
      .toLowerCase()
      .endsWith('.pdf');
    if (!byType && !byExt) return;
    setSelectedFile(file);
  };

  const handleFilesPicked = (event: React.ChangeEvent<HTMLInputElement>) => {
    mergeFile(Array.from(event.target.files || [])[0]);
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
    mergeFile(Array.from(event.dataTransfer?.files || [])[0]);
  };

  const handleRunSubmission = async () => {
    setSubmitLoading(true);
    setSubmitError('');
    setSubmitOk('');
    try {
      if (!invoiceId.trim())
        throw new Error('Missing invoice_id context. Please open this screen from Invoices Admin.');
      if (!selectedFile) throw new Error('Stage one corrected PDF file first.');

      const form = new FormData();
      form.append('invoice_id', invoiceId);
      form.append('pdfs[]', selectedFile, selectedFile.name);

      const res = await fetch(`/api/claims/invoices/${encodeURIComponent(invoiceId)}/upload_fix`, {
        method: 'POST',
        credentials: 'include',
        body: form,
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok || data?.ok === false) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      const nextRunId = String(data?.ingest_run_id || '').trim();
      if (!nextRunId) throw new Error('Fix upload started but no ingest_run_id returned.');

      setRunId(nextRunId);
      setParams(navigate, location, { ingest_run_id: nextRunId });
      setSubmitOk(`Corrected invoice version ${data?.invoice_versionno ?? ''} uploaded. OCR and GenAI are queued.`);
      setSelectedFile(null);
      await Promise.all([loadRunHeader(nextRunId), loadRunInvoices(nextRunId), loadInvoiceSteps(nextRunId)]);
    } catch (e: any) {
      setSubmitError(e?.message || 'Failed to upload corrected invoice.');
    } finally {
      setSubmitLoading(false);
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Upload Corrected Invoice Version" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <input
            ref={fileInputRef}
            type="file"
            accept="application/pdf,.pdf"
            style={{ display: 'none' }}
            onChange={handleFilesPicked}
          />

          <VStack spacing={4} align="stretch" mb={5}>
            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
              <Flex justify="space-between" align="start" wrap="wrap" gap={3}>
                <Box>
                  <Text fontSize="sm" fontWeight="bold" mb={2}>
                    Step 1: Existing Invoice Context
                  </Text>
                  <Text fontSize="xs" opacity={0.75}>
                    This upload creates only a new invoice version. It reuses the existing session, invoice, and
                    contractor.
                  </Text>
                </Box>
                <Tooltip label="This is the same processing pattern as Contractor Draft Simulator, but locked to one existing invoice.">
                  <IconButton aria-label="Upload fix help" icon={<Question size={18} />} variant="outline" />
                </Tooltip>
              </Flex>

              <Box mt={3}>
                <Box>
                  <Text fontSize="xs" opacity={0.7}>
                    Contractor
                  </Text>
                  <Text fontSize="sm" fontWeight="semibold">
                    {contractorBusinessName || '—'}
                  </Text>
                </Box>
              </Box>
            </Box>

            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
              <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={2}>
                <Text fontSize="sm" fontWeight="bold">
                  Step 2: Stage Corrected PDF
                </Text>
                <HStack spacing={2}>
                  <Button variant="outline" onClick={() => fileInputRef.current?.click()}>
                    Choose PDF
                  </Button>
                  <Tooltip label="Clear staged file">
                    <IconButton
                      aria-label="Clear staged file"
                      icon={<XCircle size={18} />}
                      variant="ghost"
                      colorScheme="red"
                      onClick={() => setSelectedFile(null)}
                      isDisabled={!selectedFile}
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
                  Drag and drop the corrected PDF here
                </Text>
                <Text fontSize="xs" opacity={0.75} mt={1}>
                  Only one corrected PDF is allowed when creating a corrected invoice version.
                </Text>
              </Box>

              <Box borderWidth="1px" borderRadius="md" overflow="auto">
                <Table size="sm" minW="760px">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th>filename</Th>
                      <Th>size</Th>
                      <Th>type</Th>
                      <Th>action</Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {selectedFile ? (
                      <Tr>
                        <Td fontSize="xs">{selectedFile.name}</Td>
                        <Td fontSize="xs">{fileSizeMb(selectedFile.size)}</Td>
                        <Td fontSize="xs">{selectedFile.type || 'application/pdf'}</Td>
                        <Td>
                          <Button size="xs" variant="ghost" colorScheme="red" onClick={() => setSelectedFile(null)}>
                            Remove
                          </Button>
                        </Td>
                      </Tr>
                    ) : (
                      <Tr>
                        <Td colSpan={4}>
                          <Text fontSize="sm" opacity={0.7}>
                            No corrected PDF staged yet.
                          </Text>
                        </Td>
                      </Tr>
                    )}
                  </Tbody>
                </Table>
              </Box>
            </Box>

            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
              <Flex justify="space-between" align="center" wrap="wrap" gap={2} mb={3}>
                <Text fontSize="sm" fontWeight="bold">
                  Step 3: Upload and Monitor
                </Text>
                <HStack>
                  <Button
                    colorScheme="blue"
                    onClick={() => void handleRunSubmission()}
                    isLoading={submitLoading}
                    loadingText="Uploading..."
                    isDisabled={!selectedFile || !invoiceId}
                  >
                    Upload Corrected Invoice Version
                  </Button>
                  <Tooltip label="Refresh run context and grids">
                    <IconButton
                      aria-label="Refresh"
                      icon={<ArrowsClockwise size={18} />}
                      onClick={refreshAll}
                      isDisabled={!runId && !invoiceId}
                    />
                  </Tooltip>
                </HStack>
              </Flex>

              {submitError && (
                <Text fontSize="sm" color="red.700" mt={2}>
                  {submitError}
                </Text>
              )}
              {submitOk && (
                <Text fontSize="sm" color="green.700" mt={2}>
                  {submitOk}
                </Text>
              )}
            </Box>
          </VStack>

          {runError && (
            <Text fontSize="sm" color="red.700" mb={4}>
              {runError}
            </Text>
          )}

          <Tabs variant="line" isFitted colorScheme="gray">
            <TabList>
              <Tab>Overall</Tab>
              <Tab>Step History for This Invoice Version</Tab>
            </TabList>
            <TabPanels>
              <TabPanel px={0}>
                {rowsError && (
                  <Text fontSize="sm" color="red.700" mb={2}>
                    {rowsError}
                  </Text>
                )}
                <Box borderWidth="1px" borderRadius="md" overflow="auto">
                  <Table size="sm" minW="920px">
                    <Thead bg="gray.50">
                      <Tr>
                        <Th>invoice_id</Th>
                        <Th>filename</Th>
                        <Th>invoice version</Th>
                        <Th>invoice status</Th>
                        <Th>stage</Th>
                        <Th>progress</Th>
                        <Th>status updated</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {invoiceRows.map((row) => (
                        <Tr key={`${row.invoice_version_id}-${row.invoice_id}`}>
                          <Td fontFamily="mono" fontSize="xs">
                            {row.invoice_id}
                          </Td>
                          <Td fontSize="xs">{row.original_filename || '—'}</Td>
                          <Td fontSize="xs">v{row.invoice_versionno ?? '—'}</Td>
                          <Td fontSize="xs">
                            <Badge colorScheme={statusColor(row.invoice_status)}>{row.invoice_status || '—'}</Badge>
                          </Td>
                          <Td fontSize="xs">{pipelineStage(row.invoice_status)}</Td>
                          <Td>{progressIndicator(row.invoice_status)}</Td>
                          <Td fontSize="xs">{fmtTs(row.invoice_status_updated_at)}</Td>
                        </Tr>
                      ))}

                      {!rowsLoading && invoiceRows.length === 0 && (
                        <Tr>
                          <Td colSpan={7}>
                            <Text fontSize="sm" opacity={0.7}>
                              No invoice rows for this fix run yet.
                            </Text>
                          </Td>
                        </Tr>
                      )}
                    </Tbody>
                  </Table>
                </Box>
              </TabPanel>

              <TabPanel px={0}>
                {stepsError && (
                  <Text fontSize="sm" color="red.700" mb={2}>
                    {stepsError}
                  </Text>
                )}

                <Box mb={4}>
                  <Text fontSize="sm" fontWeight="bold" mb={2}>
                    Classifier results
                  </Text>
                  <Box borderWidth="1px" borderRadius="md" overflow="auto">
                    <Table size="sm" minW="900px">
                      <Thead bg="gray.50">
                        <Tr>
                          <Th>upgrade type</Th>
                          <Th>confidence</Th>
                          <Th>status</Th>
                          <Th>evidence</Th>
                          <Th>updated</Th>
                        </Tr>
                      </Thead>
                      <Tbody>
                        {classifierResults.map((row) => (
                          <Tr key={row.id}>
                            <Td fontSize="xs">
                              <Text fontWeight="bold">
                                {row.upgrade_type_description || row.upgrade_type_key || '-'}
                              </Text>
                              <Text fontFamily="mono" opacity={0.7}>
                                {row.upgrade_type_key || '-'}
                              </Text>
                            </Td>
                            <Td fontSize="xs">{row.confidence ?? '-'}</Td>
                            <Td fontSize="xs">
                              <Badge colorScheme={statusColor(row.call_status)}>{row.call_status || '-'}</Badge>
                            </Td>
                            <Td fontSize="xs">{row.evidence_text || row.classifier_notes || '-'}</Td>
                            <Td fontSize="xs">{fmtTs(row.updated_at)}</Td>
                          </Tr>
                        ))}
                        {!stepsLoading && classifierResults.length === 0 && (
                          <Tr>
                            <Td colSpan={5}>
                              <Text fontSize="sm" opacity={0.7}>
                                No classifier rows yet for this invoice.
                              </Text>
                            </Td>
                          </Tr>
                        )}
                      </Tbody>
                    </Table>
                  </Box>
                </Box>

                <Box borderWidth="1px" borderRadius="md" overflow="auto">
                  <Table size="sm" minW="1000px">
                    <Thead bg="gray.50">
                      <Tr>
                        <Th>created</Th>
                        <Th>run</Th>
                        <Th>version</Th>
                        <Th>filename</Th>
                        <Th>step</Th>
                        <Th>state</Th>
                        <Th>error</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {steps.map((step) => (
                        <Tr key={step.id}>
                          <Td fontSize="xs">{fmtTs(step.created_at)}</Td>
                          <Td fontFamily="mono" fontSize="xs">
                            {step.ingest_run_id || '—'}
                          </Td>
                          <Td fontSize="xs">v{step.invoice_versionno ?? '—'}</Td>
                          <Td fontSize="xs">{step.original_filename || '—'}</Td>
                          <Td fontSize="xs">{step.step_type || '—'}</Td>
                          <Td fontSize="xs">{renderStepState(step)}</Td>
                          <Td fontSize="xs">{step.error_text || '—'}</Td>
                        </Tr>
                      ))}

                      {!stepsLoading && steps.length === 0 && (
                        <Tr>
                          <Td colSpan={7}>
                            <Text fontSize="sm" opacity={0.7}>
                              No step rows for this invoice yet.
                            </Text>
                          </Td>
                        </Tr>
                      )}
                    </Tbody>
                  </Table>
                </Box>
              </TabPanel>
            </TabPanels>
          </Tabs>
        </Box>
      </Container>
    </Flex>
  );
}
