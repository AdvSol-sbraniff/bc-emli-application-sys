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
import { ArrowsClockwise, CaretLeft, CaretRight, PencilSimple, Plus, Trash } from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type UserGridRow = {
  id: string;
  email?: string | null;
  organization?: string | null;
  role?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  name?: string | null;
  reviewed?: boolean | null;
  certified?: boolean | null;
  confirmed_at?: string | null;
  created_at?: string | null;
  updated_at?: string | null;
  omniauth_provider?: string | null;
  omniauth_uid?: string | null;
  omniauth_email?: string | null;
  omniauth_username?: string | null;
  discarded_at?: string | null;
  sign_in_count?: number | null;
  current_sign_in_at?: string | null;
  last_sign_in_at?: string | null;
  invitation_sent_at?: string | null;
  invitation_accepted_at?: string | null;
  unconfirmed_email?: string | null;
};

type UsersApiResp = {
  rows: UserGridRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
  };
};

const fmtTs = (s?: string | null) => (s ? String(s).replace('T', ' ').replace('Z', '') : '');
const fmtBool = (value?: boolean | null) => {
  if (value === true) return 'Yes';
  if (value === false) return 'No';
  return '';
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
      <Text
        fontSize="sm"
        whiteSpace="pre-wrap"
        fontFamily={label.endsWith('_id') || label === 'id' ? 'mono' : undefined}
      >
        {value === null || value === undefined || value === '' ? '--' : String(value)}
      </Text>
    </Box>
  );
}

