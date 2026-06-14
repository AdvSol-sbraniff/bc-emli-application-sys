import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Box,
  Button,
  Checkbox,
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
import {
  ArrowsClockwise,
  CaretLeft,
  CaretRight,
  Info,
  PencilSimple,
  Plus,
  Trash,
  XCircle,
} from '@phosphor-icons/react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

type ContractorGridRow = {
  id: string;
  contact_id?: string | null;
  business_name?: string | null;
  contractor_number?: string | null;
  number?: string | null;
  website?: string | null;
  email?: string | null;
  contact_email?: string | null;
  contact_name?: string | null;
  phone_number?: string | null;
  cellphone_number?: string | null;
  street_address?: string | null;
  city?: string | null;
  postal_code?: string | null;
  onboarded?: boolean | null;
  created_at?: string | null;
  updated_at?: string | null;
};

type ContractorsApiResp = {
  rows: ContractorGridRow[];
  meta?: {
    total?: number;
    page?: number;
    per?: number;
    sort?: string;
  };
};

type ContractorFormState = {
  contact_id: string;
  business_name: string;
  number: string;
  website: string;
  email: string;
  phone_number: string;
  cellphone_number: string;
  street_address: string;
  city: string;
  postal_code: string;
  onboarded: boolean;
};

const EMPTY_FORM: ContractorFormState = {
  contact_id: '',
  business_name: '',
  number: '',
  website: '',
  email: '',
  phone_number: '',
  cellphone_number: '',
  street_address: '',
  city: '',
  postal_code: '',
  onboarded: true,
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

function blankToNull(value: string) {
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function toForm(row: ContractorGridRow): ContractorFormState {
  return {
    contact_id: row.contact_id || '',
    business_name: row.business_name || '',
    number: row.number || row.contractor_number || '',
    website: row.website || '',
    email: row.email || '',
    phone_number: row.phone_number || '',
    cellphone_number: row.cellphone_number || '',
    street_address: row.street_address || '',
    city: row.city || '',
    postal_code: row.postal_code || '',
    onboarded: row.onboarded !== false,
  };
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

function FormInput({
  label,
  value,
  onChange,
  placeholder,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
}) {
  return (
    <Box>
      <Text fontSize="xs" opacity={0.7} mb={1}>
        {label}
      </Text>
      <Input value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} bg="white" />
    </Box>
  );
}

export default function ContractorsAdminScreen() {
  const location = useLocation();
  const navigate = useNavigate();

  const [q, setQ] = useState<string>('');
  const [sort, setSort] = useState<string>('business_name:asc');
  const [page, setPage] = useState<number>(1);
  const [per, setPer] = useState<number>(25);

  const [loading, setLoading] = useState<boolean>(false);
  const [saving, setSaving] = useState<boolean>(false);
  const [error, setError] = useState<string>('');
  const [rows, setRows] = useState<ContractorGridRow[]>([]);
  const [total, setTotal] = useState<number>(0);

  const { isOpen: isDetailsOpen, onOpen: onDetailsOpen, onClose: onDetailsClose } = useDisclosure();
  const { isOpen: isEditorOpen, onOpen: onEditorOpen, onClose: onEditorClose } = useDisclosure();
  const [selected, setSelected] = useState<ContractorGridRow | null>(null);
  const [editing, setEditing] = useState<ContractorGridRow | null>(null);
  const [form, setForm] = useState<ContractorFormState>(EMPTY_FORM);
  const didInitFromUrl = useRef(false);

  useEffect(() => {
    const params = new URLSearchParams(location.search);

    const next = {
      q: params.get('q') || '',
      sort: params.get('sort') || 'business_name:asc',
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

  const fetchRows = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const params = buildSearchParams({
        q: q || undefined,
        sort: sort || undefined,
        page: String(page || 1),
        per: String(per || 25),
      });

      const res = await fetch(`/api/claims/admin/contractors?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      const data: ContractorsApiResp = await res.json().catch(() => ({ rows: [] }) as ContractorsApiResp);
      if (!res.ok) {
        throw new Error((data as any)?.error || (data as any)?.message || `HTTP ${res.status}`);
      }

      setRows(Array.isArray(data?.rows) ? data.rows : []);
      setTotal(Number(data?.meta?.total || 0));
    } catch (e: any) {
      setRows([]);
      setTotal(0);
      setError(e?.message || 'Failed to load contractors.');
    } finally {
      setLoading(false);
    }
  }, [page, per, q, sort]);

  useEffect(() => {
    if (didInitFromUrl.current) fetchRows();
  }, [fetchRows]);

  const totalPages = useMemo(() => {
    const p = Math.max(1, per || 25);
    return Math.max(1, Math.ceil((total || 0) / p));
  }, [total, per]);

  const selectedFields = useMemo(() => {
    if (!selected) return [] as Array<[string, any]>;
    return [
      ['id', selected.id],
      ['business_name', selected.business_name],
      ['number', selected.number || selected.contractor_number],
      ['email', selected.email],
      ['contact_id', selected.contact_id],
      ['contact_name', selected.contact_name],
      ['contact_email', selected.contact_email],
      ['website', selected.website],
      ['phone_number', selected.phone_number],
      ['cellphone_number', selected.cellphone_number],
      ['street_address', selected.street_address],
      ['city', selected.city],
      ['postal_code', selected.postal_code],
      ['onboarded', fmtBool(selected.onboarded)],
      ['created_at', fmtTs(selected.created_at)],
      ['updated_at', fmtTs(selected.updated_at)],
    ];
  }, [selected]);

  const updateForm = (patch: Partial<ContractorFormState>) => setForm((prev) => ({ ...prev, ...patch }));

  const openDetails = (row: ContractorGridRow) => {
    setSelected(row);
    onDetailsOpen();
  };

  const closeDetails = () => {
    onDetailsClose();
    setSelected(null);
  };

  const openCreate = () => {
    setEditing(null);
    setForm(EMPTY_FORM);
    onEditorOpen();
  };

  const openEdit = (row: ContractorGridRow) => {
    setEditing(row);
    setForm(toForm(row));
    onEditorOpen();
  };

  const closeEditor = () => {
    onEditorClose();
    setEditing(null);
    setForm(EMPTY_FORM);
  };

  const saveContractor = async () => {
    setSaving(true);
    setError('');

    try {
      const endpoint = editing
        ? `/api/claims/admin/contractors/${encodeURIComponent(editing.id)}`
        : '/api/claims/admin/contractors';
      const method = editing ? 'PATCH' : 'POST';

      const res = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          contact_id: blankToNull(form.contact_id),
          business_name: blankToNull(form.business_name),
          number: blankToNull(form.number),
          website: blankToNull(form.website),
          email: blankToNull(form.email),
          phone_number: blankToNull(form.phone_number),
          cellphone_number: blankToNull(form.cellphone_number),
          street_address: blankToNull(form.street_address),
          city: blankToNull(form.city),
          postal_code: blankToNull(form.postal_code),
          onboarded: form.onboarded,
        }),
      });

      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        throw new Error((data as any)?.error || `${method} failed with HTTP ${res.status}`);
      }

      closeEditor();
      await fetchRows();
    } catch (e: any) {
      setError(e?.message || 'Failed to save contractor.');
    } finally {
      setSaving(false);
    }
  };

  const deleteContractor = async (row: ContractorGridRow) => {
    const label = row.business_name || row.number || row.id;
    if (!window.confirm(`Delete contractor ${label}?`)) return;

    try {
      const res = await fetch(`/api/claims/admin/contractors/${encodeURIComponent(row.id)}`, {
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
      setError(e?.message || 'Failed to delete contractor.');
    }
  };

  const clearFilters = () => {
    setQ('');
    setSort('business_name:asc');
    setPage(1);
    setPer(25);
    pushUrl({ q: '', sort: 'business_name:asc', page: 1, per: 25 });
  };

  return (
    <Box>
      <ThinBlueTitleBar title="Create Test Contractors" />

      <Container maxW="container.xl" py={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex align="end" justify="space-between" mb={4} gap={3} wrap="wrap">
            <Box>
              <Heading size="md">Contractors</Heading>
              <Text fontSize="sm" opacity={0.75}>
                Create lightweight contractor records for local and Gold invoice test packages.
              </Text>
            </Box>

            <Flex gap={2} wrap="wrap" align="end">
              <Button onClick={openCreate} leftIcon={<Plus size={16} />} colorScheme="green">
                Add Contractor
              </Button>
              <Input
                value={q}
                onChange={(e) => {
                  const v = e.target.value;
                  setQ(v);
                  setPage(1);
                  pushUrl({ q: v, page: 1 });
                }}
                placeholder="Search name, number, email, phone, city, postal code"
                width={{ base: '100%', md: '360px' }}
                bg="white"
              />
              <Select
                value={sort}
                onChange={(e) => {
                  const v = e.target.value;
                  setSort(v);
                  setPage(1);
                  pushUrl({ sort: v, page: 1 });
                }}
                width={{ base: '100%', md: '220px' }}
                bg="white"
              >
                <option value="business_name:asc">Business name asc</option>
                <option value="business_name:desc">Business name desc</option>
                <option value="number:asc">Number asc</option>
                <option value="number:desc">Number desc</option>
                <option value="email:asc">Email asc</option>
                <option value="email:desc">Email desc</option>
                <option value="updated_at:desc">Updated desc</option>
                <option value="updated_at:asc">Updated asc</option>
                <option value="created_at:desc">Created desc</option>
                <option value="created_at:asc">Created asc</option>
              </Select>
              <Select
                value={String(per)}
                onChange={(e) => {
                  const next = Number(e.target.value) || 25;
                  setPer(next);
                  setPage(1);
                  pushUrl({ per: next, page: 1 });
                }}
                width="120px"
                bg="white"
              >
                <option value="25">25 / page</option>
                <option value="50">50 / page</option>
                <option value="100">100 / page</option>
              </Select>
              <Tooltip label="Refresh grid">
                <IconButton
                  aria-label="Refresh grid"
                  icon={<ArrowsClockwise size={18} />}
                  variant="outline"
                  onClick={fetchRows}
                  isLoading={loading}
                />
              </Tooltip>
              <Tooltip label="Clear filters">
                <IconButton
                  aria-label="Clear filters"
                  icon={<XCircle size={18} />}
                  variant="outline"
                  onClick={clearFilters}
                />
              </Tooltip>
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
            <Table size="sm" minW="980px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>Business name</Th>
                  <Th>Number</Th>
                  <Th>Email</Th>
                  <Th>Phone</Th>
                  <Th>City</Th>
                  <Th>Postal code</Th>
                  <Th>Onboarded</Th>
                  <Th textAlign="right">Actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {loading && (
                  <Tr>
                    <Td colSpan={8}>
                      <Flex align="center" gap={3} py={6}>
                        <Spinner size="sm" />
                        <Text>Loading contractors...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                )}

                {!loading && rows.length === 0 && (
                  <Tr>
                    <Td colSpan={8}>
                      <Box py={8} textAlign="center">
                        <Text>No contractors found.</Text>
                      </Box>
                    </Td>
                  </Tr>
                )}

                {!loading &&
                  rows.map((row) => (
                    <Tr key={row.id} _hover={{ bg: 'gray.50' }}>
                      <Td fontWeight="semibold">{row.business_name || '--'}</Td>
                      <Td fontFamily="mono" fontSize="xs">
                        {row.number || row.contractor_number || '--'}
                      </Td>
                      <Td>{row.email || '--'}</Td>
                      <Td>{row.phone_number || row.cellphone_number || '--'}</Td>
                      <Td>{row.city || '--'}</Td>
                      <Td fontFamily="mono" fontSize="xs">
                        {row.postal_code || '--'}
                      </Td>
                      <Td>{fmtBool(row.onboarded) || '--'}</Td>
                      <Td>
                        <Flex justify="flex-end" gap={2}>
                          <Tooltip label="Open details drawer">
                            <IconButton
                              aria-label="Open details drawer"
                              size="xs"
                              variant="outline"
                              icon={<Info size={14} />}
                              onClick={() => openDetails(row)}
                            />
                          </Tooltip>
                          <Tooltip label="Edit contractor">
                            <IconButton
                              aria-label="Edit contractor"
                              size="xs"
                              icon={<PencilSimple size={16} />}
                              onClick={() => openEdit(row)}
                            />
                          </Tooltip>
                          <Tooltip label="Delete contractor">
                            <IconButton
                              aria-label="Delete contractor"
                              size="xs"
                              colorScheme="red"
                              variant="outline"
                              icon={<Trash size={16} />}
                              onClick={() => deleteContractor(row)}
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
              {total} total contractors
            </Text>
            <Flex gap={2} align="center">
              <Button
                size="sm"
                variant="outline"
                leftIcon={<CaretLeft size={16} />}
                onClick={() => {
                  const next = Math.max(1, page - 1);
                  setPage(next);
                  pushUrl({ page: next });
                }}
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
                onClick={() => {
                  const next = Math.min(totalPages, page + 1);
                  setPage(next);
                  pushUrl({ page: next });
                }}
                isDisabled={page >= totalPages || loading}
              >
                Next
              </Button>
            </Flex>
          </Flex>
        </Box>
      </Container>

      <Drawer isOpen={isDetailsOpen} placement="right" onClose={closeDetails} size="lg">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Contractor Details</DrawerHeader>
          <DrawerBody>
            {!selected ? (
              <Text opacity={0.7}>No contractor selected.</Text>
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

      <Drawer isOpen={isEditorOpen} placement="right" onClose={closeEditor} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>{editing ? 'Update Test Contractor' : 'Create Test Contractor'}</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={5}>
              <SimpleGrid columns={{ base: 1, md: 2 }} spacing={4}>
                <FormInput
                  label="business_name"
                  value={form.business_name}
                  onChange={(value) => updateForm({ business_name: value })}
                  placeholder="Example Windows Ltd."
                />
                <FormInput
                  label="number"
                  value={form.number}
                  onChange={(value) => updateForm({ number: value })}
                  placeholder="Leave blank to auto-assign"
                />
                <FormInput label="email" value={form.email} onChange={(value) => updateForm({ email: value })} />
                <FormInput label="website" value={form.website} onChange={(value) => updateForm({ website: value })} />
                <FormInput
                  label="phone_number"
                  value={form.phone_number}
                  onChange={(value) => updateForm({ phone_number: value })}
                />
                <FormInput
                  label="cellphone_number"
                  value={form.cellphone_number}
                  onChange={(value) => updateForm({ cellphone_number: value })}
                />
                <FormInput
                  label="street_address"
                  value={form.street_address}
                  onChange={(value) => updateForm({ street_address: value })}
                />
                <FormInput label="city" value={form.city} onChange={(value) => updateForm({ city: value })} />
                <FormInput
                  label="postal_code"
                  value={form.postal_code}
                  onChange={(value) => updateForm({ postal_code: value })}
                />
                <FormInput
                  label="contact_id"
                  value={form.contact_id}
                  onChange={(value) => updateForm({ contact_id: value })}
                  placeholder="Optional user UUID"
                />
              </SimpleGrid>

              <Checkbox isChecked={form.onboarded} onChange={(e) => updateForm({ onboarded: e.target.checked })}>
                onboarded
              </Checkbox>

              <Flex justify="flex-end" gap={2}>
                <Button variant="outline" onClick={closeEditor} isDisabled={saving}>
                  Cancel
                </Button>
                <Button colorScheme="blue" onClick={saveContractor} isLoading={saving}>
                  Save Contractor
                </Button>
              </Flex>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Box>
  );
}
