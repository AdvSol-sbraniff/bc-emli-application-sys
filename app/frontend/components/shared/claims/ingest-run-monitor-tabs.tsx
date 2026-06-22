import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  HStack,
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
  Tr,
} from '@chakra-ui/react';

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
  state_label?: string | null;
  step_note?: string | null;
  error_text?: string | null;
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

type IngestRunMonitorTabsProps = {
  runId?: string | null;
  emptyMessage?: string;
  refreshToken?: number;
};

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '-';
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

function isActiveRunStatus(status?: string | null) {
  const v = String(status || '').toLowerCase();
  return v === 'queued' || v === 'running';
}

function isActiveInvoiceStatus(status?: string | null) {
  const v = String(status || '').toLowerCase();
  return v.endsWith('_queued') || v.endsWith('_in_progress');
}

function isActiveStepStatus(status?: string | null) {
  const v = String(status || '').toLowerCase();
  return v === 'queued' || v === 'in_progress';
}

function renderStepState(step: StepRow) {
  if (String(step.state_label || '').toLowerCase() === 'reused') {
    return <Badge colorScheme="green">reused</Badge>;
  }

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

export function IngestRunMonitorTabs({
  runId,
  emptyMessage = 'Start a run to see invoice and step history.',
  refreshToken = 0,
}: IngestRunMonitorTabsProps) {
  const runIdValue = String(runId || '').trim();
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
  const currentRunIdRef = useRef(runIdValue);
  const invoiceStepsRequestSeq = useRef(0);
  const seenRefreshToken = useRef(refreshToken);

  const loadRunHeader = useCallback(async (id: string) => {
    if (!id) return;
    setRunError('');
    try {
      const res = await fetch(`/api/claims/ingest/runs/${encodeURIComponent(id)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        cache: 'no-store',
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      if (String(id).trim() !== currentRunIdRef.current) return;
      setRunHeader(data as RunHeader);
    } catch (e: any) {
      if (String(id).trim() !== currentRunIdRef.current) return;
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
        cache: 'no-store',
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      if (String(id).trim() !== currentRunIdRef.current) return;
      const rows = Array.isArray(data?.rows) ? data.rows : [];
      setInvoiceRows(rows);
      setSelectedInvoiceId((current) => {
        if (current && rows.some((row: RunInvoiceRow) => String(row.invoice_id) === current)) return current;
        return rows[0]?.invoice_id ? String(rows[0].invoice_id) : '';
      });
    } catch (e: any) {
      if (String(id).trim() !== currentRunIdRef.current) return;
      setRowsError(e?.message || 'Failed to load run invoices.');
      setInvoiceRows([]);
    } finally {
      if (String(id).trim() === currentRunIdRef.current) setRowsLoading(false);
    }
  }, []);

  const loadInvoiceSteps = useCallback(
    async (invoiceId: string) => {
      if (!invoiceId) return;
      const requestRunId = runIdValue;
      const requestSeq = invoiceStepsRequestSeq.current + 1;
      invoiceStepsRequestSeq.current = requestSeq;
      setStepsLoading(true);
      setStepsError('');
      try {
        const params = new URLSearchParams({ limit: '500' });
        if (runIdValue) params.set('ingest_run_id', runIdValue);

        const res = await fetch(
          `/api/claims/ingest/invoices/${encodeURIComponent(invoiceId)}/steps?${params.toString()}`,
          {
            method: 'GET',
            headers: { Accept: 'application/json' },
            cache: 'no-store',
            credentials: 'include',
          },
        );
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
        if (requestRunId !== currentRunIdRef.current) return;
        if (requestSeq !== invoiceStepsRequestSeq.current) return;
        setSteps(Array.isArray(data?.rows) ? data.rows : []);
        setClassifierResults(Array.isArray(data?.classifier_results) ? data.classifier_results : []);
      } catch (e: any) {
        if (requestRunId !== currentRunIdRef.current) return;
        if (requestSeq !== invoiceStepsRequestSeq.current) return;
        setStepsError(e?.message || 'Failed to load step history.');
        setSteps([]);
        setClassifierResults([]);
      } finally {
        if (requestRunId === currentRunIdRef.current && requestSeq === invoiceStepsRequestSeq.current) {
          setStepsLoading(false);
        }
      }
    },
    [runIdValue],
  );

  const refreshAll = useCallback(async () => {
    if (!runIdValue) return;
    await Promise.all([loadRunHeader(runIdValue), loadRunInvoices(runIdValue)]);
    if (selectedInvoiceId) await loadInvoiceSteps(selectedInvoiceId);
  }, [loadInvoiceSteps, loadRunHeader, loadRunInvoices, runIdValue, selectedInvoiceId]);

  useEffect(() => {
    currentRunIdRef.current = runIdValue;
    invoiceStepsRequestSeq.current += 1;
    setRunHeader(null);
    setRunError('');
    setRowsLoading(false);
    setRowsError('');
    setInvoiceRows([]);
    setSelectedInvoiceId('');
    setStepsLoading(false);
    setStepsError('');
    setSteps([]);
    setClassifierResults([]);
  }, [runIdValue]);

  useEffect(() => {
    if (!runIdValue) return;
    void loadRunHeader(runIdValue);
    void loadRunInvoices(runIdValue);
  }, [loadRunHeader, loadRunInvoices, runIdValue]);

  useEffect(() => {
    if (!selectedInvoiceId) return;
    void loadInvoiceSteps(selectedInvoiceId);
  }, [loadInvoiceSteps, selectedInvoiceId, runIdValue]);

  useEffect(() => {
    if (refreshToken === seenRefreshToken.current) return;
    seenRefreshToken.current = refreshToken;
    void refreshAll();
  }, [refreshAll, refreshToken]);

  const shouldPoll = useMemo(() => {
    if (!runIdValue) return false;

    return (
      isActiveRunStatus(runHeader?.status) ||
      invoiceRows.some((row) => isActiveInvoiceStatus(row.invoice_status)) ||
      steps.some((step) => isActiveStepStatus(step.status))
    );
  }, [invoiceRows, runHeader?.status, runIdValue, steps]);

  useEffect(() => {
    if (!shouldPoll) return;
    const id = window.setInterval(() => {
      void refreshAll();
    }, 3000);
    return () => window.clearInterval(id);
  }, [refreshAll, shouldPoll]);

  return (
    <>
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
                        <Td fontSize="xs">{r.original_filename || '-'}</Td>
                        <Td fontSize="xs">
                          <Badge colorScheme={statusColor(r.invoice_status)}>{r.invoice_status || '-'}</Badge>
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
                          {runIdValue ? 'No invoice rows for this run yet.' : emptyMessage}
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
                {selectedInvoiceId || '-'}
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
              <Table size="sm" minW="850px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>created</Th>
                    <Th>filename</Th>
                    <Th>document kind</Th>
                    <Th>step</Th>
                    <Th>state</Th>
                    <Th>error / note</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {steps.map((s) => (
                    <Tr key={s.id}>
                      <Td fontSize="xs">{fmtTs(s.created_at)}</Td>
                      <Td fontSize="xs">{s.original_filename || '-'}</Td>
                      <Td fontSize="xs">{s.document_kind || '-'}</Td>
                      <Td fontSize="xs">{s.step_type || '-'}</Td>
                      <Td fontSize="xs">{renderStepState(s)}</Td>
                      <Td fontSize="xs">{s.error_text || s.step_note || '-'}</Td>
                    </Tr>
                  ))}

                  {!stepsLoading && steps.length === 0 && (
                    <Tr>
                      <Td colSpan={6}>
                        <Text fontSize="sm" opacity={0.7}>
                          {runIdValue ? 'No step rows for current selection.' : emptyMessage}
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
    </>
  );
}
