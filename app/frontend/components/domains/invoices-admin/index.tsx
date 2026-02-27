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
  Input,
  Select,
  SimpleGrid,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

type InvoiceGridRow = {
  invoice_id: string;

  session_id: string;
  invoice_status: string;
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
const fmtMoney = (v?: string | number | null) => {
  if (v === null || v === undefined || v === '') return '';
  const n = typeof v === 'number' ? v : Number(v);
  if (Number.isNaN(n)) return String(v);
  return n.toLocaleString(undefined, { style: 'currency', currency: 'CAD' });
};
const shortId = (s?: string | null) => (s ? `${s.slice(0, 8)}…` : '');

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
  const [rows, setRows] = useState<InvoiceGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  // drawer
  const { isOpen, onOpen, onClose } = useDisclosure();
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
  window.open(url, '_blank', 'noopener,noreferrer');
};
  
  const handleOpenVersions = (invoiceId: string) => {
    const url = `/invoice-versions-admin?invoice_id=${encodeURIComponent(invoiceId)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

const handleOpenDetailsWithPdf = (sessionId: string, invoiceId: string) => {
  const url = `/sessions/${encodeURIComponent(sessionId)}/invoices/${encodeURIComponent(invoiceId)}/read`;
  window.open(url, '_blank', 'noopener,noreferrer');
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
      <BlueTitleBar title="Invoices Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Heading size="md" mb={2}>
            Invoice grid (view-backed)
          </Heading>

          <Text fontSize="sm" opacity={0.8} mb={4}>
            Powered by <code>claims.v_invoice_grid</code> (bookmarkable filters via URL query params).
          </Text>

          {/* Filters */}
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="260px">
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

            <Box minW="220px">
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

            <Box minW="300px">
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

            <Box minW="120px">
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

<Button
  onClick={() => fetchRows()}
  isLoading={loading}
  loadingText="Refreshing..."
>
  Refresh
</Button>



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
              <Thead>
                <Tr>
                  <Th>updated</Th>
                  <Th>invoice #</Th>
                  <Th>contractor</Th>
                  <Th isNumeric>total</Th>
                  <Th>status</Th>
                  <Th>AI</Th>
                  <Th isNumeric>conf</Th>
                  <Th></Th>
                </Tr>
              </Thead>

              <Tbody>
                {rows.map((r) => (
                  <Tr key={r.invoice_id}>
                    <Td fontFamily="mono" fontSize="xs">
                      {fmtTs(r.latest_invoice_version_updated_at ?? r.invoice_updated_at)}
                    </Td>

                    <Td fontFamily="mono" fontSize="xs">
                      {r.latest_di_ocr_invoice_id ?? shortId(r.invoice_id)}
                    </Td>

                    <Td fontSize="sm">
                      <Text fontWeight="semibold">{r.contractor_business_name ?? '—'}</Text>
                      <Text fontSize="xs" opacity={0.75}>
                        {(r.contractor_number ? `${r.contractor_number}` : '')}
                      </Text>
                    </Td>

                    <Td isNumeric fontFamily="mono" fontSize="xs">
                      {fmtMoney(r.latest_di_ocr_invoice_total)}
                    </Td>

                    <Td>
                      <Badge>{r.invoice_status}</Badge>
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
<Button
  size="xs"
  variant="outline"
  onClick={() => handleOpenDrawer(r)}
>
  Details
</Button>


<Button
  size="xs"
  variant="outline"
  onClick={() => handleOpenDetailsWithPdf(r.session_id, r.invoice_id)}
>
  Details with PDF
</Button>

<Button size="xs" variant="outline" onClick={() => handleOpenVersions(r.invoice_id)}>
  Versions Grid
</Button>

<Button
  size="xs"
  variant="outline"
  onClick={() => handlePopulateJobAdminWithInvoice(r)}
>
  Populate Job Admin
</Button>


                      </HStack>
                    </Td>
                  </Tr>
                ))}

                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={8}>
                      <Text fontSize="sm" opacity={0.7}>
                        No rows. Adjust filters or click Refresh.
                      </Text>
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>

            {/* Pagination */}
            <Flex mt={3} align="center" justify="space-between" wrap="wrap" gap={2}>
              <Text fontSize="xs" opacity={0.75}>
                Page {page} / {totalPages}
              </Text>

              <HStack spacing={2}>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const next = 1;
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                  isDisabled={page <= 1 || loading}
                >
                  First
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const next = Math.max(1, page - 1);
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                  isDisabled={page <= 1 || loading}
                >
                  Prev
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const next = Math.min(totalPages, page + 1);
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                  isDisabled={page >= totalPages || loading}
                >
                  Next
                </Button>
                <Button
                  size="sm"
                  variant="outline"
                  onClick={() => {
                    const next = totalPages;
                    setPage(next);
                    pushUrl({ page: next });
                  }}
                  isDisabled={page >= totalPages || loading}
                >
                  Last
                </Button>
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
          <DrawerHeader>
            Invoice {selected?.latest_di_ocr_invoice_id ?? shortId(selected?.invoice_id ?? '')}
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
                      Summary
                    </Text>
                    <Text fontSize="sm">
                      <b>Contractor:</b> {selected.contractor_business_name ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Status:</b> {selected.invoice_status}
                    </Text>
                    <Text fontSize="sm">
                      <b>Total:</b> {fmtMoney(selected.latest_di_ocr_invoice_total)}
                    </Text>
                    <HStack spacing={2} mt={1}>
                      <Text fontSize="sm">
                        <b>AI:</b>
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
                        (conf {selected.latest_genai_overall_confidence ?? '—'})
                      </Text>
                    </HStack>
                  </Box>

                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Document
                    </Text>
                    <Text fontSize="sm">
                      <b>Invoice date:</b> {selected.latest_di_ocr_invoice_date ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Vendor:</b> {selected.latest_di_ocr_vendor_name ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Filename:</b> {selected.latest_original_filename ?? '—'}
                    </Text>
                    <Text fontSize="sm">
                      <b>Last updated:</b> {fmtTs(selected.latest_invoice_version_updated_at ?? selected.invoice_updated_at)}
                    </Text>
                  </Box>
                </SimpleGrid>

                <Divider my={4} />

                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Submitter
                    </Text>
                    <Text fontSize="sm">{selected.submitter_name ?? '—'}</Text>
                    <Text fontSize="sm" opacity={0.85}>
                      {selected.submitter_email ?? ''}
                    </Text>
                    <Text fontSize="xs" opacity={0.7} fontFamily="mono" mt={1}>
                      submitter_id: {selected.submitter_id ? selected.submitter_id : '—'}
                    </Text>
                  </Box>

                  <Box>
                    <Text fontWeight="bold" mb={1}>
                      Contractor contact
                    </Text>
                    <Text fontSize="sm">{selected.contractor_contact_name ?? '—'}</Text>
                    <Text fontSize="sm" opacity={0.85}>
                      {selected.contractor_contact_email ?? ''}
                    </Text>
                    <Text fontSize="xs" opacity={0.7} fontFamily="mono" mt={1}>
                      contractor_id: {selected.contractor_id ? selected.contractor_id : '—'}
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

                <Divider my={4} />

                <HStack spacing={2} justify="flex-end">
                  <Button variant="outline" onClick={() => handleOpenVersions(selected.invoice_id)}>
                    Open versions
                  </Button>
                  <Button
                    onClick={() => {
                      // If you later add a stable invoice read route in the SPA, wire it here.
                      // For now, just open versions which is already built.
                      handleOpenVersions(selected.invoice_id);
                    }}
                  >
                    Open
                  </Button>
                </HStack>
              </Box>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}