// /app/frontend/components/domains/ai-admin/index.tsx
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
  Heading,
  HStack,
  IconButton,
  Input,
  Select,
  SimpleGrid,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
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

import { observer } from 'mobx-react-lite';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { ArrowsClockwise, Question } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: AI Admin (simpler + correct endpoints for business context)
// - Tab 1: Choose GenAI Ruleset (grid)  GET /api/claims/admin/validationgenai_rulesets
// - Tab 2: Run OCR / Run GenAI + Step Run Tracker + Context details
//   - POST /api/claims/ingest/run_ocr
//   - POST /api/claims/ingest/run_genai
//   - GET  /api/claims/ingest/steps?session_id=...
//   - Context (business-friendly) uses INVOICE GRID endpoint (not /read):
//     - GET /api/claims/admin/invoices?session_id=...
//       (select row by invoice_id; this includes contractor_business_name, etc.)
// NOTE: Upload is now handled by /upload-invoice-admin (separate screen).
// ============================================================

type RulesetRow = {
  id: string;
  ruleset_shortname?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type RulesetSearchResponse = {
  rows: RulesetRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
};

type IngestStepRow = {
  id: string;
  ingest_run_id: string;
  invoice_version_id?: string | null;
  step_type?: string | null;
  status?: string | null;
  error_text?: string | null;
  validationgenai_ruleset_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type InvoiceGridRow = {
  invoice_id: string;
  session_id: string;

  invoice_status?: string | null;
  invoice_status_updated_at?: string | null;

  session_status?: string | null;
  session_submitted_at?: string | null;

  contractor_id?: string | null;
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  contractor_email?: string | null;
  contractor_phone_number?: string | null;
  contractor_city?: string | null;

  latest_invoice_version_id?: string | null;
  latest_invoice_versionno?: number | null;
  latest_original_filename?: string | null;

  latest_di_ocr_invoice_total?: string | null;
  latest_di_ocr_invoice_date?: string | null;
  latest_di_ocr_vendor_name?: string | null;
  latest_di_ocr_invoice_id?: string | null;

  latest_genai_all_rulechecks_pass_flag?: boolean | null;
  latest_genai_overall_confidence?: number | null;
};

type InvoiceGridResponse = {
  rows: InvoiceGridRow[];
  meta?: any;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function setParams(navigate: any, location: any, patch: Record<string, string>) {
  const params = new URLSearchParams(location.search);

  Object.entries(patch).forEach(([k, v]) => {
    if (v === '' || v == null) params.delete(k);
    else params.set(k, v);
  });

  const qs = params.toString();
  navigate(`${location.pathname}${qs ? `?${qs}` : ''}`, { replace: true });
}

function sanitizeDisplayTs(s?: string | null) {
  if (!s) return '';
  return String(s).replace('T', ' ').replace('Z', '');
}

function shortGuid(s?: string | null) {
  const v = (s || '').trim();
  if (!v) return '—';
  return v.length <= 12 ? v : `${v.slice(0, 8)}…${v.slice(-4)}`;
}


  export const AIAdminScreen = observer(function AIAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  // ============================================================
  // SECTION 01 — URL-DRIVEN STATE
  // ============================================================

  // ruleset chooser
  const rulesetQ = getParam(location.search, 'ruleset_q');
  const rulesetSort = getParam(location.search, 'ruleset_sort') || 'updated_at:desc';
  const rulesetPageStr = getParam(location.search, 'ruleset_page') || '1';
  const rulesetPerStr = getParam(location.search, 'ruleset_per') || '25';

  // run tab (and shared)
  const sessionIdFromUrl = getParam(location.search, 'session_id');
  const invoiceIdFromUrl = getParam(location.search, 'invoice_id');
  const invoiceVersionIdFromUrl = getParam(location.search, 'invoice_version_id');
  const rulesetIdFromUrl = getParam(location.search, 'validationgenai_ruleset_id');

  const rulesetPage = Math.max(1, parseInt(rulesetPageStr || '1', 10) || 1);
  const rulesetPer = [25, 50, 100].includes(parseInt(rulesetPerStr, 10)) ? parseInt(rulesetPerStr, 10) : 25;

  // ============================================================
  // SECTION 02 — TAB 1: RULESET GRID
  // ============================================================

  const [rulesetLoading, setRulesetLoading] = useState(false);
  const [rulesetError, setRulesetError] = useState('');
  const [rulesetRows, setRulesetRows] = useState<RulesetRow[]>([]);
  const [rulesetTotal, setRulesetTotal] = useState(0);

  const [rulesetQDraft, setRulesetQDraft] = useState(rulesetQ);
  useEffect(() => setRulesetQDraft(rulesetQ), [rulesetQ]);

  const fetchRulesets = async () => {
    setRulesetLoading(true);
    setRulesetError('');

    try {
      const params = new URLSearchParams();
      if (rulesetQ.trim()) params.set('q', rulesetQ.trim());
      params.set('sort', rulesetSort);
      params.set('page', String(rulesetPage));
      params.set('per', String(rulesetPer));

      const url = `/api/claims/admin/validationgenai_rulesets?${params.toString()}`;
      const res = await fetch(url, { method: 'GET', headers: { Accept: 'application/json' }, credentials: 'include' });
      const data: RulesetSearchResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);

      setRulesetRows(Array.isArray(data?.rows) ? data.rows : []);
      setRulesetTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setRulesetError(e?.message || 'Failed to load rulesets.');
      setRulesetRows([]);
      setRulesetTotal(0);
    } finally {
      setRulesetLoading(false);
    }
  };

  useEffect(() => {
    fetchRulesets();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rulesetQ, rulesetSort, rulesetPage, rulesetPer]);

  const selectedRuleset = useMemo(() => {
    if (!rulesetIdFromUrl) return null;
    return rulesetRows.find((r) => String(r.id) === String(rulesetIdFromUrl)) ?? null;
  }, [rulesetRows, rulesetIdFromUrl]);

  const rulesetTotalPages = Math.max(1, Math.ceil((rulesetTotal || 0) / rulesetPer));

  // ============================================================
  // SECTION 03 — TAB 2: RUN + TRACK + CONTEXT (SIMPLER)
  // ============================================================

  const [sessionId, setSessionId] = useState(sessionIdFromUrl || '');
  const [invoiceId, setInvoiceId] = useState(invoiceIdFromUrl || '');
  const [invoiceVersionId, setInvoiceVersionId] = useState(invoiceVersionIdFromUrl || '');

  useEffect(() => setSessionId(sessionIdFromUrl || ''), [sessionIdFromUrl]);
  useEffect(() => setInvoiceId(invoiceIdFromUrl || ''), [invoiceIdFromUrl]);
  useEffect(() => setInvoiceVersionId(invoiceVersionIdFromUrl || ''), [invoiceVersionIdFromUrl]);

  // Business context fetched from invoice grid endpoint
  const [ctxLoading, setCtxLoading] = useState(false);
  const [ctxError, setCtxError] = useState('');
  const [ctxRow, setCtxRow] = useState<InvoiceGridRow | null>(null);

  const fetchBusinessContext = async () => {
    setCtxLoading(true);
    setCtxError('');
    setCtxRow(null);

    try {
      const sid = sessionId.trim();
      const iid = invoiceId.trim();
      if (!sid) throw new Error('Missing session_id.');
      if (!iid) throw new Error('Missing invoice_id.');

      const params = new URLSearchParams();
      params.set('session_id', sid);
      params.set('per', '200');
      params.set('page', '1');
      // if your invoices endpoint supports sort, keep this stable:
      params.set('sort', 'latest_invoice_version_updated_at:desc');

      const url = `/api/claims/admin/invoices?${params.toString()}`;

      const res = await fetch(url, { method: 'GET', headers: { Accept: 'application/json' }, credentials: 'include' });
      const data: InvoiceGridResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);

      const rows = Array.isArray(data?.rows) ? data.rows : [];
      const row = rows.find((r) => String(r.invoice_id) === String(iid)) ?? null;

      if (!row) {
        throw new Error(`Invoice not found in session. session_id=${sid} invoice_id=${iid}`);
      }

      setCtxRow(row);

      // best-effort: if invoice_version_id missing, fill from grid’s latest_invoice_version_id
      if (!invoiceVersionId.trim() && row.latest_invoice_version_id) {
        setInvoiceVersionId(String(row.latest_invoice_version_id));
      }
    } catch (e: any) {
      setCtxError(e?.message || 'Failed to load business context.');
    } finally {
      setCtxLoading(false);
    }
  };

  // auto-refresh business context when IDs change (but only when both are present)
  useEffect(() => {
    if (!sessionId.trim() || !invoiceId.trim()) return;
    fetchBusinessContext();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sessionId, invoiceId]);

  // Step tracker
  const [stepsLoading, setStepsLoading] = useState(false);
  const [stepsError, setStepsError] = useState('');
  const [steps, setSteps] = useState<IngestStepRow[]>([]);

  const [autoPollEnabled, setAutoPollEnabled] = useState(false);
  const [pollTargetInvoiceVersionId, setPollTargetInvoiceVersionId] = useState('');
  const [pollGraceUntilMs, setPollGraceUntilMs] = useState(0);

  const fetchStepsBySession = useCallback(async () => {
    setStepsLoading(true);
    setStepsError('');

    try {
      const sid = sessionId.trim();
      if (!sid) throw new Error('Enter a session_id first.');

      const params = new URLSearchParams();
      params.set('session_id', sid);
      params.set('limit', '200');

      const url = `/api/claims/ingest/steps?${params.toString()}`;
      const res = await fetch(url, { method: 'GET', headers: { Accept: 'application/json' }, credentials: 'include' });
      const data = await res.json().catch(() => ({}));

      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      setSteps(Array.isArray(data?.steps) ? data.steps : []);
    } catch (e: any) {
      setStepsError(e?.message || 'Failed to load steps.');
    } finally {
      setStepsLoading(false);
    }
  }, [sessionId]);

  // Run buttons
  const [isRunningOcr, setIsRunningOcr] = useState(false);
  const [ocrError, setOcrError] = useState('');
  const [ocrOkMsg, setOcrOkMsg] = useState('');

  const [isRunningGenai, setIsRunningGenai] = useState(false);
  const [genaiError, setGenaiError] = useState('');
  const [genaiOkMsg, setGenaiOkMsg] = useState('');

  const POLL_INTERVAL_MS = 2500;
  const POLL_GRACE_MS = 45000;

  const hasPendingTargetStep = useMemo(() => {
    const target = pollTargetInvoiceVersionId.trim();
    if (!target) return false;
    return steps.some(
      (s) =>
        String(s.invoice_version_id || '') === target &&
        ['queued', 'in_progress'].includes(String(s.status || '').toLowerCase()),
    );
  }, [steps, pollTargetInvoiceVersionId]);

  const shouldPollSteps =
    autoPollEnabled &&
    !!sessionId.trim() &&
    (isRunningOcr || isRunningGenai || Date.now() < pollGraceUntilMs || hasPendingTargetStep);

  useEffect(() => {
    if (!shouldPollSteps) return;

    const intervalId = window.setInterval(() => {
      void fetchStepsBySession();
    }, POLL_INTERVAL_MS);

    return () => {
      window.clearInterval(intervalId);
    };
  }, [shouldPollSteps, fetchStepsBySession]);

  const {
    isOpen: isHelpOpen,
    onOpen: onHelpOpen,
    onClose: onHelpClose,
  } = useDisclosure();

  const handleRunOcr = async () => {
    setIsRunningOcr(true);
    setOcrError('');
    setOcrOkMsg('');

    try {
      const sid = sessionId.trim();
      const ivid = invoiceVersionId.trim();

      if (!sid) throw new Error('Enter a session_id first.');
      if (!ivid) throw new Error('Enter an invoice_version_id first (or load context).');

      // Start auto-refresh on first run click and keep it alive briefly
      // so the tracker catches newly created step rows.
      setAutoPollEnabled(true);
      setPollTargetInvoiceVersionId(ivid);
      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
      await fetchStepsBySession();

      const res = await fetch(`/api/claims/ingest/run_ocr`, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ session_id: sid, invoice_version_id: ivid }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
      setOcrOkMsg(
        String(
          data?.message ||
            data?.summary ||
            `OCR queued/started for invoice_version_id=${ivid}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`,
        ),
      );

      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);

      await fetchStepsBySession();
    } catch (e: any) {
      setOcrError(e?.message || 'Run OCR failed.');
    } finally {
      setIsRunningOcr(false);
    }
  };

  const handleRunGenai = async () => {
    setIsRunningGenai(true);
    setGenaiError('');
    setGenaiOkMsg('');

    try {
      const sid = sessionId.trim();
      const ivid = invoiceVersionId.trim();
      const rid = rulesetIdFromUrl.trim();

      if (!sid) throw new Error('Enter a session_id first.');
      if (!ivid) throw new Error('Enter an invoice_version_id first (or load context).');
      if (!rid) throw new Error('Select a ruleset first (Tab: Choose Ruleset).');

      // Start auto-refresh on first run click and keep it alive briefly
      // so the tracker catches newly created step rows.
      setAutoPollEnabled(true);
      setPollTargetInvoiceVersionId(ivid);
      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);
      await fetchStepsBySession();

      const res = await fetch(`/api/claims/ingest/run_genai`, {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ session_id: sid, invoice_version_id: ivid, validationgenai_ruleset_id: rid }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);

      const stepRunId = data?.step_run_id ?? data?.ingest_step_run_id ?? data?.id ?? '';
      setGenaiOkMsg(
        String(
          data?.message ||
            data?.summary ||
            `GenAI queued/started for invoice_version_id=${ivid}${stepRunId ? ` step_run_id=${stepRunId}` : ''}`,
        ),
      );

      setPollGraceUntilMs(Date.now() + POLL_GRACE_MS);

      await fetchStepsBySession();
    } catch (e: any) {
      setGenaiError(e?.message || 'Run GenAI failed.');
    } finally {
      setIsRunningGenai(false);
    }
  };

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoices Admin - OCR & GenAI" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" mb={3}>
            <Tooltip label="Help: tabs, states, and run steps">
              <IconButton
                aria-label="Open OCR and GenAI help"
                icon={<Question size={18} />}
                size="sm"
                variant="outline"
                onClick={onHelpOpen}
              />
            </Tooltip>
          </Flex>

          <Tabs variant="line" isFitted colorScheme="gray">
            <TabList mb="1em">
              <Tab>Choose ruleset</Tab>
              <Tab>Run OCR / GenAI</Tab>
            </TabList>

            <TabPanels>
              {/* ============================================================
                  TAB 1 — RULESET CHOOSER
              ============================================================ */}
              <TabPanel px={0}>
                <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={3}>
                  <HStack spacing={2}>
                    <Select
                      size="sm"
                      value={rulesetPer}
                      onChange={(e) => setParams(navigate, location, { ruleset_per: e.target.value, ruleset_page: '1' })}
                      width="110px"
                    >
                      <option value="25">25</option>
                      <option value="50">50</option>
                      <option value="100">100</option>
                    </Select>

                    <Select
                      size="sm"
                      value={rulesetSort}
                      onChange={(e) =>
                        setParams(navigate, location, { ruleset_sort: e.target.value, ruleset_page: '1' })
                      }
                      width="220px"
                    >
                      <option value="updated_at:desc">updated_at:desc</option>
                      <option value="updated_at:asc">updated_at:asc</option>
                      <option value="created_at:desc">created_at:desc</option>
                      <option value="created_at:asc">created_at:asc</option>
                      <option value="ruleset_shortname:asc">ruleset_shortname:asc</option>
                      <option value="ruleset_shortname:desc">ruleset_shortname:desc</option>
                    </Select>

                    <Button size="sm" onClick={fetchRulesets} isLoading={rulesetLoading}>
                      Refresh
                    </Button>
                  </HStack>
                </Flex>

                <Flex gap={2} mb={3} wrap="wrap">
                  <Input
                    value={rulesetQDraft}
                    onChange={(e) => setRulesetQDraft(e.target.value)}
                    placeholder="Search (shortname, id, system_record, user_record1)…"
                    maxW="640px"
                  />
                  <Button
                    onClick={() => setParams(navigate, location, { ruleset_q: rulesetQDraft.trim(), ruleset_page: '1' })}
                    isDisabled={rulesetQDraft.trim() === rulesetQ.trim()}
                  >
                    Apply
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => {
                      setRulesetQDraft('');
                      setParams(navigate, location, { ruleset_q: '', ruleset_page: '1' });
                    }}
                    isDisabled={!rulesetQ.trim() && !rulesetQDraft.trim()}
                  >
                    Clear
                  </Button>
                </Flex>

                {rulesetError && (
                  <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {rulesetError}
                    </Text>
                  </Box>
                )}

                <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflow="hidden">
                  <Box bg="gray.50" px={3} py={2}>
                    <Flex justify="space-between" align="center">
                      <Flex align="center" gap={2}>
                        <Text as="div" fontSize="sm" fontWeight="bold">
                          Rows
                        </Text>
                        {rulesetLoading ? <Spinner size="sm" /> : null}
                      </Flex>

                      <Text as="div" fontSize="xs" opacity={0.7}>
                        total: {rulesetTotal}
                      </Text>
                    </Flex>
                  </Box>

                  <Box bg="white" p={0}>
                    <Table size="sm">
                      <Thead>
                        <Tr>
                          <Th>shortname</Th>
                          <Th>updated</Th>
                          <Th>id</Th>
                        </Tr>
                      </Thead>
                      <Tbody>
                        {rulesetRows.map((r) => {
                          const isSelected = String(r.id) === String(rulesetIdFromUrl);
                          return (
                            <Tr
                              key={r.id}
                              cursor="pointer"
                              bg={isSelected ? 'blue.50' : 'transparent'}
                              _hover={{ bg: isSelected ? 'blue.100' : 'gray.50' }}
                              onClick={() => setParams(navigate, location, { validationgenai_ruleset_id: String(r.id) })}
                            >
                              <Td fontSize="sm" fontWeight={isSelected ? 'bold' : 'normal'}>
                                {r.ruleset_shortname ?? '—'}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {sanitizeDisplayTs(r.updated_at) || '—'}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {r.id}
                              </Td>
                            </Tr>
                          );
                        })}

                        {!rulesetLoading && rulesetRows.length === 0 && (
                          <Tr>
                            <Td colSpan={3}>
                              <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                                No rulesets found.
                              </Text>
                            </Td>
                          </Tr>
                        )}
                      </Tbody>
                    </Table>
                  </Box>
                </Box>

                <Flex mt={3} justify="space-between" align="center" wrap="wrap" gap={2}>
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    page {rulesetPage} of {rulesetTotalPages}
                  </Text>

                  <HStack>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setParams(navigate, location, { ruleset_page: String(Math.max(1, rulesetPage - 1)) })}
                      isDisabled={rulesetPage <= 1}
                    >
                      Prev
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() =>
                        setParams(navigate, location, { ruleset_page: String(Math.min(rulesetTotalPages, rulesetPage + 1)) })
                      }
                      isDisabled={rulesetPage >= rulesetTotalPages}
                    >
                      Next
                    </Button>
                  </HStack>
                </Flex>
              </TabPanel>

              {/* ============================================================
                  TAB 2 — RUN OCR / GENAI + TRACKER + CONTEXT
              ============================================================ */}
              <TabPanel px={0}>
                <Flex direction="column" gap={4}>
                  {/* WORKING CONTEXT */}
                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
                    {ctxError && (
                      <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="red.700">
                          {ctxError}
                        </Text>
                      </Box>
                    )}

                    <Box mt={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                      {ctxLoading ? (
                        <Spinner size="sm" />
                      ) : ctxRow ? (
                        <>
                          <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                            Populated from the Invoice Admin screen
                          </Text>

                          <SimpleGrid columns={{ base: 1, md: 2, xl: 3 }} spacing={4}>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>session_id</Text>
                              <Text as="div" fontFamily="mono" fontSize="xs">{ctxRow.session_id || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>invoice_id</Text>
                              <Text as="div" fontFamily="mono" fontSize="xs">{ctxRow.invoice_id || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>invoice_version_id</Text>
                              <Text as="div" fontFamily="mono" fontSize="xs">{invoiceVersionId || ctxRow.latest_invoice_version_id || '—'}</Text>
                            </Box>

                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>Contractor name</Text>
                              <Text as="div" fontSize="sm" fontWeight="bold">{ctxRow.contractor_business_name || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>Contractor number</Text>
                              <Text as="div" fontSize="xs">{ctxRow.contractor_number || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>Contractor city</Text>
                              <Text as="div" fontSize="xs">{ctxRow.contractor_city || '—'}</Text>
                            </Box>

                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>Contractor email</Text>
                              <Text as="div" fontSize="xs">{ctxRow.contractor_email || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>Invoice status</Text>
                              <Text as="div" fontSize="xs">{ctxRow.invoice_status || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>Filename</Text>
                              <Text as="div" fontSize="xs">{ctxRow.latest_original_filename || '—'}</Text>
                            </Box>

                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>OCR invoice #</Text>
                              <Text as="div" fontSize="xs">{ctxRow.latest_di_ocr_invoice_id || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>OCR invoice date</Text>
                              <Text as="div" fontSize="xs">{ctxRow.latest_di_ocr_invoice_date || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>OCR vendor</Text>
                              <Text as="div" fontSize="xs">{ctxRow.latest_di_ocr_vendor_name || '—'}</Text>
                            </Box>

                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>OCR total</Text>
                              <Text as="div" fontSize="xs">{ctxRow.latest_di_ocr_invoice_total || '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>GenAI confidence</Text>
                              <Text as="div" fontSize="xs">{ctxRow.latest_genai_overall_confidence ?? '—'}</Text>
                            </Box>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>GenAI all checks pass</Text>
                              <Text as="div" fontSize="xs">
                                {ctxRow.latest_genai_all_rulechecks_pass_flag == null
                                  ? '—'
                                  : ctxRow.latest_genai_all_rulechecks_pass_flag
                                    ? 'true'
                                    : 'false'}
                              </Text>
                            </Box>
                          </SimpleGrid>
                        </>
                      ) : (
                        <Text as="div" fontSize="sm" opacity={0.7}>
                          No context loaded yet. Open this screen from Invoices Admin (OCR / AI action) to populate it.
                        </Text>
                      )}
                    </Box>

                    <Box mt={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Selected GenAI ruleset (Tab: Choose ruleset)
                      </Text>
                      <Text as="div" fontSize="sm" fontWeight="bold">
                        {selectedRuleset?.ruleset_shortname ?? '(none selected)'}
                      </Text>
                      <Text as="div" fontSize="xs" fontFamily="mono" opacity={0.9}>
                        validationgenai_ruleset_id: {rulesetIdFromUrl || '—'}
                      </Text>
                    </Box>
                  </Box>

                  {/* RUN */}
                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
                    <Flex gap={3} wrap="wrap">
                      <Button
                        colorScheme="blue"
                        onClick={handleRunOcr}
                        isLoading={isRunningOcr}
                        loadingText="Running..."
                        isDisabled={!sessionId.trim() || !invoiceVersionId.trim()}
                      >
                        Run OCR
                      </Button>

                      <Button
                        colorScheme="blue"
                        onClick={handleRunGenai}
                        isLoading={isRunningGenai}
                        loadingText="Running..."
                        isDisabled={!sessionId.trim() || !invoiceVersionId.trim() || !rulesetIdFromUrl.trim()}
                      >
                        Run GenAI
                      </Button>
                    </Flex>

                    {ocrError && (
                      <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="red.700">
                          {ocrError}
                        </Text>
                      </Box>
                    )}
                    {ocrOkMsg && (
                      <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="green.800">
                          {ocrOkMsg}
                        </Text>
                      </Box>
                    )}
                    {genaiError && (
                      <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="red.700">
                          {genaiError}
                        </Text>
                      </Box>
                    )}
                    {genaiOkMsg && (
                      <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="green.800">
                          {genaiOkMsg}
                        </Text>
                      </Box>
                    )}
                  </Box>

                  {/* STEP RUN TRACKER */}
                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
                    <Flex align="center" justify="space-between" mb={3} wrap="wrap" gap={3}>
                      <Box>
                        <Heading size="sm">Step Run Tracker</Heading>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          ingest_step_runs filtered by <Box as="code">session_id</Box>
                        </Text>
                      </Box>

                      <Flex gap={2} wrap="wrap">
                        <Tooltip label="Refresh steps">
                          <IconButton
                            aria-label="Refresh steps"
                            icon={<ArrowsClockwise size={18} />}
                            size="sm"
                            variant="outline"
                            onClick={fetchStepsBySession}
                            isLoading={stepsLoading}
                            isDisabled={!sessionId.trim()}
                          />
                        </Tooltip>
                      </Flex>
                    </Flex>

                    {stepsError && (
                      <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="red.700">
                          {stepsError}
                        </Text>
                      </Box>
                    )}

                    <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
                      <Flex align="center" justify="space-between" mb={2}>
                        <Text as="div" fontSize="sm" fontWeight="bold">
                          Steps
                        </Text>
                        {stepsLoading ? <Spinner size="sm" /> : null}
                      </Flex>

                      <Table size="sm">
                        <Thead>
                          <Tr>
                            <Th>created</Th>
                            <Th>step_id</Th>
                            <Th>type</Th>
                            <Th>state</Th>
                            <Th>invoice_version_id</Th>
                            <Th>ruleset</Th>
                            <Th>error</Th>
                          </Tr>
                        </Thead>

                        <Tbody>
                          {steps.map((s) => (
                            <Tr key={s.id}>
                              <Td fontFamily="mono" fontSize="xs">
                                {sanitizeDisplayTs(s.created_at)}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {s.id}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {s.step_type ?? ''}
                              </Td>
                              <Td fontSize="xs">
                                {String(s.status || '').toLowerCase() === 'in_progress' ? (
                                  <Spinner size="sm" />
                                ) : String(s.status || '').toLowerCase() === 'queued' ? (
                                  <Badge colorScheme="yellow">QUEUED</Badge>
                                ) : String(s.status || '').toLowerCase() === 'succeeded' ? (
                                  <Badge colorScheme="green">OK</Badge>
                                ) : String(s.status || '').toLowerCase() === 'failed' ? (
                                  <Badge colorScheme="red">FAIL</Badge>
                                ) : (
                                  <Badge colorScheme="gray">{String(s.status || 'unknown').toUpperCase()}</Badge>
                                )}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {s.invoice_version_id ?? ''}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {s.validationgenai_ruleset_id ?? ''}
                              </Td>
                              <Td fontFamily="mono" fontSize="xs" whiteSpace="pre-wrap">
                                {s.error_text ?? ''}
                              </Td>
                            </Tr>
                          ))}

                          {!stepsLoading && steps.length === 0 && (
                            <Tr>
                              <Td colSpan={7}>
                                <Text as="div" fontSize="sm" opacity={0.7}>No steps found.</Text>
                              </Td>
                            </Tr>
                          )}
                        </Tbody>
                      </Table>
                    </Box>
                  </Box>
                </Flex>
              </TabPanel>
            </TabPanels>
          </Tabs>
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoices Admin OCR and GenAI Help</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Heading size="sm" mb={2}>Two Tabs, Two Jobs</Heading>
                <Text as="div" fontSize="sm">
                  Tab 1 is where you pick the GenAI ruleset.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Tab 2 is where you run OCR or GenAI and watch the step tracker.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Think of Tab 1 as choosing the game rules, and Tab 2 as pressing play and watching what happens.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>Invoice State Basics</Heading>
                <Text as="div" fontSize="sm">
                  The state is tracked on the invoice, not on each invoice version.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  This means a newer version can move the same invoice back to an earlier-looking state, like going back to upload work.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  So if you upload a fix, the invoice can look like it moved backward, but that is expected.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>All Invoice States</Heading>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">upload_queued</Box>: waiting in line to start upload.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">upload_in_progress</Box>: upload work is happening now.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">upload_failed</Box>: upload stopped with an error.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">upload_complete</Box>: upload finished and file is saved.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">ocr_queued</Box>: OCR is waiting in line.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">ocr_in_progress</Box>: OCR is reading the PDF now.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">ocr_failed</Box>: OCR stopped with an error.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">ocr_complete</Box>: OCR finished and wrote extracted fields.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">genai_queued</Box>: GenAI is waiting in line.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">genai_in_progress</Box>: GenAI is running checks now.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">genai_failed</Box>: GenAI stopped with an error.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">genai_complete</Box>: GenAI is done and invoice is ready for contractor review.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">admin_review_inbox</Box>: invoice is in the admin review inbox.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">contractor_revision_inbox</Box>: contractor needs to fix something.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">closed_success</Box>: work is complete and accepted.</Text>
                <Text as="div" fontSize="sm"><Box as="span" fontWeight="bold">closed_reject</Box>: work is closed and rejected.</Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>Why You Sometimes See Quick States</Heading>
                <Text as="div" fontSize="sm">
                  When you click Run OCR or Run GenAI, the system puts that work into a waiting line.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  A worker then picks it up and does the work shortly after.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  That is why you can see quick in-between states like queued and in progress.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Most of the time those states pass very fast, so admins barely notice them.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  If the system has a problem, the invoice can stay in one of those in-between states longer, and that is a clue to investigate.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>How Run Steps Are Shown</Heading>
                <Text as="div" fontSize="sm">
                  The Step Run Tracker shows rows from ingest_step_runs for the current session.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Each row is one attempt of one step type: OCR or GenAI.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  State column meaning: QUEUED means waiting in queue, spinner means in progress, OK means succeeded, and FAIL means it ended with an error.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  If step type is GenAI, ruleset shows which ruleset was used.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Error column shows the failure text when a step fails.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
});