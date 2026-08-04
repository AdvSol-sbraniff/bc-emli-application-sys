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
import { getInvoiceUpgradeTypeMeta, InvoiceUpgradeTypeTile } from '../../shared/claims/invoice-upgrade-type-visual';

type RuleRecordType = 'code_rule' | 'genai_rule';
type AnyRecordType = RuleRecordType | 'code_located_field' | 'genai_located_field';

type UpgradeTypeRow = {
  id: string;
  upgrade_type_key: string;
  description?: string | null;
};

type MappingRow = {
  id?: string;
  invoice_upgrade_type_id: string;
};

type ValidationRuleRow = {
  id: string;
  record_type: AnyRecordType;
  record_key: string;
  enabled: boolean;
  updated_at?: string | null;
  created_at?: string | null;
  upgrade_types: UpgradeTypeRow[];
  detail: Record<string, any>;
  mappings: MappingRow[];
};

const RULE_TYPE_LABELS: Record<RuleRecordType, string> = {
  code_rule: 'Code',
  genai_rule: 'GenAI',
};

type RuleViewMode = 'sharing' | 'description' | 'workflow';
type ContractorVisibilityFilter = 'all' | 'hidden' | 'fail_only' | 'warn_and_fail';
type ContractorBlockingFilter = 'all' | 'non_blocking' | 'block_on_fail';
type AdminWorkflowFilter = 'all' | 'not_managed' | 'fail_only' | 'warn_and_fail' | 'all_results';

const ruleRowHoverSx = {
  td: {
    transition: 'background 140ms ease, border-color 140ms ease',
  },
  '&:hover td': {
    background: 'linear-gradient(90deg, rgba(49, 130, 206, 0.1) 0%, rgba(255, 255, 255, 0.96) 72%)',
  },
  '&:hover td:first-of-type': {
    borderLeftColor: 'blue.500',
  },
};

