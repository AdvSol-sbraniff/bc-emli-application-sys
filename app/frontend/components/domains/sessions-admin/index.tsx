// /app/frontend/components/domains/sessions-admin/index.tsx
import React, { useEffect, useState } from 'react';
import {
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
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowsClockwise, CaretLeft, CaretRight, Info, XCircle } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: Sessions Admin grid (view-backed)
// - Grid modeled after UploadInvoiceAdmin "Choose session" tab
// - Source:
//   GET /api/claims/admin/sessions_with_contractors?q=&status=&sort=&page=&per=
// - Row actions:
//   - Details => opens Drawer with ALL fields from the view row
//   - Open invoices => opens existing invoices grid in new tab with session_id prefilled
// ============================================================

type SessionRow = {
  // session fields (from s.* in the view)
  id: string;
  contractor_id?: string | null;
  submitter_id?: string | null;
  status?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  submitted_at?: string | null;

  // denormalized contractor fields (aliased in the view)
  contractor_business_name?: string | null;
  contractor_number?: string | null;
  contractor_email?: string | null;
  contractor_phone_number?: string | null;
  contractor_cellphone_number?: string | null;
  contractor_city?: string | null;
  contractor_postal_code?: string | null;
  contractor_onboarded?: boolean | null;
};

type SessionsSearchResponse = {
  rows: SessionRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
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

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '—';
}

function fmtDate(s?: string | null) {
  if (!s) return '—';
  const raw = String(s);
  if (raw.includes('T')) return raw.split('T')[0];
  return raw.slice(0, 10);
}

function yn(v: any) {
  if (v === true) return 'yes';
  if (v === false) return 'no';
  return '—';
}

function Field({ label, value }: { label: string; value: any }) {
  return (
    <Box>
      <Text fontSize="xs" opacity={0.7} mb={1}>
        {label}
      </Text>
      <Text fontSize="sm" fontFamily={label.endsWith('_id') ? 'mono' : undefined} whiteSpace="pre-wrap">
        {value === null || value === undefined || value === '' ? '—' : String(value)}
      </Text>
    </Box>
  );
}

