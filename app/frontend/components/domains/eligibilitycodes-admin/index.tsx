import React, { useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  Heading,
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
import { Info, PencilSimple, Plus } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type EligibilityGridRow = {
  user_id: string;
  email?: string | null;
  organization?: string | null;
  certified?: boolean | null;
  user_created_at?: string | null;
  user_updated_at?: string | null;
  role?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  omniauth_provider?: string | null;
  omniauth_uid?: string | null;
  discarded_at?: string | null;
  sign_in_count?: number | null;
  current_sign_in_at?: string | null;
  last_sign_in_at?: string | null;
  unconfirmed_email?: string | null;
  omniauth_email?: string | null;
  omniauth_username?: string | null;
  reviewed?: boolean | null;
  users_eligibilitycode_id?: string | null;
  eligibilitycode_user_id?: string | null;
  eligibility_code?: string | null;
  applied_at?: string | null;
  approved_at?: string | null;
  expires_at?: string | null;
  users_eligibilitycode_created_at?: string | null;
  users_eligibilitycode_updated_at?: string | null;
};

type EligibilityApiResp = {
  rows: EligibilityGridRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
  };
};

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');
const fmtDate = (s?: string | null) => {
  if (!s) return '';
  const str = String(s);
  return str.includes('T') ? str.split('T')[0] : str.slice(0, 10);
};

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

function Field({ label, value }: { label: string; value: any }) {
  return (
    <Box>
      <Text fontSize="xs" opacity={0.7} mb={1}>
        {label}
      </Text>
      <Text fontSize="sm" whiteSpace="pre-wrap" fontFamily={label.endsWith('_id') ? 'mono' : undefined}>
        {value === null || value === undefined || value === '' ? '—' : String(value)}
      </Text>
    </Box>
  );
}

