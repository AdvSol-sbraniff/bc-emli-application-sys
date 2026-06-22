// /app/frontend/components/domains/admin-create-session/index.tsx
import {
  Box,
  Button,
  Container,
  Flex,
  Heading,
  IconButton,
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
  Tooltip,
} from '@chakra-ui/react';

import React, { useEffect, useMemo, useState } from 'react';
import { ArrowsClockwise, CaretLeft, CaretRight, XCircle } from '@phosphor-icons/react';
import { observer } from 'mobx-react-lite';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
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
  email?: string | null;
  phone_number?: string | null;
  city?: string | null;
};

type ContractorSearchResponse = {
  rows: ContractorRow[];
  meta?: { total?: number; page?: number; per?: number; sort?: string; filters?: any };
};

type SubmitterRow = {
  id: string;
  email?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  name?: string | null;
  role?: string | null;
  organization?: string | null;
  omniauth_provider?: string | null;
};

type SubmitterSearchResponse = {
  rows: SubmitterRow[];
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

function displayName(user?: SubmitterRow | null): string {
  if (!user) return '--';
  return user.name || [user.first_name, user.last_name].filter(Boolean).join(' ') || '--';
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
  const submitterQ = getParam(location.search, 'submitter_q');
  const submitterSort = getParam(location.search, 'submitter_sort') || 'email:asc';
  const submitterPageStr = getParam(location.search, 'submitter_page') || '1';
  const submitterPerStr = getParam(location.search, 'submitter_per') || '25';
  const submitterIdFromUrl = getParam(location.search, 'submitter_id');
  const submittedAtFromUrl = getParam(location.search, 'submitted_at');
  const createdSessionIdFromUrl = getParam(location.search, 'created_session_id');

  const page = Math.max(1, parseInt(pageStr || '1', 10) || 1);
  const per = [25, 50, 100].includes(parseInt(perStr, 10)) ? parseInt(perStr, 10) : 25;
  const submitterPage = Math.max(1, parseInt(submitterPageStr || '1', 10) || 1);
  const submitterPer = [25, 50, 100].includes(parseInt(submitterPerStr, 10)) ? parseInt(submitterPerStr, 10) : 25;

  // ============================================================
  // SECTION 02 — CONTRACTOR GRID DATA
  // ============================================================

  const [gridLoading, setGridLoading] = useState(false);
  const [gridError, setGridError] = useState('');
  const [rows, setRows] = useState<ContractorRow[]>([]);
  const [total, setTotal] = useState<number>(0);
  const [submitterGridLoading, setSubmitterGridLoading] = useState(false);
  const [submitterGridError, setSubmitterGridError] = useState('');
  const [submitterRows, setSubmitterRows] = useState<SubmitterRow[]>([]);
  const [submitterTotal, setSubmitterTotal] = useState<number>(0);

  // local input (so typing doesn’t update URL per-keystroke)
  const [qDraft, setQDraft] = useState<string>(q);
  const [submitterQDraft, setSubmitterQDraft] = useState<string>(submitterQ);
  const [submittedAtDraft, setSubmittedAtDraft] = useState<string>(submittedAtFromUrl);

  // keep qDraft in sync when user opens a bookmarked link
  useEffect(() => {
    setQDraft(q);
  }, [q]);

  useEffect(() => {
    setSubmitterQDraft(submitterQ);
  }, [submitterQ]);

  useEffect(() => {
    setSubmittedAtDraft(submittedAtFromUrl);
  }, [submittedAtFromUrl]);

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

  const fetchSubmitters = async () => {
    setSubmitterGridLoading(true);
    setSubmitterGridError('');

    try {
      const params = new URLSearchParams();
      if (submitterQ.trim()) params.set('q', submitterQ.trim());
      params.set('sort', submitterSort);
      params.set('page', String(submitterPage));
      params.set('per', String(submitterPer));

      const res = await fetch(`/api/claims/admin/users?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: SubmitterSearchResponse = await res.json().catch(() => ({ rows: [] }));

      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setSubmitterRows(Array.isArray(data?.rows) ? data.rows : []);
      setSubmitterTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setSubmitterGridError(e?.message || 'Failed to load users.');
      setSubmitterRows([]);
      setSubmitterTotal(0);
    } finally {
      setSubmitterGridLoading(false);
    }
  };

  // auto-fetch on URL param changes (bookmarkable behavior)
  useEffect(() => {
    fetchContractors();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [q, sort, page, per]);

  useEffect(() => {
    fetchSubmitters();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [submitterQ, submitterSort, submitterPage, submitterPer]);

  // ============================================================
  // SECTION 03 — SELECTION + CREATE SESSION
  // ============================================================

  const selectedContractor = useMemo(() => {
    if (!contractorIdFromUrl) return null;
    return rows.find((r) => r.id === contractorIdFromUrl) ?? null;
  }, [rows, contractorIdFromUrl]);

  const selectedSubmitter = useMemo(() => {
    if (!submitterIdFromUrl) return null;
    return submitterRows.find((r) => r.id === submitterIdFromUrl) ?? null;
  }, [submitterRows, submitterIdFromUrl]);

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

  const handleSelectSubmitter = (u: SubmitterRow) => {
    setParams(navigate, location, { submitter_id: u.id });
  };

  const handleCreateSession = async () => {
    setIsCreating(true);
    setCreateError('');
    setLastCreateResponse(null);

    try {
      const contractor_id = contractorIdFromUrl?.trim();
      const submitter_id = submitterIdFromUrl?.trim();
      const submitted_at = submittedAtDraft.trim();
      if (!contractor_id) throw new Error('Select a contractor first.');
      if (Boolean(submitter_id) !== Boolean(submitted_at)) {
        throw new Error('submitter_id and submitted_at must both be provided to create a submitted session.');
      }

      const res = await fetch('/api/claims/sessions', {
        method: 'POST',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          contractor_id,
          submitter_id: submitter_id || null,
          submitted_at: submitted_at || null,
        }),
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
  const submitterTotalPages = Math.max(1, Math.ceil((submitterTotal || 0) / submitterPer));
  const hasInvalidSubmissionPair = Boolean(submitterIdFromUrl.trim()) !== Boolean(submittedAtDraft.trim());

  // ============================================================
  // SECTION 04 — RENDER
  // ============================================================

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Sessions Admin - Create" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Tabs variant="line" isFitted colorScheme="gray">
            <TabList mb="1em">
              <Tab>Choose contractor</Tab>
              <Tab>Choose submitter</Tab>
              <Tab>Create session</Tab>
            </TabList>

            <TabPanels>
              <TabPanel px={0}>
                <Flex gap={3} align="end" wrap="nowrap" overflowX="auto" mb={3}>
                  <Box flex="1" minW="300px">
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      Search (name, number, email, phone, city)
                    </Text>
                    <Input
                      value={qDraft}
                      onChange={(e) => setQDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') setParams(navigate, location, { q: qDraft.trim(), page: '1' });
                      }}
                      onBlur={() => setParams(navigate, location, { q: qDraft.trim(), page: '1' })}
                      placeholder="Search contractors..."
                      bg="white"
                    />
                  </Box>

                  <Box minW="220px" maxW="280px">
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      sort
                    </Text>
                    <Select
                      value={sort}
                      onChange={(e) => setParams(navigate, location, { sort: e.target.value, page: '1' })}
                      bg="white"
                    >
                      <option value="business_name:asc">business name A-Z</option>
                      <option value="business_name:desc">business name Z-A</option>
                      <option value="created_at:desc">created desc</option>
                    </Select>
                  </Box>

                  <Box minW="100px" maxW="120px">
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      per
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
                    <Tooltip label="Refresh grid">
                      <IconButton
                        aria-label="Refresh contractor grid"
                        icon={<ArrowsClockwise size={18} />}
                        onClick={fetchContractors}
                        isLoading={gridLoading}
                        variant="outline"
                      />
                    </Tooltip>

                    <Tooltip label="Clear filters">
                      <IconButton
                        aria-label="Clear contractor filters"
                        icon={<XCircle size={18} />}
                        variant="outline"
                        onClick={() => {
                          setQDraft('');
                          setParams(navigate, location, {
                            q: '',
                            sort: 'business_name:asc',
                            per: '25',
                            page: '1',
                          });
                        }}
                        isDisabled={
                          !q.trim() && !qDraft.trim() && sort === 'business_name:asc' && per === 25 && page === 1
                        }
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

                <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflow="hidden">
                  <Box bg="gray.50" px={3} py={2}>
                    <Flex justify="space-between" align="center">
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
                          <Th>email</Th>
                          <Th>phone</Th>
                          <Th>city</Th>
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
                              <Td fontSize="sm">{r.business_name ?? '--'}</Td>
                              <Td fontFamily="mono" fontSize="xs">
                                {r.contractor_number ?? '--'}
                              </Td>
                              <Td fontSize="sm">{r.email ?? '--'}</Td>
                              <Td fontSize="sm">{r.phone_number ?? '--'}</Td>
                              <Td fontSize="sm">{r.city ?? '--'}</Td>
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

                <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
                  <Text fontSize="sm" opacity={0.8}>
                    Total: {total}
                  </Text>

                  <HStack>
                    <Tooltip label="Previous page">
                      <IconButton
                        aria-label="Previous contractor page"
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
                        aria-label="Next contractor page"
                        size="sm"
                        variant="outline"
                        icon={<CaretRight size={16} />}
                        onClick={() => setParams(navigate, location, { page: String(Math.min(totalPages, page + 1)) })}
                        isDisabled={page >= totalPages}
                      />
                    </Tooltip>
                  </HStack>
                </Flex>
              </TabPanel>

              <TabPanel px={0}>
                <Flex gap={3} align="end" wrap="nowrap" overflowX="auto" mb={3}>
                  <Box flex="1" minW="300px">
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      Search submitters (email, name, role, provider)
                    </Text>
                    <Input
                      value={submitterQDraft}
                      onChange={(e) => setSubmitterQDraft(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter')
                          setParams(navigate, location, { submitter_q: submitterQDraft.trim(), submitter_page: '1' });
                      }}
                      onBlur={() =>
                        setParams(navigate, location, { submitter_q: submitterQDraft.trim(), submitter_page: '1' })
                      }
                      placeholder="Search users..."
                      bg="white"
                    />
                  </Box>

                  <Box minW="220px" maxW="280px">
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      sort
                    </Text>
                    <Select
                      value={submitterSort}
                      onChange={(e) =>
                        setParams(navigate, location, { submitter_sort: e.target.value, submitter_page: '1' })
                      }
                      bg="white"
                    >
                      <option value="email:asc">email A-Z</option>
                      <option value="email:desc">email Z-A</option>
                      <option value="last_name:asc">last name A-Z</option>
                      <option value="last_name:desc">last name Z-A</option>
                      <option value="role:asc">role A-Z</option>
                      <option value="updated_at:desc">updated desc</option>
                    </Select>
                  </Box>

                  <Box minW="100px" maxW="120px">
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      per
                    </Text>
                    <Select
                      value={String(submitterPer)}
                      onChange={(e) =>
                        setParams(navigate, location, { submitter_per: e.target.value, submitter_page: '1' })
                      }
                      bg="white"
                    >
                      <option value="25">25</option>
                      <option value="50">50</option>
                      <option value="100">100</option>
                    </Select>
                  </Box>

                  <HStack spacing={2} pb={1}>
                    <Tooltip label="Refresh grid">
                      <IconButton
                        aria-label="Refresh submitter grid"
                        icon={<ArrowsClockwise size={18} />}
                        onClick={fetchSubmitters}
                        isLoading={submitterGridLoading}
                        variant="outline"
                      />
                    </Tooltip>

                    <Tooltip label="Clear filters">
                      <IconButton
                        aria-label="Clear submitter filters"
                        icon={<XCircle size={18} />}
                        variant="outline"
                        onClick={() => {
                          setSubmitterQDraft('');
                          setParams(navigate, location, {
                            submitter_q: '',
                            submitter_sort: 'email:asc',
                            submitter_per: '25',
                            submitter_page: '1',
                            submitter_id: '',
                          });
                        }}
                        isDisabled={
                          !submitterQ.trim() &&
                          !submitterQDraft.trim() &&
                          submitterSort === 'email:asc' &&
                          submitterPer === 25 &&
                          submitterPage === 1 &&
                          !submitterIdFromUrl
                        }
                      />
                    </Tooltip>
                  </HStack>
                </Flex>

                {submitterGridError && (
                  <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {submitterGridError}
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
                        {submitterGridLoading ? <Spinner size="sm" /> : null}
                      </Flex>
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        total: {submitterTotal}
                      </Text>
                    </Flex>
                  </Box>

                  <Box bg="white" p={0}>
                    <Table size="sm">
                      <Thead>
                        <Tr>
                          <Th>email</Th>
                          <Th>name</Th>
                          <Th>role</Th>
                          <Th>provider</Th>
                        </Tr>
                      </Thead>
                      <Tbody>
                        {submitterRows.map((r) => {
                          const isSelected = r.id === submitterIdFromUrl;
                          return (
                            <Tr
                              key={r.id}
                              cursor="pointer"
                              bg={isSelected ? 'blue.50' : 'transparent'}
                              _hover={{ bg: isSelected ? 'blue.100' : 'gray.50' }}
                              onClick={() => handleSelectSubmitter(r)}
                            >
                              <Td fontSize="sm">{r.email ?? '--'}</Td>
                              <Td fontSize="sm">{displayName(r)}</Td>
                              <Td fontSize="sm">{r.role ?? '--'}</Td>
                              <Td fontSize="sm">{r.omniauth_provider ?? '--'}</Td>
                            </Tr>
                          );
                        })}

                        {!submitterGridLoading && submitterRows.length === 0 && (
                          <Tr>
                            <Td colSpan={4}>
                              <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                                No users found.
                              </Text>
                            </Td>
                          </Tr>
                        )}
                      </Tbody>
                    </Table>
                  </Box>
                </Box>

                <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
                  <Text fontSize="sm" opacity={0.8}>
                    Total: {submitterTotal}
                  </Text>
                  <HStack>
                    <Tooltip label="Previous page">
                      <IconButton
                        aria-label="Previous submitter page"
                        size="sm"
                        variant="outline"
                        icon={<CaretLeft size={16} />}
                        onClick={() =>
                          setParams(navigate, location, { submitter_page: String(Math.max(1, submitterPage - 1)) })
                        }
                        isDisabled={submitterPage <= 1}
                      />
                    </Tooltip>
                    <Text fontSize="sm">
                      Page {submitterPage} of {submitterTotalPages}
                    </Text>
                    <Tooltip label="Next page">
                      <IconButton
                        aria-label="Next submitter page"
                        size="sm"
                        variant="outline"
                        icon={<CaretRight size={16} />}
                        onClick={() =>
                          setParams(navigate, location, {
                            submitter_page: String(Math.min(submitterTotalPages, submitterPage + 1)),
                          })
                        }
                        isDisabled={submitterPage >= submitterTotalPages}
                      />
                    </Tooltip>
                  </HStack>
                </Flex>
              </TabPanel>

              <TabPanel px={0}>
                <Box mb={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
                  <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                    Selected contractor details
                  </Text>

                  <Flex direction={{ base: 'column', md: 'row' }} gap={6}>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Contractor ID
                      </Text>
                      <Text as="div" fontSize="xs" fontFamily="mono">
                        {contractorIdFromUrl || '--'}
                      </Text>
                    </Box>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Business name
                      </Text>
                      <Text as="div" fontSize="sm">
                        {selectedContractor?.business_name ?? '--'}
                      </Text>
                    </Box>
                  </Flex>

                  <Flex mt={3} direction={{ base: 'column', md: 'row' }} gap={6}>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Contractor number
                      </Text>
                      <Text as="div" fontSize="sm" fontFamily="mono">
                        {selectedContractor?.contractor_number ?? '--'}
                      </Text>
                    </Box>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Email
                      </Text>
                      <Text as="div" fontSize="sm">
                        {selectedContractor?.email ?? '--'}
                      </Text>
                    </Box>
                  </Flex>

                  <Flex mt={3} direction={{ base: 'column', md: 'row' }} gap={6}>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Phone number
                      </Text>
                      <Text as="div" fontSize="sm">
                        {selectedContractor?.phone_number ?? '--'}
                      </Text>
                    </Box>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        City
                      </Text>
                      <Text as="div" fontSize="sm">
                        {selectedContractor?.city ?? '--'}
                      </Text>
                    </Box>
                  </Flex>
                </Box>

                <Box mb={3} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
                  <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                    Selected submitter details
                  </Text>

                  <Flex direction={{ base: 'column', md: 'row' }} gap={6}>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Submitter ID
                      </Text>
                      <Text as="div" fontSize="xs" fontFamily="mono">
                        {submitterIdFromUrl || '--'}
                      </Text>
                    </Box>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Email
                      </Text>
                      <Text as="div" fontSize="sm">
                        {selectedSubmitter?.email ?? '--'}
                      </Text>
                    </Box>
                  </Flex>

                  <Flex mt={3} direction={{ base: 'column', md: 'row' }} gap={6}>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Name
                      </Text>
                      <Text as="div" fontSize="sm">
                        {displayName(selectedSubmitter)}
                      </Text>
                    </Box>
                    <Box flex="1">
                      <Text as="div" fontSize="xs" opacity={0.7}>
                        Role
                      </Text>
                      <Text as="div" fontSize="sm">
                        {selectedSubmitter?.role ?? '--'}
                      </Text>
                    </Box>
                  </Flex>
                </Box>

                <Box mb={4} p={3} borderWidth="1px" borderColor="greys.grey20" borderRadius="md" bg="white">
                  <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                    Submission fields
                  </Text>

                  <Box maxW="260px">
                    <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                      submitted_at
                    </Text>
                    <Input
                      type="date"
                      value={submittedAtDraft}
                      onChange={(e) => {
                        setSubmittedAtDraft(e.target.value);
                        setParams(navigate, location, { submitted_at: e.target.value });
                      }}
                      bg="white"
                    />
                  </Box>

                  <Text as="div" fontSize="xs" opacity={0.7} mt={2}>
                    Leave both submitter and submitted_at blank to create an open-but-not-submitted session.
                  </Text>
                </Box>

                <Button
                  variant="outline"
                  onClick={handleCreateSession}
                  isLoading={isCreating}
                  loadingText="Creating..."
                  isDisabled={!contractorIdFromUrl.trim() || hasInvalidSubmissionPair}
                >
                  Create new session
                </Button>

                {hasInvalidSubmissionPair && (
                  <Box mt={3} p={3} bg="yellow.50" borderWidth="1px" borderColor="yellow.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="yellow.800">
                      To create a submitted session, choose both a submitter and a submitted_at date.
                    </Text>
                  </Box>
                )}

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
                          window.open(`/edit-session-admin?id=${encodeURIComponent(createdSessionId)}`, '_blank');
                        }}
                      >
                        Edit session
                      </Button>

                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          window.open(`/sessions-admin?session_id=${encodeURIComponent(createdSessionId)}`, '_blank');
                        }}
                      >
                        Open session grid
                      </Button>

                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          window.open(
                            `/submission-simulator-admin?contractor_id=${encodeURIComponent(contractorIdFromUrl)}`,
                            '_blank',
                          );
                        }}
                      >
                        Open draft simulator
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
