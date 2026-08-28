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
  Radio,
  RadioGroup,
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
  VStack,
  useDisclosure,
} from '@chakra-ui/react';
import { Info, PencilSimple } from '@phosphor-icons/react';
import { useNavigate } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { getInvoiceUpgradeTypeMeta } from '../../shared/claims/invoice-upgrade-type-visual';

type UpgradeTypeRow = {
  id: string;
  upgrade_type_key: string;
  description?: string | null;
};

type MappingRow = {
  id?: string;
  invoice_upgrade_type_id: string;
  field_number?: number | null;
};

type GenaiFieldRow = {
  id: string;
  record_type: 'genai_located_field';
  record_key: string;
  enabled: boolean;
  updated_at?: string | null;
  created_at?: string | null;
  upgrade_types: UpgradeTypeRow[];
  detail: {
    contractor_display_name?: string | null;
    prompt_text?: string | null;
  };
  mappings: MappingRow[];
};

type FieldViewMode = 'sharing' | 'description';
type EnabledFilter = 'all' | 'enabled' | 'disabled';

const rowHoverSx = {
  transition: 'background-color 120ms ease, box-shadow 120ms ease',
  _hover: {
    bg: 'blue.50',
    boxShadow: 'inset 3px 0 0 var(--chakra-colors-blue-500)',
  },
};

const formatDate = (value?: string | null) => {
  if (!value) return '';
  const str = String(value);
  return str.includes('T') ? str.split('T')[0] : str.slice(0, 10);
};

const previewText = (value?: string | null, maxLength = 180) => {
  const normalized = String(value || '')
    .replace(/\s+/g, ' ')
    .trim();
  if (!normalized) return '';
  if (normalized.length <= maxLength) return normalized;
  return `${normalized.slice(0, maxLength).trim()}...`;
};

const compactUpgradeLabel = (upgradeType: UpgradeTypeRow) => {
  if (upgradeType.upgrade_type_key === 'common') return 'common';

  return upgradeType.upgrade_type_key
    .replace(/^air_source_heat_pump_/, 'ashp_')
    .replace(/heat_pump/g, 'hp')
    .replace(/electrical_service_upgrade/, 'esu')
    .replace(/health_and_safety_remediation/, 'h&s')
    .replace(/windows_doors/, 'win_door')
    .replace(/_/g, ' ');
};

const fieldDisplayName = (row: GenaiFieldRow) => {
  const configuredName = String(row.detail?.contractor_display_name || '').trim();
  if (configuredName) return configuredName;
  return row.record_key.replace(/_/g, ' ');
};

const mappingCountLabel = (count: number) => {
  if (count === 0) return 'No upgrade mappings';
  if (count === 1) return '1 upgrade type';
  return `Shared across ${count} upgrade types`;
};