export default function EligibilitycodesAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const [q, setQ] = useState<string>('');
  const [sort, setSort] = useState<string>('users_eligibilitycode_updated_at:desc');
  const [page, setPage] = useState<number>(1);
  const [per, setPer] = useState<number>(25);

  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [rows, setRows] = useState<EligibilityGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  const { isOpen, onOpen, onClose } = useDisclosure();
  const [selected, setSelected] = useState<EligibilityGridRow | null>(null);

  const didInitFromUrl = useRef(false);

  useEffect(() => {
    const params = new URLSearchParams(location.search);

    const next = {
      q: params.get('q') || '',
      sort: params.get('sort') || 'users_eligibilitycode_updated_at:desc',
      page: Number(params.get('page') || '1') || 1,
      per: Number(params.get('per') || '25') || 25,
    };

    if (!didInitFromUrl.current) {
      didInitFromUrl.current = true;
      setQ(next.q);
      setSort(next.sort);
      setPage(next.page);
      setPer(next.per);
      return;
    }

    setQ(next.q);
    setSort(next.sort);
    setPage(next.page);
    setPer(next.per);
  }, [location.search]);

  const pushUrl = (next: Partial<{ q: string; sort: string; page: number; per: number }>) => {
    const merged = {
      q,
      sort,
      page,
      per,
      ...next,
    };

    const params = buildSearchParams({
      q: merged.q || undefined,
      sort: merged.sort || undefined,
      page: String(merged.page || 1),
      per: String(merged.per || 25),
    });

    navigate({ pathname: location.pathname, search: `?${params.toString()}` }, { replace: true });
  };

  const fetchRows = async () => {
    setLoading(true);
    setError('');

    try {
      const params = buildSearchParams({
        q: q || undefined,
        sort: sort || undefined,
        page: String(page || 1),
        per: String(per || 25),
      });

      const res = await fetch(`/api/claims/admin/user_eligibilitycodes?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: EligibilityApiResp = await res.json().catch(() => ({ rows: [] } as EligibilityApiResp));

      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setError(e?.message || 'Failed to load users and eligibility codes.');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (didInitFromUrl.current) fetchRows();
  }, [q, sort, page, per]);

  const totalPages = useMemo(() => {
    const p = Math.max(1, per || 25);
    return Math.max(1, Math.ceil((total || 0) / p));
  }, [total, per]);

  const openDetails = (row: EligibilityGridRow) => {
    setSelected(row);
    onOpen();
  };

  const closeDetails = () => {
    onClose();
    setSelected(null);
  };

  const openInsertEditor = (row: EligibilityGridRow) => {
    const params = new URLSearchParams();
    params.set('mode', 'create');
    params.set('user_id', row.user_id);
    if (row.email) params.set('email', row.email);
    const name = [row.first_name, row.last_name].filter(Boolean).join(' ');
    if (name) params.set('name', name);

    window.open(`/eligibilitycode-editor?${params.toString()}`, '_blank', 'noopener,noreferrer');
  };

  const openUpdateEditor = (row: EligibilityGridRow) => {
    if (!row.users_eligibilitycode_id) return;
    window.open(
      `/eligibilitycode-editor?id=${encodeURIComponent(row.users_eligibilitycode_id)}`,
      '_blank',
      'noopener,noreferrer',
    );
  };

  const selectedUserFields = useMemo(() => {
    if (!selected) return [] as Array<[string, any]>;
    return [
      ['user_id', selected.user_id],
      ['email', selected.email],
      ['first_name', selected.first_name],
      ['last_name', selected.last_name],
      ['role', selected.role],
      ['organization', selected.organization],
      ['certified', selected.certified],
      ['reviewed', selected.reviewed],
      ['omniauth_provider', selected.omniauth_provider],
      ['omniauth_uid', selected.omniauth_uid],
      ['omniauth_username', selected.omniauth_username],
      ['omniauth_email', selected.omniauth_email],
      ['unconfirmed_email', selected.unconfirmed_email],
      ['sign_in_count', selected.sign_in_count],
      ['current_sign_in_at', selected.current_sign_in_at],
      ['last_sign_in_at', selected.last_sign_in_at],
      ['discarded_at', selected.discarded_at],
      ['user_created_at', selected.user_created_at],
      ['user_updated_at', selected.user_updated_at],
    ];
  }, [selected]);

  const selectedEligibilityFields = useMemo(() => {
    if (!selected) return [] as Array<[string, any]>;
    return [
      ['users_eligibilitycode_id', selected.users_eligibilitycode_id],
      ['eligibilitycode_user_id', selected.eligibilitycode_user_id],
      ['eligibility_code', selected.eligibility_code],
      ['applied_at', selected.applied_at],
      ['approved_at', selected.approved_at],
      ['expires_at', selected.expires_at],
      ['users_eligibilitycode_created_at', selected.users_eligibilitycode_created_at],
      ['users_eligibilitycode_updated_at', selected.users_eligibilitycode_updated_at],
    ];
  }, [selected]);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Eligibility Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Search (user id, name, email, role, provider, eligibility code)
              </Text>
              <Input
                value={q}
                onChange={(e) => {
                  const v = e.target.value;
                  setQ(v);
                  setPage(1);
                  pushUrl({ q: v, page: 1 });
                }}
                placeholder="Search users and eligibility codes..."
                bg="white"
              />
            </Box>

            <Box w="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Sort
              </Text>
              <Select
                value={sort}
                onChange={(e) => {
                  const v = e.target.value;
                  setSort(v);
                  setPage(1);
                  pushUrl({ sort: v, page: 1 });
                }}
                bg="white"
              >
                <option value="users_eligibilitycode_updated_at:desc">eligibility updated_at desc</option>
                <option value="users_eligibilitycode_updated_at:asc">eligibility updated_at asc</option>
                <option value="eligibility_code:asc">eligibility_code asc</option>
                <option value="eligibility_code:desc">eligibility_code desc</option>
                <option value="email:asc">email asc</option>
                <option value="email:desc">email desc</option>
                <option value="user_created_at:desc">user created_at desc</option>
              </Select>
            </Box>

            <Box w="120px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Per page
              </Text>
              <Select
                value={String(per)}
                onChange={(e) => {
                  const v = Number(e.target.value) || 25;
                  setPer(v);
                  setPage(1);
                  pushUrl({ per: v, page: 1 });
                }}
                bg="white"
              >
                <option value="25">25</option>
                <option value="50">50</option>
                <option value="100">100</option>
              </Select>
            </Box>

            <Button
              variant="outline"
              onClick={() => {
                setQ('');
                setSort('users_eligibilitycode_updated_at:desc');
                setPage(1);
                setPer(25);
                pushUrl({ q: '', sort: 'users_eligibilitycode_updated_at:desc', page: 1, per: 25 });
              }}
            >
              Reset
            </Button>
          </Flex>

          {error && (
            <Box mb={4} p={3} borderWidth="1px" borderRadius="md" borderColor="red.300" bg="red.50">
              <Text color="red.800" fontSize="sm">
                {error}
              </Text>
            </Box>
          )}

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1100px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>name</Th>
                  <Th>email</Th>
                  <Th>eligibility_code</Th>
                  <Th>approved_at</Th>
                  <Th>expires_at</Th>
                  <Th>Actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {loading ? (
                  <Tr>
                    <Td colSpan={6}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading rows...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : rows.length === 0 ? (
                  <Tr>
                    <Td colSpan={6}>
                      <Text py={3} opacity={0.8}>
                        No users or eligibility codes found.
                      </Text>
                    </Td>
                  </Tr>
                ) : (
                  rows.map((row, idx) => (
                    <Tr key={`${row.user_id}-${row.users_eligibilitycode_id || 'none'}-${idx}`}>
                      <Td>{[row.first_name, row.last_name].filter(Boolean).join(' ') || '—'}</Td>
                      <Td>{row.email || '—'}</Td>
                      <Td fontFamily="mono" fontSize="xs">{row.eligibility_code || '—'}</Td>
                      <Td fontFamily="mono" fontSize="xs">{fmtDate(row.approved_at)}</Td>
                      <Td fontFamily="mono" fontSize="xs">{fmtDate(row.expires_at)}</Td>
                      <Td>
                        <Flex gap={2}>
                          <Tooltip label="Open details drawer">
                            <IconButton
                              aria-label="Open details drawer"
                              size="xs"
                              variant="outline"
                              icon={<Info size={14} />}
                              onClick={() => openDetails(row)}
                            />
                          </Tooltip>
                          <Tooltip label="Insert eligibility code">
                            <IconButton
                              aria-label="Insert eligibility code"
                              size="xs"
                              variant="outline"
                              icon={<Plus size={14} />}
                              onClick={() => openInsertEditor(row)}
                            />
                          </Tooltip>
                          <Tooltip label="Update eligibility code">
                            <IconButton
                              aria-label="Update eligibility code"
                              size="xs"
                              variant="outline"
                              icon={<PencilSimple size={14} />}
                              isDisabled={!row.users_eligibilitycode_id}
                              onClick={() => openUpdateEditor(row)}
                            />
                          </Tooltip>
                        </Flex>
                      </Td>
                    </Tr>
                  ))
                )}
              </Tbody>
            </Table>
          </Box>

          <Flex mt={4} justify="space-between" align="center" wrap="wrap" gap={3}>
            <Text fontSize="sm" opacity={0.8}>
              Total: {total}
            </Text>

            <Flex gap={2} align="center">
              <Button
                size="sm"
                variant="outline"
                isDisabled={page <= 1 || loading}
                onClick={() => {
                  const next = Math.max(1, page - 1);
                  setPage(next);
                  pushUrl({ page: next });
                }}
              >
                Previous
              </Button>

              <Text fontSize="sm">
                Page {page} of {totalPages}
              </Text>

              <Button
                size="sm"
                variant="outline"
                isDisabled={page >= totalPages || loading}
                onClick={() => {
                  const next = Math.min(totalPages, page + 1);
                  setPage(next);
                  pushUrl({ page: next });
                }}
              >
                Next
              </Button>
            </Flex>
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={isOpen} placement="right" onClose={closeDetails} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>
            Eligibility details {selected?.users_eligibilitycode_id ? `(record ${selected.users_eligibilitycode_id})` : '(no eligibility row yet)'}
          </DrawerHeader>
          <DrawerBody>
            {!selected ? (
              <Text fontSize="sm" opacity={0.7}>No row selected.</Text>
            ) : (
              <Box>
                <Box borderWidth="1px" borderRadius="md" p={4} mb={4}>
                  <Heading size="sm" mb={3}>User fields</Heading>
                  <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                    {selectedUserFields.map(([k, v]) => (
                      <Box key={k}>
                        <Field label={k} value={v} />
                      </Box>
                    ))}
                  </SimpleGrid>
                </Box>

                <Box borderWidth="1px" borderRadius="md" p={4}>
                  <Heading size="sm" mb={3}>Eligibility code fields</Heading>
                  <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                    {selectedEligibilityFields.map(([k, v]) => (
                      <Box key={k}>
                        <Field label={k} value={v} />
                      </Box>
                    ))}
                  </SimpleGrid>
                </Box>
              </Box>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
