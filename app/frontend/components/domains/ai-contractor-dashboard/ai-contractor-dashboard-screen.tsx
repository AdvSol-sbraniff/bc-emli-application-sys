import {
  Box,
  Container,
  Flex,
  FormControl,
  FormLabel,
  Hide,
  IconButton,
  Input,
  Select,
  Show,
  Spacer,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
  Tooltip,
} from '@chakra-ui/react';
import { PencilIcon, XCircle } from '@phosphor-icons/react';
import { observer } from 'mobx-react-lite';
import React, { useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Link as ReactRouterLink } from 'react-router-dom';
import { useMst, useServerAPI } from '../../../setup/root';
import { getRuntimeBooleanMetaValue } from '../../../utils/utility-functions';
import { PerPageSelect } from '../../shared/base/inputs/per-page-select';
import { Paginator } from '../../shared/base/inputs/paginator';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { INVOICE_STATUS_FILTER_GROUPS, invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';
import { GreenLineSmall } from '../../shared/base/decorative/green-line-small';
import { SharedSpinner } from '../../shared/base/shared-spinner';
import { RouterLinkButton } from '../../shared/navigation/router-link-button';
import { MultiCheckSelect } from '../../shared/select/multi-check-select';
import { ContractorProgramResourcesScreen } from '../contractor-management/contractor-program-resources-screen';

type ContractorPortalRow = {
  invoiceId: string;
  sessionId: string;
  status: string;
  statusSubtype?: string | null;
  statusUpdatedAt?: string | null;
  systemHelpNotes?: string | null;
  invoiceCreatedAt?: string | null;
  invoiceUpdatedAt?: string | null;
  invoiceSubmittedAt?: string | null;
  submitted: boolean;
  latestInvoiceVersionId?: string | null;
  latestInvoiceVersionno?: number | null;
  latestOriginalFilename?: string | null;
  latestInvoiceVersionUpdatedAt?: string | null;
  latestDiOcrInvoiceId?: string | null;
  latestDiOcrInvoiceDate?: string | null;
  latestDiOcrInvoiceTotal?: number | string | null;
  latestDiOcrVendorName?: string | null;
  latestDiOcrCustomerName?: string | null;
  latestDetectedUpgradeTypeKeys?: string[] | null;
};

type ContractorPortalResponse = {
  contractor?: {
    id: string;
    businessName?: string | null;
    number?: string | null;
  };
  rows?: ContractorPortalRow[];
  error?: string;
};

function formatTimestamp(value?: string | null) {
  if (!value) return '—';

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return String(value);

  return date.toLocaleDateString(undefined, {
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });
}

function formatMoney(value?: number | string | null) {
  if (value === null || value === undefined || value === '') return '';
  const n = Number(value);
  if (Number.isNaN(n)) return String(value);
  return n.toLocaleString(undefined, { style: 'currency', currency: 'CAD' });
}

function contractorStatusLabel(status?: string | null, statusSubtype?: string | null) {
  return invoiceStatusCopy(status, statusSubtype).label;
}

const contractorStatusFilterOptions = INVOICE_STATUS_FILTER_GROUPS.map((group) => ({
  label: group.label,
  value: group.statuses.join(','),
}));

const DEFAULT_CONTRACTOR_STATUS_FILTER = 'genai_complete,contractor_revision_inbox';

const selectedStatusGroupValuesFor = (statusFilter: string) => {
  const selectedStatuses = new Set(
    statusFilter
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
  );

  if (!selectedStatuses.size) return [];

  return contractorStatusFilterOptions
    .filter((option) => option.value.split(',').every((status) => selectedStatuses.has(status)))
    .map((option) => option.value);
};

const statusFilterFromGroupValues = (values: string[]) =>
  Array.from(
    new Set(
      values
        .flatMap((value) => value.split(','))
        .map((value) => value.trim())
        .filter(Boolean),
    ),
  ).join(',');

const statusMatchesFilter = (status: string, filter: string) => {
  if (!filter) return true;
  return filter
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean)
    .includes(status);
};

