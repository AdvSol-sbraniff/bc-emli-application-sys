import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Box,
  Button,
  Container,
  Flex,
  HStack,
  IconButton,
  Input,
  Select,
  Spinner,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
} from '@chakra-ui/react';
import { ArrowsClockwise, CaretLeft, CaretRight, XCircle } from '@phosphor-icons/react';
import { useLocation } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

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

type SessionDto = {
  id: string;
  contractor_id?: string | null;
  submitter_id?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  submitted_at?: string | null;
  contractor?: {
    id?: string | null;
    business_name?: string | null;
    contractor_number?: string | null;
    email?: string | null;
    phone_number?: string | null;
    city?: string | null;
  } | null;
  submitter?: {
    id?: string | null;
    email?: string | null;
    first_name?: string | null;
    last_name?: string | null;
    role?: string | null;
    organization?: string | null;
    omniauth_provider?: string | null;
  } | null;
};

function getParam(search: string, key: string): string {
  return new URLSearchParams(search).get(key) ?? '';
}

function fmtTs(s?: string | null) {
  return s ? String(s).replace('T', ' ').replace('Z', '') : '--';
}

function fmtDateOnly(s?: string | null) {
  if (!s) return '';
  const raw = String(s);
  return raw.includes('T') ? raw.split('T')[0] : raw.slice(0, 10);
}

function displayName(user?: SubmitterRow | SessionDto['submitter'] | null): string {
  if (!user) return '--';
  return user.name || [user.first_name, user.last_name].filter(Boolean).join(' ') || '--';
}