const fmtDate = (value?: string | null) => {
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

const isRuleRow = (row: ValidationRuleRow): row is ValidationRuleRow & { record_type: RuleRecordType } =>
  row.record_type === 'code_rule' || row.record_type === 'genai_rule';

const ruleDisplayName = (row: ValidationRuleRow) => {
  const configuredName = String(row.detail?.contractor_display_name || '').trim();
  if (configuredName) return configuredName;

  return row.record_key.replace(/_/g, ' ');
};

const contractorVisibilityLabel = (value?: string | null) => {
  switch (value) {
    case 'warn_and_fail':
      return 'Warnings + errors';
    case 'fail_only':
      return 'Errors only';
    case 'hidden':
      return 'Hidden';
    default:
      return 'Unknown';
  }
};

const contractorVisibilityColor = (value?: string | null) => {
  switch (value) {
    case 'warn_and_fail':
      return 'orange';
    case 'fail_only':
      return 'teal';
    case 'hidden':
      return 'gray';
    default:
      return 'gray';
  }
};

const contractorBlockingLabel = (value?: string | null) =>
  value === 'block_on_fail' ? 'Blocks on errors' : 'Non-blocking';

const contractorBlockingColor = (value?: string | null) => (value === 'block_on_fail' ? 'red' : 'gray');

const adminWorkflowLabel = (value?: string | null) => {
  switch (value) {
    case 'all_results':
      return 'All results';
    case 'warn_and_fail':
      return 'Warnings + errors';
    case 'not_managed':
      return 'Not managed';
    case 'fail_only':
      return 'Errors only';
    default:
      return 'Unknown';
  }
};

const adminWorkflowColor = (value?: string | null) => {
  switch (value) {
    case 'all_results':
      return 'purple';
    case 'warn_and_fail':
      return 'orange';
    case 'fail_only':
      return 'teal';
    case 'not_managed':
      return 'gray';
    default:
      return 'gray';
  }
};

export default function ValidationRulesAlphabeticAdminScreen() {
  const navigate = useNavigate();
  const infoDrawer = useDisclosure();
  const [upgradeTypes, setUpgradeTypes] = useState<UpgradeTypeRow[]>([]);
  const [rows, setRows] = useState<ValidationRuleRow[]>([]);
  const [selectedRow, setSelectedRow] = useState<ValidationRuleRow | null>(null);
  const [loadingUpgradeTypes, setLoadingUpgradeTypes] = useState(false);
  const [loadingRows, setLoadingRows] = useState(false);
  const [error, setError] = useState('');
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState<'all' | RuleRecordType>('all');
  const [upgradeFilterId, setUpgradeFilterId] = useState('all');
  const [listViewMode, setListViewMode] = useState<RuleViewMode>('sharing');
  const [contractorVisibilityFilter, setContractorVisibilityFilter] = useState<ContractorVisibilityFilter>('all');
  const [contractorBlockingFilter, setContractorBlockingFilter] = useState<ContractorBlockingFilter>('all');
  const [adminWorkflowFilter, setAdminWorkflowFilter] = useState<AdminWorkflowFilter>('all');

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
      const res = await fetch('/api/claims/admin/validation_rules', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });
      const data = await res.json().catch(() => ({ rows: [] }));
      if (!res.ok) throw new Error(data?.error || `HTTP ${res.status}`);
      setRows(Array.isArray(data?.rows) ? data.rows : []);
    } catch (e: any) {
      setRows([]);
      setError(e?.message || 'Failed to load validation rules.');
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
      .filter(isRuleRow)
      .filter((row) => {
        if (typeFilter !== 'all' && row.record_type !== typeFilter) return false;
        if (
          upgradeFilterId !== 'all' &&
          !row.mappings.some((mapping) => mapping.invoice_upgrade_type_id === upgradeFilterId)
        ) {
          return false;
        }
        if (contractorVisibilityFilter !== 'all' && row.detail?.contractor_visibility !== contractorVisibilityFilter) {
          return false;
        }
        if (contractorBlockingFilter !== 'all' && row.detail?.contractor_blocking_policy !== contractorBlockingFilter) {
          return false;
        }
        if (adminWorkflowFilter !== 'all' && row.detail?.admin_workflow_policy !== adminWorkflowFilter) {
          return false;
        }
        if (!normalizedQuery) return true;

        const haystack = [
          ruleDisplayName(row),
          row.record_key,
          RULE_TYPE_LABELS[row.record_type],
          row.detail?.description,
          row.detail?.prompt_text,
          contractorVisibilityLabel(row.detail?.contractor_visibility),
          contractorBlockingLabel(row.detail?.contractor_blocking_policy),
          adminWorkflowLabel(row.detail?.admin_workflow_policy),
          ...row.upgrade_types.map((upgradeType) => upgradeType.upgrade_type_key),
          ...row.upgrade_types.map((upgradeType) => upgradeType.description),
        ]
          .filter(Boolean)
          .join(' ')
          .toLowerCase();

        return haystack.includes(normalizedQuery);
      })
      .sort((a, b) => ruleDisplayName(a).localeCompare(ruleDisplayName(b)) || a.record_key.localeCompare(b.record_key));
  }, [
    adminWorkflowFilter,
    contractorBlockingFilter,
    contractorVisibilityFilter,
    query,
    rows,
    typeFilter,
    upgradeFilterId,
  ]);

  const mappedUpgradeTypeIds = useCallback(
    (row: ValidationRuleRow) => new Set(row.mappings.map((mapping) => mapping.invoice_upgrade_type_id)),
    [],
  );

  const editUpgradeTypeIdFor = useCallback(
    (row: ValidationRuleRow) => {
      const firstMapping = row.mappings[0]?.invoice_upgrade_type_id;
      if (firstMapping) return firstMapping;

      return (
        upgradeTypes.find((upgradeType) => upgradeType.upgrade_type_key === 'common')?.id || upgradeTypes[0]?.id || ''
      );
    },
    [upgradeTypes],
  );

  const openInfo = (row: ValidationRuleRow) => {
    setSelectedRow(row);
    infoDrawer.onOpen();
  };

  const openEdit = (row: ValidationRuleRow) => {
    const editUpgradeTypeId = editUpgradeTypeIdFor(row);
    if (!editUpgradeTypeId) return;

    navigate(
      `/validation-rules-admin?${new URLSearchParams({
        invoice_upgrade_type_id: editUpgradeTypeId,
        mode: 'edit',
        record_type: row.record_type,
        record_id: row.id,
      }).toString()}`,
    );
  };

  const promptOrDescription = selectedRow?.detail?.description || selectedRow?.detail?.prompt_text || '';

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <ThinBlueTitleBar title="Advice Checks at a Glance" />
      <Container maxW="container.2xl" pb={4} flex="1" pt={6}>
        <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="lg" p={5} bg="white">
          <Box w="full" maxW="1320px" mx="auto">
            <Flex justify="flex-end" align={{ base: 'start', lg: 'center' }} gap={4} mb={5} flexWrap="wrap">
              <Button colorScheme="blue" variant="outline" onClick={() => navigate('/validation-rules-admin')}>
                Fields and Advice Editor
              </Button>
            </Flex>

            <Flex gap={3} mb={4} direction={{ base: 'column', xl: 'row' }} flexWrap="wrap">
              <Input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Filter by advice check, rule key, prompt, description, or upgrade type"
                maxW={{ base: 'full', lg: '520px' }}
              />
              <Select
                value={typeFilter}
                onChange={(event) => setTypeFilter(event.target.value as 'all' | RuleRecordType)}
                maxW={{ base: 'full', lg: '180px' }}
              >
                <option value="all">All rule types</option>
                <option value="code_rule">Code rules</option>
                <option value="genai_rule">GenAI rules</option>
              </Select>
              <Select
                value={upgradeFilterId}
                onChange={(event) => setUpgradeFilterId(event.target.value)}
                maxW={{ base: 'full', lg: '280px' }}
              >
                <option value="all">All upgrade types</option>
                {upgradeTypes.map((upgradeType) => (
                  <option key={upgradeType.id} value={upgradeType.id}>
                    {upgradeType.description || upgradeType.upgrade_type_key}
                  </option>
                ))}
              </Select>
              <Select
                value={contractorVisibilityFilter}
                onChange={(event) => setContractorVisibilityFilter(event.target.value as ContractorVisibilityFilter)}
                maxW={{ base: 'full', lg: '230px' }}
              >
                <option value="all">All contractor visibility</option>
                <option value="hidden">Hidden from contractors</option>
                <option value="fail_only">Errors only</option>
                <option value="warn_and_fail">Warnings + errors</option>
              </Select>
              <Select
                value={contractorBlockingFilter}
                onChange={(event) => setContractorBlockingFilter(event.target.value as ContractorBlockingFilter)}
                maxW={{ base: 'full', lg: '210px' }}
              >
                <option value="all">All submission blocking</option>
                <option value="non_blocking">Non-blocking</option>
                <option value="block_on_fail">Blocks on errors</option>
              </Select>
              <Select
                value={adminWorkflowFilter}
                onChange={(event) => setAdminWorkflowFilter(event.target.value as AdminWorkflowFilter)}
                maxW={{ base: 'full', lg: '230px' }}
              >
                <option value="all">All admin workflow</option>
                <option value="not_managed">Not managed</option>
                <option value="fail_only">Errors only</option>
                <option value="warn_and_fail">Warnings + errors</option>
                <option value="all_results">All results</option>
              </Select>
            </Flex>

            <Flex justify="space-between" align={{ base: 'start', md: 'center' }} gap={3} mb={4} flexWrap="wrap">
              <RadioGroup value={listViewMode} onChange={(value) => setListViewMode(value as RuleViewMode)}>
                <HStack spacing={5}>
                  <Radio value="sharing" colorScheme="blue">
                    Sharing
                  </Radio>
                  <Radio value="description" colorScheme="blue">
                    Description
                  </Radio>
                  <Radio value="workflow" colorScheme="blue">
                    Workflow
                  </Radio>
                </HStack>
              </RadioGroup>
              {listViewMode === 'description' ? (
                <Text fontSize="sm" opacity={0.75}>
                  Preview shows the first 180 characters. Use the info icon for the full rule text.
                </Text>
              ) : null}
              {listViewMode === 'workflow' ? (
                <Text fontSize="sm" opacity={0.75}>
                  Workflow shows who sees each rule, whether failed rules block submission, and what admin tracks.
                </Text>
              ) : null}
            </Flex>

            {error ? (
              <Box mb={4} borderWidth="1px" borderColor="red.200" bg="red.50" color="red.700" borderRadius="md" p={3}>
                {error}
              </Box>
            ) : null}

            {loadingRows || loadingUpgradeTypes ? (
              <Flex py={10} justify="center">
                <Spinner />
              </Flex>
            ) : (
              <Box borderWidth="1px" borderColor="greys.grey20" borderRadius="md" overflowX="auto">
                {listViewMode === 'sharing' ? (
                  <Table size="sm" width="max-content">
                    <Thead bg="gray.50">
                      <Tr>
                        <Th position="sticky" left={0} zIndex={1} bg="gray.50" minW="480px" w="480px" maxW="480px">
                          Advice check
                        </Th>
                        <Th minW="56px" w="56px" maxW="56px" px={1}>
                          Type
                        </Th>
                        <Th minW="50px" w="50px" maxW="50px" px={1}>
                          On
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
                          <Tr key={`${row.record_type}-${row.id}`} sx={ruleRowHoverSx}>
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
                              minW="460px"
                              w="480px"
                              maxW="460px"
                            >
                              <Text fontWeight="semibold" fontSize="sm" lineHeight="short" overflowWrap="anywhere">
                                {ruleDisplayName(row)}
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
                            <Td py={0.5} px={1} minW="56px" w="56px" maxW="56px">
                              <Badge colorScheme={row.record_type === 'code_rule' ? 'green' : 'blue'} fontSize="2xs">
                                {RULE_TYPE_LABELS[row.record_type]}
                              </Badge>
                            </Td>
                            <Td py={0.5} px={1} minW="50px" w="50px" maxW="50px">
                              <Badge colorScheme={row.enabled ? 'green' : 'gray'} fontSize="2xs">
                                {row.enabled ? 'Y' : 'N'}
                              </Badge>
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
                                  label={`${ruleDisplayName(row)} (${row.record_key}) ${
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
                              <HStack justify="end" spacing={1}>
                                <Tooltip label="Advice check details">
                                  <IconButton
                                    aria-label="Advice check details"
                                    icon={<Info size={18} />}
                                    size="xs"
                                    variant="ghost"
                                    onClick={() => openInfo(row)}
                                  />
                                </Tooltip>
                                <Tooltip label="Edit in Fields and Advice Editor">
                                  <IconButton
                                    aria-label="Edit advice check"
                                    icon={<PencilSimple size={18} />}
                                    size="xs"
                                    variant="ghost"
                                    onClick={() => openEdit(row)}
                                  />
                                </Tooltip>
                              </HStack>
                            </Td>
                          </Tr>
                        );
                      })}
                      {filteredRows.length === 0 ? (
                        <Tr>
                          <Td colSpan={upgradeTypes.length + 4}>
                            <Text py={6} textAlign="center" opacity={0.7}>
                              No validation rules found.
                            </Text>
                          </Td>
                        </Tr>
                      ) : null}
                    </Tbody>
                  </Table>
                ) : listViewMode === 'workflow' ? (
                  <Table size="sm">
                    <Thead bg="gray.50">
                      <Tr>
                        <Th>Advice check</Th>
                        <Th minW="56px" w="56px" maxW="56px" px={1}>
                          Type
                        </Th>
                        <Th minW="50px" w="50px" maxW="50px" px={1}>
                          On
                        </Th>
                        <Th>Contractor visibility</Th>
                        <Th>Submission blocking</Th>
                        <Th>Admin workflow management</Th>
                        <Th>Upgrade types</Th>
                        <Th textAlign="right" minW="100px">
                          Actions
                        </Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {filteredRows.map((row) => (
                        <Tr key={`${row.record_type}-${row.id}`} sx={ruleRowHoverSx}>
                          <Td py={0.5} minW="360px" borderLeftWidth="3px" borderLeftColor="transparent">
                            <Text fontWeight="semibold" fontSize="sm" lineHeight="short" overflowWrap="anywhere">
                              {ruleDisplayName(row)}
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
                            <Badge colorScheme={row.record_type === 'code_rule' ? 'green' : 'blue'} fontSize="2xs">
                              {RULE_TYPE_LABELS[row.record_type]}
                            </Badge>
                          </Td>
                          <Td py={0.5} px={1}>
                            <Badge colorScheme={row.enabled ? 'green' : 'gray'} fontSize="2xs">
                              {row.enabled ? 'Y' : 'N'}
                            </Badge>
                          </Td>
                          <Td py={0.5} minW="170px">
                            <Badge
                              colorScheme={contractorVisibilityColor(row.detail?.contractor_visibility)}
                              fontSize="xs"
                            >
                              {contractorVisibilityLabel(row.detail?.contractor_visibility)}
                            </Badge>
                          </Td>
                          <Td py={0.5} minW="160px">
                            <Badge
                              colorScheme={contractorBlockingColor(row.detail?.contractor_blocking_policy)}
                              fontSize="xs"
                            >
                              {contractorBlockingLabel(row.detail?.contractor_blocking_policy)}
                            </Badge>
                          </Td>
                          <Td py={0.5} minW="190px">
                            <Badge colorScheme={adminWorkflowColor(row.detail?.admin_workflow_policy)} fontSize="xs">
                              {adminWorkflowLabel(row.detail?.admin_workflow_policy)}
                            </Badge>
                          </Td>
                          <Td py={0.5} minW="300px">
                            <Text fontSize="xs" lineHeight="short" opacity={0.8}>
                              {row.upgrade_types.map((upgradeType) => compactUpgradeLabel(upgradeType)).join(', ') ||
                                'No mappings'}
                            </Text>
                          </Td>
                          <Td textAlign="right" py={0.5}>
                            <HStack justify="end" spacing={1}>
                              <Tooltip label="Advice check details">
                                <IconButton
                                  aria-label="Advice check details"
                                  icon={<Info size={18} />}
                                  size="xs"
                                  variant="ghost"
                                  onClick={() => openInfo(row)}
                                />
                              </Tooltip>
                              <Tooltip label="Edit in Fields and Advice Editor">
                                <IconButton
                                  aria-label="Edit advice check"
                                  icon={<PencilSimple size={18} />}
                                  size="xs"
                                  variant="ghost"
                                  onClick={() => openEdit(row)}
                                />
                              </Tooltip>
                            </HStack>
                          </Td>
                        </Tr>
                      ))}
                      {filteredRows.length === 0 ? (
                        <Tr>
                          <Td colSpan={8}>
                            <Text py={6} textAlign="center" opacity={0.7}>
                              No validation rules found.
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
                        <Th>Advice check</Th>
                        <Th minW="56px" w="56px" maxW="56px" px={1}>
                          Type
                        </Th>
                        <Th minW="50px" w="50px" maxW="50px" px={1}>
                          On
                        </Th>
                        <Th>Upgrade types</Th>
                        <Th>Description / prompt preview</Th>
                        <Th textAlign="right" minW="100px">
                          Actions
                        </Th>
                      </Tr>
                    </Thead>
                    <Tbody>
                      {filteredRows.map((row) => (
                        <Tr key={`${row.record_type}-${row.id}`} sx={ruleRowHoverSx}>
                          <Td py={0.5} minW="360px" borderLeftWidth="3px" borderLeftColor="transparent">
                            <Text fontWeight="semibold" fontSize="sm" lineHeight="short" overflowWrap="anywhere">
                              {ruleDisplayName(row)}
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
                            <Badge colorScheme={row.record_type === 'code_rule' ? 'green' : 'blue'} fontSize="2xs">
                              {RULE_TYPE_LABELS[row.record_type]}
                            </Badge>
                          </Td>
                          <Td py={0.5} px={1}>
                            <Badge colorScheme={row.enabled ? 'green' : 'gray'} fontSize="2xs">
                              {row.enabled ? 'Y' : 'N'}
                            </Badge>
                          </Td>
                          <Td py={0.5} minW="260px">
                            <Text fontSize="xs" lineHeight="short" opacity={0.8}>
                              {row.upgrade_types.map((upgradeType) => compactUpgradeLabel(upgradeType)).join(', ') ||
                                'No mappings'}
                            </Text>
                          </Td>
                          <Td py={0.5} minW="420px">
                            <Text fontSize="sm" lineHeight="short" noOfLines={2}>
                              {previewText(row.detail?.description || row.detail?.prompt_text) || 'n/a'}
                            </Text>
                          </Td>
                          <Td textAlign="right" py={0.5}>
                            <HStack justify="end" spacing={1}>
                              <Tooltip label="Advice check details">
                                <IconButton
                                  aria-label="Advice check details"
                                  icon={<Info size={18} />}
                                  size="xs"
                                  variant="ghost"
                                  onClick={() => openInfo(row)}
                                />
                              </Tooltip>
                              <Tooltip label="Edit in Fields and Advice Editor">
                                <IconButton
                                  aria-label="Edit advice check"
                                  icon={<PencilSimple size={18} />}
                                  size="xs"
                                  variant="ghost"
                                  onClick={() => openEdit(row)}
                                />
                              </Tooltip>
                            </HStack>
                          </Td>
                        </Tr>
                      ))}
                      {filteredRows.length === 0 ? (
                        <Tr>
                          <Td colSpan={6}>
                            <Text py={6} textAlign="center" opacity={0.7}>
                              No validation rules found.
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
        </Box>
      </Container>

      <Drawer isOpen={infoDrawer.isOpen} placement="right" size="lg" onClose={infoDrawer.onClose}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Validation Rule Details</DrawerHeader>
          <DrawerBody>
            {selectedRow ? (
              <VStack align="stretch" spacing={4}>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Contractor-friendly name
                  </Text>
                  <Text fontWeight="bold">{selectedRow.detail?.contractor_display_name || 'n/a'}</Text>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7}>
                    Rule key
                  </Text>
                  <Text fontWeight="bold">{selectedRow.record_key}</Text>
                </Box>
                <HStack>
                  <Badge colorScheme={selectedRow.record_type === 'code_rule' ? 'green' : 'blue'}>
                    {RULE_TYPE_LABELS[selectedRow.record_type as RuleRecordType]}
                  </Badge>
                  <Badge colorScheme={selectedRow.enabled ? 'green' : 'gray'}>
                    {selectedRow.enabled ? 'Enabled' : 'Disabled'}
                  </Badge>
                  <Badge colorScheme={selectedRow.detail?.contractor_visibility === 'hidden' ? 'gray' : 'teal'}>
                    {selectedRow.detail?.contractor_visibility === 'warn_and_fail'
                      ? 'Warnings and errors visible'
                      : selectedRow.detail?.contractor_visibility === 'fail_only'
                        ? 'Errors visible'
                        : 'Hidden from contractors'}
                  </Badge>
                  <Badge
                    colorScheme={selectedRow.detail?.contractor_blocking_policy === 'block_on_fail' ? 'red' : 'gray'}
                  >
                    {selectedRow.detail?.contractor_blocking_policy === 'block_on_fail'
                      ? 'Errors block submission'
                      : 'Non-blocking'}
                  </Badge>
                  <Badge colorScheme={selectedRow.detail?.admin_workflow_policy === 'not_managed' ? 'gray' : 'purple'}>
                    {selectedRow.detail?.admin_workflow_policy === 'all_results'
                      ? 'Workflow-managed for all results'
                      : selectedRow.detail?.admin_workflow_policy === 'warn_and_fail'
                        ? 'Workflow-managed for warnings and errors'
                        : selectedRow.detail?.admin_workflow_policy === 'not_managed'
                          ? 'Not workflow-managed'
                          : 'Workflow-managed for errors only'}
                  </Badge>
                </HStack>
                <Box>
                  <Text fontSize="sm" opacity={0.7} mb={1}>
                    Source quote
                  </Text>
                  <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" p={3} bg="gray.50">
                    <Text as="i" fontSize="sm" whiteSpace="pre-wrap">
                      {selectedRow.detail?.source_quote || 'n/a'}
                    </Text>
                  </Box>
                </Box>
                <Box>
                  <Text fontSize="sm" opacity={0.7} mb={1}>
                    Description / prompt
                  </Text>
                  <Box borderWidth="1px" borderColor="gray.200" borderRadius="md" p={3} bg="gray.50">
                    <Text fontSize="sm" whiteSpace="pre-wrap">
                      {promptOrDescription || 'n/a'}
                    </Text>
                  </Box>
                </Box>
                {selectedRow.record_type === 'code_rule' ? (
                  <Box>
                    <Text fontSize="sm" opacity={0.7} mb={1}>
                      Admin messages
                    </Text>
                    {[
                      ['Pass', selectedRow.detail?.pass_admin_message],
                      ['Warn', selectedRow.detail?.warn_admin_message],
                      ['Fail', selectedRow.detail?.fail_admin_message],
                      ['Info', selectedRow.detail?.info_admin_message],
                      ['Notes', selectedRow.detail?.admin_notes],
                    ].map(([label, value]) => (
                      <Text key={label} fontSize="sm" mb={1}>
                        <Text as="span" fontWeight="semibold">
                          {label}:
                        </Text>{' '}
                        {value || 'n/a'}
                      </Text>
                    ))}
                  </Box>
                ) : null}
                <Box>
                  <Text fontSize="sm" opacity={0.7} mb={2}>
                    Mapped upgrade types
                  </Text>
                  <VStack align="stretch" spacing={2}>
                    {selectedRow.mappings.length === 0 ? (
                      <Text fontSize="sm">No mappings.</Text>
                    ) : (
                      selectedRow.mappings.map((mapping) => {
                        const upgradeType = upgradeTypeById.get(mapping.invoice_upgrade_type_id);
                        return (
                          <HStack key={mapping.id || mapping.invoice_upgrade_type_id} spacing={3}>
                            <InvoiceUpgradeTypeTile
                              upgradeTypeKey={upgradeType?.upgrade_type_key}
                              description={upgradeType?.description}
                              size={28}
                            />
                            <Text fontSize="sm">
                              {upgradeType?.description ||
                                upgradeType?.upgrade_type_key ||
                                mapping.invoice_upgrade_type_id}
                            </Text>
                          </HStack>
                        );
                      })
                    )}
                  </VStack>
                </Box>
                <Box>
                  <Text fontSize="sm">
                    <Text as="span" fontWeight="semibold">
                      Created:
                    </Text>{' '}
                    {fmtDate(selectedRow.created_at) || 'n/a'}
                  </Text>
                  <Text fontSize="sm">
                    <Text as="span" fontWeight="semibold">
                      Updated:
                    </Text>{' '}
                    {fmtDate(selectedRow.updated_at) || 'n/a'}
                  </Text>
                </Box>
                <Button leftIcon={<PencilSimple size={16} />} onClick={() => openEdit(selectedRow)}>
                  Edit in Fields and Advice Editor
                </Button>
              </VStack>
            ) : null}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Flex>
  );
}