function sortRows(rows: ContractorPortalRow[], sort: string) {
  const sorted = [...rows];

  sorted.sort((left, right) => {
    const leftUpdated = left.statusUpdatedAt || left.latestInvoiceVersionUpdatedAt || '';
    const rightUpdated = right.statusUpdatedAt || right.latestInvoiceVersionUpdatedAt || '';

    switch (sort) {
      case 'created_at:asc':
        return String(left.invoiceCreatedAt || '').localeCompare(String(right.invoiceCreatedAt || ''));
      case 'created_at:desc':
        return String(right.invoiceCreatedAt || '').localeCompare(String(left.invoiceCreatedAt || ''));
      case 'filename:asc':
        return String(left.latestOriginalFilename || left.invoiceId).localeCompare(
          String(right.latestOriginalFilename || right.invoiceId),
        );
      case 'filename:desc':
        return String(right.latestOriginalFilename || right.invoiceId).localeCompare(
          String(left.latestOriginalFilename || left.invoiceId),
        );
      case 'status:asc':
        return contractorStatusLabel(left.status, left.statusSubtype).localeCompare(
          contractorStatusLabel(right.status, right.statusSubtype),
        );
      case 'status:desc':
        return contractorStatusLabel(right.status, right.statusSubtype).localeCompare(
          contractorStatusLabel(left.status, left.statusSubtype),
        );
      case 'updated_at:asc':
        return String(leftUpdated).localeCompare(String(rightUpdated));
      case 'updated_at:desc':
      default:
        return String(rightUpdated).localeCompare(String(leftUpdated));
    }
  });

  return sorted;
}

function AiContractorInvoiceCard({ row }: { row: ContractorPortalRow }) {
  const title = row.latestOriginalFilename || `Invoice ${row.invoiceId.slice(0, 8)}`;
  const statusCopy = invoiceStatusCopy(row.status, row.statusSubtype);
  const statusHint = `${statusCopy.hint} Technical status: ${row.status || 'unknown'}.`;
  const ocrFacts = [
    row.latestDiOcrInvoiceId ? ['Invoice #', row.latestDiOcrInvoiceId] : null,
    row.latestDiOcrCustomerName ? ['Customer', row.latestDiOcrCustomerName] : null,
    row.latestDiOcrInvoiceDate ? ['Invoice date', formatTimestamp(row.latestDiOcrInvoiceDate)] : null,
    row.latestDiOcrInvoiceTotal ? ['Invoice total', formatMoney(row.latestDiOcrInvoiceTotal)] : null,
  ].filter(Boolean) as Array<[string, string]>;

  return (
    <Flex
      direction="column"
      borderRadius="lg"
      border="1px solid"
      borderColor="border.light"
      p={8}
      align="center"
      gap={4}
      position="relative"
      bg="greys.white"
    >
      <Flex flexDirection={{ base: 'column', md: 'row' }} gap={6} w="full">
        <Flex direction="column" gap={2} flex="1" maxW="100%">
          <Flex direction="column" flex={1} gap={2}>
            <Text color="text.link" fontSize="lg" fontWeight="bold">
              {title}
            </Text>

            <Box flex="1" alignContent="center">
              <GreenLineSmall />
            </Box>

            {ocrFacts.length ? (
              <Flex gap={3} wrap="wrap">
                {ocrFacts.map(([label, value]) => (
                  <Box key={`${row.invoiceId}-${label}`} minW="130px">
                    <Text fontSize="xs" color="greys.grey01" fontWeight="bold" textTransform="uppercase">
                      {label}
                    </Text>
                    <Text fontSize="sm">{value}</Text>
                  </Box>
                ))}
              </Flex>
            ) : null}

            <Flex gap={4} flex="1" alignItems="end" wrap="wrap">
              <Text>
                Started on:
                <Text as="span"> </Text>
                <Show below="md">
                  <br />
                </Show>
                {formatTimestamp(row.invoiceCreatedAt)}
              </Text>
              <Hide below="md">
                <Text>{'  |  '}</Text>
              </Hide>
              <Show below="sm">
                <Spacer />
              </Show>
              <Text>
                Last updated:
                <Text as="span"> </Text>
                <Show below="md">
                  <br />
                </Show>
                {formatTimestamp(row.latestInvoiceVersionUpdatedAt)}
              </Text>
              {row.invoiceSubmittedAt ? (
                <>
                  <Show below="sm">
                    <Spacer />
                  </Show>
                  <Text>
                    Submitted:
                    <Text as="span"> </Text>
                    <Show below="md">
                      <br />
                    </Show>
                    {formatTimestamp(row.invoiceSubmittedAt)}
                  </Text>
                </>
              ) : null}
            </Flex>

            {row.systemHelpNotes ? (
              <Text fontSize="sm" color="greys.grey01">
                {row.systemHelpNotes}
              </Text>
            ) : null}
          </Flex>
        </Flex>

        <Flex direction="column" align={{ base: 'flex-start', md: 'flex-end' }} gap={4} flexShrink={0}>
          <Tooltip label={statusHint}>
            <Text fontSize="sm" fontWeight="semibold" color="gray.700">
              {contractorStatusLabel(row.status, row.statusSubtype)}
            </Text>
          </Tooltip>

          <Tooltip label="Edit or view" hasArrow>
            <IconButton
              as={ReactRouterLink}
              to={`/contractor/sessions/${row.sessionId}/invoices/${row.invoiceId}/review?source=portal`}
              aria-label={`Edit or view invoice submission for ${title}`}
              icon={<PencilIcon size={20} />}
              variant="outline"
              borderRadius="full"
            />
          </Tooltip>
        </Flex>
      </Flex>
    </Flex>
  );
}

