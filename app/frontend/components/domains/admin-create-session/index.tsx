// /app/frontend/components/domains/admin-create-session/index.tsx
import {
  Box,
  Button,
  Container,
  Flex,
  Heading,
  Input,
  Spinner,
  Table,
  Thead,
  Tbody,
  Tr,
  Th,
  Td,
  Tabs,
  TabList,
  TabPanels,
  Tab,
  TabPanel,
  Text,
  HStack,
  Select,
} from '@chakra-ui/react';

import React, { useEffect, useMemo, useState } from 'react';
import { observer } from 'mobx-react-lite';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { useLocation, useNavigate } from 'react-router-dom';

// ============================================================
// SECTION 00 — FILE OVERVIEW
// PURPOSE: Admin Create Session
// - Tab 1: Contractor chooser (bookmarkable grid)
// - Tab 2: Create session (POST /api/claims/sessions)
// ============================================================

type ContractorRow = {
  id: string; // public.contractors.id
  business_name?: string | null;
  contractor_number?: string | null;
  contact_name?: string | null;
  email?: string | null;
};

type ContractorSearchResponse = {
  rows: ContractorRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
};

type CreateSessionResponse =
  | { session_id: string }
  | { id: string }
  | { sessionId: string }
  | { session?: { id?: string } }
  | any;

function safeJsonStringify(obj: any): string {
  try {
    return JSON.stringify(obj, null, 2);
  } catch {
    return String(obj);
  }
}

function tryGetSessionIdFromCreateResponse(data: CreateSessionResponse): string {
  const sid = data?.session_id ?? data?.id ?? data?.sessionId ?? data?.session?.id ?? '';
  return sid ? String(sid) : '';
}

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

