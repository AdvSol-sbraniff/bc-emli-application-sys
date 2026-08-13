import React, { useEffect, useMemo, useState } from 'react';
import {
  Box,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  Grid,
  GridItem,
  HStack,
  IconButton,
  Input,
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
} from '@chakra-ui/react';
import { ArrowsClockwise, Question } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

type SummaryResp = {
  invoice_count: number;
  total_value_cad: number;
  avg_value_cad?: number | null;
  median_value_cad?: number | null;
  active_contractors: number;
};

type TrendRow = {
  period_start: string;
  invoice_count: number;
  total_value_cad: number;
};

type TrendResp = {
  grain: 'day' | 'week' | 'month';
  rows: TrendRow[];
};

type DetailRow = {
  invoice_id: string;
  session_id: string;
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  invoice_status?: string | null;
  invoice_created_at?: string | null;
  invoice_total_cad?: number | null;
  ocr_invoice_number?: string | null;
};

type DetailResp = {
  rows: DetailRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
  };
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

function toMoney(v?: number | null) {
  if (v === null || v === undefined || Number.isNaN(v)) return '—';
  return v.toLocaleString(undefined, { style: 'currency', currency: 'CAD' });
}

function fmtDate(s?: string | null) {
  if (!s) return '—';
  const raw = String(s);
  return raw.includes('T') ? raw.split('T')[0] : raw.slice(0, 10);
}

