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
import {
  ArrowsClockwise,
  CaretLeft,
  CaretRight,
  FileArrowUp,
  Info,
  Question,
  Trash,
  XCircle,
} from '@phosphor-icons/react';
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
// ============================================================

type SessionRow = {
  // session fields (from s.* in the view)
  id: string;
  contractor_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
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
  const [deletingSessionId, setDeletingSessionId] = useState('');
  const [rows, setRows] = useState<SessionRow[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [selectedSessionForUpload, setSelectedSessionForUpload] = useState<SessionRow | null>(null);

  const fetchSessions = async () => {
    setGridLoading(true);
    setGridError('');

    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set('q', q.trim());
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
  }, [q, sort, page, per]);

  const totalPages = Math.max(1, Math.ceil((total || 0) / per));

  // ============================================================
  // SECTION 03 — DRAWER
  // ============================================================

  const { isOpen, onOpen, onClose } = useDisclosure();
  const { isOpen: isHelpOpen, onOpen: onHelpOpen, onClose: onHelpClose } = useDisclosure();
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

  const openContractorDraftSimulator = (row: SessionRow) => {
    const contractorId = String(row.contractor_id || '').trim();
    const url = contractorId
      ? `/submission-simulator-admin?contractor_id=${encodeURIComponent(contractorId)}`
      : '/submission-simulator-admin';
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  const deleteSession = async (sessionId: string) => {
    const confirmed = window.confirm(
      'Delete this session and all child claim records (invoices, versions, runs, step runs, and related artifacts)? This cannot be undone.',
    );
    if (!confirmed) return;

    setDeletingSessionId(sessionId);
    setGridError('');

    try {
      const res = await fetch(`/api/claims/admin/sessions_with_contractors/${encodeURIComponent(sessionId)}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      if (selected?.id === sessionId) {
        closeDrawer();
      }

      await fetchSessions();
    } catch (e: any) {
      setGridError(e?.message || 'Failed to delete session.');
    } finally {
      setDeletingSessionId('');
    }
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
                Search session id
              </Text>
              <Input
                value={q}
                onChange={(e) => setParams(navigate, location, { q: e.target.value, page: '1' })}
                placeholder="Search sessions..."
                bg="white"
              />
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
              <Tooltip label="Help: what sessions are and why this screen exists">
                <IconButton
                  aria-label="Open sessions help"
                  icon={<Question size={18} />}
                  variant="outline"
                  onClick={onHelpOpen}
                />
              </Tooltip>

              <Tooltip label="Clear filters">
                <IconButton
                  aria-label="Clear filters"
                  icon={<XCircle size={18} />}
                  variant="outline"
                  onClick={() => {
                    setParams(navigate, location, {
                      q: '',
                      sort: 'updated_at:desc',
                      per: '25',
                      page: '1',
                    });
                  }}
                  isDisabled={!q.trim() && sort === 'updated_at:desc' && per === 25}
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
            <Table size="sm" minW="720px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>created</Th>
                  <Th>updated</Th>
                  <Th>session_id</Th>
                  <Th></Th>
                </Tr>
              </Thead>
              <Tbody>
                {gridLoading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={4}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading sessions...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                )}

                {rows.map((r) => {
                  const isSelectedForUpload = selectedSessionForUpload?.id === r.id;

                  return (
                    <Tr
                      key={r.id}
                      bg={isSelectedForUpload ? 'blue.50' : undefined}
                      cursor="pointer"
                      _hover={{ bg: isSelectedForUpload ? 'blue.50' : 'gray.50' }}
                      onClick={() => setSelectedSessionForUpload(r)}
                    >
                      <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                        {fmtDate(r.created_at)}
                      </Td>

                      <Td fontFamily="mono" fontSize="xs" whiteSpace="nowrap">
                        {fmtDate(r.updated_at)}
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
                              onClick={(event) => {
                                event.stopPropagation();
                                setSelectedSessionForUpload(r);
                                openDrawer(r);
                              }}
                            />
                          </Tooltip>
                          <Tooltip label="Delete session and all child claim records">
                            <IconButton
                              aria-label="Delete session"
                              size="xs"
                              variant="outline"
                              colorScheme="red"
                              icon={<Trash size={14} />}
                              onClick={(event) => {
                                event.stopPropagation();
                                deleteSession(r.id);
                              }}
                              isLoading={deletingSessionId === r.id}
                              isDisabled={gridLoading || (!!deletingSessionId && deletingSessionId !== r.id)}
                            />
                          </Tooltip>
                        </HStack>
                      </Td>
                    </Tr>
                  );
                })}

                {!gridLoading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={4}>
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

          <Flex mt={3} gap={3} align="center" wrap="wrap">
            <Button size="sm" onClick={() => navigate('/admin-create-session')}>
              Create new session
            </Button>
            <Button
              size="sm"
              variant="outline"
              leftIcon={<FileArrowUp size={16} />}
              onClick={() => selectedSessionForUpload && openContractorDraftSimulator(selectedSessionForUpload)}
              isDisabled={!selectedSessionForUpload?.id}
            >
              Open contractor simulator
            </Button>
            {selectedSessionForUpload?.id && (
              <Text fontSize="xs" opacity={0.7}>
                Selected session: {selectedSessionForUpload.id}
              </Text>
            )}
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Sessions Admin Help</DrawerHeader>
          <DrawerBody>
            <Text fontSize="sm" mb={3}>
              A session is a folder that groups multiple invoice submissions together. Contractors can see and use this
              folder in their workflow, so admins also need to see it and understand it.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Why admins need this screen
            </Text>
            <Text fontSize="sm" mb={3}>
              Even if many admin users do not work with sessions every day, they still need a mental map of this
              structure. When contractor-side information needs correction or investigation, sessions are part of how
              records are organized and traced.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Important design tradeoff
            </Text>
            <Text fontSize="sm" mb={3}>
              Needing to upload multiple invoices at once does not automatically require exposing a session object in
              the user interface. If contractors only had a simple multi-click upload flow with no visible session
              concept, this complexity would be much less visible in both contractor and admin UX.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Why we still use sessions
            </Text>
            <Text fontSize="sm" mb={3}>
              The session pattern is useful for larger contractor organizations and for broader government use cases
              where grouped submission tracking, review context, and auditability matter. Because it scales well, it is
              being adopted as a reusable pattern.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Day-to-day operations vs testing
            </Text>
            <Text fontSize="sm" mb={3}>
              Admins may rarely create sessions in routine daily work. However, session behavior is still a core
              technical construct and must be tested in UAT and integration flows.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Why this is in the GUI
            </Text>
            <Text fontSize="sm" mb={3}>
              Testing cannot be only a technical activity. Business staff also need to run realistic scenarios. A GUI
              for sessions allows both technical and business teams to validate the same workflow, using the same
              screen, before release.
            </Text>

            <Text fontSize="sm" fontWeight="bold" mb={1}>
              Simple examples
            </Text>
            <Text fontSize="sm" mb={2}>
              Example 1: A contractor submits several invoices in one work package. The session groups those records so
              reviewers can follow them together.
            </Text>
            <Text fontSize="sm" mb={2}>
              Example 2: UAT team needs to prove invoices are grouped correctly after upload and AI processing. Sessions
              Admin gives one place to verify that grouping.
            </Text>
            <Text fontSize="sm">
              Example 3: A support issue references a contractor upload day. Session grouping helps admins narrow the
              investigation quickly.
            </Text>
          </DrawerBody>
        </DrawerContent>
      </Drawer>

      {/* Drawer */}
      <Drawer isOpen={isOpen} placement="right" onClose={closeDrawer} size="lg">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Session {selected?.id ? selected.id.slice(0, 8) + '…' : ''}</DrawerHeader>

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
                    <b>Updated:</b>{' '}
                    <Box as="span" fontFamily="mono">
                      {fmtTs(selected.updated_at)}
                    </Box>
                  </Text>
                </Box>

                <Divider my={4} />

                <Heading size="sm" mb={2}>
                  Session fields
                </Heading>
                <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                  <Field label="id" value={selected.id} />
                  <Field label="created_at" value={fmtTs(selected.created_at)} />
                  <Field label="updated_at" value={fmtTs(selected.updated_at)} />
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
