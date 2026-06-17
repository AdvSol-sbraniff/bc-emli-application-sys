// /app/frontend/components/domains/invoices-admin/index.tsx
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Container,
  Divider,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  HStack,
  IconButton,
  Input,
  Select,
  Spinner,
  Table,
  Tbody,
  Tooltip,
  Td,
  Text,
  Th,
  Thead,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import {
  ArrowsClockwise,
  CaretLeft,
  CaretRight,
  ChatDots,
  Info,
  MagnifyingGlass,
  Trash,
  Wrench,
  XCircle,
} from '@phosphor-icons/react';
import { LightGradientTitleBar } from '../../shared/base/light-gradient-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';
import { MultiCheckSelect } from '../../shared/select/multi-check-select';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { INVOICE_STATUS_FILTER_GROUPS, invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';

type DetectedUpgradeType = {
  confidence?: number | null;
  description?: string | null;
  upgrade_type_key?: string | null;
};

type UpgradeTypeOption = {
  description?: string | null;
  upgrade_type_key: string;
};

type InvoiceGridRow = {
  invoice_id?: string | null;

  session_id: string;
  session_created_at?: string | null;
  invoice_status?: string | null;
  invoice_status_subtype?: string | null;
  invoice_status_updated_at?: string | null;
  invoice_created_at?: string | null;
  invoice_updated_at?: string | null;
  invoice_submitted_at?: string | null;

  contractor_id?: string | null;
  contractor_business_name?: string | null;
  contractor_number?: string | null;

  submitter_id?: string | null;
  submitter_name?: string | null;
  submitter_email?: string | null;

  contractor_contact_name?: string | null;
  contractor_contact_email?: string | null;

  latest_invoice_version_id?: string | null;
  latest_invoice_versionno?: number | null;
  latest_invoice_version_updated_at?: string | null;

  latest_original_filename?: string | null;

  latest_di_ocr_invoice_id?: string | null;
  latest_di_ocr_invoice_date?: string | null;
  latest_di_ocr_vendor_name?: string | null;
  latest_di_ocr_invoice_total?: string | number | null;

  latest_genai_result?: 'pass' | 'warn' | 'fail' | string | null;
  latest_genai_overall_confidence?: number | null;
  latest_detected_upgrade_type_keys?: string[] | null;
  latest_detected_upgrade_types_json?: DetectedUpgradeType[] | null;

  system_help_notes?: string | null;
};

type ApiResp = {
  rows: InvoiceGridRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
    filters?: any;
  };
};

const fmtDateTime = (s?: string | null) => {
  if (!s) return '';
  const raw = String(s);
  if (raw.includes('T'))
    return raw
      .replace('T', ' ')
      .replace(/\.\d+Z?$/, '')
      .replace(/Z$/, '')
      .slice(0, 16);
  return raw.slice(0, 16);
};
const fmtMoney = (v?: string | number | null) => {
  if (v === null || v === undefined || v === '') return '';
  const n = typeof v === 'number' ? v : Number(v);
  if (Number.isNaN(n)) return String(v);
  return n.toLocaleString(undefined, { style: 'currency', currency: 'CAD' });
};

const normalizeResult = (result: unknown): 'pass' | 'warn' | 'fail' | null => {
  const value = String(result ?? '')
    .trim()
    .toLowerCase();
  return value === 'pass' || value === 'warn' || value === 'fail' ? value : null;
};

const rowActionButtonProps = {
  h: '38px',
  minW: '38px',
  w: '38px',
  size: 'sm' as const,
  variant: 'outline' as const,
};

const rowActionIconSize = 18;

function ResultDot({ val }: { val: unknown }) {
  const result = normalizeResult(val);
  const visual =
    result === 'pass'
      ? { bg: 'green.400', glow: 'rgba(72, 187, 120, 0.45)' }
      : result === 'warn'
        ? { bg: 'yellow.400', glow: 'rgba(236, 201, 75, 0.5)' }
        : result === 'fail'
          ? { bg: 'red.400', glow: 'rgba(245, 101, 101, 0.55)' }
          : { bg: 'gray.300', glow: 'transparent' };

  return (
    <Box
      w="14px"
      h="14px"
      borderRadius="full"
      bg={visual.bg}
      display="inline-block"
      boxShadow={result ? `0 0 0 4px ${visual.glow}, 0 0 14px ${visual.glow}` : 'none'}
      sx={
        result
          ? {
              '@keyframes claimsAiSignalPulse': {
                '0%, 100%': {
                  boxShadow: `0 0 0 3px ${visual.glow}, 0 0 10px ${visual.glow}`,
                },
                '50%': {
                  boxShadow: `0 0 0 6px ${visual.glow}, 0 0 18px ${visual.glow}`,
                },
              },
              animation: 'claimsAiSignalPulse 2.8s ease-in-out infinite',
            }
          : undefined
      }
    />
  );
}

