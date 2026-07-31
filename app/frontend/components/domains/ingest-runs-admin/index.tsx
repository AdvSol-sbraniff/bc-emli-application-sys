import React, { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Code,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  FormControl,
  FormLabel,
  HStack,
  IconButton,
  Input,
  Select,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowsClockwise, CaretLeft, CaretRight, Info, MagnifyingGlass } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type IngestRunRow = {
  id: string;
  session_id: string;
  contractor_id?: string | null;
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  resolved_invoice_version_id?: string | null;
  status: string;
  cleanup_failed_invoice_artifacts: boolean;
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

type IngestStepRunRow = StepDiagnostics & {
  id: string;
  ingest_run_id: string;
  session_id: string;
  invoice_version_id?: string | null;
  ingest_document_id?: string | null;
  ingest_document_original_filename?: string | null;
  invoice_upgrade_type_id?: string | null;
  supporting_document_type_id?: string | null;
  step_type: string;
  status: string;
  error_text?: string | null;
  has_di_results_json?: boolean;
  has_genai_results_json?: boolean;
  has_context_window_json?: boolean;
  di_results_json?: unknown;
  genai_results_json?: unknown;
  context_window_json?: unknown;
  created_at?: string | null;
  updated_at?: string | null;
  completed_at?: string | null;
  duration_seconds?: number | null;
};

type GridResponse<T> = {
  rows?: T[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
  };
  error?: string;
  message?: string;
};

type DetailRecord =
  | { kind: 'run'; title: string; value: IngestRunRow }
  | { kind: 'step'; title: string; value: IngestStepRunRow };

const PAGE_SIZES = [25, 50, 100];
const STEP_PAGE_SIZE = 100;

function formatTimestamp(value?: string | null) {
  if (!value) return '—';
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return String(value);
  return parsed.toLocaleString();
}

function formatDuration(value?: number | null) {
  const seconds = Number(value);
  if (!Number.isFinite(seconds) || seconds < 0) return '—';
  if (seconds < 1) return `${Math.round(seconds * 1000)} ms`;
  if (seconds < 60) return `${seconds.toFixed(1)} s`;

  const minutes = Math.floor(seconds / 60);
  const remainingSeconds = seconds - minutes * 60;
  if (minutes < 60) return `${minutes}m ${remainingSeconds.toFixed(1)}s`;

  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return `${hours}h ${remainingMinutes}m`;
}

function statusColor(status?: string | null) {
  switch (String(status || '').toLowerCase()) {
    case 'succeeded':
      return 'green';
    case 'failed':
      return 'red';
    case 'partial':
      return 'orange';
    case 'running':
    case 'in_progress':
      return 'blue';
    case 'queued':
      return 'yellow';
    default:
      return 'gray';
  }
}

function shortId(value?: string | null) {
  if (!value) return '—';
  return value.length > 12 ? `${value.slice(0, 8)}…` : value;
}

function JsonDetail({ value }: { value: unknown }) {
  return (
    <Code
      display="block"
      p={4}
      w="full"
      overflowX="auto"
      whiteSpace="pre-wrap"
      wordBreak="break-word"
      fontSize="xs"
      bg="gray.50"
      borderWidth="1px"
      borderColor="gray.200"
      borderRadius="md"
    >
      {JSON.stringify(value, null, 2)}
    </Code>
  );
}

export default function IngestRunsAdminScreen() {
  const [searchInput, setSearchInput] = useState('');
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('');
  const [sort, setSort] = useState('created_at:desc');
  const [page, setPage] = useState(1);
  const [per, setPer] = useState(25);
  const [runs, setRuns] = useState<IngestRunRow[]>([]);
  const [runTotal, setRunTotal] = useState(0);
  const [runsLoading, setRunsLoading] = useState(false);
  const [runsError, setRunsError] = useState('');
  const [selectedRunId, setSelectedRunId] = useState('');

  const [steps, setSteps] = useState<IngestStepRunRow[]>([]);
  const [stepTotal, setStepTotal] = useState(0);
  const [stepPage, setStepPage] = useState(1);
  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const selectedRunIdRef = useRef('');

  const [detail, setDetail] = useState<DetailRecord | null>(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [detailError, setDetailError] = useState('');
  const detailRequestSequence = useRef(0);
  const detailDrawer = useDisclosure();

  const runPages = Math.max(1, Math.ceil(runTotal / per));
  const stepPages = Math.max(1, Math.ceil(stepTotal / STEP_PAGE_SIZE));
  const selectedRun = useMemo(() => runs.find((row) => row.id === selectedRunId) || null, [runs, selectedRunId]);

  const loadRuns = useCallback(async () => {
    setRunsLoading(true);
    setRunsError('');

    try {
      const params = new URLSearchParams({
        page: String(page),
        per: String(per),
        sort,
      });
      if (query) params.set('q', query);
      if (status) params.set('status', status);

      const response = await fetch(`/api/claims/admin/ingest_runs?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
        cache: 'no-store',
      });
      const payload: GridResponse<IngestRunRow> = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || payload.message || `HTTP ${response.status}`);

      const nextRuns = Array.isArray(payload.rows) ? payload.rows : [];
      setRuns(nextRuns);
      setRunTotal(Number(payload.meta?.total || 0));
      setSelectedRunId((current) => {
        if (current && nextRuns.some((row) => row.id === current)) return current;
        return nextRuns[0]?.id || '';
      });
    } catch (error: any) {
      setRuns([]);
      setRunTotal(0);
      setSelectedRunId('');
      setRunsError(error?.message || 'Failed to load ingest runs.');
    } finally {
      setRunsLoading(false);
    }
  }, [page, per, query, sort, status]);

  const loadSteps = useCallback(async () => {
    if (!selectedRunId) {
      setSteps([]);
      setStepTotal(0);
      setStepsLoading(false);
      setStepsError('');
      return;
    }

    const requestedRunId = selectedRunId;
    setStepsLoading(true);
    setStepsError('');

    try {
      const params = new URLSearchParams({
        page: String(stepPage),
        per: String(STEP_PAGE_SIZE),
        sort: 'created_at:asc',
      });
      const response = await fetch(
        `/api/claims/admin/ingest_runs/${encodeURIComponent(requestedRunId)}/steps?${params.toString()}`,
        {
          method: 'GET',
          headers: { Accept: 'application/json' },
          credentials: 'include',
          cache: 'no-store',
        },
      );
      const payload: GridResponse<IngestStepRunRow> = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || payload.message || `HTTP ${response.status}`);
      if (requestedRunId !== selectedRunIdRef.current) return;

      setSteps(Array.isArray(payload.rows) ? payload.rows : []);
      setStepTotal(Number(payload.meta?.total || 0));
    } catch (error: any) {
      if (requestedRunId !== selectedRunIdRef.current) return;
      setSteps([]);
      setStepTotal(0);
      setStepsError(error?.message || 'Failed to load ingest step runs.');
    } finally {
      if (requestedRunId === selectedRunIdRef.current) setStepsLoading(false);
    }
  }, [selectedRunId, stepPage]);

  useEffect(() => {
    void loadRuns();
  }, [loadRuns]);

  useEffect(() => {
    selectedRunIdRef.current = selectedRunId;
    setStepPage(1);
  }, [selectedRunId]);

  useEffect(() => {
    void loadSteps();
  }, [loadSteps]);

  const submitSearch = (event: FormEvent) => {
    event.preventDefault();
    setPage(1);
    setQuery(searchInput.trim());
  };

  const resetFilters = () => {
    setSearchInput('');
    setQuery('');
    setStatus('');
    setSort('created_at:desc');
    setPage(1);
    setPer(25);
  };

  const openDetail = (nextDetail: DetailRecord) => {
    detailRequestSequence.current += 1;
    setDetailLoading(false);
    setDetailError('');
    setDetail(nextDetail);
    detailDrawer.onOpen();
  };

  const openStepDetail = async (step: IngestStepRunRow) => {
    const requestSequence = detailRequestSequence.current + 1;
    detailRequestSequence.current = requestSequence;
    setDetail({
      kind: 'step',
      title: `Ingest step ${step.id}`,
      value: step,
    });
    setDetailLoading(true);
    setDetailError('');
    detailDrawer.onOpen();

    try {
      const response = await fetch(`/api/claims/admin/ingest_step_runs/${encodeURIComponent(step.id)}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
        cache: 'no-store',
      });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || payload.message || `HTTP ${response.status}`);
      if (requestSequence !== detailRequestSequence.current) return;
      setDetail({
        kind: 'step',
        title: `Ingest step ${step.id}`,
        value: payload as IngestStepRunRow,
      });
    } catch (error: any) {
      if (requestSequence !== detailRequestSequence.current) return;
      setDetailError(error?.message || 'Failed to load ingest step details.');
    } finally {
      if (requestSequence === detailRequestSequence.current) {
        setDetailLoading(false);
      }
    }
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Ingest Runs" />

      <Container maxW="95vw" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white" mb={6}>
          <Flex justify="space-between" align="center" gap={4} mb={4} wrap="wrap">
            <Box>
              <Text fontSize="xl" fontWeight="bold">
                Ingest Runs View
              </Text>
              <Text fontSize="sm" color="gray.600">
                Read-only processing runs, including contractor details and retained failure diagnostics.
              </Text>
            </Box>
            <Tooltip label="Refresh both grids">
              <IconButton
                aria-label="Refresh ingest runs"
                icon={<ArrowsClockwise size={18} />}
                variant="outline"
                onClick={() => {
                  void loadRuns();
                  void loadSteps();
                }}
                isLoading={runsLoading || stepsLoading}
              />
            </Tooltip>
          </Flex>

          <Flex as="form" onSubmit={submitSearch} gap={3} align="end" wrap="wrap" mb={4}>
            <FormControl flex="1" minW="300px">
              <FormLabel fontSize="sm">Search</FormLabel>
              <Input
                value={searchInput}
                onChange={(event) => setSearchInput(event.target.value)}
                placeholder="Run, session, contractor, invoice version, or error code"
              />
            </FormControl>
            <FormControl w="180px">
              <FormLabel fontSize="sm">Status</FormLabel>
              <Select
                value={status}
                onChange={(event) => {
                  setStatus(event.target.value);
                  setPage(1);
                }}
              >
                <option value="">All statuses</option>
                <option value="queued">Queued</option>
                <option value="running">Running</option>
                <option value="succeeded">Succeeded</option>
                <option value="failed">Failed</option>
                <option value="partial">Partial</option>
              </Select>
            </FormControl>
            <FormControl w="240px">
              <FormLabel fontSize="sm">Sort</FormLabel>
              <Select
                value={sort}
                onChange={(event) => {
                  setSort(event.target.value);
                  setPage(1);
                }}
              >
                <option value="created_at:desc">Created — newest first</option>
                <option value="created_at:asc">Created — oldest first</option>
                <option value="updated_at:desc">Updated — newest first</option>
                <option value="completed_at:desc">Completed — newest first</option>
                <option value="contractor_business_name:asc">Contractor — A to Z</option>
                <option value="status:asc">Status — A to Z</option>
              </Select>
            </FormControl>
            <Button
              type="submit"
              leftIcon={<MagnifyingGlass size={17} />}
              bg="#053662"
              color="white"
              _hover={{ bg: '#042b4e' }}
            >
              Search
            </Button>
            <Button variant="outline" borderColor="#2D2D2D" color="#2D2D2D" onClick={resetFilters}>
              Reset all
            </Button>
          </Flex>

          {runsError ? (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text color="red.700">{runsError}</Text>
            </Box>
          ) : null}

          <Box borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1480px">
              <Thead bg="#FAF9F8">
                <Tr>
                  <Th>Start</Th>
                  <Th>End</Th>
                  <Th>Duration</Th>
                  <Th>Contractor</Th>
                  <Th>Status</Th>
                  <Th isNumeric>Files</Th>
                  <Th>Root error</Th>
                  <Th>HTTP status</Th>
                  <Th>Provider code</Th>
                  <Th>Retryable</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {runs.map((run) => {
                  const isSelected = run.id === selectedRunId;
                  return (
                    <Tr
                      key={run.id}
                      cursor="pointer"
                      bg={isSelected ? 'blue.50' : undefined}
                      _hover={{ bg: isSelected ? 'blue.50' : 'gray.50' }}
                      onClick={() => setSelectedRunId(run.id)}
                    >
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatTimestamp(run.created_at)}
                      </Td>
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatTimestamp(run.completed_at)}
                      </Td>
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatDuration(run.duration_seconds)}
                      </Td>
                      <Td fontSize="xs">
                        <Text fontWeight="semibold">{run.contractor_business_name || 'System / no contractor'}</Text>
                        <Text color="gray.600">{run.contractor_number || '—'}</Text>
                      </Td>
                      <Td>
                        <Badge colorScheme={statusColor(run.status)}>{run.status}</Badge>
                      </Td>
                      <Td isNumeric fontSize="xs" whiteSpace="nowrap">
                        {run.completed_files}/{run.total_files}
                        {run.failed_files > 0 ? (
                          <Text color="red.700" fontSize="xs">
                            {run.failed_files} failed
                          </Text>
                        ) : null}
                      </Td>
                      <Td fontSize="xs" maxW="260px">
                        {run.primary_failure?.error_code || run.pipeline_error_code ? (
                          <Tooltip label={run.pipeline_error_description || run.pipeline_error_code || ''}>
                            <Badge colorScheme="red">
                              {run.primary_failure?.error_code || run.pipeline_error_code}
                            </Badge>
                          </Tooltip>
                        ) : (
                          '—'
                        )}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {run.primary_failure?.provider_status ?? '—'}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {run.primary_failure?.provider_code || '—'}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {run.primary_failure?.retryable == null ? '—' : run.primary_failure.retryable ? 'Yes' : 'No'}
                      </Td>
                      <Td>
                        <Tooltip label="View all run fields and structured failure details">
                          <IconButton
                            aria-label={`View ingest run ${run.id}`}
                            icon={<Info size={16} />}
                            size="xs"
                            variant="outline"
                            onClick={(event) => {
                              event.stopPropagation();
                              setSelectedRunId(run.id);
                              openDetail({ kind: 'run', title: `Ingest run ${run.id}`, value: run });
                            }}
                          />
                        </Tooltip>
                      </Td>
                    </Tr>
                  );
                })}

                {runsLoading && runs.length === 0 ? (
                  <Tr>
                    <Td colSpan={11}>
                      <HStack py={3}>
                        <Spinner size="sm" />
                        <Text>Loading ingest runs…</Text>
                      </HStack>
                    </Td>
                  </Tr>
                ) : null}

                {!runsLoading && runs.length === 0 ? (
                  <Tr>
                    <Td colSpan={11}>
                      <Text py={3} color="gray.600">
                        No ingest runs match the current filters.
                      </Text>
                    </Td>
                  </Tr>
                ) : null}
              </Tbody>
            </Table>
          </Box>

          <Flex mt={4} justify="space-between" align="center" gap={3} wrap="wrap">
            <HStack>
              <Text fontSize="sm">
                {runTotal} runs · page {page} of {runPages}
              </Text>
              <Select
                size="sm"
                w="100px"
                value={String(per)}
                onChange={(event) => {
                  setPer(Number(event.target.value));
                  setPage(1);
                }}
              >
                {PAGE_SIZES.map((size) => (
                  <option key={size} value={size}>
                    {size}
                  </option>
                ))}
              </Select>
            </HStack>
            <HStack>
              <IconButton
                aria-label="Previous run page"
                icon={<CaretLeft size={16} />}
                size="sm"
                variant="outline"
                isDisabled={page <= 1}
                onClick={() => setPage((current) => Math.max(1, current - 1))}
              />
              <IconButton
                aria-label="Next run page"
                icon={<CaretRight size={16} />}
                size="sm"
                variant="outline"
                isDisabled={page >= runPages}
                onClick={() => setPage((current) => Math.min(runPages, current + 1))}
              />
            </HStack>
          </Flex>
        </Box>

        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Box mb={4}>
            <Text fontSize="xl" fontWeight="bold">
              Ingest Step Runs
            </Text>
            <Text fontSize="sm" color="gray.600">
              {selectedRun
                ? `Read-only step attempts for ${selectedRun.contractor_business_name || 'system run'} — ${selectedRun.id}`
                : 'Select an ingest run above to see its processing steps.'}
            </Text>
          </Box>

          {stepsError ? (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text color="red.700">{stepsError}</Text>
            </Box>
          ) : null}

          <Box borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" overflow="auto">
            <Table size="sm" minW="2540px">
              <Thead bg="#FAF9F8">
                <Tr>
                  <Th>Start</Th>
                  <Th>End</Th>
                  <Th>Duration</Th>
                  <Th>Step</Th>
                  <Th>Status</Th>
                  <Th>Invoice version</Th>
                  <Th>Ingest document / filename</Th>
                  <Th>Upgrade type</Th>
                  <Th>Supporting type</Th>
                  <Th>Error code</Th>
                  <Th>HTTP status</Th>
                  <Th>Provider code</Th>
                  <Th>Retryable</Th>
                  <Th>Diagnostic ID</Th>
                  <Th>Error text</Th>
                  <Th>Payloads</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {steps.map((step) => {
                  const payloadCount = [
                    step.has_di_results_json,
                    step.has_genai_results_json,
                    step.has_context_window_json,
                  ].filter(Boolean).length;
                  return (
                    <Tr key={step.id}>
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatTimestamp(step.created_at)}
                      </Td>
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatTimestamp(step.completed_at)}
                      </Td>
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatDuration(step.duration_seconds)}
                      </Td>
                      <Td fontSize="xs" fontWeight="semibold">
                        {step.step_type}
                      </Td>
                      <Td>
                        <Badge colorScheme={statusColor(step.status)}>{step.status}</Badge>
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        <Tooltip label={step.invoice_version_id || ''}>{shortId(step.invoice_version_id)}</Tooltip>
                      </Td>
                      <Td fontSize="xs" maxW="260px">
                        {step.ingest_document_original_filename ? (
                          <>
                            <Tooltip label={step.ingest_document_original_filename}>
                              <Text noOfLines={2} fontWeight="semibold">
                                {step.ingest_document_original_filename}
                              </Text>
                            </Tooltip>
                            <Tooltip label={step.ingest_document_id || ''}>
                              <Text fontFamily="mono" color="gray.600">
                                {shortId(step.ingest_document_id)}
                              </Text>
                            </Tooltip>
                          </>
                        ) : (
                          <Tooltip label={step.ingest_document_id || ''}>
                            <Text fontFamily="mono">{shortId(step.ingest_document_id)}</Text>
                          </Tooltip>
                        )}
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        <Tooltip label={step.invoice_upgrade_type_id || ''}>
                          {shortId(step.invoice_upgrade_type_id)}
                        </Tooltip>
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        <Tooltip label={step.supporting_document_type_id || ''}>
                          {shortId(step.supporting_document_type_id)}
                        </Tooltip>
                      </Td>
                      <Td fontSize="xs">
                        {step.error_code ? <Badge colorScheme="red">{step.error_code}</Badge> : '—'}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {step.provider_status ?? '—'}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {step.provider_code || '—'}
                      </Td>
                      <Td fontSize="xs" whiteSpace="nowrap">
                        {step.retryable == null ? '—' : step.retryable ? 'Yes' : 'No'}
                      </Td>
                      <Td fontFamily="mono" fontSize="xs">
                        <Tooltip label={step.diagnostic_id || ''}>{shortId(step.diagnostic_id)}</Tooltip>
                      </Td>
                      <Td fontSize="xs" maxW="360px">
                        <Tooltip label={step.error_text || ''}>
                          <Text noOfLines={2} color={step.error_text ? 'red.700' : undefined}>
                            {step.error_text || '—'}
                          </Text>
                        </Tooltip>
                      </Td>
                      <Td fontSize="xs">{payloadCount}</Td>
                      <Td>
                        <Tooltip label="View all step fields and JSON payloads">
                          <IconButton
                            aria-label={`View ingest step ${step.id}`}
                            icon={<Info size={16} />}
                            size="xs"
                            variant="outline"
                            onClick={() => void openStepDetail(step)}
                          />
                        </Tooltip>
                      </Td>
                    </Tr>
                  );
                })}

                {stepsLoading && steps.length === 0 ? (
                  <Tr>
                    <Td colSpan={17}>
                      <HStack py={3}>
                        <Spinner size="sm" />
                        <Text>Loading ingest step runs…</Text>
                      </HStack>
                    </Td>
                  </Tr>
                ) : null}

                {!stepsLoading && steps.length === 0 ? (
                  <Tr>
                    <Td colSpan={17}>
                      <Text py={3} color="gray.600">
                        {selectedRunId ? 'No step runs exist for the selected ingest run.' : 'No ingest run selected.'}
                      </Text>
                    </Td>
                  </Tr>
                ) : null}
              </Tbody>
            </Table>
          </Box>

          <Flex mt={4} justify="space-between" align="center">
            <Text fontSize="sm">
              {stepTotal} steps · page {stepPage} of {stepPages}
            </Text>
            <HStack>
              <IconButton
                aria-label="Previous step page"
                icon={<CaretLeft size={16} />}
                size="sm"
                variant="outline"
                isDisabled={stepPage <= 1}
                onClick={() => setStepPage((current) => Math.max(1, current - 1))}
              />
              <IconButton
                aria-label="Next step page"
                icon={<CaretRight size={16} />}
                size="sm"
                variant="outline"
                isDisabled={stepPage >= stepPages}
                onClick={() => setStepPage((current) => Math.min(stepPages, current + 1))}
              />
            </HStack>
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={detailDrawer.isOpen} placement="right" size="xl" onClose={detailDrawer.onClose}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>{detail?.title || 'Ingest details'}</DrawerHeader>
          <DrawerBody pb={8}>
            <Text fontSize="sm" color="gray.600" mb={4}>
              Read-only {detail?.kind === 'step' ? 'ingest_step_runs' : 'v_ingest_runs'} record.
            </Text>
            {detailLoading ? (
              <HStack>
                <Spinner size="sm" />
                <Text>Loading full step payloads…</Text>
              </HStack>
            ) : null}
            {detailError ? (
              <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                <Text color="red.700">{detailError}</Text>
              </Box>
            ) : null}
            {!detailLoading && detail ? <JsonDetail value={detail.value} /> : null}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