export default function ValidationFieldsAlphabeticAdminScreen() {
  const navigate = useNavigate();
  const infoDrawer = useDisclosure();
  const [upgradeTypes, setUpgradeTypes] = useState<UpgradeTypeRow[]>([]);
  const [rows, setRows] = useState<GenaiFieldRow[]>([]);
  const [selectedRow, setSelectedRow] = useState<GenaiFieldRow | null>(null);
  const [loadingUpgradeTypes, setLoadingUpgradeTypes] = useState(false);
  const [loadingRows, setLoadingRows] = useState(false);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [upgradeFilterId, setUpgradeFilterId] = useState('all');
  const [enabledFilter, setEnabledFilter] = useState<EnabledFilter>('all');
  const [listViewMode, setListViewMode] = useState<FieldViewMode>('description');

  const fetchUpgradeTypes = useCallback(async () => {
    setLoadingUpgradeTypes(true);
    try {
      const res = await fetch('/api/claims/admin/validation_rules/upgrade_types', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setUpgradeTypes(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setError(e?.message || 'Failed to load upgrade types.');
      setUpgradeTypes([]);
    } finally {
      setLoadingUpgradeTypes(false);
    }
  }, []);

  const fetchRows = useCallback(async () => {
    setLoadingRows(true);
    setError('');
    try {
      const params = new URLSearchParams({ record_type: 'genai_located_field' });
      const res = await fetch(`/api/claims/admin/validation_rules?${params.toString()}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setRows(
        (Array.isArray(data?.rows) ? data.rows : []).filter(
          (row: GenaiFieldRow) => row.record_type === 'genai_located_field',
        ),
      );
    } catch (e: any) {
      setError(e?.message || 'Failed to load GenAI fields.');
      setRows([]);
    } finally {
      setLoadingRows(false);
    }
  }, []);

  useEffect(() => {
    fetchUpgradeTypes();
    fetchRows();
  }, [fetchRows, fetchUpgradeTypes]);

  const upgradeTypeById = useMemo(
    () => new Map(upgradeTypes.map((upgradeType) => [upgradeType.id, upgradeType])),
    [upgradeTypes],
  );

  const filteredRows = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();

    return rows
      .filter((row) => {
        if (
          upgradeFilterId !== 'all' &&
          !row.mappings.some((mapping) => mapping.invoice_upgrade_type_id === upgradeFilterId)
        ) {
          return false;
        }
        if (enabledFilter === 'enabled' && !row.enabled) return false;
        if (enabledFilter === 'disabled' && row.enabled) return false;
        if (!normalizedQuery) return true;

        const searchableText = [
          row.record_key,
          row.detail?.contractor_display_name,
          row.detail?.prompt_text,
          ...row.upgrade_types.map((upgradeType) => upgradeType.upgrade_type_key),
          ...row.upgrade_types.map((upgradeType) => upgradeType.description),
        ]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();

        return searchableText.includes(normalizedQuery);
      })
      .sort((left, right) => left.record_key.localeCompare(right.record_key));
  }, [enabledFilter, query, rows, upgradeFilterId]);

  const mappedUpgradeTypeIds = useCallback(
    (row: GenaiFieldRow) => new Set(row.mappings.map((mapping) => mapping.invoice_upgrade_type_id)),
    [],
  );

  const editUpgradeTypeIdFor = useCallback(
    (row: GenaiFieldRow) => {
      if (
        upgradeFilterId !== 'all' &&
        row.mappings.some((mapping) => mapping.invoice_upgrade_type_id === upgradeFilterId)
      ) {
        return upgradeFilterId;
      }

      const commonUpgradeTypeId = upgradeTypes.find((upgradeType) => upgradeType.upgrade_type_key === 'common')?.id;
      if (
        commonUpgradeTypeId &&
        row.mappings.some((mapping) => mapping.invoice_upgrade_type_id === commonUpgradeTypeId)
      ) {
        return commonUpgradeTypeId;
      }

      return row.mappings[0]?.invoice_upgrade_type_id || commonUpgradeTypeId || upgradeTypes[0]?.id || '';
    },
    [upgradeFilterId, upgradeTypes],
  );

  const openInfo = (row: GenaiFieldRow) => {
    setSelectedRow(row);
    infoDrawer.onOpen();
  };

  const openEdit = (row: GenaiFieldRow) => {
    const editUpgradeTypeId = editUpgradeTypeIdFor(row);
    if (!editUpgradeTypeId) return;

    navigate(
      `/validation-rules-admin?${new URLSearchParams({
        invoice_upgrade_type_id: editUpgradeTypeId,
        mode: 'edit',
        record_type: 'genai_located_field',
        record_id: row.id,
      }).toString()}`,
    );
  };

  const renderActions = (row: GenaiFieldRow) => (
    <HStack justify="end" spacing={1}>
      <Tooltip label="Field details">
        <IconButton
          aria-label="Field details"
          icon={<Info size={18} />}
          size="xs"
          variant="ghost"
          onClick={() => openInfo(row)}
        />
      </Tooltip>
      <Tooltip label="Edit in Fields and Advice Editor">
        <IconButton
          aria-label="Edit GenAI field"
          icon={<PencilSimple size={18} />}
          size="xs"
          variant="ghost"
          onClick={() => openEdit(row)}
        />
      </Tooltip>
    </HStack>
  );

  const loading = loadingRows || loadingUpgradeTypes;

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="GenAI Fields at a Glance" />
      <Container maxW="container.2xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Flex justify="flex-end" align={{ base: 'start', lg: 'center' }} gap={3} mb={5} flexWrap="wrap">
            <Button colorScheme="blue" variant="outline" onClick={() => navigate('/validation-rules-alphabetic-admin')}>
              Advice Checks at a Glance
            </Button>
            <Button colorScheme="blue" variant="outline" onClick={() => navigate('/validation-rules-admin')}>
              Fields and Advice Editor
            </Button>
          </Flex>

          <Flex gap={3} mb={4} direction={{ base: 'column', lg: 'row' }} flexWrap="wrap">
            <Input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Filter by field name, key, prompt, or upgrade type"
              maxW={{ base: 'full', lg: '520px' }}
            />
            <Select
              value={upgradeFilterId}
              onChange={(event) => setUpgradeFilterId(event.target.value)}
              maxW={{ base: 'full', lg: '300px' }}
            >
              <option value="all">All upgrade types</option>
              {upgradeTypes.map((upgradeType) => (
                <option key={upgradeType.id} value={upgradeType.id}>
                  {upgradeType.description || upgradeType.upgrade_type_key}
                </option>
              ))}
            </Select>
            <Select
              value={enabledFilter}
              onChange={(event) => setEnabledFilter(event.target.value as EnabledFilter)}
              maxW={{ base: 'full', lg: '180px' }}
            >
              <option value="all">All statuses</option>
              <option value="enabled">Enabled</option>
              <option value="disabled">Disabled</option>
            </Select>
          </Flex>

          <Flex justify="space-between" align={{ base: 'start', md: 'center' }} gap={3} mb={4} flexWrap="wrap">
            <RadioGroup value={listViewMode} onChange={(value) => setListViewMode(value as FieldViewMode)}>
              <HStack spacing={5} flexWrap="wrap">
                <Radio value="sharing" colorScheme="blue">
                  Sharing
                </Radio>
                <Radio value="description" colorScheme="blue">
                  Description
                </Radio>
              </HStack>
            </RadioGroup>
            <Text fontSize="sm" opacity={0.75}>
              {listViewMode === 'sharing'
                ? 'Sharing shows exactly which upgrade types use each field.'
                : 'Description shows all mappings beside each field. Use the info icon for the full prompt.'}
            </Text>
          </Flex>

          {error ? (
            <Box bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md" p={3} mb={4}>
              <Text color="red.700">{error}</Text>
            </Box>
          ) : null}

          <Text fontSize="sm" opacity={0.7} mb={2}>
            {filteredRows.length} {filteredRows.length === 1 ? 'field' : 'fields'}
          </Text>

          {loading ? (
            <Flex py={10} justify="center">
              <Spinner />
            </Flex>
          ) : (
            <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflowX="auto">
              {listViewMode === 'sharing' ? (
                <Table size="sm" width="max-content">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th position="sticky" left={0} zIndex={1} bg="gray.50" minW="330px" w="330px" maxW="330px">
                        GenAI field
                      </Th>
                      <Th minW="50px" w="50px" maxW="50px" px={1}>
                        On
                      </Th>
                      <Th minW="260px" w="260px" maxW="260px">
                        Prompt preview
                      </Th>
                      {upgradeTypes.map((upgradeType) => {
                        const meta = getInvoiceUpgradeTypeMeta(upgradeType.upgrade_type_key, upgradeType.description);
                        return (
                          <Th
                            key={upgradeType.id}
                            textAlign="center"
                            minW="42px"
                            w="42px"
                            maxW="42px"
                            px={1}
                            py={2}
                            verticalAlign="bottom"
                            borderLeftWidth="1px"
                            borderLeftColor="gray.100"
                          >
                            <Tooltip label={upgradeType.description || meta.label}>
                              <Flex h="220px" align="center" justify="center">
                                <Text
                                  fontSize="xs"
                                  lineHeight="shorter"
                                  whiteSpace="nowrap"
                                  transform="rotate(-90deg)"
                                  transformOrigin="center"
                                  w="210px"
                                  textAlign="center"
                                >
                                  {compactUpgradeLabel(upgradeType)}
                                </Text>
                              </Flex>
                            </Tooltip>
                          </Th>
                        );
                      })}
                      <Th textAlign="right" minW="100px">
                        Actions
                      </Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {filteredRows.map((row) => {
                      const mappedIds = mappedUpgradeTypeIds(row);
                      return (
                        <Tr key={row.id} sx={rowHoverSx}>
                          <Td
                            position="sticky"
                            left={0}
                            zIndex={1}
                            bg="white"
                            borderLeftWidth="3px"
                            borderLeftColor="transparent"
                            borderRightWidth="1px"
                            borderColor="gray.100"
                            py={0.5}
                            minW="330px"
                            w="330px"
                            maxW="330px"
                          >
                            <Text fontWeight="semibold" fontSize="sm" lineHeight="short" overflowWrap="anywhere">
                              {fieldDisplayName(row)}
                            </Text>
                            <Text
                              fontFamily="mono"
                              fontSize="xs"
                              opacity={0.55}
                              lineHeight="short"
                              overflowWrap="anywhere"
                            >
                              {row.record_key}
                            </Text>
                          </Td>
                          <Td py={0.5} px={1}>
                            <Badge colorScheme={row.enabled ? 'green' : 'gray'} fontSize="2xs">
                              {row.enabled ? 'Y' : 'N'}
                            </Badge>
                          </Td>
                          <Td py={0.5} minW="260px" w="260px" maxW="260px">
                            <Text fontSize="xs" lineHeight="short" noOfLines={3}>
                              {previewText(row.detail?.prompt_text, 220) || 'n/a'}
                            </Text>
                          </Td>
                          {upgradeTypes.map((upgradeType) => (
                            <Td
                              key={upgradeType.id}
                              textAlign="center"
                              color={mappedIds.has(upgradeType.id) ? 'blue.700' : 'gray.300'}
                              fontWeight="bold"
                              borderLeftWidth="1px"
                              borderLeftColor="gray.100"
                              minW="42px"
                              w="42px"
                              maxW="42px"
                              px={1}
                              py={0.5}
                              lineHeight="short"
                            >
                              <Tooltip
                                label={`${fieldDisplayName(row)} (${row.record_key}) ${
                                  mappedIds.has(upgradeType.id) ? 'is mapped to' : 'is not mapped to'
                                } ${upgradeType.description || upgradeType.upgrade_type_key}`}
                                hasArrow
                              >
                                <Text as="span" display="inline-block" minW="18px">
                                  {mappedIds.has(upgradeType.id) ? 'X' : ''}
                                </Text>
                              </Tooltip>
                            </Td>
                          ))}
                          <Td textAlign="right" py={0.5}>
                            {renderActions(row)}
                          </Td>
                        </Tr>
                      );
                    })}
                    {filteredRows.length === 0 ? (
                      <Tr>
                        <Td colSpan={upgradeTypes.length + 4}>
                          <Text py={6} textAlign="center" opacity={0.7}>
                            No GenAI fields found.
                          </Text>
                        </Td>
                      </Tr>
                    ) : null}
                  </Tbody>
                </Table>
              ) : (
                <Table size="sm">
                  <Thead bg="gray.50">
                    <Tr>
                      <Th>GenAI field</Th>
                      <Th minW="50px" w="50px" maxW="50px" px={1}>
                        On
                      </Th>
                      <Th>Prompt preview</Th>
                      <Th textAlign="right" minW="100px">
                        Actions
                      </Th>
                    </Tr>
                  </Thead>
                  <Tbody>
                    {filteredRows.map((row) => (
                      <Tr key={row.id} sx={rowHoverSx}>
                        <Td py={0.5} minW="360px" borderLeftWidth="3px" borderLeftColor="transparent">
                          <Text fontWeight="semibold" fontSize="sm" lineHeight="short" overflowWrap="anywhere">
                            {fieldDisplayName(row)}
                          </Text>
                          <Text
                            fontFamily="mono"
                            fontSize="xs"
                            opacity={0.55}
                            lineHeight="short"
                            overflowWrap="anywhere"
                          >
                            {row.record_key}
                          </Text>
                        </Td>
                        <Td py={0.5} px={1}>
                          <Badge colorScheme={row.enabled ? 'green' : 'gray'} fontSize="2xs">
                            {row.enabled ? 'Y' : 'N'}
                          </Badge>
                        </Td>
                        <Td py={2} minW="720px">
                          <Text fontSize="sm" lineHeight="base" noOfLines={6}>
                            {previewText(row.detail?.prompt_text, 1200) || 'n/a'}
                          </Text>
                        </Td>
                        <Td textAlign="right" py={0.5}>
                          {renderActions(row)}
                        </Td>
                      </Tr>
                    ))}
                    {filteredRows.length === 0 ? (
                      <Tr>
                        <Td colSpan={4}>
                          <Text py={6} textAlign="center" opacity={0.7}>
                            No GenAI fields found.
                          </Text>
                        </Td>
                      </Tr>
                    ) : null}
                  </Tbody>
                </Table>
              )}
            </Box>
          )}
        </Box>
      </Container>

      <Drawer isOpen={infoDrawer.isOpen} placement="right" size="lg" onClose={infoDrawer.onClose}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>GenAI Field Details</DrawerHeader>
          <DrawerBody>
            {selectedRow ? (
              <VStack align="stretch" spacing={4}>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Display name
                  </Text>
                  <Text fontWeight="bold">{fieldDisplayName(selectedRow)}</Text>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Field key
                  </Text>
                  <Text fontWeight="bold" fontFamily="mono">
                    {selectedRow.record_key}
                  </Text>
                </Box>
                <HStack flexWrap="wrap">
                  <Badge colorScheme="blue">GenAI field</Badge>
                  <Badge colorScheme={selectedRow.enabled ? 'green' : 'gray'}>
                    {selectedRow.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                  <Badge colorScheme={selectedRow.upgrade_types.length > 1 ? 'blue' : 'gray'}>
                    {mappingCountLabel(selectedRow.upgrade_types.length)}
                  </Badge>
                </HStack>
                <Box>
                  <Text fontSize="sm" opacity={0.7} mb={1}>
                    Full location prompt
                  </Text>
                  <Text whiteSpace="pre-wrap">{selectedRow.detail?.prompt_text || 'n/a'}</Text>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7} mb={2}>
                    Upgrade mappings and prompt positions
                  </Text>
                  <Table size="sm" variant="simple">
                    <Thead>
                      <Tr>
                        <Th px={0}>Upgrade type</Th>
                        <Th px={0} textAlign="right">
                          Position
                        </Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {selectedRow.mappings
                        .map((mapping) => ({
                          mapping,
                          upgradeType: upgradeTypeById.get(mapping.invoice_upgrade_type_id),
                        }))
                        .sort((left, right) =>
                          (left.upgradeType?.upgrade_type_key || '').localeCompare(
                            right.upgradeType?.upgrade_type_key || '',
                          ),
                        )
                        .map(({ mapping, upgradeType }) => (
                          <Tr key={mapping.id || mapping.invoice_upgrade_type_id}>
                            <Td px={0}>
                              {upgradeType?.description || upgradeType?.upgrade_type_key || 'Unknown upgrade type'}
                            </Td>
                            <Td px={0} textAlign="right">
                              {mapping.field_number ?? 'n/a'}
                            </Td>
                          </Tr>
                        ))}
                      {selectedRow.mappings.length === 0 ? (
                        <Tr>
                          <Td px={0} colSpan={2}>
                            No upgrade mappings
                          </Td>
                        </Tr>
                      ) : null}
                    </Tbody>
                  </Table>
                </Box>
                <HStack spacing={8}>
                  <Box>
                    <Text fontSize="sm" opacity={0.7}>
                      Created
                    </Text>
                    <Text>{formatDate(selectedRow.created_at) || 'n/a'}</Text>
                  </Box>
                  <Box>
                    <Text fontSize="sm" opacity={0.7}>
                      Updated
                    </Text>
                    <Text>{formatDate(selectedRow.updated_at) || 'n/a'}</Text>
                  </Box>
                </HStack>
              </VStack>
            ) : null}
          </DrawerBody>
          <DrawerFooter>
            <Button variant="outline" mr={3} onClick={infoDrawer.onClose}>
              Close
            </Button>
            <Button
              colorScheme="blue"
              leftIcon={<PencilSimple size={18} />}
              onClick={() => selectedRow && openEdit(selectedRow)}
              isDisabled={!selectedRow}
            >
              Edit field
            </Button>
          </DrawerFooter>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
