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
  Tooltip,
  Tr,
} from '@chakra-ui/react';

type RunHeader = {
  id: string;
  session_id: string;
  contractor_id?: string | null;
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  resolved_invoice_version_id?: string | null;
  status: string;
  cleanup_failed_invoice_artifacts?: boolean;
  total_files: number;
  completed_files: number;
  failed_files: number;
  pipeline_error_code?: string | null;
  pipeline_error_description?: string | null;
  failure_status?: string | null;
  failure_status_subtype?: string | null;
  primary_failure?: StepDiagnostics | null;
  created_at?: string | null;
  updated_at?: string | null;
  completed_at?: string | null;
  duration_seconds?: number | null;
};

type StepDiagnostics = {
  failure_status?: string | null;
  failure_status_subtype?: string | null;
  error_code?: string | null;
  error_category?: string | null;
  error_phase?: string | null;
  retryable?: boolean | null;
  diagnostic_id?: string | null;
  provider_status?: number | null;
  provider_code?: string | null;
  provider_attempt_count?: number | null;
};

type RunInvoiceRow = {
  invoice_id: string;
  invoice_status?: string | null;
  invoice_status_subtype?: string | null;
  invoice_status_subtype_admin_label?: string | null;
  invoice_status_subtype_hint?: string | null;
  invoice_status_subtype_retry_guidance?: string | null;
  invoice_status_updated_at?: string | null;
  invoice_version_id?: string | null;
  invoice_versionno?: number | null;
  original_filename?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type StepRow = StepDiagnostics & {
  id: string;
  ingest_run_id?: string | null;
  ingest_document_id?: string | null;
  ingest_document_original_filename?: string | null;
  invoice_id?: string | null;
  invoice_version_id?: string | null;
  invoice_upgrade_type_id?: string | null;
  supporting_document_type_id?: string | null;
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
  completed_at?: string | null;
  duration_seconds?: number | null;
};

type FailedAttemptDisplay = 'retrying' | 'retried';

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

function fmtDuration(value?: number | null) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds < 0) return '-';
  if (seconds < 1) return `${Math.round(seconds * 1000)} ms`;
  if (seconds < 60) return `${seconds.toFixed(1)} s`;

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds - minutes * 60;
  if (minutes < 60) return `${minutes}m ${remainingSeconds.toFixed(1)}s`;

  const hours = Math.floor(minutes / 60);
  return `${hours}h ${minutes % 60}m`;
}

function statusColor(status?: string | null) {
  const v = String(status || '').toLowerCase();
  if (v.includes('fail') || v === 'package_needs_correction') return 'red';
  if (v.includes('complete') || v.includes('succeed')) return 'green';
  if (v.includes('progress') || v === 'running' || v === 'queued') return 'yellow';
  return 'gray';
}