export default function EditSessionAdminScreen() {
  const location = useLocation();
  const id = getParam(location.search, 'id');

  const [isLoading, setIsLoading] = useState(true);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState('');
  const [session, setSession] = useState<SessionDto | null>(null);

  const [submitterId, setSubmitterId] = useState('');
  const [submittedAt, setSubmittedAt] = useState('');
  const [initialSubmitterId, setInitialSubmitterId] = useState('');
  const [initialSubmittedAt, setInitialSubmittedAt] = useState('');

  const [submitterQ, setSubmitterQ] = useState('');
  const [submitterSort, setSubmitterSort] = useState('email:asc');
  const [submitterPage, setSubmitterPage] = useState(1);
  const [submitterPer, setSubmitterPer] = useState(25);
  const [submitterRows, setSubmitterRows] = useState<SubmitterRow[]>([]);
  const [submitterTotal, setSubmitterTotal] = useState(0);
  const [submitterLoading, setSubmitterLoading] = useState(false);
  const [submitterError, setSubmitterError] = useState('');

  const selectedSubmitter = useMemo(() => {
    if (submitterId && session?.submitter?.id === submitterId) return session.submitter;
    return submitterRows.find((row) => row.id === submitterId) || null;
  }, [submitterId, session, submitterRows]);

  const isDirty = submitterId !== initialSubmitterId || submittedAt !== initialSubmittedAt;
  const hasInvalidPair = Boolean(submitterId.trim()) !== Boolean(submittedAt.trim());
  const submitterTotalPages = Math.max(1, Math.ceil((submitterTotal || 0) / submitterPer));

  const loadSession = useCallback(async () => {
    setIsLoading(true);
    setError('');

    try {
      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const res = await fetch(`/api/claims/admin/sessions/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: SessionDto = await res.json().catch(() => ({}) as SessionDto);
      if (!res.ok) {
        throw new Error((data as any)?.error || `HTTP ${res.status}`);
      }

      const nextSubmittedAt = fmtDateOnly(data.submitted_at);
      setSession(data);
      setSubmitterId(data.submitter_id || '');
      setSubmittedAt(nextSubmittedAt);
      setInitialSubmitterId(data.submitter_id || '');
      setInitialSubmittedAt(nextSubmittedAt);
    } catch (e: any) {
      setError(e?.message || 'Failed to load session.');
    } finally {
      setIsLoading(false);
    }
  }, [id]);

  const fetchSubmitters = useCallback(async () => {
    setSubmitterLoading(true);
    setSubmitterError('');

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
        throw new Error((data as any)?.error || `HTTP ${res.status}`);
      }

      setSubmitterRows(Array.isArray(data?.rows) ? data.rows : []);
      setSubmitterTotal(Number(data?.meta?.total ?? 0));
    } catch (e: any) {
      setSubmitterError(e?.message || 'Failed to load users.');
      setSubmitterRows([]);
      setSubmitterTotal(0);
    } finally {
      setSubmitterLoading(false);
    }
  }, [submitterPage, submitterPer, submitterQ, submitterSort]);

  const save = async () => {
    if (!id || hasInvalidPair) return;

    setIsSaving(true);
    setError('');
    try {
      const res = await fetch(`/api/claims/admin/sessions/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          submitter_id: submitterId.trim() || null,
          submitted_at: submittedAt.trim() || null,
        }),
      });

      const data: SessionDto = await res.json().catch(() => ({}) as SessionDto);
      if (!res.ok) {
        throw new Error((data as any)?.error || `HTTP ${res.status}`);
      }

      const nextSubmittedAt = fmtDateOnly(data.submitted_at);
      setSession(data);
      setSubmitterId(data.submitter_id || '');
      setSubmittedAt(nextSubmittedAt);
      setInitialSubmitterId(data.submitter_id || '');
      setInitialSubmittedAt(nextSubmittedAt);
    } catch (e: any) {
      setError(e?.message || 'Failed to update session.');
    } finally {
      setIsSaving(false);
    }
  };

  useEffect(() => {
    loadSession();
  }, [loadSession]);

  useEffect(() => {
    fetchSubmitters();
  }, [fetchSubmitters]);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Edit Session" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          {!id && (
            <Box p={4} borderWidth="1px" borderRadius="md">
              <Text fontWeight="bold">Missing id</Text>
              <Text>Use: /edit-session-admin?id=&lt;uuid&gt;</Text>
            </Box>
          )}

          {!!id && (
            <Flex direction="column" gap={4}>
              {isLoading && (
                <Flex align="center" gap={3}>
                  <Spinner size="sm" />
                  <Text>Loading session...</Text>
                </Flex>
              )}

              {error && (
                <Box p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                  <Text as="div" fontSize="sm" color="red.700">
                    {error}
                  </Text>
                </Box>
              )}

              {!isLoading && session && (
                <>
                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="gray.50">
                    <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                      Session summary
                    </Text>

                    <Flex direction={{ base: 'column', md: 'row' }} gap={6}>
                      <Box flex="1">
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          session_id
                        </Text>
                        <Text as="div" fontSize="xs" fontFamily="mono">
                          {session.id}
                        </Text>
                      </Box>
                      <Box flex="1">
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          created_at
                        </Text>
                        <Text as="div" fontSize="sm">
                          {fmtTs(session.created_at)}
                        </Text>
                      </Box>
                    </Flex>

                    <Flex mt={3} direction={{ base: 'column', md: 'row' }} gap={6}>
                      <Box flex="1">
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          contractor
                        </Text>
                        <Text as="div" fontSize="sm">
                          {session.contractor?.business_name || '--'}
                        </Text>
                      </Box>
                      <Box flex="1">
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          contractor_number
                        </Text>
                        <Text as="div" fontSize="sm" fontFamily="mono">
                          {session.contractor?.contractor_number || '--'}
                        </Text>
                      </Box>
                      <Box flex="1">
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          updated_at
                        </Text>
                        <Text as="div" fontSize="sm">
                          {fmtTs(session.updated_at)}
                        </Text>
                      </Box>
                    </Flex>
                  </Box>

                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
                    <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                      Editable session fields
                    </Text>

                    <Flex direction={{ base: 'column', md: 'row' }} gap={6}>
                      <Box flex="1">
                        <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                          submitter_id
                        </Text>
                        <Text as="div" fontSize="xs" fontFamily="mono">
                          {submitterId || '--'}
                        </Text>
                        <Text as="div" fontSize="sm" mt={2}>
                          {selectedSubmitter?.email || '--'}
                        </Text>
                        <Text as="div" fontSize="xs" opacity={0.7}>
                          {displayName(selectedSubmitter)}
                        </Text>
                      </Box>

                      <Box w={{ base: 'full', md: '260px' }}>
                        <Text as="div" fontSize="xs" opacity={0.7} mb={1}>
                          submitted_at
                        </Text>
                        <Input
                          type="date"
                          value={submittedAt}
                          onChange={(e) => setSubmittedAt(e.target.value)}
                          bg="white"
                        />
                      </Box>
                    </Flex>

                    <Text as="div" fontSize="xs" opacity={0.7} mt={3}>
                      Sessions are only grouping containers. Editing submitter and submitted_at affects ownership and
                      reporting context, not a session state machine.
                    </Text>
                  </Box>

                  <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" p={4} bg="white">
                    <Text as="div" fontSize="sm" fontWeight="bold" mb={3}>
                      Choose submitter
                    </Text>

                    <Flex gap={3} align="end" wrap="wrap" mb={3}>
                      <Box flex="1" minW="280px">
                        <Text fontSize="xs" opacity={0.7} mb={1}>
                          Search submitters (email, name, role, provider)
                        </Text>
                        <Input
                          value={submitterQ}
                          onChange={(e) => {
                            setSubmitterQ(e.target.value);
                            setSubmitterPage(1);
                          }}
                          placeholder="Search users..."
                          bg="white"
                        />
                      </Box>

                      <Box w="220px">
                        <Text fontSize="xs" opacity={0.7} mb={1}>
                          sort
                        </Text>
                        <Select
                          value={submitterSort}
                          onChange={(e) => {
                            setSubmitterSort(e.target.value);
                            setSubmitterPage(1);
                          }}
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

                      <Box w="120px">
                        <Text fontSize="xs" opacity={0.7} mb={1}>
                          per
                        </Text>
                        <Select
                          value={String(submitterPer)}
                          onChange={(e) => {
                            setSubmitterPer(Number(e.target.value) || 25);
                            setSubmitterPage(1);
                          }}
                          bg="white"
                        >
                          <option value="25">25</option>
                          <option value="50">50</option>
                          <option value="100">100</option>
                        </Select>
                      </Box>

                      <HStack spacing={2} pb={1}>
                        <Tooltip label="Clear submitter filters">
                          <IconButton
                            aria-label="Clear submitter filters"
                            icon={<XCircle size={18} />}
                            variant="outline"
                            onClick={() => {
                              setSubmitterQ('');
                              setSubmitterSort('email:asc');
                              setSubmitterPer(25);
                              setSubmitterPage(1);
                            }}
                          />
                        </Tooltip>

                        <Tooltip label="Refresh grid">
                          <IconButton
                            aria-label="Refresh submitter grid"
                            icon={<ArrowsClockwise size={18} />}
                            variant="outline"
                            onClick={fetchSubmitters}
                            isLoading={submitterLoading}
                          />
                        </Tooltip>
                      </HStack>
                    </Flex>

                    {submitterError && (
                      <Box mb={3} p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                        <Text as="div" fontSize="sm" color="red.700">
                          {submitterError}
                        </Text>
                      </Box>
                    )}

                    <Box borderWidth="1px" borderRadius="md" overflow="auto">
                      <Table size="sm" minW="720px">
                        <Thead bg="gray.50">
                          <Tr>
                            <Th>email</Th>
                            <Th>name</Th>
                            <Th>role</Th>
                            <Th>provider</Th>
                            <Th></Th>
                          </Tr>
                        </Thead>
                        <Tbody>
                          {submitterLoading && submitterRows.length === 0 && (
                            <Tr>
                              <Td colSpan={5}>
                                <Flex align="center" gap={2} py={3}>
                                  <Spinner size="sm" />
                                  <Text>Loading users...</Text>
                                </Flex>
                              </Td>
                            </Tr>
                          )}

                          {submitterRows.map((row) => (
                            <Tr key={row.id} bg={row.id === submitterId ? 'blue.50' : 'transparent'}>
                              <Td fontSize="sm">{row.email || '--'}</Td>
                              <Td fontSize="sm">{displayName(row)}</Td>
                              <Td fontSize="sm">{row.role || '--'}</Td>
                              <Td fontSize="sm">{row.omniauth_provider || '--'}</Td>
                              <Td>
                                <Button size="xs" variant="outline" onClick={() => setSubmitterId(row.id)}>
                                  Choose
                                </Button>
                              </Td>
                            </Tr>
                          ))}

                          {!submitterLoading && submitterRows.length === 0 && (
                            <Tr>
                              <Td colSpan={5}>
                                <Text as="div" fontSize="sm" opacity={0.7} p={3}>
                                  No users found.
                                </Text>
                              </Td>
                            </Tr>
                          )}
                        </Tbody>
                      </Table>
                    </Box>

                    <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
                      <Button size="sm" variant="outline" onClick={() => setSubmitterId('')}>
                        Clear submitter
                      </Button>

                      <HStack>
                        <IconButton
                          aria-label="Previous submitter page"
                          size="sm"
                          variant="outline"
                          icon={<CaretLeft size={16} />}
                          onClick={() => setSubmitterPage(Math.max(1, submitterPage - 1))}
                          isDisabled={submitterPage <= 1}
                        />
                        <Text fontSize="sm">
                          Page {submitterPage} of {submitterTotalPages}
                        </Text>
                        <IconButton
                          aria-label="Next submitter page"
                          size="sm"
                          variant="outline"
                          icon={<CaretRight size={16} />}
                          onClick={() => setSubmitterPage(Math.min(submitterTotalPages, submitterPage + 1))}
                          isDisabled={submitterPage >= submitterTotalPages}
                        />
                      </HStack>
                    </Flex>
                  </Box>

                  {hasInvalidPair && (
                    <Box p={3} bg="yellow.50" borderWidth="1px" borderColor="yellow.200" borderRadius="md">
                      <Text as="div" fontSize="sm" color="yellow.800">
                        submitter_id and submitted_at must either both be provided or both be blank.
                      </Text>
                    </Box>
                  )}

                  <Flex justify="space-between" align="center" wrap="wrap" gap={3}>
                    <Text fontSize="sm" opacity={0.8}>
                      {isDirty ? 'Unsaved changes' : 'Saved'}
                    </Text>

                    <HStack>
                      <Button variant="outline" onClick={loadSession} isDisabled={isLoading || isSaving}>
                        Reload
                      </Button>
                      <Button
                        colorScheme="blue"
                        onClick={save}
                        isLoading={isSaving}
                        isDisabled={!isDirty || hasInvalidPair}
                      >
                        Save session
                      </Button>
                    </HStack>
                  </Flex>
                </>
              )}
            </Flex>
          )}
        </Box>
      </Container>
    </Flex>
  );
}
