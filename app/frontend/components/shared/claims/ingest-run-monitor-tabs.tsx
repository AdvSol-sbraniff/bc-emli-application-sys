import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
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
  useDisclosure,
} from '@chakra-ui/react';
import { Info } from '@phosphor-icons/react';
import {
  formatIngestDuration,
  formatIngestTimestamp,
  IngestAttemptSummary,
  IngestDiagnosticDrawer,
  IngestDiagnosticSelection,
  IngestInvoiceDiagnostic,
  IngestRunDiagnostic,
  IngestStepDiagnostic,
  ingestStatusColor,
} from './ingest-diagnostic-drawer';

type RunHeader = IngestRunDiagnostic & {
  session_id: string;
  status: string;
  total_files: number;
  completed_files: number;
  failed_files: number;
  attempt_summary?: IngestAttemptSummary | null;
};

type RunInvoiceRow = IngestInvoiceDiagnostic & {
  invoice_id: string;
  invoice_status?: string | null;
  invoice_status_updated_at?: string | null;
};

type StepRow = IngestStepDiagnostic & {
  invoice_id?: string | null;
  invoice_versionno?: number | null;
  document_kind?: string | null;
  invoice_status?: string | null;
  state_label?: string | null;
};

type ClassifierResultRow = {
  id: string;
  invoice_version_id?: string | null;
  invoice_upgrade_type_id?: string | null;
  upgrade_type_key?: string | null;
  upgrade_type_description?: string | null;
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

function statusColor(status?: string | null) {
  const v = String(status || '').toLowerCase();
  if (v.includes('fail') || v === 'package_needs_correction') return 'red';
  if (v.includes('complete') || v.includes('succeed')) return 'green';
  if (v.includes('progress') || v === 'running' || v === 'queued') return 'yellow';
  return 'gray';
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
    const failure = runHeader.terminal_failure;
    const details = [
      failure?.error_code,
      failure?.provider_status ? `provider HTTP ${failure.provider_status}` : '',
      failure?.provider_code,
      failure?.retryable === false ? 'non-retryable' : '',
    ].filter(Boolean);
    return details.length
      ? `${details.join('; ')}.`
      : runHeader.pipeline_error_description || 'Pipeline checker found a problem.';
  }
  if (String(runHeader.status || '').toLowerCase() === 'succeeded') {
    const recovered = runHeader.attempt_summary?.recovered_attempts || 0;
    return recovered
      ? `Pipeline completed successfully after ${recovered} recovered attempt${recovered === 1 ? '' : 's'}.`
      : 'No pipeline checker error recorded.';
  }
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

function renderStepState(step: StepRow) {
  if (String(step.state_label || '').toLowerCase() === 'reused') {
    return <Badge colorScheme="green">reused</Badge>;
  }

  const stepStatus = String(step.display_status || step.status || '').toLowerCase();
  if (['succeeded', 'failed', 'recovered', 'retrying'].includes(stepStatus)) {
    return <Badge colorScheme={ingestStatusColor(stepStatus)}>{stepStatus}</Badge>;
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

function attemptHistory(summary?: IngestAttemptSummary | null) {
  if (summary?.retrying_targets) return `${summary.retrying_targets} retrying`;
  if (summary?.recovered_attempts) return `${summary.recovered_attempts} recovered`;
  if (summary?.failed_targets) return `${summary.failed_targets} failed`;
  return 'No retries';
}

function stepTargetLabel(step: StepRow) {
  return (
    step.ingest_document_original_filename ||
    step.original_filename ||
    step.invoice_upgrade_type_description ||
    step.invoice_upgrade_type_key ||
    step.supporting_document_type_description ||
    step.supporting_document_type_key ||
    'Package / invoice'
  );
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
  const [lastUpdatedAt, setLastUpdatedAt] = useState<Date | null>(null);
  const [diagnosticSelection, setDiagnosticSelection] = useState<IngestDiagnosticSelection | null>(null);
  const diagnosticDrawer = useDisclosure();
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
      setLastUpdatedAt(new Date());
    } catch (e: any) {
      if (String(id).trim() !== currentRunIdRef.current) return;
      setRunError(e?.message || 'Failed to load run header.');
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
      setLastUpdatedAt(new Date());
      return rows;
    } catch (e: any) {
      if (String(id).trim() !== currentRunIdRef.current) return [];
      setRowsError(e?.message || 'Failed to load run invoices.');
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
      setLastUpdatedAt(new Date());
    } catch (e: any) {
      if (requestRunId !== currentRunIdRef.current) return;
      if (requestSeq !== stepsRequestSeq.current) return;
      setStepsError(e?.message || 'Failed to load ingest step runs.');
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
    if (relatedInvoiceId) await loadClassifierResults(relatedInvoiceId, runIdValue);
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
    setLastUpdatedAt(null);
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
    if (!runHeader && invoiceRows.length === 0 && steps.length === 0) return true;

    return (
      isActiveRunStatus(runHeader?.status) ||
      invoiceRows.some((row) => isActiveInvoiceStatus(row.invoice_status)) ||
      steps.some((step) => isActiveStepStatus(step.status))
    );
  }, [invoiceRows, runHeader, runIdValue, steps]);

  const checkerBadgeInfo = checkerBadge(runHeader);

  const openDiagnostic = (selection: IngestDiagnosticSelection) => {
    setDiagnosticSelection(selection);
    diagnosticDrawer.onOpen();
  };

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
          Showing the last successful diagnostics. Refresh failed: {runError}
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
          {runHeader?.terminal_failure?.provider_status ? (
            <HStack mt={2} spacing={2} wrap="wrap">
              <Badge colorScheme="red">HTTP {runHeader.terminal_failure.provider_status}</Badge>
              {runHeader.terminal_failure.provider_code ? (
                <Badge colorScheme="gray">{runHeader.terminal_failure.provider_code}</Badge>
              ) : null}
              <Badge colorScheme={runHeader.terminal_failure.retryable === false ? 'red' : 'orange'}>
                {runHeader.terminal_failure.retryable === false ? 'non-retryable' : 'retryable'}
              </Badge>
            </HStack>
          ) : null}
          {lastUpdatedAt ? (
            <Text fontSize="xs" color="gray.500" mt={2}>
              {shouldPoll ? 'Live monitoring' : 'Last refreshed'} · {lastUpdatedAt.toLocaleTimeString()}
            </Text>
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
              <Table size="sm" minW="1050px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>start</Th>
                    <Th>end</Th>
                    <Th>duration</Th>
                    <Th>contractor</Th>
                    <Th>status</Th>
                    <Th>files</Th>
                    <Th>attempt history</Th>
                    <Th>terminal error</Th>
                    <Th />
                  </Tr>
                </Thead>
                <Tbody>
                  {runHeader ? (
                    <Tr>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {formatIngestTimestamp(runHeader.created_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {formatIngestTimestamp(runHeader.completed_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {formatIngestDuration(runHeader.duration_seconds)}
                      </Td>
                      <Td fontSize="xs">
                        <Text fontWeight="semibold">
                          {runHeader.contractor_business_name || 'System / no contractor'}
                        </Text>
                        <Text opacity={0.7}>{runHeader.contractor_number || '-'}</Text>
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
                      <Td fontSize="xs">{attemptHistory(runHeader.attempt_summary)}</Td>
                      <Td fontSize="xs">
                        {runHeader.terminal_failure?.error_code || runHeader.pipeline_error_code ? (
                          <Tooltip label={runHeader.pipeline_error_description || runHeader.pipeline_error_code || ''}>
                            <Badge colorScheme="red">
                              {runHeader.terminal_failure?.error_code || runHeader.pipeline_error_code}
                            </Badge>
                          </Tooltip>
                        ) : (
                          '-'
                        )}
                      </Td>
                      <Td>
                        <Tooltip label="View identifiers and full run details">
                          <IconButton
                            aria-label="View ingest run details"
                            icon={<Info size={16} />}
                            size="xs"
                            variant="outline"
                            onClick={() =>
                              openDiagnostic({ kind: 'run', title: 'Ingest run details', value: runHeader })
                            }
                          />
                        </Tooltip>
                      </Td>
                    </Tr>
                  ) : (
                    <Tr>
                      <Td colSpan={9}>
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
              <Table size="sm" minW="980px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>filename</Th>
                    <Th>invoice version</Th>
                    <Th>invoice status</Th>
                    <Th>status updated</Th>
                    <Th>created</Th>
                    <Th />
                  </Tr>
                </Thead>
                <Tbody>
                  {invoiceRows.map((r) => {
                    return (
                      <Tr key={`${r.invoice_version_id}-${r.invoice_id}`}>
                        <Td fontSize="xs">{r.original_filename || '-'}</Td>
                        <Td fontSize="xs">{r.invoice_versionno == null ? '-' : `v${r.invoice_versionno}`}</Td>
                        <Td fontSize="xs">
                          <Badge colorScheme={statusColor(r.invoice_status)}>{r.invoice_status || '-'}</Badge>
                        </Td>
                        <Td fontSize="xs">{formatIngestTimestamp(r.invoice_status_updated_at)}</Td>
                        <Td fontSize="xs">{formatIngestTimestamp(r.created_at)}</Td>
                        <Td>
                          <Tooltip label="View invoice identifiers and details">
                            <IconButton
                              aria-label="View related invoice details"
                              icon={<Info size={16} />}
                              size="xs"
                              variant="outline"
                              onClick={() =>
                                openDiagnostic({ kind: 'invoice', title: 'Related invoice details', value: r })
                              }
                            />
                          </Tooltip>
                        </Td>
                      </Tr>
                    );
                  })}

                  {!rowsLoading && invoiceRows.length === 0 && (
                    <Tr>
                      <Td colSpan={6}>
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
                        <Td fontSize="xs">{r.evidence_text || r.classifier_notes || '-'}</Td>
                        <Td fontSize="xs">{formatIngestTimestamp(r.updated_at)}</Td>
                      </Tr>
                    ))}
                    {!rowsLoading && classifierResults.length === 0 && (
                      <Tr>
                        <Td colSpan={4}>
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
              <Table size="sm" minW="1150px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>start</Th>
                    <Th>duration</Th>
                    <Th>step</Th>
                    <Th>attempt</Th>
                    <Th>status</Th>
                    <Th>target</Th>
                    <Th>error code</Th>
                    <Th>provider</Th>
                    <Th>error / note</Th>
                    <Th />
                  </Tr>
                </Thead>
                <Tbody>
                  {steps.map((s) => (
                    <Tr key={s.id}>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {formatIngestTimestamp(s.created_at)}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {formatIngestDuration(s.duration_seconds)}
                      </Td>
                      <Td fontSize="xs">{s.step_type || '-'}</Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {s.attempt_number || 1} of {s.attempt_count || 1}
                      </Td>
                      <Td fontSize="xs">{renderStepState(s)}</Td>
                      <Td fontSize="xs" maxW="280px">
                        <Text fontWeight="semibold" noOfLines={2}>
                          {stepTargetLabel(s)}
                        </Text>
                        {s.invoice_upgrade_type_key || s.supporting_document_type_key ? (
                          <Text color="gray.600">{s.invoice_upgrade_type_key || s.supporting_document_type_key}</Text>
                        ) : null}
                      </Td>
                      <Td fontSize="xs">
                        {s.error_code ? (
                          <Badge colorScheme={s.display_status === 'recovered' ? 'gray' : 'red'}>{s.error_code}</Badge>
                        ) : (
                          '-'
                        )}
                      </Td>
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
                      <Td fontSize="xs">{s.error_text || s.step_note || '-'}</Td>
                      <Td>
                        <Tooltip label="View identifiers and full step details">
                          <IconButton
                            aria-label={`View ${s.step_type || 'ingest'} step details`}
                            icon={<Info size={16} />}
                            size="xs"
                            variant="outline"
                            onClick={() =>
                              openDiagnostic({
                                kind: 'step',
                                title: `Ingest step · ${s.step_type || 'unknown'}`,
                                value: s,
                              })
                            }
                          />
                        </Tooltip>
                      </Td>
                    </Tr>
                  ))}

                  {!stepsLoading && steps.length === 0 && (
                    <Tr>
                      <Td colSpan={10}>
                        <Text fontSize="sm" opacity={0.7}>
                          {runIdValue ? 'No ingest step runs recorded yet.' : emptyMessage}
                        </Text>
                      </Td>
                    </Tr>
                  )}
                  {stepsLoading && steps.length === 0 && (
                    <Tr>
                      <Td colSpan={10}>
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
      <IngestDiagnosticDrawer
        isOpen={diagnosticDrawer.isOpen}
        onClose={diagnosticDrawer.onClose}
        selection={diagnosticSelection}
      />
    </>
  );
}
