// /app/frontend/components/domains/invoices-admin/index.tsx
import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
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
import { keyframes } from '@emotion/react';
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
import { Link as RouterLink, useLocation, useNavigate } from 'react-router-dom';
import { MultiCheckSelect } from '../../shared/select/multi-check-select';
import {
  getInvoiceUpgradeTypeMeta,
  INVOICE_UPGRADE_TYPE_FILTER_ORDER,
  InvoiceUpgradeTypeTile,
} from '../../shared/claims/invoice-upgrade-type-visual';
import { INVOICE_STATUS_FILTER_GROUPS, invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';
import { formatClaimsReferenceNumber } from '../../../utils/format-claims-reference-number';

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
  reference_number?: number | string | null;
  unread_by_contractor_count?: number | null;
  unread_by_admin_count?: number | null;

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

  latest_genai_result?: 'pass' | 'info' | 'warn' | 'fail' | string | null;
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
    unread_by_admin_filtered_invoice_count?: number;
    unread_by_admin_overall_invoice_count?: number;
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

type AiResult = 'pass' | 'info' | 'warn' | 'fail';

const normalizeResult = (result: unknown): AiResult | null => {
  const value = String(result ?? '')
    .trim()
    .toLowerCase();
  return value === 'pass' || value === 'info' || value === 'warn' || value === 'fail' ? value : null;
};

const claimsAiSignalPulse = keyframes`
  0%, 100% { opacity: 0.45; transform: scale(1); }
  50% { opacity: 0.18; transform: scale(1.65); }
`;

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
      ? 'green.400'
      : result === 'info'
        ? 'blue.400'
        : result === 'warn'
          ? 'yellow.400'
          : result === 'fail'
            ? 'red.400'
            : 'gray.300';

  return (
    <Box
      w="14px"
      h="14px"
      borderRadius="full"
      color={visual}
      bg="currentColor"
      display="inline-block"
      position="relative"
      sx={
        result
          ? {
              '&::after': {
                content: '""',
                position: 'absolute',
                inset: 0,
                borderRadius: 'inherit',
                boxShadow: '0 0 0 3px currentColor, 0 0 10px currentColor',
                pointerEvents: 'none',
                animation: `${claimsAiSignalPulse} 2.8s ease-in-out infinite`,
              },
              '@media (prefers-reduced-motion: reduce)': {
                '&::after': {
                  animation: 'none',
                  opacity: 0.3,
                },
              },
            }
          : undefined
      }
    />
  );
}

function UnreadMessageStatus({
  count,
  audience,
  colorScheme,
}: {
  count: unknown;
  audience: 'contractor' | 'admin';
  colorScheme: string;
}) {
  const isUnread = Math.max(0, Number(count) || 0) > 0;
  return (
    <Tooltip
      label={isUnread ? `Messages have not been read by any ${audience}.` : `No messages are unread by ${audience}.`}
    >
      <Badge
        minW="58px"
        textAlign="center"
        colorScheme={isUnread ? colorScheme : 'gray'}
        variant={isUnread ? 'solid' : 'subtle'}
        borderRadius="full"
      >
        {isUnread ? 'Unread' : 'Read'}
      </Badge>
    </Tooltip>
  );
}