export const AiContractorDashboardScreen = observer(function AiContractorDashboardScreen() {
  const SUBMIT_INVOICE_ENABLED = getRuntimeBooleanMetaValue('submit-invoice-enabled', true);

  const { t } = useTranslation();
  const { userStore } = useMst();
  const api = useServerAPI();
  const currentUser = userStore.currentUser;
  const [tabIndex, setTabIndex] = useState(0);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState('');
  const [rows, setRows] = useState<ContractorPortalRow[]>([]);
  const [query, setQuery] = useState('');
  const [statusFilter, setStatusFilter] = useState(DEFAULT_CONTRACTOR_STATUS_FILTER);
  const [sort, setSort] = useState('updated_at:desc');
  const [currentPage, setCurrentPage] = useState(1);
  const [countPerPage, setCountPerPage] = useState(10);

  const isSubmitInvoiceDisabled =
    !SUBMIT_INVOICE_ENABLED || currentUser?.contractorSuspended || currentUser?.contractorAccessBlocked;

  useEffect(() => {
    let cancelled = false;

    const load = async () => {
      setIsLoading(true);
      setError('');

      const response = await api.fetchClaimsContractorInvoices();
      const payload = (response.data || {}) as ContractorPortalResponse;

      if (cancelled) return;

      if (!response.ok) {
        setRows([]);
        setError(payload.error || 'Unable to load AI invoice submissions.');
        setIsLoading(false);
        return;
      }

      setRows(Array.isArray(payload.rows) ? payload.rows : []);
      setIsLoading(false);
    };

    load();

    return () => {
      cancelled = true;
    };
  }, [api]);

  useEffect(() => {
    setCurrentPage(1);
  }, [countPerPage, query, sort, statusFilter]);

  const filteredRows = useMemo(() => {
    const normalizedQuery = query.trim().toLowerCase();

    const scopedRows = rows.filter((row) => {
      if (!statusMatchesFilter(row.status, statusFilter)) return false;

      if (!normalizedQuery) return true;

      const haystack = [
        row.latestOriginalFilename,
        row.invoiceId,
        row.sessionId,
        row.status,
        contractorStatusLabel(row.status),
        row.latestDiOcrInvoiceId,
        row.latestDiOcrCustomerName,
        row.latestDiOcrVendorName,
        ...(row.latestDetectedUpgradeTypeKeys || []),
      ]
        .filter(Boolean)
        .join(' ')
        .toLowerCase();

      return haystack.includes(normalizedQuery);
    });

    return sortRows(scopedRows, sort);
  }, [query, rows, sort, statusFilter]);

  const totalCount = filteredRows.length;
  const totalPages = Math.max(1, Math.ceil(totalCount / countPerPage));
  const pagedRows = filteredRows.slice((currentPage - 1) * countPerPage, currentPage * countPerPage);
  const selectedStatusGroupValues = useMemo(() => selectedStatusGroupValuesFor(statusFilter), [statusFilter]);

  const selectedTabStyles = {
    color: 'theme.blueAlt',
    borderBottomColor: 'theme.blueAlt',
    borderBottomWidth: '3px',
    fontWeight: 'bold',
  };

  return (
    <Flex as="main" direction="column" w="full" bg="greys.white" pb="24" minH="100vh">
      <BlueTitleBar title="AI contractor portal" />

      <Container maxW="container.lg" pb={4} flex="1">
        <Tabs
          index={tabIndex}
          onChange={setTabIndex}
          variant="unstyled"
          w="full"
          pt={6}
          h="full"
          display="flex"
          flexDirection="column"
        >
          <TabList borderBottom="2px solid" borderColor="greys.grey20">
            <Tab
              px={4}
              py={2}
              _selected={selectedTabStyles}
              _focus={{
                outline: 'none',
                boxShadow: 'none',
              }}
              _focusVisible={{
                outline: '2px solid',
                outlineColor: 'theme.blue',
                outlineOffset: '2px',
              }}
            >
              {t('landing.contractor.dashboard.invoiceSubmission', 'Invoice submissions')}
            </Tab>
            <Box px={2} py={2} color="greys.dividerGrey">
              |
            </Box>
            <Tab
              px={4}
              py={2}
              _selected={selectedTabStyles}
              _focus={{
                outline: 'none',
                boxShadow: 'none',
              }}
              _focusVisible={{
                outline: '2px solid',
                outlineColor: 'theme.blue',
                outlineOffset: '2px',
              }}
            >
              {t('landing.contractor.dashboard.programResources', 'Program resources')}
            </Tab>
          </TabList>

          <TabPanels flex="1" minH="500px">
            <TabPanel px={0} pt={0} h="full">
              <Flex as="section" direction="column" p={6} gap={6} flex={1}>
                <Flex
                  gap={6}
                  align={{ base: 'flex-start', md: 'flex-end' }}
                  justify="space-between"
                  direction={{ base: 'column', md: 'row' }}
                >
                  <RouterLinkButton
                    to={'/contractor/upload-invoices'}
                    variant="primary"
                    w={{ base: 'full', md: 'fit-content' }}
                    aria-label={
                      isSubmitInvoiceDisabled
                        ? t('contractor.suspended.buttonDisabled')
                        : 'Upload invoice PDFs for AI review'
                    }
                    isDisabled={isSubmitInvoiceDisabled}
                  >
                    Upload invoice(s)
                  </RouterLinkButton>

                  <Flex
                    align={{ md: 'end' }}
                    gap={4}
                    direction={{ base: 'column', md: 'row' }}
                    w={{ base: 'full', md: 'fit-content' }}
                  >
                    <Flex direction={{ base: 'column', md: 'row' }} alignItems={{ md: 'end', base: 'stretch' }} gap={4}>
                      <FormControl flex={1}>
                        <FormLabel>{t('ui.search')}</FormLabel>
                        <Box minW={{ md: 250, base: '100%' }}>
                          <Input
                            value={query}
                            onChange={(event) => setQuery(event.target.value)}
                            placeholder="Search invoices..."
                            bg="white"
                          />
                        </Box>
                      </FormControl>

                      <FormControl w={{ base: 'full', md: '280px' }}>
                        <FormLabel>Status</FormLabel>
                        <MultiCheckSelect
                          selectedValues={selectedStatusGroupValues}
                          setSelectedValues={(values) => setStatusFilter(statusFilterFromGroupValues(values))}
                          allItems={contractorStatusFilterOptions}
                          placeholder="All statuses"
                          menuListMinW="360px"
                        />
                      </FormControl>

                      <FormControl w={{ base: 'full', md: '220px' }}>
                        <FormLabel>Sort</FormLabel>
                        <Select value={sort} onChange={(event) => setSort(event.target.value)} bg="white">
                          <option value="updated_at:desc">updated desc</option>
                          <option value="updated_at:asc">updated asc</option>
                          <option value="created_at:desc">created desc</option>
                          <option value="created_at:asc">created asc</option>
                          <option value="filename:asc">filename A-Z</option>
                          <option value="filename:desc">filename Z-A</option>
                          <option value="status:asc">status A-Z</option>
                          <option value="status:desc">status Z-A</option>
                        </Select>
                      </FormControl>

                      {(query || statusFilter !== DEFAULT_CONTRACTOR_STATUS_FILTER || sort !== 'updated_at:desc') && (
                        <Tooltip label="Clear filters">
                          <IconButton
                            aria-label="Clear filters"
                            icon={<XCircle size={18} />}
                            variant="outline"
                            mb={{ base: 0, md: 2 }}
                            onClick={() => {
                              setQuery('');
                              setStatusFilter(DEFAULT_CONTRACTOR_STATUS_FILTER);
                              setSort('updated_at:desc');
                            }}
                          />
                        </Tooltip>
                      )}
                    </Flex>
                  </Flex>
                </Flex>

                {isLoading ? (
                  <Flex py="50" w="full">
                    <SharedSpinner h={50} w={50} />
                  </Flex>
                ) : error ? (
                  <Box p={3} bg="red.50" borderWidth="1px" borderColor="red.200" borderRadius="md">
                    <Text as="div" fontSize="sm" color="red.700">
                      {error}
                    </Text>
                  </Box>
                ) : pagedRows.length === 0 ? (
                  <Flex direction="column" w="full">
                    <Box borderBottom="2px solid" borderColor="greys.lightGrey" mt={4} />
                    <Flex py="10" w="full" justify="center" role="status" aria-live="polite">
                      {rows.length === 0 ? 'No AI invoice submissions yet.' : 'No results match the current filters.'}
                    </Flex>
                  </Flex>
                ) : (
                  pagedRows.map((row) => <AiContractorInvoiceCard key={row.invoiceId} row={row} />)
                )}
              </Flex>

              <Flex px={6} justify="space-between">
                <PerPageSelect
                  handleCountPerPageChange={(value) => setCountPerPage(value)}
                  countPerPage={countPerPage}
                  totalCount={totalCount}
                />
                <Paginator
                  current={currentPage}
                  total={totalCount}
                  totalPages={totalPages}
                  pageSize={countPerPage}
                  handlePageChange={setCurrentPage}
                  showLessItems={true}
                />
              </Flex>
            </TabPanel>

            <TabPanel px={0} pt={0} h="full">
              <ContractorProgramResourcesScreen hideBlueSection />
            </TabPanel>
          </TabPanels>
        </Tabs>
      </Container>
    </Flex>
  );
});