export default function UsersAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const [q, setQ] = useState<string>('');
  const [sort, setSort] = useState<string>('updated_at:desc');
  const [page, setPage] = useState<number>(1);
  const [per, setPer] = useState<number>(25);

  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [rows, setRows] = useState<UserGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  const { isOpen, onOpen, onClose } = useDisclosure();
  const [selected, setSelected] = useState<UserGridRow | null>(null);
  const didInitFromUrl = useRef(false);

  useEffect(() => {
    const params = new URLSearchParams(location.search);

    const next = {
      q: params.get('q') || '',
      sort: params.get('sort') || 'updated_at:desc',
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
    const merged = { q, sort, page, per, ...next };

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

      const res = await fetch(`/api/claims/admin/users?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: UsersApiResp = await res.json().catch(() => ({ rows: [] }) as UsersApiResp);
      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setError(e?.message || 'Failed to load users.');
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

  const openDetails = (row: UserGridRow) => {
    setSelected(row);
    onOpen();
  };

  const closeDetails = () => {
    onClose();
    setSelected(null);
  };

  const openEditor = (row: UserGridRow) => {
    window.open(`/user-editor?id=${encodeURIComponent(row.id)}`, '_blank', 'noopener,noreferrer');
  };

  const openCreateEditor = () => {
    window.open('/user-editor?mode=create', '_blank', 'noopener,noreferrer');
  };

  const deleteUser = async (row: UserGridRow) => {
    const label = row.email || row.name || row.id;
    if (!window.confirm(`Delete user ${label}?`)) return;

    try {
      const res = await fetch(`/api/claims/admin/users/${encodeURIComponent(row.id)}`, {
        method: 'DELETE',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error((data as any)?.error || `HTTP ${res.status}`);
      }

      setRows((prev) => prev.filter((r) => r.id !== row.id));
      setTotal((prev) => Math.max(0, prev - 1));
      if (selected?.id === row.id) closeDetails();
    } catch (e: any) {
      setError(e?.message || 'Failed to delete user.');
    }
  };

  const selectedFields = useMemo(() => {
    if (!selected) return [] as Array<[string, any]>;
    return [
      ['id', selected.id],
      ['email', selected.email],
      ['first_name', selected.first_name],
      ['last_name', selected.last_name],
      ['organization', selected.organization],
      ['role', selected.role],
      ['reviewed', fmtBool(selected.reviewed)],
      ['certified', fmtBool(selected.certified)],
      ['confirmed_at', fmtTs(selected.confirmed_at)],
      ['omniauth_provider', selected.omniauth_provider],
      ['omniauth_uid', selected.omniauth_uid],
      ['omniauth_email', selected.omniauth_email],
      ['omniauth_username', selected.omniauth_username],
      ['unconfirmed_email', selected.unconfirmed_email],
      ['sign_in_count', selected.sign_in_count],
      ['current_sign_in_at', fmtTs(selected.current_sign_in_at)],
      ['last_sign_in_at', fmtTs(selected.last_sign_in_at)],
      ['invitation_sent_at', fmtTs(selected.invitation_sent_at)],
      ['invitation_accepted_at', fmtTs(selected.invitation_accepted_at)],
      ['discarded_at', fmtTs(selected.discarded_at)],
      ['created_at', fmtTs(selected.created_at)],
      ['updated_at', fmtTs(selected.updated_at)],
    ];
  }, [selected]);

  return (
    <Box>
      <ThinBlueTitleBar title="Create Test Users" />

      <Container maxW="container.xl" py={6}>
        <Flex align="center" justify="space-between" mb={4} gap={3} wrap="wrap">
          <Heading size="md">Users Grid</Heading>
          <Flex gap={2} wrap="wrap">
            <Button onClick={openCreateEditor} leftIcon={<Plus size={16} />} colorScheme="green">
              Add User
            </Button>
            <Input
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search email, name, org, role, provider, guid"
              width={{ base: '100%', md: '360px' }}
            />
            <Select value={sort} onChange={(e) => setSort(e.target.value)} width={{ base: '100%', md: '220px' }}>
              <option value="updated_at:desc">Updated desc</option>
              <option value="updated_at:asc">Updated asc</option>
              <option value="created_at:desc">Created desc</option>
              <option value="created_at:asc">Created asc</option>
              <option value="email:asc">Email asc</option>
              <option value="email:desc">Email desc</option>
              <option value="last_name:asc">Last name asc</option>
              <option value="last_name:desc">Last name desc</option>
              <option value="role:asc">Role asc</option>
              <option value="role:desc">Role desc</option>
              <option value="last_sign_in_at:desc">Last sign-in desc</option>
              <option value="last_sign_in_at:asc">Last sign-in asc</option>
            </Select>
            <Select
              value={String(per)}
              onChange={(e) => {
                const next = Number(e.target.value) || 25;
                setPer(next);
                setPage(1);
              }}
              width="110px"
            >
              <option value="25">25 / page</option>
              <option value="50">50 / page</option>
              <option value="100">100 / page</option>
            </Select>
            <Button onClick={() => pushUrl({ q, sort, page: 1, per })} colorScheme="blue">
              Search
            </Button>
            <Button
              onClick={() => fetchRows()}
              variant="outline"
              leftIcon={<ArrowsClockwise size={16} />}
              isDisabled={loading}
            >
              Reload
            </Button>
          </Flex>
        </Flex>

        {error && (
          <Box p={3} borderWidth="1px" borderRadius="md" mb={4} borderColor="red.300" bg="red.50">
            <Text color="red.800" fontSize="sm">
              {error}
            </Text>
          </Box>
        )}

        <Box borderWidth="1px" borderRadius="lg" overflowX="auto" bg="white">
          <Table size="sm">
            <Thead>
              <Tr>
                <Th>Email</Th>
                <Th>Name</Th>
                <Th>Role</Th>
                <Th>Organization</Th>
                <Th>Reviewed</Th>
                <Th>Provider</Th>
                <Th>Last Sign-In</Th>
                <Th textAlign="right">Actions</Th>
              </Tr>
            </Thead>
            <Tbody>
              {loading && (
                <Tr>
                  <Td colSpan={8}>
                    <Flex align="center" gap={3} py={6}>
                      <Spinner size="sm" />
                      <Text>Loading users...</Text>
                    </Flex>
                  </Td>
                </Tr>
              )}

              {!loading && rows.length === 0 && (
                <Tr>
                  <Td colSpan={8}>
                    <Box py={8} textAlign="center">
                      <Text>No users found.</Text>
                    </Box>
                  </Td>
                </Tr>
              )}

              {!loading &&
                rows.map((row) => (
                  <Tr key={row.id} _hover={{ bg: 'gray.50' }}>
                    <Td>{row.email || '--'}</Td>
                    <Td>{row.name?.trim() || [row.first_name, row.last_name].filter(Boolean).join(' ') || '--'}</Td>
                    <Td>{row.role || '--'}</Td>
                    <Td>{row.organization || '--'}</Td>
                    <Td>{fmtBool(row.reviewed) || '--'}</Td>
                    <Td>{row.omniauth_provider || '--'}</Td>
                    <Td>{fmtTs(row.last_sign_in_at) || '--'}</Td>
                    <Td>
                      <Flex justify="flex-end" gap={2}>
                        <Button size="xs" variant="outline" onClick={() => openDetails(row)}>
                          Details
                        </Button>
                        <Tooltip label="Open user editor">
                          <IconButton
                            aria-label="Edit user"
                            size="xs"
                            icon={<PencilSimple size={16} />}
                            onClick={() => openEditor(row)}
                          />
                        </Tooltip>
                        <Tooltip label="Delete user">
                          <IconButton
                            aria-label="Delete user"
                            size="xs"
                            colorScheme="red"
                            variant="outline"
                            icon={<Trash size={16} />}
                            onClick={() => deleteUser(row)}
                          />
                        </Tooltip>
                      </Flex>
                    </Td>
                  </Tr>
                ))}
            </Tbody>
          </Table>
        </Box>

        <Flex mt={4} justify="space-between" align="center" gap={3} wrap="wrap">
          <Text fontSize="sm" opacity={0.8}>
            {total} total users
          </Text>
          <Flex gap={2} align="center">
            <Button
              size="sm"
              variant="outline"
              leftIcon={<CaretLeft size={16} />}
              onClick={() => setPage(Math.max(1, page - 1))}
              isDisabled={page <= 1 || loading}
            >
              Prev
            </Button>
            <Text fontSize="sm">
              Page {page} of {totalPages}
            </Text>
            <Button
              size="sm"
              variant="outline"
              rightIcon={<CaretRight size={16} />}
              onClick={() => setPage(Math.min(totalPages, page + 1))}
              isDisabled={page >= totalPages || loading}
            >
              Next
            </Button>
          </Flex>
        </Flex>
      </Container>

      <Drawer isOpen={isOpen} placement="right" onClose={closeDetails} size="lg">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>User Details</DrawerHeader>
          <DrawerBody>
            {!selected ? (
              <Text opacity={0.7}>No user selected.</Text>
            ) : (
              <Flex direction="column" gap={4}>
                {selectedFields.map(([label, value]) => (
                  <Field key={label} label={label} value={value} />
                ))}
              </Flex>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Box>
  );
}