function csvEscape(v: unknown) {
  const str = v === null || v === undefined ? '' : String(v);
  const escaped = str.replace(/"/g, '""');
  return `"${escaped}"`;
}

export default function ReportsVolumeValueScreen() {
  const location = useLocation();
  const navigate = useNavigate();
  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();

  const q = getParam(location.search, 'q');
  const status = getParam(location.search, 'status');
  const dateFrom = getParam(location.search, 'date_from');
  const dateTo = getParam(location.search, 'date_to');
  const minValue = getParam(location.search, 'min_value');
  const maxValue = getParam(location.search, 'max_value');
  const grain = (getParam(location.search, 'grain') || 'week') as 'day' | 'week' | 'month';
  const sort = getParam(location.search, 'sort') || 'invoice_created_at:desc';
  const page = Math.max(1, parseInt(getParam(location.search, 'page') || '1', 10) || 1);
  const per = [25, 50, 100].includes(parseInt(getParam(location.search, 'per') || '25', 10))
    ? parseInt(getParam(location.search, 'per') || '25', 10)
    : 25;

  const [summaryLoading, setSummaryLoading] = useState(false);
  const [summary, setSummary] = useState<SummaryResp | null>(null);

  const [trendLoading, setTrendLoading] = useState(false);
  const [trendRows, setTrendRows] = useState<TrendRow[]>([]);

  const [detailLoading, setDetailLoading] = useState(false);
  const [detailRows, setDetailRows] = useState<DetailRow[]>([]);
  const [detailTotal, setDetailTotal] = useState(0);

  const [error, setError] = useState('');

  const baseParams = useMemo(() => {
    const params = new URLSearchParams();
    if (q.trim()) params.set('q', q.trim());
    if (status.trim()) params.set('status', status.trim());
    if (dateFrom.trim()) params.set('date_from', dateFrom.trim());
    if (dateTo.trim()) params.set('date_to', dateTo.trim());
    if (minValue.trim()) params.set('min_value', minValue.trim());
    if (maxValue.trim()) params.set('max_value', maxValue.trim());
    return params;
  }, [q, status, dateFrom, dateTo, minValue, maxValue]);

  const fetchSummary = async () => {
    setSummaryLoading(true);
    try {
      const res = await fetch(`/api/claims/admin/reports/volume_value/summary?${baseParams.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      setSummary(data as SummaryResp);
    } finally {
      setSummaryLoading(false);
    }
  };

  const fetchTrend = async () => {
    setTrendLoading(true);
    try {
      const params = new URLSearchParams(baseParams);
      params.set('grain', grain);
      const res = await fetch(`/api/claims/admin/reports/volume_value/trend?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data: TrendResp = await res.json().catch(() => ({ grain, rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      setTrendRows(Array.isArray(data?.rows) ? data.rows : []);
    } finally {
      setTrendLoading(false);
    }
  };

  const fetchDetail = async () => {
    setDetailLoading(true);
    try {
      const params = new URLSearchParams(baseParams);
      params.set('sort', sort);
      params.set('page', String(page));
      params.set('per', String(per));

      const res = await fetch(`/api/claims/admin/reports/volume_value/detail?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data: DetailResp = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      setDetailRows(Array.isArray(data?.rows) ? data.rows : []);
      setDetailTotal(Number(data?.meta?.total ?? 0));
    } finally {
      setDetailLoading(false);
    }
  };

  const refreshAll = async () => {
    setError('');
    try {
      await Promise.all([fetchSummary(), fetchTrend(), fetchDetail()]);
    } catch (e: any) {
      setError(e?.message || 'Failed to load report data.');
      setSummary(null);
      setTrendRows([]);
      setDetailRows([]);
      setDetailTotal(0);
    }
  };

  useEffect(() => {
    refreshAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, status, dateFrom, dateTo, minValue, maxValue, grain, sort, page, per]);

  const totalPages = Math.max(1, Math.ceil((detailTotal || 0) / per));

  const exportCsv = () => {
    const headers = [
      'invoice_id',
      'session_id',
      'contractor_business_name',
      'contractor_number',
      'invoice_status',
      'invoice_created_at',
      'invoice_total_cad',
      'ocr_invoice_number',
    ];

    const lines = [headers.map(csvEscape).join(',')];
    detailRows.forEach((r) => {
      lines.push(
        [
          r.invoice_id,
          r.session_id,
          r.contractor_business_name,
          r.contractor_number,
          r.invoice_status,
          r.invoice_created_at,
          r.invoice_total_cad,
          r.ocr_invoice_number,
        ]
          .map(csvEscape)
          .join(','),
      );
    });

    const blob = new Blob([lines.join('\n')], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'volume_value_report_detail.csv';
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Reports - Volume and Value" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box minW="220px" flex="1">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Search
              </Text>
              <Input
                value={q}
                onChange={(e) => setParams(navigate, location, { q: e.target.value, page: '1' })}
                placeholder="contractor, invoice #, ids"
              />
            </Box>

            <Box minW="180px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Status
              </Text>
              <Select
                value={status}
                onChange={(e) => setParams(navigate, location, { status: e.target.value, page: '1' })}
              >
                <option value="">(all)</option>
                <option value="contractor_precheck">contractor_precheck</option>
                <option value="admin_review_inbox">admin_review_inbox</option>
                <option value="contractor_revision_inbox">contractor_revision_inbox</option>
                <option value="in_review">in_review</option>
                <option value="approved_pending">approved_pending</option>
                <option value="approved_paid">approved_paid</option>
                <option value="ineligible">ineligible</option>
                <option value="contractor_withdrawn">contractor_withdrawn</option>
              </Select>
            </Box>

            <Box minW="160px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Date from
              </Text>
              <Input
                type="date"
                value={dateFrom}
                onChange={(e) => setParams(navigate, location, { date_from: e.target.value, page: '1' })}
              />
            </Box>

            <Box minW="160px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Date to
              </Text>
              <Input
                type="date"
                value={dateTo}
                onChange={(e) => setParams(navigate, location, { date_to: e.target.value, page: '1' })}
              />
            </Box>

            <Box minW="140px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Min value
              </Text>
              <Input
                type="number"
                step="0.01"
                value={minValue}
                onChange={(e) => setParams(navigate, location, { min_value: e.target.value, page: '1' })}
              />
            </Box>

            <Box minW="140px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Max value
              </Text>
              <Input
                type="number"
                step="0.01"
                value={maxValue}
                onChange={(e) => setParams(navigate, location, { max_value: e.target.value, page: '1' })}
              />
            </Box>

            <Tooltip label="Refresh all tabs">
              <IconButton aria-label="Refresh all tabs" icon={<ArrowsClockwise size={18} />} onClick={refreshAll} />
            </Tooltip>

            <Tooltip label="Help: metric definitions, filters, and interpretation">
              <IconButton
                aria-label="Open reports help"
                icon={<Question size={18} />}
                variant="outline"
                onClick={onHelpOpen}
              />
            </Tooltip>
          </Flex>

          {error && (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          <Tabs variant="enclosed">
            <TabList>
              <Tab>Overview</Tab>
              <Tab>Trend</Tab>
              <Tab>Invoice Detail</Tab>
            </TabList>

            <TabPanels>
              <TabPanel px={0} pt={4}>
                {summaryLoading ? (
                  <Spinner size="sm" />
                ) : (
                  <Grid templateColumns={{ base: '1fr', md: 'repeat(5, 1fr)' }} gap={3}>
                    <GridItem borderWidth="1px" borderRadius="md" p={3}>
                      <Text fontSize="xs" opacity={0.7}>
                        Invoice count
                      </Text>
                      <Text fontSize="2xl" fontWeight="bold">
                        {summary?.invoice_count ?? 0}
                      </Text>
                    </GridItem>
                    <GridItem borderWidth="1px" borderRadius="md" p={3}>
                      <Text fontSize="xs" opacity={0.7}>
                        Total value
                      </Text>
                      <Text fontSize="2xl" fontWeight="bold">
                        {toMoney(summary?.total_value_cad)}
                      </Text>
                    </GridItem>
                    <GridItem borderWidth="1px" borderRadius="md" p={3}>
                      <Text fontSize="xs" opacity={0.7}>
                        Average value
                      </Text>
                      <Text fontSize="2xl" fontWeight="bold">
                        {toMoney(summary?.avg_value_cad)}
                      </Text>
                    </GridItem>
                    <GridItem borderWidth="1px" borderRadius="md" p={3}>
                      <Text fontSize="xs" opacity={0.7}>
                        Median value
                      </Text>
                      <Text fontSize="2xl" fontWeight="bold">
                        {toMoney(summary?.median_value_cad)}
                      </Text>
                    </GridItem>
                    <GridItem borderWidth="1px" borderRadius="md" p={3}>
                      <Text fontSize="xs" opacity={0.7}>
                        Active contractors
                      </Text>
                      <Text fontSize="2xl" fontWeight="bold">
                        {summary?.active_contractors ?? 0}
                      </Text>
                    </GridItem>
                  </Grid>
                )}
              </TabPanel>

              <TabPanel px={0} pt={4}>
                <HStack mb={3}>
                  <Text fontSize="sm" opacity={0.8}>
                    Bucket
                  </Text>
                  <Select
                    value={grain}
                    w="180px"
                    onChange={(e) => setParams(navigate, location, { grain: e.target.value, page: '1' })}
                  >
                    <option value="day">day</option>
                    <option value="week">week</option>
                    <option value="month">month</option>
                  </Select>
                </HStack>

                <Box borderWidth="1px" borderRadius="md" overflow="auto">
                  <Table size="sm">
                    <Thead bg="gray.50">
                      <Tr>
                        <Th>period start</Th>
                        <Th isNumeric>invoice count</Th>
                        <Th isNumeric>total value</Th>
                        <Th isNumeric>avg value</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {trendLoading && (
                        <Tr>
                          <Td colSpan={4}>
                            <Spinner size="sm" />
                          </Td>
                        </Tr>
                      )}

                      {!trendLoading &&
                        trendRows.map((r) => (
                          <Tr key={`${r.period_start}-${r.invoice_count}`}>
                            <Td fontFamily="mono" fontSize="xs">
                              {fmtDate(r.period_start)}
                            </Td>
                            <Td isNumeric>{r.invoice_count}</Td>
                            <Td isNumeric>{toMoney(r.total_value_cad)}</Td>
                            <Td isNumeric>{toMoney(r.invoice_count > 0 ? r.total_value_cad / r.invoice_count : 0)}</Td>
                          </Tr>
                        ))}

                      {!trendLoading && trendRows.length === 0 && (
                        <Tr>
                          <Td colSpan={4}>
                            <Text fontSize="sm" opacity={0.7}>
                              No trend rows for current filters.
                            </Text>
                          </Td>
                        </Tr>
                      )}
                    </Tbody>
                  </Table>
                </Box>
              </TabPanel>

              <TabPanel px={0} pt={4}>
                <Flex justify="space-between" align="center" mb={3} gap={3} wrap="wrap">
                  <HStack>
                    <Text fontSize="sm" opacity={0.8}>
                      Sort
                    </Text>
                    <Select
                      value={sort}
                      w="260px"
                      onChange={(e) => setParams(navigate, location, { sort: e.target.value })}
                    >
                      <option value="invoice_created_at:desc">invoice_created_at desc</option>
                      <option value="invoice_created_at:asc">invoice_created_at asc</option>
                      <option value="invoice_total_cad:desc">invoice_total_cad desc</option>
                      <option value="invoice_total_cad:asc">invoice_total_cad asc</option>
                      <option value="contractor_business_name:asc">contractor asc</option>
                      <option value="contractor_business_name:desc">contractor desc</option>
                    </Select>
                  </HStack>

                  <HStack>
                    <Select
                      value={String(per)}
                      w="100px"
                      onChange={(e) => setParams(navigate, location, { per: e.target.value, page: '1' })}
                    >
                      <option value="25">25</option>
                      <option value="50">50</option>
                      <option value="100">100</option>
                    </Select>
                    <IconButton
                      aria-label="Export CSV"
                      icon={<Text fontSize="xs">CSV</Text>}
                      onClick={exportCsv}
                      variant="outline"
                    />
                  </HStack>
                </Flex>

                <Box borderWidth="1px" borderRadius="md" overflow="auto">
                  <Table size="sm" minW="980px">
                    <Thead bg="gray.50">
                      <Tr>
                        <Th>created</Th>
                        <Th>contractor</Th>
                        <Th>contractor #</Th>
                        <Th>invoice #</Th>
                        <Th>status</Th>
                        <Th isNumeric>value</Th>
                        <Th>invoice_id</Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {detailLoading && (
                        <Tr>
                          <Td colSpan={7}>
                            <Spinner size="sm" />
                          </Td>
                        </Tr>
                      )}

                      {!detailLoading &&
                        detailRows.map((r) => (
                          <Tr key={r.invoice_id}>
                            <Td fontFamily="mono" fontSize="xs">
                              {fmtDate(r.invoice_created_at)}
                            </Td>
                            <Td>{r.contractor_business_name || '—'}</Td>
                            <Td fontFamily="mono" fontSize="xs">
                              {r.contractor_number || '—'}
                            </Td>
                            <Td fontFamily="mono" fontSize="xs">
                              {r.ocr_invoice_number || '—'}
                            </Td>
                            <Td>{r.invoice_status || '—'}</Td>
                            <Td isNumeric>{toMoney(r.invoice_total_cad)}</Td>
                            <Td fontFamily="mono" fontSize="xs">
                              {r.invoice_id}
                            </Td>
                          </Tr>
                        ))}

                      {!detailLoading && detailRows.length === 0 && (
                        <Tr>
                          <Td colSpan={7}>
                            <Text fontSize="sm" opacity={0.7}>
                              No invoices for current filters.
                            </Text>
                          </Td>
                        </Tr>
                      )}
                    </Tbody>
                  </Table>
                </Box>

                <Flex mt={3} justify="space-between" align="center" gap={3} wrap="wrap">
                  <Text fontSize="sm" opacity={0.8}>
                    Total: {detailTotal}
                  </Text>
                  <HStack>
                    <Text fontSize="sm">
                      Page {page} of {totalPages}
                    </Text>
                    <Select
                      value={String(page)}
                      w="100px"
                      onChange={(e) => setParams(navigate, location, { page: e.target.value })}
                    >
                      {Array.from({ length: totalPages }).map((_, i) => (
                        <option key={i + 1} value={String(i + 1)}>
                          {i + 1}
                        </option>
                      ))}
                    </Select>
                  </HStack>
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
          <DrawerHeader>Volume and Value Report Help</DrawerHeader>
          <DrawerBody>
            <Text fontSize="sm" mb={3}>
              This screen is a business reporting view over invoice data. It is designed to answer: how many invoices
              are flowing, how much dollar value is represented, and which contractors or time periods are driving
              outcomes.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Data scope and assumptions
            </Text>
            <Text fontSize="sm" mb={3}>
              All tabs use the same filter set. Values are sourced from the reporting view backed by invoice business
              fields. Dollar value comes from the latest OCR invoice total available for each invoice. If a value is
              missing for an invoice, count metrics still include the invoice, while value metrics treat missing amounts
              as null and exclude them from average/median calculations.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Global filters
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Search:</b> matches invoice id, session id, contractor name/number, and OCR invoice number.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Status:</b> limits results to one business status at a time (for stage-specific reporting).
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Date from / Date to:</b> applied to invoice created date.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Min / Max value:</b> applied to invoice total CAD.
            </Text>
            <Text fontSize="sm" mb={3}>
              <b>Refresh:</b> reloads all tabs (Overview, Trend, Detail) with current filters.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Overview tab (KPI definitions)
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Invoice count:</b> number of invoices matching current filters.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Total value:</b> sum of invoice total CAD for filtered invoices with non-null amounts.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Average value:</b> arithmetic mean of non-null invoice total CAD values.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Median value:</b> 50th percentile of non-null invoice total CAD values.
            </Text>
            <Text fontSize="sm" mb={3}>
              <b>Active contractors:</b> distinct contractor ids in filtered invoices.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Trend tab
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Bucket:</b> day/week/month changes grouping granularity.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Invoice count:</b> invoices created in each period bucket.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Total value:</b> sum of invoice values in each bucket.
            </Text>
            <Text fontSize="sm" mb={3}>
              <b>Avg value:</b> total value divided by count per bucket (display-only derived metric).
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Invoice Detail tab
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Sort:</b> controls ordering for the detailed rows endpoint.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>Per page / Page:</b> controls pagination for large result sets.
            </Text>
            <Text fontSize="sm" mb={2}>
              <b>CSV:</b> exports currently displayed detail rows in the table (page-scoped export).
            </Text>
            <Text fontSize="sm" mb={3}>
              Columns include created date, contractor identifiers, OCR invoice number, status, value, and invoice id.
              This tab is the drill-down layer used to validate summary or trend changes.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Interpretation guide
            </Text>
            <Text fontSize="sm" mb={2}>
              Use Overview first to detect changes in business volume/value, then use Trend to locate when the shift
              started, and finally use Detail to identify which invoices or contractors explain the movement.
            </Text>
            <Text fontSize="sm" mb={2}>
              Large swings in total value with stable count usually indicate value-mix changes (fewer high-value
              invoices or more low-value invoices).
            </Text>
            <Text fontSize="sm" mb={2}>
              Rising count with flat value usually indicates lower average invoice amount, often tied to submission mix
              changes.
            </Text>
            <Text fontSize="sm" mb={2}>
              If median diverges from average, check for outliers in Detail tab and verify whether large invoices are
              driving totals.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Common pitfalls
            </Text>
            <Text fontSize="sm" mb={2}>
              Date filters are based on invoice creation time, not OCR date or closure date.
            </Text>
            <Text fontSize="sm" mb={2}>
              Missing OCR totals lower value coverage; monitor count-to-value consistency before decision-making.
            </Text>
            <Text fontSize="sm" mb={2}>
              CSV export is current page only; paginate if you need complete extracts.
            </Text>
            <Text fontSize="sm" mb={4}>
              Status filter is single-select in v1 to keep comparisons clean and explicit.
            </Text>

            <Text fontSize="sm" opacity={0.75}>
              Recommended workflow: set date window, check Overview, inspect Trend at week grain, switch to day grain
              for anomalies, then confirm root causes in Invoice Detail.
            </Text>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