export default observer(function AdminCreateSessionScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  // ============================================================
  // SECTION 01 — URL-DRIVEN STATE (contractor grid)
  // ============================================================

  const q = getParam(location.search, 'q');
  const sort = getParam(location.search, 'sort') || 'business_name:asc';
  const pageStr = getParam(location.search, 'page') || '1';
  const perStr = getParam(location.search, 'per') || '25';
  const contractorIdFromUrl = getParam(location.search, 'contractor_id');
  const createdSessionIdFromUrl = getParam(location.search, 'created_session_id');

  const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
  const per = [25, 50, 100].includes(parseInt(perStr, 10)) ? parseInt(perStr, 10) : 25;

  // ============================================================
  // SECTION 02 — CONTRACTOR GRID DATA
  // ============================================================

  const [gridLoading, setGridLoading] = useState(false);
  const [gridError, setGridError] = useState('');
  const [rows, setRows] = useState<ContractorRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  // local input (so typing doesn’t update URL per-keystroke)
  const [qDraft, setQDraft] = useState<string>(q);

  // keep qDraft in sync when user opens a bookmarked link
  useEffect(() => {
    setQDraft(q);
  }, [q]);

  const fetchContractors = async () => {
    setGridLoading(true);
    setGridError('');

    try {
      const params = new URLSearchParams();
      if (q.trim()) params.set('q', q.trim());
      params.set('sort', sort);
      params.set('page', String(page));
      params.set('per', String(per));

      const url = `/api/claims/admin/contractors?${params.toString()}`;

      const res = await fetch(url, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: ContractorSearchResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setGridError(e?.message || 'Failed to load contractors.');
      setRows([]);
      setTotal(0);
    } finally {
      setGridLoading(false);
    }
  };

  // auto-fetch on URL param changes (bookmarkable behavior)
  useEffect(() => {
    fetchContractors();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, sort, page, per]);

  // ============================================================
  // SECTION 03 — SELECTION + CREATE SESSION
  // ============================================================

  const selectedContractor = useMemo(() => {
    if (!contractorIdFromUrl) return null;
    return rows.find((r) => r.id === contractorIdFromUrl) ?? null;
  }, [rows, contractorIdFromUrl]);

  const [isCreating, setIsCreating] = useState(false);
  const [createError, setCreateError] = useState('');
  const [createdSessionId, setCreatedSessionId] = useState<string>(createdSessionIdFromUrl || '');
  const [lastCreateResponse, setLastCreateResponse] = useState<any>(null);

  useEffect(() => {
    setCreatedSessionId(createdSessionIdFromUrl || '');
  }, [createdSessionIdFromUrl]);

  const handleSelectContractor = (c: ContractorRow) => {
    setParams(navigate, location, { contractor_id: c.id });
  };

  const handleCreateSession = async () => {
    setIsCreating(true);
    setCreateError('');
    setLastCreateResponse(null);

    try {
      const contractor_id = contractorIdFromUrl?.trim();
      if (!contractor_id) throw new Error('Select a contractor first.');

      const res = await fetch('/api/claims/sessions', {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({ contractor_id }),
      });

      const data = await res.json().catch(() => ({}));
      setLastCreateResponse(data);

      if (!res.ok) {
        throw new Error(data?.error || data?.message || `HTTP ${res.status}`);
      }

      const sid = tryGetSessionIdFromCreateResponse(data);
      if (!sid) throw new Error('Create session succeeded but response did not include session_id.');

      setCreatedSessionId(sid);
      setParams(navigate, location, { created_session_id: sid });
    } catch (e: any) {
      setCreateError(e?.message || 'Failed to create session.');
    } finally {
      setIsCreating(false);
    }
  };

  const totalPages = Math.max(1, Math.ceil((total || 0) / per));

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="Admin Create Session" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Tabs variant="line" isFitted colorScheme="gray">
            <TabList mb="1em">
              <Tab>Choose contractor</Tab>
              <Tab>Create session</Tab>
            </TabList>

            <TabPanels>
              {/* ============================================================
                  TAB 1 — CONTRACTOR CHOOSER
              ============================================================ */}
              <TabPanel px={0}>
                <Flex justify="space-between" align="center" mb={3} wrap="wrap" gap={3}>
                  <Box>
                    <Heading size="sm">Contractors</Heading>
                    <Text as="div" fontSize="xs" opacity={0.7}>
                      Search and select a contractor. Selection is stored in the URL as{' '}
                      <Box as="code">contractor_id</Box>.
                    </Text>
                  </Box>

                  <HStack spacing={2}>
                    <Select
                      size="sm"
                      value={per}
                      onChange={(e) => setParams(navigate, location, { per: e.target.value, page: '1' })}
                      width="110px"
                    >
                      <option value="25">25</option>
                      <option value="50">50</option>
                      <option value="100">100</option>
                    </Select>

                    <Select
                      size="sm"
                      value={sort}
                      onChange={(e) => setParams(navigate, location, { sort: e.target.value, page: '1' })}
                      width="200px"
                    >
                      <option value="business_name:asc">business_name:asc</option>
                      <option value="business_name:desc">business_name:desc</option>
                      <option value="created_at:desc">created_at:desc</option>
                    </Select>

                    <Button size="sm" onClick={fetchContractors} isLoading={gridLoading}>
                      Refresh
                    </Button>
                  </HStack>
                </Flex>

                <Flex gap={2} mb={3} wrap="wrap">
                  <Input
                    value={qDraft}
                    onChange={(e) => setQDraft(e.target.value)}
                    placeholder="Search (name, number, email, contact)…"
                    maxW="520px"
                  />
                  <Button
                    onClick={() => setParams(navigate, location, { q: qDraft.trim(), page: '1' })}
                    isDisabled={qDraft.trim() === q.trim()}
                  >
                    Apply
                  </Button>
                  <Button
                    variant="outline"
                    onClick={() => {
                      setQDraft('');
                      setParams(navigate, location, { q: '', page: '1' });
                    }}
                    isDisabled={!q.trim() && !qDraft.trim()}
                  >
                    Clear
                  </Button>
                </Flex>

                {gridError && (
                  <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {gridError}
                    </Text>
                  </Box>
                )}

                <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflow="hidden">
                  <Box bg="gray.50" px={3} py={2}>
                    <Flex justify="space-between" align="center">
                      {/* FIX: Text renders as <p>; don't put Spinner (div) inside it */}
                      <Flex align="center" gap={2}>
                        <Text as="div" fontSize="sm" fontWeight="bold">
                          Rows
                        </Text>
                        {gridLoading ? <Spinner size="sm" /> : null}
                      </Flex>

                      <Text as="div" fontSize="xs" opacity={0.7}>
                        total: {total}
                      </Text>
                    </Flex>
                  </Box>

                  <Box bg="white" p={0}>
                    <Table size="sm">
                      <Thead>
                        <Tr>
                          <Th>business</Th>
                          <Th>number</Th>
                          <Th>contact</Th>
                          <Th>email</Th>
                          <Th>id</Th>
                        </Tr>
                      </Thead>
                      <Tbody>
                        {rows.map((r) => {
                          const isSelected = r.id === contractorIdFromUrl;
                          return (
                            <Tr
                              key={r.id}
                              cursor="pointer"
                              bg={isSelected ? 'blue.50' : 'transparent'}
                              _hover={{ bg: isSelected ? 'blue.100' : 'gray.50' }}
                              onClick={() => handleSelectContractor(r)}
                            >
                              <Td fontSize="sm">{r.business_name ?? '—'}</Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {r.contractor_number ?? '—'}
                              </Td>
                              <Td fontSize="sm">{r.contact_name ?? '—'}</Td>
                              <Td fontSize="sm">{r.email ?? '—'}</Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {r.id}
                              </Td>
                            </Tr>
                          );
                        })}

                        {!gridLoading && rows.length === 0 && (
                          <Tr>
                            <Td colSpan={5}>
                              <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                                No contractors found.
                              </Text>
                            </Td>
                          </Tr>
                        )}
                      </Tbody>
                    </Table>
                  </Box>
                </Box>

                {/* simple paging */}
                <Flex mt={3} justify="space-between" align="center" wrap="wrap" gap={2}>
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    page {page} of {totalPages}
                  </Text>

                  <HStack>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setParams(navigate, location, { page: String(Math.max(1, page - 1)) })}
                      isDisabled={page <= 1}
                    >
                      Prev
                    </Button>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => setParams(navigate, location, { page: String(Math.min(totalPages, page + 1)) })}
                      isDisabled={page >= totalPages}
                    >
                      Next
                    </Button>
                  </HStack>
                </Flex>
              </TabPanel>

              {/* ============================================================
                  TAB 2 — CREATE SESSION
              ============================================================ */}
              <TabPanel px={0}>
                <Heading size="sm" mb={2}>
                  Create session
                </Heading>

                <Text as="div" fontSize="xs" opacity={0.7} mb={3}>
                  Uses <Box as="code">claims.sessions.contractor_id</Box> (FK → <Box as="code">public.contractors.id</Box>).
                </Text>

                <Box mb={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="gray.50">
                  <Text as="div" fontSize="xs" opacity={0.7}>
                    Selected contractor
                  </Text>

                  <Text as="div" fontSize="sm" fontWeight="bold">
                    {selectedContractor?.business_name ?? '(none selected)'}
                  </Text>

                  <Text as="div" fontSize="xs" fontFamily="mono" opacity={0.9}>
                    contractor_id: {contractorIdFromUrl || '—'}
                  </Text>

                  {selectedContractor?.contractor_number && (
                    <Text as="div" fontSize="xs" opacity={0.8}>
                      contractor_number:{' '}
                      <Box as="span" fontFamily="mono">
                        {selectedContractor.contractor_number}
                      </Box>
                    </Text>
                  )}
                </Box>

                <Button
                  colorScheme="blue"
                  onClick={handleCreateSession}
                  isLoading={isCreating}
                  loadingText="Creating..."
                  isDisabled={!contractorIdFromUrl.trim()}
                >
                  Create new session
                </Button>

                {createError && (
                  <Box mt={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {createError}
                    </Text>
                  </Box>
                )}

                {createdSessionId && (
                  <Box mt={3} p={3} bg="green.50" borderWidth="1px" borderColor="green.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="green.800" fontWeight="bold">
                      Session created
                    </Text>
                    <Text as="div" fontSize="xs" fontFamily="mono" color="green.900">
                      session_id: {createdSessionId}
                    </Text>

<HStack mt={2} spacing={2}>
  <Button
    size="sm"
    onClick={() => {
      // New Sessions Grid (you’ll build this route)
      window.open(`/sessions-admin?session_id=${encodeURIComponent(createdSessionId)}`, '_blank');
    }}
  >
    Open session grid
  </Button>

  <Button
    size="sm"
    variant="outline"
    onClick={() => {
      // Existing Upload Invoice screen (already uses session_id from URL)
      window.open(`/upload-invoice-admin?session_id=${encodeURIComponent(createdSessionId)}`, '_blank');
    }}
  >
    Upload new invoice
  </Button>

  <Button
    size="sm"
    variant="outline"
    onClick={() => navigator.clipboard.writeText(createdSessionId)}
  >
    Copy session_id
  </Button>
</HStack>
                  </Box>
                )}

                {/* lightweight debug (keeps you from needing docker logs) */}
                {lastCreateResponse && (
                  <Box mt={4}>
                    <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                      Last create-session response
                    </Text>
                    <Box
                      borderWidth="1px"
                      borderColor="greys.grey20"
                      borderRadius="md"
                      p={3}
                      bg="white"
                      fontFamily="mono"
                      fontSize="xs"
                      whiteSpace="pre-wrap"
                    >
                      {safeJsonStringify(lastCreateResponse)}
                    </Box>
                  </Box>
                )}
              </TabPanel>
            </TabPanels>
          </Tabs>
        </Box>
      </Container>
    </Flex>
  );
});