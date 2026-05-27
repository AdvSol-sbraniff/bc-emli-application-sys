import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  HStack,
  IconButton,
  Select,
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
  useDisclosure,
  VStack,
} from '@chakra-ui/react';
import { ArrowsClockwise, Question, XCircle } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ContractorRow = {
  id: string;
  business_name?: string | null;
};

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
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type StepRow = {
  id: string;
  ingest_run_id?: string | null;
  ingest_document_id?: string | null;
  invoice_id?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  document_kind?: string | null;
  invoice_status?: string | null;
  step_type?: string | null;
  status?: string | null;
  error_text?: string | null;
  validationgenai_ruleset_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type ClassifierResultRow = {
  id: string;
  invoice_version_id?: string | null;
  invoice_upgrade_type_id?: string | null;
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

const contractorOptionLabel = (contractor: ContractorRow): string => {
  return contractor.business_name?.trim() || 'Unnamed contractor';
};

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

  const invoiceStatus = String(step.invoice_status || '').toLowerCase();
  const stepType = String(step.step_type || '').toLowerCase();

  if (stepType && invoiceStatus === `${stepType}_queued`) {
    return <Badge colorScheme="yellow">queued</Badge>;
  }

  if (stepType && invoiceStatus === `${stepType}_in_progress`) {
    return (
      <HStack spacing={2}>
        <Spinner size="xs" color="blue.500" />
        <Text fontSize="xs">in progress</Text>
      </HStack>
    );
  }

  return <Badge colorScheme="gray">pending</Badge>;
}

export default function SubmissionSimulatorAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const contractorIdFromUrl = getParam(location.search, 'contractor_id');
  const runIdFromUrl = getParam(location.search, 'ingest_run_id');

  const [contractorId, setContractorId] = useState(contractorIdFromUrl);
  const [runId, setRunId] = useState(runIdFromUrl);

  const [contractors, setContractors] = useState<ContractorRow[]>([]);

  const [selectedFiles, setSelectedFiles] = useState<File[]>([]);
  const fileInputRef = useRef<HTMLInputElement | null>(null);
  const [isDragActive, setIsDragActive] = useState(false);
  const [submitLoading, setSubmitLoading] = useState(false);
  const [submitError, setSubmitError] = useState('');
  const [submitOk, setSubmitOk] = useState('');

  const [runHeader, setRunHeader] = useState<RunHeader | null>(null);
  const [runError, setRunError] = useState('');

  const [rowsLoading, setRowsLoading] = useState(false);
  const [rowsError, setRowsError] = useState('');
  const [invoiceRows, setInvoiceRows] = useState<RunInvoiceRow[]>([]);

  const [selectedInvoiceId, setSelectedInvoiceId] = useState('');

  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const [steps, setSteps] = useState<StepRow[]>([]);
  const [classifierResults, setClassifierResults] = useState<ClassifierResultRow[]>([]);
  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  useEffect(() => setContractorId(contractorIdFromUrl), [contractorIdFromUrl]);
  useEffect(() => setRunId(runIdFromUrl), [runIdFromUrl]);

  const loadContractors = useCallback(async () => {
    try {
      const params = new URLSearchParams({ page: '1', per: '200', sort: 'business_name:asc' });
      const res = await fetch(`/api/claims/admin/contractors?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      setContractors(Array.isArray(data?.rows) ? data.rows : []);
    } catch {
      setContractors([]);
    }
  }, []);

  const loadRunHeader = useCallback(async (id: string) => {
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
      setRunHeader(data as RunHeader);
    } catch (e: any) {
      setRunError(e?.message || 'Failed to load run header.');
      setRunHeader(null);
    }
  }, []);

  const loadRunInvoices = useCallback(async (id: string) => {
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
      const rows = Array.isArray(data?.rows) ? data.rows : [];
      setInvoiceRows(rows);
      if (!selectedInvoiceId && rows[0]?.invoice_id) setSelectedInvoiceId(String(rows[0].invoice_id));
    } catch (e: any) {
      setRowsError(e?.message || 'Failed to load run invoices.');
      setInvoiceRows([]);
    } finally {
      setRowsLoading(false);
    }
  }, [selectedInvoiceId]);

  const loadInvoiceSteps = useCallback(async (invoiceId: string) => {
    if (!invoiceId) return;
    setStepsLoading(true);
    setStepsError('');
    try {
      const params = new URLSearchParams({ limit: '500' });
      if (runId) params.set('ingest_run_id', runId);

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
      setStepsError(e?.message || 'Failed to load step history.');
      setSteps([]);
      setClassifierResults([]);
    } finally {
      setStepsLoading(false);
    }
  }, [runId]);

  const refreshAll = useCallback(async () => {
    if (!runId) return;
    await Promise.all([loadRunHeader(runId), loadRunInvoices(runId)]);
    if (selectedInvoiceId) await loadInvoiceSteps(selectedInvoiceId);
  }, [loadInvoiceSteps, loadRunHeader, loadRunInvoices, runId, selectedInvoiceId]);

  useEffect(() => {
    void loadContractors();
  }, [loadContractors]);

  useEffect(() => {
    if (!runId) return;
    void loadRunHeader(runId);
    void loadRunInvoices(runId);
  }, [loadRunHeader, loadRunInvoices, runId]);

  useEffect(() => {
    if (!selectedInvoiceId) return;
    void loadInvoiceSteps(selectedInvoiceId);
  }, [loadInvoiceSteps, selectedInvoiceId, runId]);

  const shouldPoll = useMemo(() => {
    const s = String(runHeader?.status || '').toLowerCase();
    return runId && (s === 'queued' || s === 'running');
  }, [runHeader?.status, runId]);

  useEffect(() => {
    if (!shouldPoll) return;
    const id = window.setInterval(() => {
      void refreshAll();
    }, 3000);
    return () => window.clearInterval(id);
  }, [refreshAll, selectedInvoiceId, shouldPoll, runId]);

  const handleRunSubmission = async () => {
    setSubmitLoading(true);
    setSubmitError('');
    setSubmitOk('');
    try {
      if (!contractorId.trim()) throw new Error('Select a contractor first.');
      if (!selectedFiles.length) throw new Error('Select one or more PDF files.');

      const form = new FormData();
      if (contractorId.trim()) form.append('contractor_id', contractorId.trim());
      selectedFiles.forEach((f) => form.append('pdfs[]', f, f.name));

      const res = await fetch('/api/claims/ingest/admin_submit_batch', {
        method: 'POST',
        credentials: 'include',
        body: form,
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const nextRunId = String(data?.ingest_run_id || '').trim();
      const nextSessionId = String(data?.session_id || '').trim();
      if (!nextRunId) throw new Error('Run started but no ingest_run_id returned.');

      setRunId(nextRunId);

      setParams(navigate, location, {
        ingest_run_id: nextRunId,
        session_id: nextSessionId,
        contractor_id: contractorId,
      });

      setSubmitOk(`Contractor draft simulation started. Run ${nextRunId}.`);
      setSelectedFiles([]);
      await refreshAll();
    } catch (e: any) {
      setSubmitError(e?.message || 'Failed to start contractor draft simulation.');
    } finally {
      setSubmitLoading(false);
    }
  };

  const openFilePicker = () => {
    fileInputRef.current?.click();
  };

  const mergeStagedFiles = (files: File[]) => {
    const pdfsOnly = files.filter((f) => {
      const byType = String(f.type || '').toLowerCase() === 'application/pdf';
      const byExt = String(f.name || '')
        .toLowerCase()
        .endsWith('.pdf');
      return byType || byExt;
    });

    if (!pdfsOnly.length) return;

    setSelectedFiles((prev: File[]) => {
      const next = [...prev];
      pdfsOnly.forEach((f: File) => {
        const alreadyStaged = next.some(
          (p) => p.name === f.name && p.size === f.size && p.lastModified === f.lastModified,
        );
        if (!alreadyStaged) next.push(f);
      });
      return next;
    });
  };

  const handleFilesPicked = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []) as File[];
    if (!files.length) return;

    mergeStagedFiles(files);

    e.target.value = '';
  };

  const handleDropZoneDragOver = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    if (!isDragActive) setIsDragActive(true);
  };

  const handleDropZoneDragLeave = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragActive(false);
  };

  const handleDropZoneDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    setIsDragActive(false);
    const files = Array.from(e.dataTransfer?.files || []) as File[];
    if (!files.length) return;
    mergeStagedFiles(files);
  };

  const removeStagedFile = (index: number) => {
    setSelectedFiles((prev) => prev.filter((_, i) => i !== index));
  };

  const clearStagedFiles = () => setSelectedFiles([]);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Contractor Draft Simulator" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" mb={3}>
            <HStack spacing={2}>
              <Tooltip label="Help: staged contractor draft processing and run tracking">
                <IconButton
                  aria-label="Open contractor draft simulator help"
                  icon={<Question size={18} />}
                  variant="outline"
                  onClick={onHelpOpen}
                />
              </Tooltip>
            </HStack>
          </Flex>

          <input
            ref={fileInputRef}
            type="file"
            multiple
            accept="application/pdf,.pdf"
            style={{ display: 'none' }}
            onChange={handleFilesPicked}
          />

          <VStack spacing={4} align="stretch" mb={5}>
            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
              <Text fontSize="sm" fontWeight="bold" mb={3}>
                Step 1: Run Context
              </Text>
              <Text fontSize="xs" opacity={0.75} mb={3}>
                A fresh session id is created automatically when the staged batch is submitted.
              </Text>
              <HStack spacing={3} wrap="wrap" align="end">
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    Contractor
                  </Text>
                  <Select value={contractorId} onChange={(e) => setContractorId(e.target.value)} w="330px">
                    <option value="">Select contractor...</option>
                    {contractors.map((c) => (
                      <option key={c.id} value={c.id}>
                        {contractorOptionLabel(c)}
                      </option>
                    ))}
                  </Select>
                </Box>
              </HStack>
            </Box>

            <Box p={4} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
              <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={2}>
                <Text fontSize="sm" fontWeight="bold">
                  Step 2: Stage PDF Files
                </Text>
                <HStack spacing={2}>
                  <Button variant="outline" onClick={openFilePicker}>
                    Add PDFs
                  </Button>
                  <Tooltip label="Clear all staged files">
                    <IconButton
                      aria-label="Clear all staged files"
                      icon={<XCircle size={18} />}
                      variant="ghost"
                      colorScheme="red"
                      onClick={clearStagedFiles}
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
                  Drag and drop PDF files here
                </Text>
                <Text fontSize="xs" opacity={0.75} mt={1}>
                  or use Add PDFs to browse from your device
                </Text>
              </Box>

              <Box borderWidth="1px" borderRadius="md" overflow="auto">
                <Table size="sm" minW="760px">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th>#</Th>
                      <Th>filename</Th>
                      <Th>size</Th>
                      <Th>type</Th>
                      <Th>action</Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {selectedFiles.map((file, index) => (
                      <Tr key={`${file.name}-${file.size}-${file.lastModified}`}>
                        <Td fontSize="xs">{index + 1}</Td>
                        <Td fontSize="xs">{file.name}</Td>
                        <Td fontSize="xs">{fileSizeMb(file.size)}</Td>
                        <Td fontSize="xs">{file.type || 'application/pdf'}</Td>
                        <Td>
                          <Button size="xs" variant="ghost" colorScheme="red" onClick={() => removeStagedFile(index)}>
                            Remove
                          </Button>
                        </Td>
                      </Tr>
                    ))}
                    {selectedFiles.length === 0 && (
                      <Tr>
                        <Td colSpan={5}>
                          <Text fontSize="sm" opacity={0.7}>
                            No staged PDFs yet. Click Add PDFs to build the batch.
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
                  Step 3: Submit and Monitor
                </Text>
                <HStack>
                  <Button
                    colorScheme="blue"
                    onClick={() => void handleRunSubmission()}
                    isLoading={submitLoading}
                    loadingText="Starting..."
                    isDisabled={!selectedFiles.length || !contractorId}
                  >
                    Create Contractor Drafts
                  </Button>
                  <Tooltip label="Refresh run context and grids">
                    <IconButton
                      aria-label="Refresh"
                      icon={<ArrowsClockwise size={18} />}
                      onClick={refreshAll}
                      isDisabled={!runId}
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
              <Tab>Step History for Selected Bundle</Tab>
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
                        <Th>invoice status</Th>
                        <Th>stage</Th>
                        <Th>progress</Th>
                        <Th>status updated</Th>
                        <Th>created</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {invoiceRows.map((r) => {
                        const isSelected = String(r.invoice_id) === String(selectedInvoiceId);
                        return (
                          <Tr
                            key={`${r.invoice_version_id}-${r.invoice_id}`}
                            cursor="pointer"
                            bg={isSelected ? 'blue.50' : 'transparent'}
                            _hover={{ bg: isSelected ? 'blue.100' : 'gray.50' }}
                            onClick={() => setSelectedInvoiceId(String(r.invoice_id))}
                          >
                            <Td fontFamily="mono" fontSize="xs">
                              {r.invoice_id}
                            </Td>
                            <Td fontSize="xs">{r.original_filename || '—'}</Td>
                            <Td fontSize="xs">
                              <Badge colorScheme={statusColor(r.invoice_status)}>{r.invoice_status || '—'}</Badge>
                            </Td>
                            <Td fontSize="xs">{pipelineStage(r.invoice_status)}</Td>
                            <Td>{progressIndicator(r.invoice_status)}</Td>
                            <Td fontSize="xs">{fmtTs(r.invoice_status_updated_at)}</Td>
                            <Td fontSize="xs">{fmtTs(r.created_at)}</Td>
                          </Tr>
                        );
                      })}

                      {!rowsLoading && invoiceRows.length === 0 && (
                        <Tr>
                          <Td colSpan={7}>
                            <Text fontSize="sm" opacity={0.7}>
                              No invoice rows for this run yet.
                            </Text>
                          </Td>
                        </Tr>
                      )}
                    </Tbody>
                  </Table>
                </Box>
              </TabPanel>

              <TabPanel px={0}>
                <HStack mb={3} spacing={3}>
                  <Text fontSize="sm" fontWeight="bold">
                    Selected invoice_id:
                  </Text>
                  <Text fontSize="sm" fontFamily="mono">
                    {selectedInvoiceId || '—'}
                  </Text>
                </HStack>

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
                        {classifierResults.map((r) => (
                          <Tr key={r.id}>
                            <Td fontSize="xs">
                              <Text fontWeight="bold">{r.upgrade_type_description || r.upgrade_type_key || '-'}</Text>
                              <Text fontFamily="mono" opacity={0.7}>
                                {r.upgrade_type_key || '-'}
                              </Text>
                            </Td>
                            <Td fontSize="xs">{r.confidence ?? '-'}</Td>
                            <Td fontSize="xs">
                              <Badge colorScheme={statusColor(r.call_status)}>{r.call_status || '-'}</Badge>
                            </Td>
                            <Td fontSize="xs">{r.evidence_text || r.classifier_notes || '-'}</Td>
                            <Td fontSize="xs">{fmtTs(r.updated_at)}</Td>
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
                        <Th>document</Th>
                        <Th>run</Th>
                        <Th>step</Th>
                        <Th>state</Th>
                        <Th>error</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {steps.map((s) => (
                        <Tr key={s.id}>
                          <Td fontSize="xs">{fmtTs(s.created_at)}</Td>
                          <Td fontSize="xs">
                            <Text>{s.original_filename || 'â€”'}</Text>
                            <Text opacity={0.7}>{s.document_kind || 'â€”'}</Text>
                          </Td>
                          <Td fontFamily="mono" fontSize="xs">
                            {s.ingest_run_id || '—'}
                          </Td>
                          <Td fontSize="xs">{s.step_type || '—'}</Td>
                          <Td fontSize="xs">{renderStepState(s)}</Td>
                          <Td fontSize="xs">{s.error_text || '—'}</Td>
                        </Tr>
                      ))}

                      {!stepsLoading && steps.length === 0 && (
                        <Tr>
                          <Td colSpan={6}>
                            <Text fontSize="sm" opacity={0.7}>
                              No step rows for current selection.
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

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Contractor Draft Simulator Help</DrawerHeader>
          <DrawerBody>
            <VStack align="stretch" spacing={4}>
              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  How this screen works
                </Text>
                <Text fontSize="sm">
                  Step 1 sets the contractor, Step 2 stages PDFs, and Step 3 creates contractor draft invoices.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Files are staged in browser memory until you click Create Contractor Drafts.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Created invoices stop at genai_complete after OCR and GenAI. They do not get a submitter_id or
                  submitted_at until the contractor submits them to admin.
                </Text>
              </Box>

              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  Overall tab
                </Text>
                <Text fontSize="sm">
                  One row per ingest bundle shell invoice in the selected run. Click it to inspect both staged-file and resolved invoice step history.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Progress indicator: spinner means active, green means complete, red means failed.
                </Text>
              </Box>

              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  Step History tab
                </Text>
                <Text fontSize="sm">
                  Shows both staged-file steps and the later resolved invoice steps for the selected bundle invoice.
                </Text>
                <Text fontSize="sm" mt={1}>
                  State values: queued, in progress, succeeded, failed.
                </Text>
              </Box>

              <Box>
                <Text fontSize="sm" fontWeight="bold" mb={1}>
                  Troubleshooting
                </Text>
                <Text fontSize="sm">
                  If rows stay queued, verify Sidekiq claims worker is running and consuming claims queues.
                </Text>
                <Text fontSize="sm" mt={1}>
                  Use /sidekiq to inspect queue depth, busy jobs, retries, and active processes.
                </Text>
              </Box>
            </VStack>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