export default function SessionsAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  // ============================================================
  // SECTION 01 — URL-DRIVEN STATE
  // ============================================================

  const q = getParam(location.search, 'q');
  const status = getParam(location.search, 'status');
  const sort = getParam(location.search, 'sort') || 'updated_at:desc';
  const pageStr = getParam(location.search, 'page') || '1';
  const perStr = getParam(location.search, 'per') || '25';

  const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
  const per = [25, 50, 100].includes(parseInt(perStr, 10)) ? parseInt(perStr, 10) : 25;

  // ============================================================
  // SECTION 02 — GRID DATA
  // ============================================================

  const [gridLoading, setGridLoading] = useState(false);
  const [gridError, setGridError] = useState('');
  const [rows, setRows] = useState<SessionRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  const fetchSessions = async () => {
    setGridLoading(true);
    setGridError('');

    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set('q', q.trim());
      if (status.trim()) params.set('status', status.trim());
      params.set('sort', sort);
      params.set('page', String(page));
      params.set('per', String(per));

      const url = `/api/claims/admin/sessions_with_contractors?${params.toString()}`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: SessionsSearchResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setGridError(e?.message || 'Failed to load sessions.');
      setRows([]);
      setTotal(0);
    } finally {
      setGridLoading(false);
    }
  };

  useEffect(() => {
    fetchSessions();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, status, sort, page, per]);

  const totalPages = Math.max(1, Math.ceil((total || 0) / per));

  // ============================================================
  // SECTION 03 — DRAWER
  // ============================================================

  const { isOpen, onOpen, onClose } = useDisclosure();
  const [selected, setSelected] = useState<SessionRow | null>(null);

  const openDrawer = (row: SessionRow) => {
    setSelected(row);
    onOpen();
  };

  const closeDrawer = () => {
    onClose();
    setSelected(null);
  };

  // ============================================================
  // SECTION 04 — OPEN INVOICES GRID
  // ============================================================

  const openInvoicesGrid = (sessionId: string) => {
    const url = `/invoices-admin?session_id=${encodeURIComponent(sessionId)}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  // ============================================================
  // SECTION 05 — RENDER
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Sessions Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Search (contractor name/number/email/city/postal, ids)
              </Text>
              <Input
                value={q}
                onChange={(e) => setParams(navigate, location, { q: e.target.value, page: '1' })}
                placeholder="Search sessions..."
                bg="white"
              />
            </Box>

            <Box w="220px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Status
              </Text>
              <Select
                value={status}
                onChange={(e) => setParams(navigate, location, { status: e.target.value, page: '1' })}
                bg="white"
              >
                <option value="">(any)</option>
                <option value="OPENBUTNOTSUBMITTED">OPENBUTNOTSUBMITTED</option>
                <option value="OPENANDSUBMITTED">OPENANDSUBMITTED</option>
                <option value="CLOSED">CLOSED</option>
              </Select>
            </Box>

            <Box w="240px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Sort
              </Text>
              <Select
                value={sort}
                onChange={(e) => setParams(navigate, location, { sort: e.target.value, page: '1' })}
                bg="white"
              >
                <option value="updated_at:desc">updated_at desc</option>
                <option value="created_at:desc">created_at desc</option>
                <option value="submitted_at:desc">submitted_at desc</option>
                <option value="status:asc">status asc</option>
                <option value="status:desc">status desc</option>
                <option value="contractor_business_name:asc">contractor name asc</option>
                <option value="contractor_business_name:desc">contractor name desc</option>
              </Select>
            </Box>

            <Box w="120px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Per page
              </Text>
              <Select
                value={String(per)}
                onChange={(e) => setParams(navigate, location, { per: e.target.value, page: '1' })}
                bg="white"
              >
                <option value="25">25</option>
                <option value="50">50</option>
                <option value="100">100</option>
              </Select>
            </Box>

            <HStack spacing={2} pb={1}>
              <Tooltip label="Clear filters">
                <IconButton
                  aria-label="Clear filters"
                  icon={<XCircle size={18} />}
                  variant="outline"
                  onClick={() => {
                    setParams(navigate, location, {
                      q: '',
                      status: '',
                      sort: 'updated_at:desc',
                      per: '25',
                      page: '1',
                    });
                  }}
                  isDisabled={!q.trim() && !status.trim() && sort === 'updated_at:desc' && per === 25}
                />
              </Tooltip>

              <Tooltip label="Refresh grid">
                <IconButton
                  aria-label="Refresh grid"
                  icon={<ArrowsClockwise size={18} />}
                  variant="outline"
                  onClick={fetchSessions}
                  isLoading={gridLoading}
                />
              </Tooltip>
            </HStack>
          </Flex>

          {gridError && (
            <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
              <Text as="div" fontSize="sm" color="red.700">
                {gridError}
              </Text>
            </Box>
          )}

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="980px">
                <Thead bg="gray.50">
                  <Tr>
                    <Th>created</Th>
                    <Th>contractor</Th>
                    <Th>contractor #</Th>
                    <Th>session status</Th>
                    <Th>submitted</Th>
                    <Th>session_id</Th>
                    <Th></Th>
                  </Tr>
                </Thead>
              <Tbody>
                {gridLoading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={7}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading sessions...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                )}

                  {rows.map((r) => (
                    <Tr key={r.id} _hover={{ bg: 'gray.50' }}>
                      <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                        {fmtDate(r.created_at)}
                      </Td>

                      <Td fontSize="sm" whiteSpace="nowrap">
                        {r.contractor_business_name ?? '—'}
                      </Td>

                      <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                        {r.contractor_number ?? '—'}
                      </Td>

                      <Td fontFamily="mono" fontSize="xs">
                        {r.status ?? '—'}
                      </Td>

                      <Td fontFamily="mono" fontSize="xs">
                        {fmtTs(r.submitted_at)}
                      </Td>

                      <Td fontFamily="mono" fontSize="xs">
                        {r.id}
                      </Td>

                      <Td>
                        <HStack justify="flex-end" spacing={2}>
                          <Tooltip label="Open details drawer">
                            <IconButton
                              aria-label="Open details drawer"
                              size="xs"
                              variant="outline"
                              icon={<Info size={14} />}
                              onClick={() => openDrawer(r)}
                            />
                          </Tooltip>
                          <Button size="xs" variant="outline" onClick={() => openInvoicesGrid(r.id)}>
                            Open invoices
                          </Button>
                        </HStack>
                      </Td>
                    </Tr>
                  ))}

                  {!gridLoading && rows.length === 0 && (
                    <Tr>
                      <Td colSpan={7}>
                        <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                          No sessions found.
                        </Text>
                      </Td>
                    </Tr>
                  )}
              </Tbody>
            </Table>
          </Box>

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
                  onClick={() => setParams(navigate, location, { page: String(Math.max(1, page - 1)) })}
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
                  onClick={() => setParams(navigate, location, { page: String(Math.min(totalPages, page + 1)) })}
                  isDisabled={page >= totalPages}
                />
              </Tooltip>
            </HStack>
          </Flex>

          <Flex mt={3}>
            <Button size="sm" onClick={() => navigate('/admin-create-session')}>
              Create new session
            </Button>
          </Flex>
        </Box>
      </Container>

      {/* Drawer */}
      <Drawer isOpen={isOpen} placement="right" onClose={closeDrawer} size="lg">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>
            Session {selected?.id ? selected.id.slice(0, 8) + '…' : ''}
          </DrawerHeader>

          <DrawerBody>
            {!selected ? (
              <Text fontSize="sm" opacity={0.7}>
                No session selected.
              </Text>
            ) : (
              <Box>
                <Box mb={3}>
                  <Heading size="sm" mb={1}>
                    Summary
                  </Heading>
                  <Text fontSize="sm">
                    <b>Contractor:</b> {selected.contractor_business_name ?? '—'}
                  </Text>
                  <Text fontSize="sm">
                    <b>Status:</b> <Box as="span" fontFamily="mono">{selected.status ?? '—'}</Box>
                  </Text>
                  <Text fontSize="sm">
                    <b>Updated:</b> <Box as="span" fontFamily="mono">{fmtTs(selected.updated_at)}</Box>
                  </Text>
                  <Text fontSize="sm">
                    <b>Submitted:</b> <Box as="span" fontFamily="mono">{fmtTs(selected.submitted_at)}</Box>
                  </Text>
                </Box>

                <Divider my={4} />

                <Heading size="sm" mb={2}>
                  Session fields
                </Heading>
                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Field label="id" value={selected.id} />
                  <Field label="status" value={selected.status} />
                  <Field label="contractor_id" value={selected.contractor_id} />
                  <Field label="submitter_id" value={selected.submitter_id} />
                  <Field label="created_at" value={fmtTs(selected.created_at)} />
                  <Field label="updated_at" value={fmtTs(selected.updated_at)} />
                  <Field label="submitted_at" value={fmtTs(selected.submitted_at)} />
                </SimpleGrid>

                <Divider my={4} />

                <Heading size="sm" mb={2}>
                  Contractor fields (denormalized)
                </Heading>
                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Field label="contractor_business_name" value={selected.contractor_business_name} />
                  <Field label="contractor_number" value={selected.contractor_number} />
                  <Field label="contractor_email" value={selected.contractor_email} />
                  <Field label="contractor_phone_number" value={selected.contractor_phone_number} />
                  <Field label="contractor_cellphone_number" value={selected.contractor_cellphone_number} />
                  <Field label="contractor_city" value={selected.contractor_city} />
                  <Field label="contractor_postal_code" value={selected.contractor_postal_code} />
                  <Field label="contractor_onboarded" value={yn(selected.contractor_onboarded)} />
                </SimpleGrid>

                <Divider my={4} />
              </Box>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}