const aiResultHint = (result: unknown) => {
  const normalized = normalizeResult(result);
  if (normalized === 'pass') return 'AI Advice says the latest checks pass.';
  if (normalized === 'info') return 'AI advice includes informational notes that do not require contractor correction.';
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

const DEFAULT_INVOICE_STATUS_FILTER = '';
const ALL_STATUS_FILTER_URL_VALUE = 'all';
const ALL_STATUS_FILTER_ITEM_VALUE = '__all_statuses__';

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

const INVOICE_STATUS_FILTER_ITEMS = [
  {
    label: 'All statuses',
    value: ALL_STATUS_FILTER_ITEM_VALUE,
  },
  ...INVOICE_STATUS_FILTER_GROUPS.map((group) => ({
    label: group.label,
    value: statusGroupValue(group.statuses),
  })),
];

const INVOICE_SORT_OPTIONS = [
  { value: 'latest_invoice_version_updated_at:desc', label: 'Recently updated' },
  { value: 'latest_invoice_version_updated_at:asc', label: 'Least recently updated' },
  { value: 'unread_by_admin_count:desc', label: 'Unread by admin first' },
  { value: 'unread_by_admin_count:asc', label: 'Read by admin first' },
  { value: 'unread_by_contractor_count:desc', label: 'Unread by contractor first' },
  { value: 'unread_by_contractor_count:asc', label: 'Read by contractor first' },
  { value: 'contractor_business_name:asc', label: 'Contractor A–Z' },
  { value: 'contractor_business_name:desc', label: 'Contractor Z–A' },
  { value: 'invoice_status:asc', label: 'Status A–Z' },
  { value: 'invoice_status:desc', label: 'Status Z–A' },
  { value: 'reference_number:asc', label: 'Reference # low–high' },
  { value: 'reference_number:desc', label: 'Reference # high–low' },
];

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
  const [unreadByAdminFilteredInvoiceCount, setUnreadByAdminFilteredInvoiceCount] = useState<number>(0);
  const [unreadByAdminOverallInvoiceCount, setUnreadByAdminOverallInvoiceCount] = useState<number>(0);
  const [upgradeTypeOptions, setUpgradeTypeOptions] = useState<UpgradeTypeOption[]>([]);

  // drawer
  const { isOpen, onOpen, onClose } = useDisclosure();
  const [selected, setSelected] = useState<InvoiceGridRow | null>(null);

  const didInitFromUrl = useRef(false);

  const selectedStatusFilterValues = useMemo(
    () => (invoiceStatus.trim() ? selectedStatusGroupValuesFor(invoiceStatus) : [ALL_STATUS_FILTER_ITEM_VALUE]),
    [invoiceStatus],
  );

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
      setUnreadByAdminFilteredInvoiceCount(Number(data?.meta?.unread_by_admin_filtered_invoice_count || 0));
      setUnreadByAdminOverallInvoiceCount(Number(data?.meta?.unread_by_admin_overall_invoice_count || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setUnreadByAdminFilteredInvoiceCount(0);
      setUnreadByAdminOverallInvoiceCount(0);
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

  const handleOpenPackageFix = (row: InvoiceGridRow) => {
    const params = new URLSearchParams();
    if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
    if (row.session_id) params.set('session_id', String(row.session_id));
    if (row.latest_invoice_version_id) params.set('latest_invoice_version_id', String(row.latest_invoice_version_id));
    if (row.latest_invoice_versionno !== null && row.latest_invoice_versionno !== undefined)
      params.set('latest_invoice_versionno', String(row.latest_invoice_versionno));
    if (row.contractor_business_name) params.set('contractor_business_name', String(row.contractor_business_name));
    if (row.latest_di_ocr_invoice_id) params.set('di_ocr_invoice_id', String(row.latest_di_ocr_invoice_id));

    const url = `/contractorfixsimulation?${params.toString()}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const handleOpenAdviceRefresh = (row: InvoiceGridRow) => {
    const params = new URLSearchParams();
    if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
    if (row.session_id) params.set('session_id', String(row.session_id));
    if (row.latest_invoice_version_id) params.set('latest_invoice_version_id', String(row.latest_invoice_version_id));
    if (row.latest_invoice_versionno !== null && row.latest_invoice_versionno !== undefined)
      params.set('latest_invoice_versionno', String(row.latest_invoice_versionno));
    if (row.contractor_business_name) params.set('contractor_business_name', String(row.contractor_business_name));
    if (row.latest_di_ocr_invoice_id) params.set('di_ocr_invoice_id', String(row.latest_di_ocr_invoice_id));

    const url = `/advice-refresh-simulation-admin?${params.toString()}`;
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
            <Box flex="0 1 300px" minW="220px" maxW="300px">
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

            <Flex
              role="status"
              aria-live="polite"
              align="center"
              gap={2}
              minH="40px"
              px={3}
              py={2}
              borderWidth="1px"
              borderColor={unreadByAdminOverallInvoiceCount > 0 ? 'purple.300' : 'gray.200'}
              borderRadius="md"
              bg={unreadByAdminOverallInvoiceCount > 0 ? 'purple.50' : 'gray.50'}
              color={unreadByAdminOverallInvoiceCount > 0 ? 'purple.800' : 'gray.600'}
              whiteSpace="nowrap"
              fontWeight={unreadByAdminOverallInvoiceCount > 0 ? 'bold' : 'normal'}
              flexShrink={0}
            >
              <ChatDots size={20} weight={unreadByAdminOverallInvoiceCount > 0 ? 'fill' : 'regular'} />
              <Text fontSize="sm">
                Unread by admin: {unreadByAdminFilteredInvoiceCount} current · {unreadByAdminOverallInvoiceCount}{' '}
                overall
              </Text>
            </Flex>

            <Box minW="260px" maxW="360px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                status
              </Text>
              <MultiCheckSelect
                selectedValues={selectedStatusFilterValues}
                setSelectedValues={(values) => {
                  let nextValues = values;
                  if (values.includes(ALL_STATUS_FILTER_ITEM_VALUE)) {
                    nextValues =
                      selectedStatusFilterValues.includes(ALL_STATUS_FILTER_ITEM_VALUE) && values.length > 1
                        ? values.filter((value) => value !== ALL_STATUS_FILTER_ITEM_VALUE)
                        : [ALL_STATUS_FILTER_ITEM_VALUE];
                  }

                  const nextStatus = nextValues.includes(ALL_STATUS_FILTER_ITEM_VALUE)
                    ? ''
                    : invoiceStatusFromGroupValues(nextValues);
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

            <Box minW="220px" maxW="250px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                sort
              </Text>
              <Select
                value={sort}
                onChange={(event) => {
                  const nextSort = event.target.value;
                  setSort(nextSort);
                  setPage(1);
                  pushUrl({ sort: nextSort, page: 1 });
                }}
                bg="white"
              >
                {INVOICE_SORT_OPTIONS.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}
                  </option>
                ))}
              </Select>
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

            <Table size="sm" w="100%" sx={{ tableLayout: 'fixed' }}>
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
                  <Th w="150px">
                    <SortableHeader
                      field="reference_number"
                      label="Reference #"
                      sort={sort}
                      onSort={handleHeaderSort}
                    />
                  </Th>
                  <Th w="220px">Invoice #</Th>
                  <Th w="190px"></Th>
                  <Th w="160px" textAlign="center">
                    <SortableHeader
                      field="unread_by_contractor_count"
                      label="Unread by contractor"
                      sort={sort}
                      onSort={handleHeaderSort}
                    />
                  </Th>
                  <Th w="140px" textAlign="center">
                    <SortableHeader
                      field="unread_by_admin_count"
                      label="Unread by admin"
                      sort={sort}
                      onSort={handleHeaderSort}
                    />
                  </Th>
                  <Th w="225px" textAlign="right"></Th>
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
                              as={RouterLink}
                              to={`/invoices/${encodeURIComponent(String(r.invoice_id))}/review`}
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
                              _hover={{
                                bg: 'blue.50',
                                color: 'black',
                                textDecoration: 'none',
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

                      <Td fontSize="sm" whiteSpace="nowrap">
                        {r.reference_number !== null && r.reference_number !== undefined
                          ? formatClaimsReferenceNumber(r.reference_number)
                          : '—'}
                      </Td>

                      <Td fontSize="sm" minW={0}>
                        <Text noOfLines={1}>{r.latest_di_ocr_invoice_id || '—'}</Text>
                      </Td>

                      <Td whiteSpace="nowrap">
                        <Flex gap={2} wrap="nowrap" align="center" minW={0} overflow="hidden">
                          <Tooltip label={aiResultHint(r.latest_genai_result)}>
                            <Box as="span" display="inline-flex" alignItems="center" flexShrink={0}>
                              <ResultDot val={r.latest_genai_result} />
                            </Box>
                          </Tooltip>

                          {Array.isArray(r.latest_detected_upgrade_types_json) &&
                          r.latest_detected_upgrade_types_json.length > 0 ? (
                            r.latest_detected_upgrade_types_json.map((upgradeType) => {
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
                            })
                          ) : (
                            <Text fontSize="xs" opacity={0.55}>
                              none
                            </Text>
                          )}
                        </Flex>
                      </Td>

                      <Td textAlign="center">
                        <UnreadMessageStatus
                          count={r.unread_by_contractor_count}
                          audience="contractor"
                          colorScheme="blue"
                        />
                      </Td>

                      <Td textAlign="center">
                        <UnreadMessageStatus count={r.unread_by_admin_count} audience="admin" colorScheme="purple" />
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

                          <Tooltip label="Upload a revised package">
                            <IconButton
                              aria-label="Upload a revised package"
                              {...rowActionButtonProps}
                              icon={<Wrench size={rowActionIconSize} />}
                              onClick={() => handleOpenPackageFix(r)}
                              isDisabled={!hasInvoice || !r.latest_invoice_version_id}
                            />
                          </Tooltip>

                          <Tooltip label="Refresh AI Advice">
                            <IconButton
                              aria-label="Refresh AI Advice"
                              {...rowActionButtonProps}
                              icon={<ArrowsClockwise size={rowActionIconSize} />}
                              onClick={() => handleOpenAdviceRefresh(r)}
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
                    <Td colSpan={10}>
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