const aiResultHint = (result: unknown) => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'AI Advice says the latest checks pass.';
  if (normalized === 'warn')
    return 'AI advice includes warnings that may need contractor pre-check or admin attention.';
  if (normalized === 'fail') return 'AI Advice includes failing checks that need attention.';
  return 'AI advice result is not available yet.';
};

const sortParts = (sort: string) => {
  const [field, direction] = sort.split(':', 2);
  return {
    field,
    direction: direction === 'asc' ? 'asc' : 'desc',
  };
};

const ADMIN_WORK_QUEUE_STATUS_FILTER = ['admin_review_inbox', 'in_review'];
const DEFAULT_INVOICE_STATUS_FILTER = ADMIN_WORK_QUEUE_STATUS_FILTER.join(',');
const ALL_STATUS_FILTER_URL_VALUE = 'all';

const statusGroupValue = (statuses: string[]) => statuses.join(',');

const normalizeStatusFilterFromUrl = (value: string | null) => {
  if (value === null) return DEFAULT_INVOICE_STATUS_FILTER;
  if (value === ALL_STATUS_FILTER_URL_VALUE) return '';
  return value;
};

const selectedStatusGroupValuesFor = (invoiceStatus: string) => {
  const selectedStatuses = new Set(
    invoiceStatus
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
  );

  if (!selectedStatuses.size) return [];

  return INVOICE_STATUS_FILTER_GROUPS.filter((group) =>
    group.statuses.every((status) => selectedStatuses.has(status)),
  ).map((group) => statusGroupValue(group.statuses));
};

const invoiceStatusFromGroupValues = (values: string[]) =>
  Array.from(
    new Set(
      values
        .flatMap((value) => value.split(','))
        .map((value) => value.trim())
        .filter(Boolean),
    ),
  ).join(',');

const INVOICE_STATUS_FILTER_ITEMS = INVOICE_STATUS_FILTER_GROUPS.map((group) => ({
  label: group.label,
  value: statusGroupValue(group.statuses),
}));

function SortableHeader({
  field,
  label,
  sort,
  onSort,
}: {
  field: string;
  label: string;
  sort: string;
  onSort: (field: string) => void;
}) {
  const activeSort = sortParts(sort);
  const isActive = activeSort.field === field;
  const arrow = isActive ? (activeSort.direction === 'asc' ? '↑' : '↓') : '↕';

  return (
    <Box
      as="button"
      type="button"
      display="inline-flex"
      alignItems="center"
      gap={1.5}
      px={1.5}
      py={1}
      ml={-1.5}
      borderRadius="md"
      cursor="pointer"
      role="group"
      transition="background-color 140ms ease, color 140ms ease"
      onClick={() => onSort(field)}
      _hover={{ bg: 'blue.50', color: 'blue.800' }}
      _focusVisible={{ boxShadow: 'outline' }}
    >
      <Text as="span" fontSize="sm" fontWeight="semibold" textTransform="none">
        {label}
      </Text>
      <Text
        as="span"
        fontSize="sm"
        color={isActive ? 'blue.600' : 'gray.400'}
        opacity={isActive ? 1 : 0.45}
        textShadow={isActive ? '0 0 8px rgba(49, 130, 206, 0.35)' : 'none'}
        transition="opacity 140ms ease, color 140ms ease, transform 140ms ease"
        _groupHover={{ opacity: 0.8 }}
      >
        {arrow}
      </Text>
    </Box>
  );
}

function buildSearchParams(obj: Record<string, string | undefined>) {
  const p = new URLSearchParams();
  Object.entries(obj).forEach(([k, v]) => {
    if (v === undefined) return;
    const vv = v.toString().trim();
    if (!vv) return;
    p.set(k, vv);
  });
  return p;
}

