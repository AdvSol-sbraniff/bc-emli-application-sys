import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Badge,
  Box,
  Button,
  Container,
  Drawer,
  DrawerBody,
  DrawerCloseButton,
  DrawerContent,
  DrawerFooter,
  DrawerHeader,
  DrawerOverlay,
  Flex,
  HStack,
  IconButton,
  Input,
  Select,
  Spinner,
  Switch,
  Table,
  Tbody,
  Td,
  Text,
  Textarea,
  Th,
  Thead,
  Tooltip,
  Tr,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowsClockwise, PencilSimple, XCircle } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { InvoiceUpgradeTypeTile } from '../../shared/claims/invoice-upgrade-type-visual';

type UpgradeTypeRow = {
  id: string;
  upgrade_type_key: string;
  description?: string | null;
};

type CodeRuleRow = {
  id: string;
  code_rule_key: string;
  description: string;
  enabled: boolean;
  pass_admin_message?: string | null;
  warn_admin_message?: string | null;
  fail_admin_message?: string | null;
  info_admin_message?: string | null;
  admin_notes?: string | null;
  source_quote?: string | null;
  contractor_visible_flag?: boolean | null;
  updated_at?: string | null;
  upgrade_types?: UpgradeTypeRow[];
};

const fmtDate = (s?: string | null) => {
  if (!s) return '';
  const str = String(s);
  return str.includes('T') ? str.split('T')[0] : str.slice(0, 10);
};

function buildSearchParams(obj: Record<string, string | undefined>) {
  const p = new URLSearchParams();
  Object.entries(obj).forEach(([k, v]) => {
    const value = v?.toString().trim();
    if (value) p.set(k, value);
  });
  return p;
}

