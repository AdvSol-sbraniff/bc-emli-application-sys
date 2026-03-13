// /app/frontend/components/domains/invoices-admin/index.tsx
import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Divider,
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
  FileArrowUp,
  FilePdf,
  GitBranch,
  Info,
  MagnifyingGlass,
  Question,
  Scan,
  Sparkle,
  Trash,
  Wrench,
  XCircle,
} from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

type InvoiceGridRow = {
  invoice_id?: string | null;

  session_id: string;
  session_created_at?: string | null;
  invoice_status?: string | null;
  invoice_status_updated_at?: string | null;
  invoice_created_at?: string | null;
  invoice_updated_at?: string | null;

  session_status?: string | null;
  session_submitted_at?: string | null;

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

  latest_genai_all_rulechecks_pass_flag?: boolean | null;
  latest_genai_overall_confidence?: number | null;

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

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');
const fmtDate = (s?: string | null) => {
  if (!s) return '';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
};
const fmtMoney = (v?: string | number | null) => {
  if (v === null || v === undefined || v === '') return '';
  const n = typeof v === 'number' ? v : Number(v);
  if (Number.isNaN(n)) return String(v);
  return n.toLocaleString(undefined, { style: 'currency', currency: 'CAD' });
};

function PassDot({ val }: { val: boolean | null | undefined }) {
  // neutral dot if null/undefined
  const bg = val === true ? 'green.400' : val === false ? 'red.400' : 'gray.300';
  return <Box w="10px" h="10px" borderRadius="full" bg={bg} display="inline-block" />;
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
  const [invoiceStatus, setInvoiceStatus] = useState<string>(''); // single for PoC (can extend to multi later)
  const [sort, setSort] = useState<string>('latest_invoice_version_updated_at:desc');
  const [page, setPage] = useState<number>(1);
  const [per, setPer] = useState<number>(25);

  // data
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [deletingInvoiceId, setDeletingInvoiceId] = useState<string>('');
  const [rows, setRows] = useState<InvoiceGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  // drawer
  const { isOpen, onOpen, onClose } = useDisclosure();
  const {
    isOpen: isUploadHelpOpen,
    onOpen: onUploadHelpOpen,
    onClose: onUploadHelpClose,
  } = useDisclosure();
  const [selected, setSelected] = useState<InvoiceGridRow | null>(null);

  const didInitFromUrl = useRef(false);

  // 1) initialize state from URL once (and whenever user manually edits URL)
  useEffect(() => {
    const params = new URLSearchParams(location.search);

    // Only overwrite local state if:
    // - first load, or
    // - URL was changed by back/forward navigation
    const next = {
      session_id: params.get('session_id') || '',
      q: params.get('q') || '',
      invoice_status: params.get('invoice_status') || '',
      sort: params.get('sort') || 'latest_invoice_version_updated_at:desc',
      page: Number(params.get('page') || '1') || 1,
      per: Number(params.get('per') || '25') || 25,
    };

    if (!didInitFromUrl.current) {
      didInitFromUrl.current = true;
      setSessionId(next.session_id);
      setQ(next.q);
      setInvoiceStatus(next.invoice_status);
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
    setSort(next.sort);
    setPage(next.page);
    setPer(next.per);
  }, [location.search]);

  // 2) push state to URL (bookmarkable)
  const pushUrl = (next: Partial<{ sessionId: string; q: string; invoiceStatus: string; sort: string; page: number; per: number }>) => {
    const merged = {
      sessionId,
      q,
      invoiceStatus,
      sort,
      page,
      per,
      ...next,
    };

    const params = buildSearchParams({
      session_id: merged.sessionId || undefined,
      q: merged.q || undefined,
      invoice_status: merged.invoiceStatus || undefined,
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

const fetchRows = async () => {
  setLoading(true);
  setError('');
  try {
    const params = buildSearchParams({
      session_id: sessionId || undefined,
      q: q || undefined,
      invoice_status: invoiceStatus || undefined,
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
};

// ============================================================
// SECTION 05.02 — AUTO FETCH
// PURPOSE: Fetch whenever filter/sort/page params change
// ============================================================

useEffect(() => {
  if (didInitFromUrl.current) fetchRows();
}, [sessionId, q, invoiceStatus, sort, page, per]);





  const totalPages = useMemo(() => {
    const p = Math.max(1, per || 25);
    return Math.max(1, Math.ceil((total || 0) / p));
  }, [total, per]);


const handlePopulateJobAdminWithInvoice = (row: InvoiceGridRow) => {
  const params = new URLSearchParams();

  if (row.session_id) params.set('session_id', row.session_id);
  if (row.invoice_id) params.set('invoice_id', row.invoice_id);
  if (row.latest_invoice_version_id) params.set('invoice_version_id', row.latest_invoice_version_id);

  const url = `/ai-admin?${params.toString()}`;
  window.open(url, '_blank');
};
  
  const handleOpenVersions = (invoiceId: string) => {
    const url = `/invoice-versions-admin?invoice_id=${encodeURIComponent(invoiceId)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

const handleOpenDetailsWithPdf = (sessionId: string, invoiceId: string) => {
  const url = `/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read`;
  window.open(url, '_blank', 'noopener,noreferrer');
};

const handleOpenUploadNewInvoice = (sessionId: string) => {
  const url = `/upload-invoice-admin?session_id=${encodeURIComponent(sessionId)}`;
  window.open(url, '_blank', 'noopener,noreferrer');
};

const handleOpenUploadFix = (row: InvoiceGridRow) => {
  const params = new URLSearchParams();
  if (row.invoice_id) params.set('invoice_id', String(row.invoice_id));
  if (row.session_id) params.set('session_id', String(row.session_id));
  if (row.latest_invoice_version_id) params.set('latest_invoice_version_id', String(row.latest_invoice_version_id));
  if (row.latest_invoice_versionno !== null && row.latest_invoice_versionno !== undefined) params.set('latest_invoice_versionno', String(row.latest_invoice_versionno));
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
  if (row.session_status) params.set('context_session_status', String(row.session_status));
  if (row.invoice_status) params.set('context_invoice_status', String(row.invoice_status));
  if (row.contractor_business_name) params.set('context_contractor_business_name', String(row.contractor_business_name));
  if (row.latest_di_ocr_invoice_id) params.set('context_di_ocr_invoice_id', String(row.latest_di_ocr_invoice_id));
  const url = `/revision-requests-admin?${params.toString()}`;
  window.open(url, '_blank', 'noopener,noreferrer');
};

const handleDeleteInvoice = async (invoiceId: string) => {
  const confirmed = window.confirm(
    'Delete this invoice and all child records (invoice versions, revision requests, lineitems, step runs, and related artifacts)? This cannot be undone.'
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

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Invoices Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          {/* Filters */}
          <Flex gap={3} align="end" wrap="nowrap" mb={4} overflowX="auto">
            <Box flex="1" minW="220px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                session_id (optional)
              </Text>
              <Input
                value={sessionId}
                onChange={(e) => {
                  setSessionId(e.target.value);
                  setPage(1);
                }}
                onBlur={() => pushUrl({ sessionId, page: 1 })}
                placeholder="session UUID (optional)"
                bg="white"
                fontFamily="mono"
              />
            </Box>

            <Box flex="1" minW="260px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                search (q)
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

            <Box minW="180px" maxW="220px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                invoice_status
              </Text>
              <Select
                value={invoiceStatus}
                onChange={(e) => {
                  setInvoiceStatus(e.target.value);
                  setPage(1);
                  // push immediately
                  pushUrl({ invoiceStatus: e.target.value, page: 1 });
                }}
                bg="white"
              >
                <option value="">(all)</option>
                <option value="upload_failed">upload_failed</option>
                <option value="upload_complete">upload_complete</option>
                <option value="ocr_failed">ocr_failed</option>
                <option value="ocr_complete">ocr_complete</option>
                <option value="genai_failed">genai_failed</option>
                <option value="genai_complete">genai_complete</option>
                <option value="awaiting_admin_review">awaiting_admin_review</option>
                <option value="contractor_revision_required">contractor_revision_required</option>
                <option value="closed">closed</option>
              </Select>
            </Box>

            <Box minW="220px" maxW="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                sort
              </Text>
              <Select
                value={sort}
                onChange={(e) => {
                  setSort(e.target.value);
                  pushUrl({ sort: e.target.value });
                }}
                bg="white"
              >
                <option value="latest_invoice_version_updated_at:desc">latest update ↓</option>
                <option value="latest_invoice_version_updated_at:asc">latest update ↑</option>
                <option value="invoice_created_at:desc">created ↓</option>
                <option value="invoice_created_at:asc">created ↑</option>
                <option value="contractor_business_name:asc">contractor A→Z</option>
                <option value="contractor_business_name:desc">contractor Z→A</option>
                <option value="latest_genai_overall_confidence:desc">confidence ↓</option>
                <option value="latest_genai_overall_confidence:asc">confidence ↑</option>
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

            <HStack spacing={2} pb={1} flexShrink={0}>
              <Tooltip label="Help: upload new, upload fix, OCR / AI, inspect versions">
                <IconButton
                  aria-label="Open invoices help"
                  icon={<Question size={18} />}
                  variant="outline"
                  size="sm"
                  onClick={onUploadHelpOpen}
                />
              </Tooltip>

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
                    setInvoiceStatus('');
                    setSort('latest_invoice_version_updated_at:desc');
                    setPer(25);
                    setPage(1);
                    pushUrl({
                      sessionId: '',
                      q: '',
                      invoiceStatus: '',
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
          <Box bg="white" borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={3}>
            <Flex align="center" justify="space-between" mb={2}>
              <HStack spacing={3}>
                <Text fontSize="sm" fontWeight="bold">
                  Invoices
                </Text>
                <Text fontSize="xs" opacity={0.7}>
                  {total.toLocaleString()} total
                </Text>
              </HStack>
              {loading && <Spinner size="sm" />}
            </Flex>

            <Table size="sm">
              <Thead bg="gray.50">
                <Tr>
                  <Th>session created</Th>
                  <Th>contractor</Th>
                  <Th>contractor #</Th>
                  <Th>invoice #</Th>
                  <Th isNumeric>total</Th>
                  <Th>status</Th>
                  <Th>AI</Th>
                  <Th isNumeric>conf</Th>
                  <Th>Actions</Th>
                </Tr>
              </Thead>

              <Tbody>
                {rows.map((r, idx) => {
                  const hasInvoice = Boolean(r.invoice_id && String(r.invoice_id).trim());
                  return (
                  <Tr key={`${r.invoice_id || 'no-invoice'}-${r.session_id}-${idx}`}>
                    <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                      {fmtDate(r.session_created_at)}
                    </Td>

                    <Td fontSize="sm" whiteSpace="nowrap">
                      {r.contractor_business_name ?? '—'}
                    </Td>

                    <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                      {r.contractor_number ?? '—'}
                    </Td>

                    <Td fontFamily="mono" fontSize="xs">
                      {r.latest_di_ocr_invoice_id || '—'}
                    </Td>

                    <Td isNumeric fontFamily="mono" fontSize="xs">
                      {fmtMoney(r.latest_di_ocr_invoice_total)}
                    </Td>

                    <Td>
                      <Badge>{r.invoice_status || '—'}</Badge>
                    </Td>

                    <Td>
                      <HStack spacing={2}>
                        <PassDot val={r.latest_genai_all_rulechecks_pass_flag} />
                        <Text fontSize="xs" opacity={0.8}>
                          {r.latest_genai_all_rulechecks_pass_flag === null || r.latest_genai_all_rulechecks_pass_flag === undefined
                            ? 'unknown'
                            : r.latest_genai_all_rulechecks_pass_flag
                              ? 'pass'
                              : 'fail'}
                        </Text>
                      </HStack>
                    </Td>

                    <Td isNumeric fontFamily="mono" fontSize="xs">
                      {r.latest_genai_overall_confidence ?? ''}
                    </Td>

                    <Td>
                      <HStack justify="flex-end" spacing={2}>
<Tooltip label="Open details drawer">
<IconButton
  aria-label="Open details drawer"
  size="xs"
  variant="outline"
  icon={<Info size={14} />}
  onClick={() => handleOpenDrawer(r)}
  isDisabled={!hasInvoice}
/>
</Tooltip>

<Tooltip label ="Open PDF viewer"> 
<IconButton
  aria-label="Open PDF viewer"
  size="xs"
  variant="outline"
  icon={<FilePdf size={14} />}
  onClick={() => handleOpenDetailsWithPdf(r.session_id, String(r.invoice_id))}
  isDisabled={!hasInvoice}
/>
</Tooltip>

<Tooltip label="Delete invoice and all child claim records">
<IconButton
  aria-label="Delete invoice"
  size="xs"
  variant="outline"
  colorScheme="red"
  icon={<Trash size={14} />}
  onClick={() => handleDeleteInvoice(String(r.invoice_id))}
  isDisabled={!hasInvoice || loading || (!!deletingInvoiceId && deletingInvoiceId !== String(r.invoice_id))}
  isLoading={deletingInvoiceId === String(r.invoice_id)}
/>
</Tooltip>

<Tooltip label="inspect prior versions of this invoice">
<IconButton
  aria-label="Inspect invoice versions"
  size="xs"
  variant="outline"
  icon={<MagnifyingGlass size={14} />}
  onClick={() => handleOpenVersions(String(r.invoice_id))}
  isDisabled={!hasInvoice}
/>
</Tooltip>

<Tooltip label="view all revision requests for all versions for this invoice">
<IconButton
  aria-label="Open revision requests"
  size="xs"
  variant="outline"
  icon={<GitBranch size={14} />}
  onClick={() => handleOpenRevisions(r)}
  isDisabled={!hasInvoice}
/>
</Tooltip>

<Tooltip label="Re-run OCR and AI jobs for this invoice">
<IconButton
  aria-label="Run OCR and AI jobs"
  size="xs"
  variant="outline"
  icon={
    <HStack spacing={0.5}>
      <Scan size={12} />
      <Sparkle size={12} />
    </HStack>
  }
  onClick={() => handlePopulateJobAdminWithInvoice(r)}
  isDisabled={!hasInvoice}
/>
</Tooltip>

<Tooltip label="upload net new invoice (not a fix) for this session">
<IconButton
  aria-label="Upload new invoice"
  size="xs"
  variant="outline"
  icon={<FileArrowUp size={14} />}
  onClick={() => handleOpenUploadNewInvoice(r.session_id)}
/>
</Tooltip>

<Tooltip label="upload a +1 version fixing a problem with prior pdf invoice (not a net new invoice)">
<IconButton
  aria-label="Upload fix invoice version"
  size="xs"
  variant="outline"
  icon={<Wrench size={14} />}
  onClick={() => handleOpenUploadFix(r)}
  isDisabled={!hasInvoice || !r.latest_invoice_version_id}
/>
</Tooltip>


                      </HStack>
                    </Td>
                  </Tr>
                );
                })}

                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={9}>
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

      <Drawer isOpen={isUploadHelpOpen} placement="left" onClose={onUploadHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Invoices Admin Help</DrawerHeader>
          <DrawerBody>
            <Text fontSize="sm" mb={3}>
              This screen has six related but distinct actions: Submission, upload new, upload fix, OCR / AI, Inspect Versions, and Revision Requests. They are intentionally separated so full-pipeline simulation, document upload, OCR/GenAI processing, version inspection, and revision-request review remain clear and testable.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Upload new
            </Text>
            <Text fontSize="sm" mb={3}>
              Use this when the contractor omitted an entire homeowner invoice from their batch. This creates a new invoice record and its first invoice version (version 1). Although the button appears on a row that displays invoice-level details, this action is session-scoped and uses the selected session to add a net-new invoice to that session.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Upload fix
            </Text>
            <Text fontSize="sm" mb={3}>
              Use this when an existing invoice PDF needs correction (for example, a typo or other source-document error). This creates a new child invoice version (+1) under the same invoice.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              OCR / AI
            </Text>
            <Text fontSize="sm" mb={3}>
              The upload buttons only store the PDF and create invoice/invoice-version records. They do not run OCR extraction or GenAI rule checks. OCR and GenAI are run separately via OCR / AI so they can be re-run without re-uploading files.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Inspect Versions
            </Text>
            <Text fontSize="sm" mb={3}>
              The main Invoices grid shows only the current (latest) version for each invoice. Use Inspect Versions to view prior versions and compare what the contractor changed between revision requests.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Revision Requests
            </Text>
            <Text fontSize="sm" mb={3}>
              Revision Requests opens an invoice-scoped grid across all versions for the selected invoice, even though this Invoices grid only shows the current version. For example, an invoice with 3 versions might show 5 revision requests in total: 2 on version 1, 2 on version 2, and 1 on version 3. Each revision request record includes both the admin request and the contractor response.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Why this separation matters
            </Text>
            <Text fontSize="sm" mb={2}>
              Example 1: Participant or account data changed (such as a corrected eligibility code). Re-run GenAI only to refresh rule checks against current system data.
            </Text>
            <Text fontSize="sm" mb={2}>
              Example 2: The source PDF itself was incorrect. Request the contractor to correct and upload a fix, then run OCR/GenAI on the new invoice version.
            </Text>
            <Text fontSize="sm" mb={2}>
              Example 3: A new validation ruleset is introduced. Re-run GenAI and select the new ruleset to evaluate outcomes without uploading again.
            </Text>
            <Text fontSize="sm" mb={2}>
              Example 4: OCR quality improvements are released. Re-run OCR (and then GenAI if needed) to pick up improved extraction quality from the same uploaded PDF.
            </Text>
            <Text fontSize="sm">
              Example 5: Operational troubleshooting. If a prior run failed due to transient processing issues, re-run only the failed step instead of repeating full upload.
            </Text>
          </DrawerBody>
        </DrawerContent>
      </Drawer>

      {/* Drawer */}
      <Drawer isOpen={isOpen} placement="right" onClose={handleCloseDrawer} size="md">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>
            Invoice {selected?.latest_di_ocr_invoice_id || '—'}
          </DrawerHeader>

          <DrawerBody>
            {!selected ? (
              <Text fontSize="sm" opacity={0.7}>
                No invoice selected.
              </Text>
            ) : (
              <Box>
                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Invoice
                    </Text>
                    <Text fontSize="sm">
                      <b>Invoice number (DI):</b> {selected.latest_di_ocr_invoice_id || '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Invoice id:</b> {selected.invoice_id ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Invoice status:</b> {selected.invoice_status ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Status updated at:</b> {fmtTs(selected.invoice_status_updated_at) || '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Created at:</b> {fmtTs(selected.invoice_created_at) || '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Updated at:</b> {fmtTs(selected.invoice_updated_at) || '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Invoice total (DI):</b> {fmtMoney(selected.latest_di_ocr_invoice_total)}
                    </Text>
                    <HStack spacing={2} mt={1}>
                      <Text fontSize="sm">
                        <b>GenAI:</b>
                      </Text>
                      <PassDot val={selected.latest_genai_all_rulechecks_pass_flag} />
                      <Text fontSize="sm" opacity={0.85}>
                        {selected.latest_genai_all_rulechecks_pass_flag === null || selected.latest_genai_all_rulechecks_pass_flag === undefined
                          ? 'unknown'
                          : selected.latest_genai_all_rulechecks_pass_flag
                            ? 'pass'
                            : 'fail'}
                      </Text>
                      <Text fontSize="sm" opacity={0.85}>
                        (confidence {selected.latest_genai_overall_confidence ?? '—'})
                      </Text>
                    </HStack>
                  </Box>

                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Session
                    </Text>
                    <Text fontSize="sm">
                      <b>Session id:</b> {selected.session_id ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Session status:</b> {selected.session_status ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Session submitted at:</b> {fmtTs(selected.session_submitted_at) || '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Session created at:</b> {fmtTs(selected.session_created_at) || '—'}
                    </Text>
                  </Box>
                </SimpleGrid>

                <Divider my={4} />

                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Contractor
                    </Text>
                    <Text fontSize="sm">
                      <b>Contractor id:</b> {selected.contractor_id ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Business name:</b> {selected.contractor_business_name ?? '—'}
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

                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Submitter
                    </Text>
                    <Text fontSize="sm">
                      <b>Submitter id:</b> {selected.submitter_id ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Name:</b> {selected.submitter_name ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Email:</b> {selected.submitter_email ?? '—'}
                    </Text>
                  </Box>
                </SimpleGrid>

                <Divider my={4} />

                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Invoice Version (latest)
                    </Text>
                    <Text fontSize="sm">
                      <b>Version id:</b> {selected.latest_invoice_version_id ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Version number:</b> {selected.latest_invoice_versionno ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Version updated at:</b> {fmtTs(selected.latest_invoice_version_updated_at) || '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Original filename:</b> {selected.latest_original_filename ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Last updated (effective):</b>{' '}
                      {fmtTs(selected.latest_invoice_version_updated_at ?? selected.invoice_updated_at) || '—'}
                    </Text>
                  </Box>

                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      DI Extracted Values
                    </Text>
                    <Text fontSize="sm">
                      <b>Invoice number:</b> {selected.latest_di_ocr_invoice_id ?? '—'}
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
                </SimpleGrid>

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