export function InvoicesAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  // URL-driven state
  const [sessionId, setSessionId] = useState<string>('');
  const [q, setQ] = useState<string>('');
  const [invoiceStatus, setInvoiceStatus] = useState<string>(DEFAULT_INVOICE_STATUS_FILTER);
  const [selectedUpgradeTypeKeys, setSelectedUpgradeTypeKeys] = useState<string[]>([]);
  const [sort, setSort] = useState<string>('latest_invoice_version_updated_at:desc');
  const [page, setPage] = useState<number>(1);
  const [per, setPer] = useState<number>(25);

  // data
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [deletingInvoiceId, setDeletingInvoiceId] = useState<string>('');
  const [rows, setRows] = useState<InvoiceGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [upgradeTypeOptions, setUpgradeTypeOptions] = useState<UpgradeTypeOption[]>([]);

  // drawer
  const { isOpen, onOpen, onClose } = useDisclosure();
  const [selected, setSelected] = useState<InvoiceGridRow | null>(null);

  const didInitFromUrl = useRef(false);

  const selectedStatusGroupValues = useMemo(() => selectedStatusGroupValuesFor(invoiceStatus), [invoiceStatus]);

  // 1) initialize state from URL once (and whenever user manually edits URL)
  useEffect(() => {
    const params = new URLSearchParams(location.search);

    // Only overwrite local state if:
    // - first load, or
    // - URL was changed by back/forward navigation
    const next = {
      session_id: params.get('session_id') || '',
      q: params.get('q') || '',
      invoice_status: normalizeStatusFilterFromUrl(params.get('invoice_status')),
      upgrade_type_keys: (params.get('upgrade_type_keys') || '')
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean),
      sort: params.get('sort') || 'latest_invoice_version_updated_at:desc',
      page: Number(params.get('page') || '1') || 1,
      per: Number(params.get('per') || '25') || 25,
    };

    if (!didInitFromUrl.current) {
      didInitFromUrl.current = true;
      setSessionId(next.session_id);
      setQ(next.q);
      setInvoiceStatus(next.invoice_status);
      setSelectedUpgradeTypeKeys(next.upgrade_type_keys);
      setSort(next.sort);
      setPage(next.page);
      setPer(next.per);
      return;
    }

    // If back/forward changed URL, sync it.
    // (We keep it simple: always sync on location.search changes.)
    setSessionId(next.session_id);
    setQ(next.q);
    setInvoiceStatus(next.invoice_status);
    setSelectedUpgradeTypeKeys(next.upgrade_type_keys);
    setSort(next.sort);
    setPage(next.page);
    setPer(next.per);
  }, [location.search]);

  // 2) push state to URL (bookmarkable)
  const pushUrl = (
    next: Partial<{
      sessionId: string;
      q: string;
      invoiceStatus: string;
      selectedUpgradeTypeKeys: string[];
      sort: string;
      page: number;
      per: number;
    }>,
  ) => {
    const merged = {
      sessionId,
      q,
      invoiceStatus,
      selectedUpgradeTypeKeys,
      sort,
      page,
      per,
      ...next,
    };

    const params = buildSearchParams({
      session_id: merged.sessionId || undefined,
      q: merged.q || undefined,
      invoice_status:
        merged.invoiceStatus === ''
          ? ALL_STATUS_FILTER_URL_VALUE
          : merged.invoiceStatus || DEFAULT_INVOICE_STATUS_FILTER,
      upgrade_type_keys: merged.selectedUpgradeTypeKeys.length ? merged.selectedUpgradeTypeKeys.join(',') : undefined,
      sort: merged.sort || undefined,
      page: String(merged.page || 1),
      per: String(merged.per || 25),
    });

    navigate({ pathname: location.pathname, search: `?${params.toString()}` }, { replace: true });
  };

  // ============================================================
  // SECTION 05.01 — FETCH ROWS
  // PURPOSE: Load invoice grid rows from API (callable by button + by effect)
  // ============================================================

  const fetchRows = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const params = buildSearchParams({
        session_id: sessionId || undefined,
        q: q || undefined,
        invoice_status: invoiceStatus || undefined,
        upgrade_type_keys: selectedUpgradeTypeKeys.length ? selectedUpgradeTypeKeys.join(',') : undefined,
        sort: sort || undefined,
        page: String(page || 1),
        per: String(per || 25),
      });

      const url = `/api/claims/admin/invoices?${params.toString()}`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: ApiResp = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setError(e?.message || 'Failed to load invoice grid.');
    } finally {
      setLoading(false);
    }
  }, [invoiceStatus, page, per, q, selectedUpgradeTypeKeys, sessionId, sort]);

  const loadUpgradeTypes = useCallback(async () => {
    try {
      const res = await fetch('/api/claims/admin/invoice_upgrade_types', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);

      const rows = Array.isArray(data?.rows) ? data.rows : [];
      const normalized = rows
        .filter((row: UpgradeTypeOption) => row?.upgrade_type_key && row.upgrade_type_key !== 'common')
        .sort((a: UpgradeTypeOption, b: UpgradeTypeOption) => {
          const orderA = INVOICE_UPGRADE_TYPE_FILTER_ORDER.indexOf(a.upgrade_type_key as any);
          const orderB = INVOICE_UPGRADE_TYPE_FILTER_ORDER.indexOf(b.upgrade_type_key as any);
          const normalizedA = orderA === -1 ? Number.MAX_SAFE_INTEGER : orderA;
          const normalizedB = orderB === -1 ? Number.MAX_SAFE_INTEGER : orderB;

          if (normalizedA !== normalizedB) return normalizedA - normalizedB;
          return (a.description || a.upgrade_type_key).localeCompare(b.description || b.upgrade_type_key);
        });

      setUpgradeTypeOptions(normalized);
    } catch {
      setUpgradeTypeOptions(
        INVOICE_UPGRADE_TYPE_FILTER_ORDER.map((upgradeTypeKey) => ({
          upgrade_type_key: upgradeTypeKey,
          description: getInvoiceUpgradeTypeMeta(upgradeTypeKey).label,
        })),
      );
    }
  }, []);

  // ============================================================
  // SECTION 05.02 — AUTO FETCH
  // PURPOSE: Fetch whenever filter/sort/page params change
  // ============================================================

  useEffect(() => {
    if (didInitFromUrl.current) fetchRows();
  }, [fetchRows]);

  useEffect(() => {
    loadUpgradeTypes();
  }, [loadUpgradeTypes]);

  const totalPages = useMemo(() => {
    const p = Math.max(1, per || 25);
    return Math.max(1, Math.ceil((total || 0) / p));
  }, [total, per]);

  const upgradeTypeFilterItems = useMemo(
    () =>
      upgradeTypeOptions.map((row) => ({
        label: row.description || getInvoiceUpgradeTypeMeta(row.upgrade_type_key).label,
        value: row.upgrade_type_key,
      })),
    [upgradeTypeOptions],
  );

  const handleOpenVersions = (invoiceId: string) => {
    const url = `/invoice-versions-admin?invoice_id=${encodeURIComponent(invoiceId)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const handleOpenDetailsWithPdf = (row: InvoiceGridRow) => {
    const invoiceId = String(row.invoice_id || '').trim();
    if (!invoiceId) return;

    const url = `/invoices/${encodeURIComponent(invoiceId)}/review`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const handleOpenUploadFix = (row: InvoiceGridRow) => {
    const params = new URLSearchParams();
    if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
    if (row.session_id) params.set('session_id', String(row.session_id));
    if (row.latest_invoice_version_id) params.set('latest_invoice_version_id', String(row.latest_invoice_version_id));
    if (row.latest_invoice_versionno !== null && row.latest_invoice_versionno !== undefined)
      params.set('latest_invoice_versionno', String(row.latest_invoice_versionno));
    if (row.contractor_business_name) params.set('contractor_business_name', String(row.contractor_business_name));
    if (row.latest_di_ocr_invoice_id) params.set('di_ocr_invoice_id', String(row.latest_di_ocr_invoice_id));

    const url = `/upload-invoice-fix-admin?${params.toString()}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const handleOpenRevisions = (row: InvoiceGridRow) => {
    const params = new URLSearchParams();
    if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
    if (row.session_id) params.set('context_session_id', String(row.session_id));
    if (row.session_created_at) params.set('context_session_created_at', String(row.session_created_at));
    if (row.invoice_status) params.set('context_invoice_status', String(row.invoice_status));
    if (row.contractor_business_name)
      params.set('context_contractor_business_name', String(row.contractor_business_name));
    if (row.latest_di_ocr_invoice_id) params.set('context_di_ocr_invoice_id', String(row.latest_di_ocr_invoice_id));
    if (row.latest_invoice_version_id) params.set('latest_invoice_version_id', String(row.latest_invoice_version_id));
    if (row.latest_invoice_versionno !== null && row.latest_invoice_versionno !== undefined)
      params.set('latest_invoice_versionno', String(row.latest_invoice_versionno));
    const url = `/revision-requests-admin?${params.toString()}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const handleDeleteInvoice = async (invoiceId: string) => {
    const confirmed = window.confirm(
      'Delete this invoice and all child records (invoice versions, revision requests, lineitems, step runs, and related artifacts)? This cannot be undone.',
    );
    if (!confirmed) return;

    setDeletingInvoiceId(invoiceId);
    setError('');

    try {
      const res = await fetch(`/api/claims/admin/invoices/${encodeURIComponent(invoiceId)}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      if (selected?.invoice_id === invoiceId) {
        handleCloseDrawer();
      }

      await fetchRows();
    } catch (e: any) {
      setError(e?.message || 'Failed to delete invoice.');
    } finally {
      setDeletingInvoiceId('');
    }
  };

  const handleOpenDrawer = (row: InvoiceGridRow) => {
    setSelected(row);
    onOpen();
  };

  const handleCloseDrawer = () => {
    onClose();
    setSelected(null);
  };

  const handleHeaderSort = (field: string) => {
    const current = sortParts(sort);
    const defaultDirection = field === 'contractor_business_name' ? 'asc' : 'desc';
    const nextDirection = current.field === field ? (current.direction === 'asc' ? 'desc' : 'asc') : defaultDirection;
    const nextSort = `${field}:${nextDirection}`;

    setSort(nextSort);
    setPage(1);
    pushUrl({ sort: nextSort, page: 1 });
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <LightGradientTitleBar title="Invoices Admin" />

      <Container maxW="full" px={6} pb={4} flex="1" pt={6}>
        <Box p={5} bg="white">
          {/* Filters */}
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="260px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                search
              </Text>
              <Input
                value={q}
                onChange={(e) => {
                  setQ(e.target.value);
                  setPage(1);
                }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') pushUrl({ q, page: 1 });
                }}
                onBlur={() => pushUrl({ q, page: 1 })}
                placeholder="contractor, invoice #, email, filename…"
                bg="white"
              />
            </Box>

            <Box minW="260px" maxW="360px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                status
              </Text>
              <MultiCheckSelect
                selectedValues={selectedStatusGroupValues}
                setSelectedValues={(values) => {
                  const nextStatus = invoiceStatusFromGroupValues(values);
                  setInvoiceStatus(nextStatus);
                  setPage(1);
                  pushUrl({ invoiceStatus: nextStatus, page: 1 });
                }}
                allItems={INVOICE_STATUS_FILTER_ITEMS}
                placeholder="All statuses"
                menuListMinW="360px"
              />
            </Box>

            <Box minW="240px" maxW="320px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                upgrade types
              </Text>
              <MultiCheckSelect
                selectedValues={selectedUpgradeTypeKeys}
                setSelectedValues={(values) => {
                  setSelectedUpgradeTypeKeys(values);
                  setPage(1);
                  pushUrl({ selectedUpgradeTypeKeys: values, page: 1 });
                }}
                allItems={upgradeTypeFilterItems}
                placeholder="All upgrade types"
                menuListMinW="420px"
              />
            </Box>

            <Box minW="100px" maxW="120px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                per
              </Text>
              <Select
                value={String(per)}
                onChange={(e) => {
                  const next = Number(e.target.value) || 25;
                  setPer(next);
                  setPage(1);
                  pushUrl({ per: next, page: 1 });
                }}
                bg="white"
              >
                <option value="25">25</option>
                <option value="50">50</option>
                <option value="100">100</option>
              </Select>
            </Box>

            <HStack spacing={1.5} pb={1} flexShrink={0} alignSelf="flex-end">
              <Tooltip label="Refresh grid">
                <IconButton
                  aria-label="Refresh grid"
                  icon={<ArrowsClockwise size={18} />}
                  onClick={() => fetchRows()}
                  isLoading={loading}
                  variant="outline"
                />
              </Tooltip>

              <Tooltip label="Clear filters">
                <IconButton
                  aria-label="Clear filters"
                  icon={<XCircle size={18} />}
                  variant="outline"
                  onClick={() => {
                    setSessionId('');
                    setQ('');
                    setInvoiceStatus(DEFAULT_INVOICE_STATUS_FILTER);
                    setSelectedUpgradeTypeKeys([]);
                    setSort('latest_invoice_version_updated_at:desc');
                    setPer(25);
                    setPage(1);
                    pushUrl({
                      sessionId: '',
                      q: '',
                      invoiceStatus: DEFAULT_INVOICE_STATUS_FILTER,
                      selectedUpgradeTypeKeys: [],
                      sort: 'latest_invoice_version_updated_at:desc',
                      per: 25,
                      page: 1,
                    });
                  }}
                />
              </Tooltip>
            </HStack>
          </Flex>

          {error && (
            <Box mb={4} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text fontSize="sm" color="red.700">
                {error}
              </Text>
            </Box>
          )}

          {/* Grid */}
          <Box bg="white" overflowX="auto">
            <Flex align="center" justify="flex-end" mb={2}>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm" w="100%" tableLayout="fixed">
              <Thead
                sx={{
                  th: {
                    bg: 'linear-gradient(180deg, rgba(49, 130, 206, 0.12) 0%, rgba(255, 255, 255, 0) 88%)',
                    color: 'blue.900',
                    borderBottomColor: 'gray.200',
                    fontSize: 'sm',
                    fontWeight: 'semibold',
                    letterSpacing: 'normal',
                    textTransform: 'none',
                  },
                }}
              >
                <Tr>
                  <Th w="220px">
                    <SortableHeader field="invoice_status" label="status" sort={sort} onSort={handleHeaderSort} />
                  </Th>
                  <Th w="190px">
                    <SortableHeader
                      field="latest_invoice_version_updated_at"
                      label="version updated"
                      sort={sort}
                      onSort={handleHeaderSort}
                    />
                  </Th>
                  <Th w="86px">version #</Th>
                  <Th w="300px">
                    <SortableHeader
                      field="contractor_business_name"
                      label="contractor"
                      sort={sort}
                      onSort={handleHeaderSort}
                    />
                  </Th>
                  <Th w="220px">Invoice #</Th>
                  <Th w="190px"></Th>
                  <Th w="46px">AI</Th>
                  <Th w="220px" textAlign="right"></Th>
                </Tr>
              </Thead>

              <Tbody>
                {rows.map((r, idx) => {
                  const hasInvoice = Boolean(r.invoice_id && String(r.invoice_id).trim());
                  const statusCopy = invoiceStatusCopy(r.invoice_status, r.invoice_status_subtype);
                  const technicalStatus = String(r.invoice_status || '').trim() || 'unknown';
                  return (
                    <Tr
                      key={`${r.invoice_id || 'no-invoice'}-${r.session_id}-${idx}`}
                      transition="background 140ms ease, box-shadow 140ms ease"
                      _hover={{
                        bg: 'linear-gradient(90deg, rgba(49, 130, 206, 0.07) 0%, rgba(255, 255, 255, 0.98) 72%)',
                        boxShadow: 'inset 3px 0 0 rgba(49, 130, 206, 0.35)',
                      }}
                    >
                      <Td>
                        <Tooltip label={`${statusCopy.hint} Technical status: ${technicalStatus}.`}>
                          <Text fontSize="sm" noOfLines={1}>
                            {statusCopy.label}
                          </Text>
                        </Tooltip>
                      </Td>

                      <Td fontSize="sm" whiteSpace="nowrap">
                        {fmtDateTime(r.latest_invoice_version_updated_at ?? r.invoice_updated_at)}
                      </Td>

                      <Td whiteSpace="nowrap">
                        <Text fontSize="sm">v{r.latest_invoice_versionno ?? 1}</Text>
                      </Td>

                      <Td fontSize="sm" minW={0}>
                        {hasInvoice ? (
                          <Tooltip label="Open Reviewer">
                            <Text
                              as="button"
                              type="button"
                              fontSize="sm"
                              fontWeight="normal"
                              color="gray.800"
                              textAlign="left"
                              cursor="pointer"
                              maxW="100%"
                              display="block"
                              whiteSpace="nowrap"
                              overflow="hidden"
                              textOverflow="ellipsis"
                              px={2}
                              py={1}
                              ml={-2}
                              borderRadius="md"
                              transition="background-color 140ms ease, box-shadow 140ms ease, color 140ms ease, transform 140ms ease"
                              onClick={() => handleOpenDetailsWithPdf(r)}
                              _hover={{
                                bg: 'blue.50',
                                color: 'black',
                                boxShadow: '0 8px 18px rgba(49, 130, 206, 0.14)',
                              }}
                              _focusVisible={{ boxShadow: 'outline', borderRadius: 'sm' }}
                            >
                              {r.contractor_business_name ?? '—'}
                            </Text>
                          </Tooltip>
                        ) : (
                          <Text noOfLines={1}>{r.contractor_business_name ?? '—'}</Text>
                        )}
                      </Td>

                      <Td fontSize="sm" minW={0}>
                        <Text noOfLines={1}>{r.latest_di_ocr_invoice_id || '—'}</Text>
                      </Td>

                      <Td whiteSpace="nowrap">
                        {Array.isArray(r.latest_detected_upgrade_types_json) &&
                        r.latest_detected_upgrade_types_json.length > 0 ? (
                          <Flex gap={2} wrap="nowrap" align="center" minW={0} overflow="hidden">
                            {r.latest_detected_upgrade_types_json.map((upgradeType) => {
                              const label =
                                upgradeType.description ||
                                getInvoiceUpgradeTypeMeta(upgradeType.upgrade_type_key).label;
                              const confidenceSuffix =
                                upgradeType.confidence === null || upgradeType.confidence === undefined
                                  ? ''
                                  : ` (${upgradeType.confidence}%)`;

                              return (
                                <Tooltip
                                  key={`${r.invoice_id || 'invoice'}-${upgradeType.upgrade_type_key || 'unknown'}`}
                                  label={`${label}${confidenceSuffix}`}
                                >
                                  <Box flexShrink={0}>
                                    <InvoiceUpgradeTypeTile
                                      upgradeTypeKey={upgradeType.upgrade_type_key}
                                      description={upgradeType.description}
                                    />
                                  </Box>
                                </Tooltip>
                              );
                            })}
                          </Flex>
                        ) : (
                          <Text fontSize="xs" opacity={0.55}>
                            none
                          </Text>
                        )}
                      </Td>

                      <Td>
                        <Tooltip label={aiResultHint(r.latest_genai_result)}>
                          <Box as="span" display="inline-flex" alignItems="center">
                            <ResultDot val={r.latest_genai_result} />
                          </Box>
                        </Tooltip>
                      </Td>

                      <Td whiteSpace="nowrap">
                        <Flex justify="flex-end" align="center" gap={1.5} wrap="nowrap">
                          <Tooltip label="Open details drawer">
                            <IconButton
                              aria-label="Open details drawer"
                              {...rowActionButtonProps}
                              icon={<Info size={rowActionIconSize} />}
                              onClick={() => handleOpenDrawer(r)}
                              isDisabled={!hasInvoice}
                            />
                          </Tooltip>

                          <Tooltip label="Open invoice messages and internal notes. Use messages for the back-and-forth with the contractor about requested changes; use internal notes for admin-only context.">
                            <IconButton
                              aria-label="Open invoice messages and internal notes"
                              {...rowActionButtonProps}
                              icon={<ChatDots size={rowActionIconSize} />}
                              onClick={() => handleOpenRevisions(r)}
                              isDisabled={!hasInvoice}
                            />
                          </Tooltip>

                          <Tooltip label="inspect prior versions of this invoice">
                            <IconButton
                              aria-label="Inspect invoice versions"
                              {...rowActionButtonProps}
                              icon={<MagnifyingGlass size={rowActionIconSize} />}
                              onClick={() => handleOpenVersions(String(r.invoice_id))}
                              isDisabled={!hasInvoice}
                            />
                          </Tooltip>

                          <Divider orientation="vertical" h="18px" borderColor="gray.300" mx={1} />

                          <Tooltip label="upload a +1 version fixing a problem with prior pdf invoice (not a net new invoice)">
                            <IconButton
                              aria-label="Upload fix invoice version"
                              {...rowActionButtonProps}
                              icon={<Wrench size={rowActionIconSize} />}
                              onClick={() => handleOpenUploadFix(r)}
                              isDisabled={!hasInvoice || !r.latest_invoice_version_id}
                            />
                          </Tooltip>

                          <Tooltip label="Delete invoice and all child claim records">
                            <IconButton
                              aria-label="Delete invoice"
                              {...rowActionButtonProps}
                              colorScheme="red"
                              icon={<Trash size={rowActionIconSize} />}
                              onClick={() => handleDeleteInvoice(String(r.invoice_id))}
                              isDisabled={
                                !hasInvoice ||
                                loading ||
                                (!!deletingInvoiceId && deletingInvoiceId !== String(r.invoice_id))
                              }
                              isLoading={deletingInvoiceId === String(r.invoice_id)}
                            />
                          </Tooltip>
                        </Flex>
                      </Td>
                    </Tr>
                  );
                })}

                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={7}>
                      <Text fontSize="sm" opacity={0.7}>
                        No rows. Adjust filters or click Refresh.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>

            {/* Pagination */}
            <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
              <Text fontSize="sm" opacity={0.8}>
                Total: {total}
              </Text>

              <HStack>
                <Tooltip label="Previous page">
                  <IconButton
                    aria-label="Previous page"
                    size="sm"
                    variant="outline"
                    icon={<CaretLeft size={16} />}
                    onClick={() => {
                      const next = Math.max(1, page - 1);
                      setPage(next);
                      pushUrl({ page: next });
                    }}
                    isDisabled={page <= 1}
                  />
                </Tooltip>
                <Text fontSize="sm">
                  Page {page} of {totalPages}
                </Text>
                <Tooltip label="Next page">
                  <IconButton
                    aria-label="Next page"
                    size="sm"
                    variant="outline"
                    icon={<CaretRight size={16} />}
                    onClick={() => {
                      const next = Math.min(totalPages, page + 1);
                      setPage(next);
                      pushUrl({ page: next });
                    }}
                    isDisabled={page >= totalPages}
                  />
                </Tooltip>
              </HStack>
            </Flex>
          </Box>
        </Box>
      </Container>

      {/* Drawer */}
      <Drawer isOpen={isOpen} placement="right" onClose={handleCloseDrawer} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoice {selected?.latest_di_ocr_invoice_id || '—'}</DrawerHeader>

          <DrawerBody>
            {!selected ? (
              <Text fontSize="sm" opacity={0.7}>
                No invoice selected.
              </Text>
            ) : (
              <Box>
                <Box>
                  <Text fontWeight="bold" mb={1}>
                    Contractor contact
                  </Text>
                  <Text fontSize="sm">
                    <b>Contractor number:</b> {selected.contractor_number ?? '—'}
                  </Text>
                  <Text fontSize="sm">
                    <b>Contact name:</b> {selected.contractor_contact_name ?? '—'}
                  </Text>
                  <Text fontSize="sm">
                    <b>Contact email:</b> {selected.contractor_contact_email ?? '—'}
                  </Text>
                </Box>

                <Divider my={4} />

                <Box>
                  <Text fontWeight="bold" mb={1}>
                    Submitter
                  </Text>
                  <Text fontSize="sm">
                    <b>Name:</b> {selected.submitter_name ?? '—'}
                  </Text>
                  <Text fontSize="sm">
                    <b>Email:</b> {selected.submitter_email ?? '—'}
                  </Text>
                </Box>

                <Divider my={4} />

                <Box>
                  <Text fontWeight="bold" mb={1}>
                    Current PDF
                  </Text>
                  <Text fontSize="sm">
                    <b>Original filename:</b> {selected.latest_original_filename ?? '—'}
                  </Text>
                </Box>

                <Divider my={4} />

                <Box>
                  <Text fontWeight="bold" mb={1}>
                    Extracted invoice values
                  </Text>
                  <Text fontSize="sm">
                    <b>Invoice date:</b> {selected.latest_di_ocr_invoice_date ?? '—'}
                  </Text>
                  <Text fontSize="sm">
                    <b>Vendor:</b> {selected.latest_di_ocr_vendor_name ?? '—'}
                  </Text>
                  <Text fontSize="sm">
                    <b>Invoice total:</b> {fmtMoney(selected.latest_di_ocr_invoice_total)}
                  </Text>
                </Box>

                {selected.system_help_notes ? (
                  <>
                    <Divider my={4} />
                    <Box>
                      <Text fontWeight="bold" mb={1}>
                        Help notes
                      </Text>
                      <Text fontSize="sm" whiteSpace="pre-wrap">
                        {selected.system_help_notes}
                      </Text>
                    </Box>
                  </>
                ) : null}
              </Box>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