export default function CodeRulesetsAdminScreen() {
  const { isOpen, onOpen, onClose } = useDisclosure();

  const [q, setQ] = useState('');
  const [invoiceUpgradeTypeId, setInvoiceUpgradeTypeId] = useState('');
  const [enabledFilter, setEnabledFilter] = useState('');
  const [upgradeTypes, setUpgradeTypes] = useState<UpgradeTypeRow[]>([]);
  const [rows, setRows] = useState<CodeRuleRow[]>([]);
  const [selected, setSelected] = useState<CodeRuleRow | null>(null);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const [form, setForm] = useState({
    description: '',
    enabled: true,
    pass_admin_message: '',
    warn_admin_message: '',
    fail_admin_message: '',
    info_admin_message: '',
    admin_notes: '',
    source_quote: '',
    contractor_visible_flag: true,
  });

  const fetchUpgradeTypes = useCallback(async () => {
    try {
      const res = await fetch('/api/claims/admin/invoice_upgrade_types', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setUpgradeTypes(Array.isArray(data?.rows) ? data.rows : []);
    } catch {
      setUpgradeTypes([]);
    }
  }, []);

  const fetchRows = useCallback(async () => {
    setLoading(true);
    setError('');

    try {
      const params = buildSearchParams({
        q: q || undefined,
        invoice_upgrade_type_id: invoiceUpgradeTypeId || undefined,
        enabled: enabledFilter || undefined,
      });

      const res = await fetch(`/api/claims/admin/code_rules?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setRows([]);
      setError(e?.message || 'Failed to load code rules.');
    } finally {
      setLoading(false);
    }
  }, [q, invoiceUpgradeTypeId, enabledFilter]);

  useEffect(() => {
    fetchUpgradeTypes();
  }, [fetchUpgradeTypes]);

  useEffect(() => {
    fetchRows();
  }, [fetchRows]);

  const openEdit = (row: CodeRuleRow) => {
    setSelected(row);
    setForm({
      description: row.description || '',
      enabled: Boolean(row.enabled),
      pass_admin_message: row.pass_admin_message || '',
      warn_admin_message: row.warn_admin_message || '',
      fail_admin_message: row.fail_admin_message || '',
      info_admin_message: row.info_admin_message || '',
      admin_notes: row.admin_notes || '',
      source_quote: row.source_quote || '',
      contractor_visible_flag: row.contractor_visible_flag !== false,
    });
    onOpen();
  };

  const saveSelected = async () => {
    if (!selected) return;

    setSaving(true);
    setError('');

    try {
      const res = await fetch(`/api/claims/admin/code_rules/${encodeURIComponent(selected.id)}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify(form),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      onClose();
      setSelected(null);
      await fetchRows();
    } catch (e: any) {
      setError(e?.message || 'Failed to save code rule.');
    } finally {
      setSaving(false);
    }
  };

  const clearFilters = () => {
    setQ('');
    setInvoiceUpgradeTypeId('');
    setEnabledFilter('');
  };

  const filterIsDirty = Boolean(q.trim() || invoiceUpgradeTypeId || enabledFilter);
  const totalEnabled = useMemo(() => rows.filter((row) => row.enabled).length, [rows]);

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Code Rulesets Admin" />

      <Container maxW="container.xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="space-between" gap={4} wrap="wrap" align="start" mb={5}>
            <Box>
              <Text fontSize="lg" fontWeight="bold">
                Code-owned rules registry
              </Text>
              <Text fontSize="sm" opacity={0.75} maxW="860px" mt={1}>
                These rules are implemented in source code. This screen lets admins see which upgrade types each rule
                applies to, enable or disable current rules, and maintain simple guidance sentences that are appended to
                the code-generated explanation.
              </Text>
            </Box>
            <Badge colorScheme="green" variant="subtle" px={3} py={1}>
              {totalEnabled} enabled
            </Badge>
          </Flex>

          <Flex gap={3} align="end" wrap="wrap" mb={4}>
            <Box flex="1" minW="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Search key, description, or notes
              </Text>
              <Input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Example: ahri or efficiency" />
            </Box>

            <Box w="280px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Upgrade type
              </Text>
              <Select value={invoiceUpgradeTypeId} onChange={(e) => setInvoiceUpgradeTypeId(e.target.value)}>
                <option value="">All upgrade types</option>
                {upgradeTypes.map((type) => (
                  <option key={type.id} value={type.id}>
                    {type.description || type.upgrade_type_key}
                  </option>
                ))}
              </Select>
            </Box>

            <Box w="150px">
              <Text fontSize="xs" opacity={0.7} mb={1}>
                Enabled
              </Text>
              <Select value={enabledFilter} onChange={(e) => setEnabledFilter(e.target.value)}>
                <option value="">All</option>
                <option value="true">Enabled</option>
                <option value="false">Disabled</option>
              </Select>
            </Box>

            <HStack spacing={2} pb={1}>
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
                  isDisabled={!filterIsDirty}
                />
              </Tooltip>
            </HStack>
          </Flex>

          {error && (
            <Box mb={4} p={3} borderWidth="1px" borderRadius="md" borderColor="red.300" bg="red.50">
              <Text color="red.800" fontSize="sm" whiteSpace="pre-wrap">
                {error}
              </Text>
            </Box>
          )}

          <Box borderWidth="1px" borderRadius="md" overflow="auto">
            <Table size="sm" minW="1120px">
              <Thead bg="gray.50">
                <Tr>
                  <Th>Code rule</Th>
                  <Th w="260px">Upgrade types</Th>
                  <Th>Enabled</Th>
                  <Th>Description</Th>
                  <Th>Updated</Th>
                  <Th>Actions</Th>
                </Tr>
              </Thead>
              <Tbody>
                {loading ? (
                  <Tr>
                    <Td colSpan={6}>
                      <Flex align="center" gap={2} py={3}>
                        <Spinner size="sm" />
                        <Text>Loading code rules...</Text>
                      </Flex>
                    </Td>
                  </Tr>
                ) : rows.length === 0 ? (
                  <Tr>
                    <Td colSpan={6}>
                      <Text py={3} opacity={0.8}>
                        No code rules found.
                      </Text>
                    </Td>
                  </Tr>
                ) : (
                  rows.map((row) => (
                    <Tr key={row.id}>
                      <Td fontFamily="mono" fontSize="xs" fontWeight="semibold">
                        {row.code_rule_key}
                      </Td>
                      <Td w="260px" minW="260px">
                        <Flex gap={2} wrap="nowrap">
                          {(row.upgrade_types || []).map((type) => (
                            <Tooltip key={type.id} label={type.description || type.upgrade_type_key}>
                              <Box>
                                <InvoiceUpgradeTypeTile
                                  upgradeTypeKey={type.upgrade_type_key}
                                  description={type.description}
                                  size={30}
                                />
                              </Box>
                            </Tooltip>
                          ))}
                        </Flex>
                      </Td>
                      <Td>
                        <Badge colorScheme={row.enabled ? 'green' : 'gray'}>
                          {row.enabled ? 'enabled' : 'disabled'}
                        </Badge>
                      </Td>
                      <Td maxW="300px">
                        <Text fontSize="sm" noOfLines={2}>
                          {row.description}
                        </Text>
                      </Td>
                      <Td>{fmtDate(row.updated_at)}</Td>
                      <Td>
                        <Tooltip label="Edit code rule admin overlay">
                          <IconButton
                            aria-label="Edit code rule admin overlay"
                            size="xs"
                            variant="outline"
                            icon={<PencilSimple size={14} />}
                            onClick={() => openEdit(row)}
                          />
                        </Tooltip>
                      </Td>
                    </Tr>
                  ))
                )}
              </Tbody>
            </Table>
          </Box>
        </Box>
      </Container>

      <Drawer isOpen={isOpen} placement="right" onClose={onClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Code rule admin overlay</DrawerHeader>
          <DrawerBody>
            {selected && (
              <Flex direction="column" gap={4}>
                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    code_rule_key
                  </Text>
                  <Text fontFamily="mono" fontSize="sm" fontWeight="semibold">
                    {selected.code_rule_key}
                  </Text>
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    Applies to
                  </Text>
                  <Flex gap={2} wrap="wrap">
                    {(selected.upgrade_types || []).map((type) => (
                      <Tooltip key={type.id} label={type.description || type.upgrade_type_key}>
                        <Box>
                          <InvoiceUpgradeTypeTile
                            upgradeTypeKey={type.upgrade_type_key}
                            description={type.description}
                            size={34}
                          />
                        </Box>
                      </Tooltip>
                    ))}
                  </Flex>
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    enabled
                  </Text>
                  <Switch
                    isChecked={form.enabled}
                    onChange={(e) => setForm((prev) => ({ ...prev, enabled: e.target.checked }))}
                  />
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    description
                  </Text>
                  <Textarea
                    value={form.description}
                    onChange={(e) => setForm((prev) => ({ ...prev, description: e.target.value }))}
                    minH="90px"
                  />
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    source_quote
                  </Text>
                  <Textarea
                    value={form.source_quote}
                    onChange={(e) => setForm((prev) => ({ ...prev, source_quote: e.target.value }))}
                    minH="90px"
                  />
                </Box>

                <Box>
                  <Text fontSize="xs" opacity={0.7} mb={1}>
                    contractor_visible_flag
                  </Text>
                  <Switch
                    isChecked={form.contractor_visible_flag}
                    onChange={(e) => setForm((prev) => ({ ...prev, contractor_visible_flag: e.target.checked }))}
                  />
                </Box>

                {[
                  ['pass_admin_message', 'pass_admin_message'],
                  ['warn_admin_message', 'warn_admin_message'],
                  ['fail_admin_message', 'fail_admin_message'],
                  ['info_admin_message', 'info_admin_message'],
                  ['admin_notes', 'admin_notes'],
                ].map(([field, label]) => (
                  <Box key={field}>
                    <Text fontSize="xs" opacity={0.7} mb={1}>
                      {label}
                    </Text>
                    <Textarea
                      value={(form as any)[field]}
                      onChange={(e) => setForm((prev) => ({ ...prev, [field]: e.target.value }))}
                      minH={field === 'admin_notes' ? '90px' : '80px'}
                      placeholder={
                        field === 'admin_notes'
                          ? 'Internal admin notes about this code rule.'
                          : 'Optional simple guidance sentence appended to this result.'
                      }
                    />
                  </Box>
                ))}
              </Flex>
            )}
          </DrawerBody>
          <DrawerFooter>
            <Button variant="ghost" mr={3} onClick={onClose} isDisabled={saving}>
              Cancel
            </Button>
            <Button colorScheme="blue" onClick={saveSelected} isLoading={saving}>
              Save
            </Button>
          </DrawerFooter>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