function progressIndicator(status?: string | null) {
  const v = String(status || '').toLowerCase();

  if (v === 'genai_complete' || v === 'admin_review_inbox' || v === 'approved_pending' || v === 'approved_paid') {
    return <Box w="10px" h="10px" borderRadius="full" bg="green.400" />;
  }

  if (v.endsWith('_failed') || v === 'technical_failure' || v === 'ineligible') {
    return <Box w="10px" h="10px" borderRadius="full" bg="red.400" />;
  }

  if (v === 'package_needs_correction' || v === 'contractor_revision_inbox') {
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
  if (v === 'package_needs_correction') return 'Package Correction';
  if (v === 'technical_failure') return 'Technical Failure';
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

function checkerStatusText(runHeader: RunHeader | null) {
  if (!runHeader) return 'Pipeline checker status will appear after a run starts.';
  if (isActiveRunStatus(runHeader.status)) return 'Pipeline checker pending until the run succeeds.';
  if (runHeader.pipeline_error_code) {
    const failure = runHeader.primary_failure;
    const details = [
      failure?.error_code,
      failure?.provider_status ? `provider HTTP ${failure.provider_status}` : '',
      failure?.provider_code,
      failure?.retryable === false ? 'non-retryable' : '',
      failure?.diagnostic_id ? `diagnostic ${failure.diagnostic_id}` : '',
    ].filter(Boolean);
    return details.length
      ? `${details.join('; ')}.`
      : runHeader.pipeline_error_description || 'Pipeline checker found a problem.';
  }
  if (String(runHeader.status || '').toLowerCase() === 'succeeded') return 'No pipeline checker error recorded.';
  return 'Pipeline checker did not run because this pipeline did not finish successfully.';
}

function checkerBadge(runHeader: RunHeader | null) {
  if (!runHeader) return { label: 'pending', colorScheme: 'gray' };
  if (runHeader.pipeline_error_code) return { label: runHeader.pipeline_error_code, colorScheme: 'red' };
  if (isActiveRunStatus(runHeader.status)) return { label: 'pending', colorScheme: 'yellow' };
  if (String(runHeader.status || '').toLowerCase() === 'succeeded')
    return { label: 'no_error_recorded', colorScheme: 'green' };
  return { label: 'not_run', colorScheme: 'gray' };
}

function stepAttemptKey(step: StepRow) {
  return [
    step.step_type || '',
    step.ingest_document_id || '',
    step.invoice_version_id || '',
    step.invoice_upgrade_type_id || '',
    step.supporting_document_type_id || '',
  ].join('|');
}

function stepTimeMs(step: StepRow) {
  const value = Date.parse(String(step.created_at || ''));
  return Number.isFinite(value) ? value : 0;
}

function buildFailedAttemptDisplay(steps: StepRow[], runIsActive: boolean): Record<string, FailedAttemptDisplay> {
  const ordered = [...steps].sort((a, b) => stepTimeMs(a) - stepTimeMs(b));
  const laterNonFailedByKey = new Set<string>();
  const displayById: Record<string, FailedAttemptDisplay> = {};

  for (let index = ordered.length - 1; index >= 0; index -= 1) {
    const step = ordered[index];
    const key = stepAttemptKey(step);
    const status = String(step.status || '').toLowerCase();

    if (status === 'failed') {
      if (laterNonFailedByKey.has(key)) {
        displayById[step.id] = 'retried';
      } else if (runIsActive) {
        displayById[step.id] = 'retrying';
      }
    } else if (status === 'queued' || status === 'in_progress' || status === 'succeeded') {
      laterNonFailedByKey.add(key);
    }
  }

  return displayById;
}

function renderStepState(step: StepRow, failedAttemptDisplay?: FailedAttemptDisplay) {
  if (String(step.state_label || '').toLowerCase() === 'reused') {
    return <Badge colorScheme="green">reused</Badge>;
  }

  const stepStatus = String(step.status || '').toLowerCase();

  if (stepStatus === 'succeeded') return <Badge colorScheme="green">succeeded</Badge>;
  if (stepStatus === 'failed') {
    if (failedAttemptDisplay === 'retried') return <Badge colorScheme="gray">retried</Badge>;
    if (failedAttemptDisplay === 'retrying') return <Badge colorScheme="orange">retrying</Badge>;
    return <Badge colorScheme="red">failed</Badge>;
  }
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
  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const [steps, setSteps] = useState<StepRow[]>([]);
  const [classifierResults, setClassifierResults] = useState<ClassifierResultRow[]>([]);
  const currentRunIdRef = useRef(runIdValue);
  const stepsRequestSeq = useRef(0);
  const classifierRequestSeq = useRef(0);
  const seenRefreshToken = useRef(refreshToken);

  const loadRunHeader = useCallback(async (id: string) => {
    if (!id) return;
    setRunError('');
    try {
      const res = await fetch(`/api/claims/admin/ingest_runs/${encodeURIComponent(id)}`, {
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

  const loadRunInvoices = useCallback(async (id: string): Promise<RunInvoiceRow[]> => {
    if (!id) return [];
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
      if (String(id).trim() !== currentRunIdRef.current) return [];
      const rows = Array.isArray(data?.rows) ? data.rows : [];
      setInvoiceRows(rows);
      return rows;
    } catch (e: any) {
      if (String(id).trim() !== currentRunIdRef.current) return [];
      setRowsError(e?.message || 'Failed to load run invoices.');
      setInvoiceRows([]);
      return [];
    } finally {
      if (String(id).trim() === currentRunIdRef.current) setRowsLoading(false);
    }
  }, []);

  const loadRunSteps = useCallback(async (id: string) => {
    if (!id) return;
    const requestRunId = String(id).trim();
    const requestSeq = stepsRequestSeq.current + 1;
    stepsRequestSeq.current = requestSeq;
    setStepsLoading(true);
    setStepsError('');
    try {
      const params = new URLSearchParams({ page: '1', per: '500', sort: 'created_at:asc' });

      const res = await fetch(
        `/api/claims/admin/ingest_runs/${encodeURIComponent(requestRunId)}/steps?${params.toString()}`,
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
      if (requestSeq !== stepsRequestSeq.current) return;
      setSteps(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      if (requestRunId !== currentRunIdRef.current) return;
      if (requestSeq !== stepsRequestSeq.current) return;
      setStepsError(e?.message || 'Failed to load ingest step runs.');
      setSteps([]);
    } finally {
      if (requestRunId === currentRunIdRef.current && requestSeq === stepsRequestSeq.current) {
        setStepsLoading(false);
      }
    }
  }, []);

  const loadClassifierResults = useCallback(async (invoiceId: string, id: string) => {
    if (!invoiceId || !id) {
      setClassifierResults([]);
      return;
    }
    const requestRunId = String(id).trim();
    const requestSeq = classifierRequestSeq.current + 1;
    classifierRequestSeq.current = requestSeq;
    try {
      const params = new URLSearchParams({ ingest_run_id: requestRunId, limit: '1' });
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
      if (requestRunId !== currentRunIdRef.current || requestSeq !== classifierRequestSeq.current) return;
      setClassifierResults(Array.isArray(data?.classifier_results) ? data.classifier_results : []);
    } catch {
      if (requestRunId !== currentRunIdRef.current || requestSeq !== classifierRequestSeq.current) return;
      setClassifierResults([]);
    }
  }, []);

  const refreshAll = useCallback(async () => {
    if (!runIdValue) return;
    const [, nextInvoiceRows] = await Promise.all([
      loadRunHeader(runIdValue),
      loadRunInvoices(runIdValue),
      loadRunSteps(runIdValue),
    ]);
    const relatedInvoiceId = nextInvoiceRows[0]?.invoice_id ? String(nextInvoiceRows[0].invoice_id) : '';
    await loadClassifierResults(relatedInvoiceId, runIdValue);
  }, [loadClassifierResults, loadRunHeader, loadRunInvoices, loadRunSteps, runIdValue]);

  useEffect(() => {
    currentRunIdRef.current = runIdValue;
    stepsRequestSeq.current += 1;
    classifierRequestSeq.current += 1;
    setRunHeader(null);
    setRunError('');
    setRowsLoading(false);
    setRowsError('');
    setInvoiceRows([]);
    setStepsLoading(false);
    setStepsError('');
    setSteps([]);
    setClassifierResults([]);
  }, [runIdValue]);

  useEffect(() => {
    if (!runIdValue) return;
    void refreshAll();
  }, [refreshAll, runIdValue]);

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

  const failedAttemptDisplayById = useMemo(
    () => buildFailedAttemptDisplay(steps, isActiveRunStatus(runHeader?.status)),
    [runHeader?.status, steps],
  );
  const checkerBadgeInfo = checkerBadge(runHeader);

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

      {runIdValue && (
        <Box
          borderWidth="1px"
          borderRadius="md"
          mb={4}
          p={3}
          bg={runHeader?.pipeline_error_code ? 'red.50' : 'gray.50'}
          borderColor={runHeader?.pipeline_error_code ? 'red.200' : 'gray.200'}
        >
          <HStack mb={1} spacing={2}>
            <Text fontSize="sm" fontWeight="bold">
              Pipeline checker
            </Text>
            <Badge colorScheme={checkerBadgeInfo.colorScheme}>{checkerBadgeInfo.label}</Badge>
          </HStack>
          <Text fontSize="sm" whiteSpace="pre-wrap">
            {checkerStatusText(runHeader)}
          </Text>
          {runHeader?.primary_failure?.provider_status ? (
            <HStack mt={2} spacing={2} wrap="wrap">
              <Badge colorScheme="red">HTTP {runHeader.primary_failure.provider_status}</Badge>
              {runHeader.primary_failure.provider_code ? (
                <Badge colorScheme="gray">{runHeader.primary_failure.provider_code}</Badge>
              ) : null}
              <Badge colorScheme={runHeader.primary_failure.retryable === false ? 'red' : 'orange'}>
                {runHeader.primary_failure.retryable === false ? 'non-retryable' : 'retryable'}
              </Badge>
            </HStack>
          ) : null}
        </Box>
      )}

      <Tabs variant="line" isFitted colorScheme="gray">
        <TabList>
          <Tab>Ingest Run</Tab>
          <Tab>Ingest Step Runs</Tab>
        </TabList>
        <TabPanels>
          <TabPanel px={0}>
            <Box borderWidth="1px" borderRadius="md" overflow="auto">
              <Table size="sm" minW="1500px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>start</Th>
                    <Th>end</Th>
                    <Th>duration</Th>
                    <Th>contractor</Th>
                    <Th>status</Th>
                    <Th>files</Th>
                    <Th>root error</Th>
                    <Th>run ID</Th>
                    <Th>session ID</Th>
                    <Th>resolved invoice version</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {runHeader ? (
                    <Tr>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {fmtTs(runHeader.created_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {fmtTs(runHeader.completed_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {fmtDuration(runHeader.duration_seconds)}
                      </Td>
                      <Td fontSize="xs">
                        <Text fontWeight="semibold">
                          {runHeader.contractor_business_name || 'System / no contractor'}
                        </Text>
                        <Text opacity={0.7}>{runHeader.contractor_number || runHeader.contractor_id || '-'}</Text>
                      </Td>
                      <Td>
                        <Badge colorScheme={statusColor(runHeader.status)}>{runHeader.status || '-'}</Badge>
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {runHeader.completed_files}/{runHeader.total_files}
                        {runHeader.failed_files > 0 ? (
                          <Text color="red.700" fontSize="xs">
                            {runHeader.failed_files} failed
                          </Text>
                        ) : null}
                      </Td>
                      <Td fontSize="xs">
                        {runHeader.primary_failure?.error_code || runHeader.pipeline_error_code ? (
                          <Tooltip label={runHeader.pipeline_error_description || runHeader.pipeline_error_code || ''}>
                            <Badge colorScheme="red">
                              {runHeader.primary_failure?.error_code || runHeader.pipeline_error_code}
                            </Badge>
                          </Tooltip>
                        ) : (
                          '-'
                        )}
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        {runHeader.id}
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        {runHeader.session_id || '-'}
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        {runHeader.resolved_invoice_version_id || '-'}
                      </Td>
                    </Tr>
                  ) : (
                    <Tr>
                      <Td colSpan={10}>
                        <HStack py={2}>
                          {runIdValue ? <Spinner size="xs" /> : null}
                          <Text fontSize="sm" opacity={0.7}>
                            {runIdValue ? 'Loading ingest run…' : emptyMessage}
                          </Text>
                        </HStack>
                      </Td>
                    </Tr>
                  )}
                </Tbody>
              </Table>
            </Box>

            <Text fontSize="sm" fontWeight="bold" mt={5} mb={2}>
              Related invoice
            </Text>
            {rowsError && (
              <Text fontSize="sm" color="red.700" mb={2}>
                {rowsError}
              </Text>
            )}
            <Box borderWidth="1px" borderRadius="md" overflow="auto">
              <Table size="sm" minW="1040px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>invoice_id</Th>
                    <Th>filename</Th>
                    <Th>invoice version</Th>
                    <Th>invoice status</Th>
                    <Th>invoice substatus</Th>
                    <Th>stage</Th>
                    <Th>progress</Th>
                    <Th>status updated</Th>
                    <Th>created</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {invoiceRows.map((r) => {
                    const substatusHint = String(r.invoice_status_subtype_hint || '').trim();
                    return (
                      <Tr key={`${r.invoice_version_id}-${r.invoice_id}`}>
                        <Td fontFamily="mono" fontSize="xs">
                          {r.invoice_id}
                        </Td>
                        <Td fontSize="xs">{r.original_filename || '-'}</Td>
                        <Td fontFamily="mono" fontSize="xs">
                          {r.invoice_version_id || '-'}
                        </Td>
                        <Td fontSize="xs">
                          <Badge colorScheme={statusColor(r.invoice_status)}>{r.invoice_status || '-'}</Badge>
                        </Td>
                        <Td fontSize="xs">
                          {r.invoice_status_subtype ? (
                            <Tooltip label={substatusHint || r.invoice_status_subtype} hasArrow placement="top">
                              <Badge colorScheme="orange">{r.invoice_status_subtype}</Badge>
                            </Tooltip>
                          ) : (
                            '-'
                          )}
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
                      <Td colSpan={9}>
                        <Text fontSize="sm" opacity={0.7}>
                          {rowsLoading
                            ? 'Loading related invoice…'
                            : runIdValue
                              ? 'No related invoice yet.'
                              : emptyMessage}
                        </Text>
                      </Td>
                    </Tr>
                  )}
                </Tbody>
              </Table>
            </Box>

            <Box mt={5}>
              <Text fontSize="sm" fontWeight="bold" mb={2}>
                Related invoice classifier results
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
                    {!rowsLoading && classifierResults.length === 0 && (
                      <Tr>
                        <Td colSpan={5}>
                          <Text fontSize="sm" opacity={0.7}>
                            No classifier rows yet for the related invoice.
                          </Text>
                        </Td>
                      </Tr>
                    )}
                  </Tbody>
                </Table>
              </Box>
            </Box>
          </TabPanel>

          <TabPanel px={0}>
            {stepsError && (
              <Text fontSize="sm" color="red.700" mb={2}>
                {stepsError}
              </Text>
            )}

            <Box borderWidth="1px" borderRadius="md" overflow="auto">
              <Table size="sm" minW="2300px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>start</Th>
                    <Th>end</Th>
                    <Th>duration</Th>
                    <Th>step</Th>
                    <Th>status</Th>
                    <Th>invoice version</Th>
                    <Th>ingest document / filename</Th>
                    <Th>upgrade type</Th>
                    <Th>supporting type</Th>
                    <Th>error code</Th>
                    <Th>provider</Th>
                    <Th>diagnostic</Th>
                    <Th>error / note</Th>
                  </Tr>
                </Thead>
                <Tbody>
                  {steps.map((s) => (
                    <Tr key={s.id}>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {fmtTs(s.created_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {fmtTs(s.completed_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {fmtDuration(s.duration_seconds)}
                      </Td>
                      <Td fontSize="xs">{s.step_type || '-'}</Td>
                      <Td fontSize="xs">{renderStepState(s, failedAttemptDisplayById[s.id])}</Td>
                      <Td fontSize="xs" fontFamily="mono">
                        {s.invoice_version_id || '-'}
                      </Td>
                      <Td fontSize="xs">
                        <Text fontWeight="semibold">{s.ingest_document_original_filename || '-'}</Text>
                        <Text fontFamily="mono" opacity={0.7}>
                          {s.ingest_document_id || '-'}
                        </Text>
                      </Td>
                      <Td fontSize="xs" fontFamily="mono">
                        {s.invoice_upgrade_type_id || '-'}
                      </Td>
                      <Td fontSize="xs" fontFamily="mono">
                        {s.supporting_document_type_id || '-'}
                      </Td>
                      <Td fontSize="xs">{s.error_code ? <Badge colorScheme="red">{s.error_code}</Badge> : '-'}</Td>
                      <Td fontSize="xs">
                        {s.provider_status ? (
                          <>
                            <Text fontWeight="bold">HTTP {s.provider_status}</Text>
                            <Text>{s.provider_code || '-'}</Text>
                          </>
                        ) : (
                          '-'
                        )}
                      </Td>
                      <Td fontSize="xs" fontFamily="mono">
                        {s.diagnostic_id || '-'}
                      </Td>
                      <Td fontSize="xs">{s.error_text || s.step_note || '-'}</Td>
                    </Tr>
                  ))}

                  {!stepsLoading && steps.length === 0 && (
                    <Tr>
                      <Td colSpan={13}>
                        <Text fontSize="sm" opacity={0.7}>
                          {runIdValue ? 'No ingest step runs recorded yet.' : emptyMessage}
                        </Text>
                      </Td>
                    </Tr>
                  )}
                  {stepsLoading && steps.length === 0 && (
                    <Tr>
                      <Td colSpan={13}>
                        <HStack py={2}>
                          <Spinner size="xs" />
                          <Text fontSize="sm">Loading ingest step runs…</Text>
                        </HStack>
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
