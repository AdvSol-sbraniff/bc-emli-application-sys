// /app/frontend/components/domains/ai-admin/index.tsx
import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  Heading,
  HStack,
  Input,
  Select,
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
  Tr,
} from '@chakra-ui/react';

import { observer } from 'mobx-react-lite';
import React, { useEffect, useMemo, useState } from 'react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
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
  ok?: boolean | null;
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
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [lastAutoRefreshAt, setLastAutoRefreshAt] = useState('');

  const hasRunningStep = useMemo(() => steps.some((s) => s.ok === null || typeof s.ok === 'undefined'), [steps]);

  const fetchStepsBySession = async () => {
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
  };

  useEffect(() => {
    if (!autoRefresh) return;
    if (!sessionId.trim()) return;
    if (steps.length === 0) return;
    if (!hasRunningStep) return;

    let cancelled = false;

    const tick = async () => {
      if (cancelled) return;
      await fetchStepsBySession();
      if (!cancelled) setLastAutoRefreshAt(new Date().toLocaleTimeString());
    };

    const id = window.setInterval(tick, 2000);
    tick();

    return () => {
      cancelled = true;
      window.clearInterval(id);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [autoRefresh, hasRunningStep, sessionId, steps.length]);

  // Run buttons
  const [isRunningOcr, setIsRunningOcr] = useState(false);
  const [ocrError, setOcrError] = useState('');
  const [ocrOkMsg, setOcrOkMsg] = useState('');

  const [isRunningGenai, setIsRunningGenai] = useState(false);
  const [genaiError, setGenaiError] = useState('');
  const [genaiOkMsg, setGenaiOkMsg] = useState('');

  const handleRunOcr = async () => {
    setIsRunningOcr(true);
    setOcrError('');
    setOcrOkMsg('');

    try {
      const sid = sessionId.trim();
      const ivid = invoiceVersionId.trim();

      if (!sid) throw new Error('Enter a session_id first.');
      if (!ivid) throw new Error('Enter an invoice_version_id first (or load context).');

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
      <BlueTitleBar title="Job Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
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
                  <Box>
                    <Heading size="sm">Validation GenAI Rulesets</Heading>
                    <Text as="div" fontSize="xs" opacity={0.7}>
                      Select a ruleset. Selection is stored in the URL as{' '}
                      <Box as="code">validationgenai_ruleset_id</Box>.
                    </Text>
                  </Box>

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

                <Box mt={4} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    Selected ruleset
                  </Text>
                  <Text as="div" fontSize="sm" fontWeight="bold">
                    {selectedRuleset?.ruleset_shortname ?? '(none selected)'}
                  </Text>
                  <Text as="div" fontSize="xs" fontFamily="mono" opacity={0.9}>
                    validationgenai_ruleset_id: {rulesetIdFromUrl || '—'}
                  </Text>
                </Box>
              </TabPanel>

              {/* ============================================================
                  TAB 2 — RUN OCR / GENAI + TRACKER + CONTEXT
              ============================================================ */}
              <TabPanel px={0}>
                <Flex direction="column" gap={4}>
                  {/* WORKING CONTEXT */}
                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
                    <Flex justify="space-between" align="flex-start" wrap="wrap" gap={3}>
                      <Box>
                        <Heading size="sm">Working context</Heading>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          Context is populated via the Invoice Grid Admin screen (paste the IDs from there). Uploads happen
                          in <Box as="code">/upload-invoice-admin</Box>.
                        </Text>
                      </Box>

                      <HStack spacing={2}>
                        <Button
                          size="sm"
                          onClick={() =>
                            setParams(navigate, location, {
                              session_id: sessionId.trim(),
                              invoice_id: invoiceId.trim(),
                              invoice_version_id: invoiceVersionId.trim(),
                            })
                          }
                        >
                          Save to URL
                        </Button>

                        <Button
                          size="sm"
                          variant="outline"
                          onClick={fetchBusinessContext}
                          isLoading={ctxLoading}
                          isDisabled={!sessionId.trim() || !invoiceId.trim()}
                        >
                          Refresh context
                        </Button>
                      </HStack>
                    </Flex>

                    {ctxError && (
                      <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="red.700">
                          {ctxError}
                        </Text>
                      </Box>
                    )}

                    <Flex mt={3} gap={3} wrap="wrap">
                      <Box flex="1" minW="320px">
                        <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                          session_id
                        </Text>
                        <Input value={sessionId} onChange={(e) => setSessionId(e.target.value)} fontFamily="mono" />
                      </Box>

                      <Box flex="1" minW="320px">
                        <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                          invoice_id
                        </Text>
                        <Input value={invoiceId} onChange={(e) => setInvoiceId(e.target.value)} fontFamily="mono" />
                      </Box>

                      <Box flex="1" minW="320px">
                        <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                          invoice_version_id
                        </Text>
                        <Input
                          value={invoiceVersionId}
                          onChange={(e) => setInvoiceVersionId(e.target.value)}
                          placeholder="(required for runs)"
                          fontFamily="mono"
                        />
                      </Box>
                    </Flex>

                    <Box mt={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                      {ctxLoading ? (
                        <Spinner size="sm" />
                      ) : ctxRow ? (
                        <>
                          <Flex justify="space-between" align="center" wrap="wrap" gap={2}>
                            <Box>
                              <Text as="div" fontSize="xs" opacity={0.7}>
                                Contractor
                              </Text>
                              <Text as="div" fontSize="sm" fontWeight="bold">
                                {ctxRow.contractor_business_name || '—'}
                              </Text>
                              <Text as="div" fontSize="xs" opacity={0.75}>
                                {ctxRow.contractor_city || '—'} • {ctxRow.contractor_email || '—'}
                              </Text>
                            </Box>

                            <Box textAlign="right">
                              <Text as="div" fontSize="xs" opacity={0.7}>
                                Invoice
                              </Text>
                              <Text as="div" fontSize="sm" fontWeight="bold">
                                status: {ctxRow.invoice_status || '—'}
                              </Text>
                              <Text as="div" fontSize="xs" opacity={0.75}>
                                file: {ctxRow.latest_original_filename || '—'}
                              </Text>
                            </Box>
                          </Flex>

                          <Flex mt={3} wrap="wrap" gap={6}>
                            <Box minW="260px">
                              <Text fontSize="xs" opacity={0.7}>
                                DI (latest)
                              </Text>
                              <Text fontSize="sm" fontWeight="bold">
                                total: {ctxRow.latest_di_ocr_invoice_total || '—'}
                              </Text>
                              <Text fontSize="xs" opacity={0.75}>
                                date: {ctxRow.latest_di_ocr_invoice_date || '—'} • vendor:{' '}
                                {ctxRow.latest_di_ocr_vendor_name || '—'}
                              </Text>
                            </Box>

                            <Box minW="260px">
                              <Text fontSize="xs" opacity={0.7}>
                                GenAI (latest)
                              </Text>
                              <Text fontSize="sm" fontWeight="bold">
                                conf: {ctxRow.latest_genai_overall_confidence ?? '—'}
                              </Text>
                              <Text fontSize="xs" opacity={0.75}>
                                pass: {ctxRow.latest_genai_all_rulechecks_pass_flag == null
                                  ? '—'
                                  : ctxRow.latest_genai_all_rulechecks_pass_flag
                                    ? 'true'
                                    : 'false'}
                              </Text>
                            </Box>

                            <Box minW="260px">
                              <Text fontSize="xs" opacity={0.7}>
                                IDs (short)
                              </Text>
                              <Text fontFamily="mono" fontSize="xs">
                                session: {shortGuid(ctxRow.session_id)}
                              </Text>
                              <Text fontFamily="mono" fontSize="xs">
                                invoice: {shortGuid(ctxRow.invoice_id)}
                              </Text>
                              <Text fontFamily="mono" fontSize="xs">
                                version: {shortGuid(invoiceVersionId || ctxRow.latest_invoice_version_id || '')}
                              </Text>
                            </Box>
                          </Flex>
                        </>
                      ) : (
                        <Text as="div" fontSize="sm" opacity={0.7}>
                          (no context yet — enter session_id + invoice_id, then click “Refresh context”)
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
                    <Heading size="sm" mb={2}>
                      Run
                    </Heading>
                    <Text as="div" fontSize="xs" opacity={0.7} mb={3}>
                      These enqueue Sidekiq jobs. Step tracker below shows progress.
                    </Text>

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

                      <Button variant="outline" onClick={fetchStepsBySession} isLoading={stepsLoading} isDisabled={!sessionId.trim()}>
                        Refresh steps
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
                        {autoRefresh && lastAutoRefreshAt ? (
                          <Text as="div" fontSize="xs" opacity={0.6}>
                            auto-refresh: {lastAutoRefreshAt}
                          </Text>
                        ) : null}
                      </Box>

                      <Flex gap={2} wrap="wrap">
                        <Button size="sm" onClick={fetchStepsBySession} isLoading={stepsLoading} isDisabled={!sessionId.trim()}>
                          Refresh
                        </Button>

                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => {
                            setSteps([]);
                            setStepsError('');
                          }}
                          isDisabled={steps.length === 0}
                        >
                          Clear
                        </Button>

                        <Button size="sm" variant="ghost" onClick={() => setAutoRefresh((v) => !v)}>
                          auto: {autoRefresh ? 'on' : 'off'}
                        </Button>
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
                            <Th>ok</Th>
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
                                {s.ok === null || typeof s.ok === 'undefined' ? (
                                  <Spinner size="sm" />
                                ) : (
                                  <Badge colorScheme={s.ok ? 'green' : 'red'}>{s.ok ? 'OK' : 'FAIL'}</Badge>
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
                                <Text as="div" fontSize="sm" opacity={0.7}>
                                  Paste a session_id and click Refresh.
                                </Text>
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
    </Flex>
  );
});