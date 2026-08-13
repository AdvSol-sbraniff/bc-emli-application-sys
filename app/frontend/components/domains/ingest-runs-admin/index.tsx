import React, { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
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
import { IngestProcessPipeCell } from '../../shared/claims/ingest-process-pipeline';
import {
  formatIngestDuration,
  formatIngestTimestamp,
  IngestAttemptSummary,
  IngestDiagnosticDrawer,
  IngestDiagnosticSelection,
  IngestRunDiagnostic,
  IngestStepDiagnostic,
  ingestStatusColor,
} from '../../shared/claims/ingest-diagnostic-drawer';

type IngestRunRow = IngestRunDiagnostic & {
  status: string;
  cleanup_failed_invoice_artifacts: boolean;
  total_files: number;
  completed_files: number;
  failed_files: number;
  attempt_summary?: IngestAttemptSummary | null;
};

type IngestStepRunRow = IngestStepDiagnostic & {
  ingest_run_id: string;
  session_id: string;
  step_type: string;
  status: string;
  has_di_results_json?: boolean;
  has_genai_results_json?: boolean;
  has_context_window_json?: boolean;
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

const PAGE_SIZES = [25, 50, 100];
const STEP_PAGE_SIZE = 100;

function RunAttemptHistory({ summary }: { summary?: IngestAttemptSummary | null }) {
  if (summary?.retrying_targets) return <Badge colorScheme="orange">{summary.retrying_targets} retrying</Badge>;
  if (summary?.recovered_attempts) return <Badge colorScheme="gray">{summary.recovered_attempts} recovered</Badge>;
  if (summary?.failed_targets) return <Badge colorScheme="red">{summary.failed_targets} failed</Badge>;
  return <Text fontSize="xs">No retries</Text>;
}

function stepTargetLabel(step: IngestStepRunRow) {
  return (
    step.ingest_document_original_filename ||
    step.invoice_upgrade_type_description ||
    step.invoice_upgrade_type_key ||
    step.supporting_document_type_description ||
    step.supporting_document_type_key ||
    'Package / invoice'
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
  const [lastUpdatedAt, setLastUpdatedAt] = useState<Date | null>(null);
  const [diagnosticSelection, setDiagnosticSelection] = useState<IngestDiagnosticSelection | null>(null);
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
      setLastUpdatedAt(new Date());
      setSelectedRunId((current) => {
        if (current && nextRuns.some((row) => row.id === current)) return current;
        return nextRuns[0]?.id || '';
      });
    } catch (error: any) {
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
      setLastUpdatedAt(new Date());
    } catch (error: any) {
      if (requestedRunId !== selectedRunIdRef.current) return;
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

  const shouldPoll = useMemo(
    () =>
      runs.some((run) => ['queued', 'running'].includes(String(run.status).toLowerCase())) ||
      steps.some((step) => ['queued', 'in_progress'].includes(String(step.status).toLowerCase())),
    [runs, steps],
  );

  useEffect(() => {
    if (!shouldPoll) return;
    const intervalId = window.setInterval(() => {
      void loadRuns();
      void loadSteps();
    }, 3000);
    return () => window.clearInterval(intervalId);
  }, [loadRuns, loadSteps, shouldPoll]);

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

  const openDetail = (selection: IngestDiagnosticSelection) => {
    setDiagnosticSelection(selection);
    detailDrawer.onOpen();
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
              {lastUpdatedAt ? (
                <Text fontSize="xs" color="gray.500" mt={1}>
                  {shouldPoll ? 'Live monitoring' : 'Last refreshed'} · {lastUpdatedAt.toLocaleTimeString()}
                </Text>
              ) : null}
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
                placeholder="Contractor, filename, run/session/step ID, diagnostic ID, or error code"
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
              <Text color="red.700">Showing the last successful data. Refresh failed: {runsError}</Text>
            </Box>
          ) : null}

          <Box borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1040px">
              <Thead bg="#FAF9F8">
                <Tr>
                  <Th>Start</Th>
                  <Th>Duration</Th>
                  <Th>Contractor</Th>
                  <Th>Run kind</Th>
                  <Th>Status</Th>
                  <Th isNumeric>Files</Th>
                  <Th>Attempt history</Th>
                  <Th>Terminal error</Th>
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
                        {formatIngestTimestamp(run.created_at)}
                      </Td>
                      <Td whiteSpace="nowrap" fontSize="xs">
                        {formatIngestDuration(run.duration_seconds)}
                      </Td>
                      <Td fontSize="xs">
                        <Text fontWeight="semibold">{run.contractor_business_name || 'System / no contractor'}</Text>
                        <Text color="gray.600">{run.contractor_number || '—'}</Text>
                      </Td>
                      <Td fontSize="xs">{run.run_kind || '—'}</Td>
                      <Td>
                        <Badge colorScheme={ingestStatusColor(run.status)}>{run.status}</Badge>
                      </Td>
                      <Td isNumeric fontSize="xs" whiteSpace="nowrap">
                        {run.completed_files}/{run.total_files}
                        {run.failed_files > 0 ? (
                          <Text color="red.700" fontSize="xs">
                            {run.failed_files} failed
                          </Text>
                        ) : null}
                      </Td>
                      <Td>
                        <RunAttemptHistory summary={run.attempt_summary} />
                      </Td>
                      <Td fontSize="xs" maxW="280px">
                        {run.terminal_failure?.error_code || run.pipeline_error_code ? (
                          <Tooltip label={run.pipeline_error_description || run.pipeline_error_code || ''}>
                            <Badge colorScheme="red">
                              {run.terminal_failure?.error_code || run.pipeline_error_code}
                            </Badge>
                          </Tooltip>
                        ) : (
                          '—'
                        )}
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
                    <Td colSpan={9}>
                      <HStack py={3}>
                        <Spinner size="sm" />
                        <Text>Loading ingest runs…</Text>
                      </HStack>
                    </Td>
                  </Tr>
                ) : null}

                {!runsLoading && runs.length === 0 ? (
                  <Tr>
                    <Td colSpan={9}>
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
                ? `Read-only step attempts for ${selectedRun.contractor_business_name || 'system run'} · ${formatIngestTimestamp(selectedRun.created_at)}`
                : 'Select an ingest run above to see its processing steps.'}
            </Text>
          </Box>

          {stepsError ? (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text color="red.700">Showing the last successful step data. Refresh failed: {stepsError}</Text>
            </Box>
          ) : null}

          <Box borderWidth="1px" borderColor="#D8D8D8" borderRadius="md" overflow="auto">
            <Table size="sm" minW="720px">
              <Thead bg="#FAF9F8">
                <Tr>
                  <Th w="64px" minW="64px" p={0} aria-label="Pipeline" />
                  <Th>Step / target</Th>
                  <Th>Attempt</Th>
                  <Th>Outcome</Th>
                  <Th>Duration</Th>
                  <Th>Error code</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {steps.map((step, index) => (
                  <Tr key={step.id}>
                    <Td p={0} position="relative">
                      <IngestProcessPipeCell
                        step={step}
                        first={index === 0}
                        last={index === steps.length - 1}
                        onOpen={() =>
                          openDetail({ kind: 'step', title: `Ingest step · ${step.step_type}`, value: step })
                        }
                      />
                    </Td>
                    <Td fontSize="xs" maxW="320px">
                      <Text noOfLines={2} fontWeight="semibold">
                        {step.step_type}
                      </Text>
                      <Text color="gray.600" noOfLines={2}>
                        {stepTargetLabel(step)}
                      </Text>
                    </Td>
                    <Td fontSize="xs" whiteSpace="nowrap">
                      {step.attempt_number || 1} of {step.attempt_count || 1}
                    </Td>
                    <Td>
                      <Badge colorScheme={ingestStatusColor(step.display_status || step.status)}>
                        {step.display_status || step.status}
                      </Badge>
                    </Td>
                    <Td whiteSpace="nowrap" fontSize="xs">
                      {formatIngestDuration(step.duration_seconds)}
                    </Td>
                    <Td fontSize="xs">
                      {step.error_code ? (
                        <Badge colorScheme={step.display_status === 'recovered' ? 'gray' : 'red'}>
                          {step.error_code}
                        </Badge>
                      ) : (
                        '—'
                      )}
                    </Td>
                    <Td>
                      <Tooltip label="View all step fields and JSON payloads">
                        <IconButton
                          aria-label={`View ingest step ${step.id}`}
                          icon={<Info size={16} />}
                          size="xs"
                          variant="outline"
                          onClick={() =>
                            openDetail({ kind: 'step', title: `Ingest step · ${step.step_type}`, value: step })
                          }
                        />
                      </Tooltip>
                    </Td>
                  </Tr>
                ))}

                {stepsLoading && steps.length === 0 ? (
                  <Tr>
                    <Td colSpan={7}>
                      <HStack py={3}>
                        <Spinner size="sm" />
                        <Text>Loading ingest step runs…</Text>
                      </HStack>
                    </Td>
                  </Tr>
                ) : null}

                {!stepsLoading && steps.length === 0 ? (
                  <Tr>
                    <Td colSpan={7}>
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

      <IngestDiagnosticDrawer
        isOpen={detailDrawer.isOpen}
        onClose={detailDrawer.onClose}
        selection={diagnosticSelection}
      />
    </Flex>
  );
}
