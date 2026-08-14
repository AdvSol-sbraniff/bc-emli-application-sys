import {
  Badge,
  Box,
  Button,
  Container,
  Flex,
  FormControl,
  FormLabel,
  Hide,
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
import { observer } from 'mobx-react-lite';
import { ChatDots } from '@phosphor-icons/react';
import React, { useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useMst, useServerAPI } from '../../../setup/root';
import { formatClaimsReferenceNumber } from '../../../utils/format-claims-reference-number';
import { getRuntimeBooleanMetaValue } from '../../../utils/utility-functions';
import { PerPageSelect } from '../../shared/base/inputs/per-page-select';
import { Paginator } from '../../shared/base/inputs/paginator';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { INVOICE_STATUS_FILTER_GROUPS, invoiceStatusCopy } from '../../shared/claims/invoice-status-copy';
import { InvoiceStatusBadge } from '../../shared/claims/invoice-status-badge';
import { GreenLineSmall } from '../../shared/base/decorative/green-line-small';
import { SharedSpinner } from '../../shared/base/shared-spinner';
import { RouterLinkButton } from '../../shared/navigation/router-link-button';
import { MultiCheckSelect } from '../../shared/select/multi-check-select';
import { ContractorProgramResourcesScreen } from '../contractor-management/contractor-program-resources-screen';

type ContractorPortalRow = {
  invoiceId: string;
  unreadMessageCount?: number;
  referenceNumber: number | string;
  sessionId: string;
  status: string;
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
  latestDiOcrCustomerAddress?: string | null;
  submitterName?: string | null;
  latestDetectedUpgradeTypeKeys?: string[] | null;
  latestIngestRunId?: string | null;
  latestIngestRunKind?: string | null;
  latestIngestRunStatus?: string | null;
  latestIngestFailureCategory?: string | null;
  latestIngestFailureCode?: string | null;
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

function contractorStatusLabel(status?: string | null) {
  return invoiceStatusCopy(status).label;
}

function contractorInvoicePresentation(row: ContractorPortalRow) {
  const runStatus = String(row.latestIngestRunStatus || '').trim();
  if (runStatus === 'queued' || runStatus === 'running') {
    return {
      label: 'Preparing AI Advice',
      hint: 'Your uploaded package is still being processed.',
      visualStatus: 'preparing_ai_advice',
    };
  }
  if (runStatus === 'failed' && row.latestIngestFailureCategory === 'package_needs_correction') {
    return {
      label: 'Package Needs Correction',
      hint: 'The latest upload needs a package correction.',
      visualStatus: 'package_needs_correction',
    };
  }
  if (runStatus === 'failed') {
    return {
      label: 'Needs Technical Help',
      hint: 'A service error stopped the latest processing run.',
      visualStatus: 'needs_technical_help',
    };
  }
  return { ...invoiceStatusCopy(row.status), visualStatus: row.status };
}

function lastUpdatedAt(row: ContractorPortalRow) {
  return row.statusUpdatedAt || row.latestInvoiceVersionUpdatedAt || row.invoiceUpdatedAt || row.invoiceCreatedAt || '';
}

const ALL_STATUSES_FILTER_VALUE = '__all_statuses__';
const contractorStatusFilterOptions = [
  { label: 'All statuses', value: ALL_STATUSES_FILTER_VALUE },
  ...INVOICE_STATUS_FILTER_GROUPS.map((group) => ({
    label: group.label,
    value: group.statuses.join(','),
  })),
];

const DEFAULT_CONTRACTOR_STATUS_FILTER = '';

const STATUS_COMPLETION_RANK: Record<string, number> = {
  approved_paid: 0,
  ineligible: 0,
  contractor_withdrawn: 0,
  approved_pending: 1,
  in_review: 2,
  contractor_revision_inbox: 3,
  admin_review_inbox: 4,
  contractor_precheck: 5,
};

const selectedStatusGroupValuesFor = (statusFilter: string) => {
  const selectedStatuses = new Set(
    statusFilter
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
  );

  if (!selectedStatuses.size) return [ALL_STATUSES_FILTER_VALUE];

  return contractorStatusFilterOptions
    .filter(
      (option) =>
        option.value !== ALL_STATUSES_FILTER_VALUE &&
        option.value.split(',').every((status) => selectedStatuses.has(status)),
    )
    .map((option) => option.value);
};

const statusFilterFromGroupValues = (values: string[]) => {
  if (!values.length || values[values.length - 1] === ALL_STATUSES_FILTER_VALUE) return '';

  return Array.from(
    new Set(
      values
        .filter((value) => value !== ALL_STATUSES_FILTER_VALUE)
        .flatMap((value) => value.split(','))
        .map((value) => value.trim())
        .filter(Boolean),
    ),
  ).join(',');
};

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
    const leftUpdated = lastUpdatedAt(left);
    const rightUpdated = lastUpdatedAt(right);
    const leftCompletionRank = STATUS_COMPLETION_RANK[left.status];
    const rightCompletionRank = STATUS_COMPLETION_RANK[right.status];
    const leftRankKnown = leftCompletionRank !== undefined;
    const rightRankKnown = rightCompletionRank !== undefined;

    switch (sort) {
      case 'status_completion:most':
      case 'status_completion:least': {
        if (leftRankKnown !== rightRankKnown) return leftRankKnown ? -1 : 1;

        if (leftRankKnown && rightRankKnown && leftCompletionRank !== rightCompletionRank) {
          return sort === 'status_completion:most'
            ? leftCompletionRank - rightCompletionRank
            : rightCompletionRank - leftCompletionRank;
        }

        return String(rightUpdated).localeCompare(String(leftUpdated));
      }
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
  const title = row.latestDiOcrCustomerAddress || 'Service address unavailable';
  const statusCopy = contractorInvoicePresentation(row);
  const statusHint = `${statusCopy.hint} Technical status: ${row.status || 'unknown'}.`;
  const isProcessing = ['queued', 'running'].includes(String(row.latestIngestRunStatus || ''));
  const isPrecheckContinuation = !isProcessing && row.status === 'contractor_precheck' && !row.invoiceSubmittedAt;
  const actionLabel = isPrecheckContinuation ? 'Continue' : 'View';
  const hasUnreadMessages = Number(row.unreadMessageCount || 0) > 0;
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
                    <Text fontSize="md" color="#2D2D2D">
                      {label}
                    </Text>
                    <Text fontSize="md">{value}</Text>
                  </Box>
                ))}
              </Flex>
            ) : null}

            <Flex gap={4} flex="1" alignItems="end" wrap="wrap">
              <Text fontSize="md" color="#2D2D2D">
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
              <Text fontSize="md" color="#2D2D2D">
                Last updated:
                <Text as="span"> </Text>
                <Show below="md">
                  <br />
                </Show>
                {formatTimestamp(lastUpdatedAt(row))}
              </Text>
              {row.invoiceSubmittedAt ? (
                <>
                  <Show below="sm">
                    <Spacer />
                  </Show>
                  <Text fontSize="md" color="#2D2D2D">
                    Submitted:
                    <Text as="span"> </Text>
                    <Show below="md">
                      <br />
                    </Show>
                    {formatTimestamp(row.invoiceSubmittedAt)}
                  </Text>
                </>
              ) : null}
              {row.submitterName ? (
                <>
                  <Show below="sm">
                    <Spacer />
                  </Show>
                  <Text fontSize="md" color="#2D2D2D">
                    Submitted by:
                    <Text as="span"> </Text>
                    <Show below="md">
                      <br />
                    </Show>
                    {row.submitterName}
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
          {hasUnreadMessages ? (
            <Tooltip label="The program team has sent a message that has not yet been read." hasArrow>
              <Badge
                px={2}
                py={1}
                colorScheme="blue"
                borderRadius="md"
                fontWeight="bold"
                textTransform="uppercase"
                whiteSpace="nowrap"
              >
                Unread message
              </Badge>
            </Tooltip>
          ) : null}
          <InvoiceStatusBadge
            label={statusCopy.label}
            status={statusCopy.visualStatus}
            tooltip={statusHint}
            fontSize="md"
          />

          <Box>
            <Text align={{ base: 'left', md: 'right' }} fontSize="md" color="#2D2D2D">
              Reference #
            </Text>
            <Text align={{ base: 'left', md: 'right' }} fontSize="md">
              {formatClaimsReferenceNumber(row.referenceNumber)}
            </Text>
          </Box>

          {isProcessing ? (
            <Button isDisabled>Preparing</Button>
          ) : (
            <RouterLinkButton
              to={`/contractor/sessions/${row.sessionId}/invoices/${row.invoiceId}/review?source=portal`}
              aria-label={`${actionLabel} invoice submission for ${title}`}
              variant={isPrecheckContinuation ? 'secondary' : 'primary'}
              bg={isPrecheckContinuation ? 'greys.white' : undefined}
              color={isPrecheckContinuation ? '#2D2D2D' : undefined}
              borderColor={isPrecheckContinuation ? '#2D2D2D' : undefined}
            >
              {actionLabel}
            </RouterLinkButton>
          )}
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
        row.referenceNumber,
        formatClaimsReferenceNumber(row.referenceNumber),
        row.latestDiOcrCustomerAddress,
        row.submitterName,
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
  const unreadInvoiceCount = rows.filter((row) => Number(row.unreadMessageCount || 0) > 0).length;
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
                <Flex gap={4} direction="column" w="full">
                  <Flex
                    align={{ base: 'stretch', md: 'center' }}
                    justify="space-between"
                    direction={{ base: 'column', md: 'row' }}
                    gap={3}
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
                      Upload invoice
                    </RouterLinkButton>

                    <Flex
                      role="status"
                      aria-live="polite"
                      align="center"
                      gap={2}
                      minH="40px"
                      px={unreadInvoiceCount > 0 ? 3 : 0}
                      py={unreadInvoiceCount > 0 ? 2 : 0}
                      borderWidth={unreadInvoiceCount > 0 ? '1px' : '0'}
                      borderColor="blue.300"
                      borderRadius="md"
                      bg={unreadInvoiceCount > 0 ? 'blue.50' : 'transparent'}
                      color={unreadInvoiceCount > 0 ? 'blue.800' : 'gray.600'}
                      whiteSpace="nowrap"
                      fontWeight={unreadInvoiceCount > 0 ? 'bold' : 'normal'}
                    >
                      <ChatDots size={20} weight={unreadInvoiceCount > 0 ? 'fill' : 'regular'} />
                      <Text fontSize="sm">
                        {unreadInvoiceCount > 0
                          ? `${unreadInvoiceCount} ${unreadInvoiceCount === 1 ? 'invoice' : 'invoices'} with unread messages`
                          : 'No unread messages'}
                      </Text>
                    </Flex>
                  </Flex>

                  <Flex justify="flex-start" w="full">
                    <Flex direction={{ base: 'column', md: 'row' }} alignItems={{ md: 'end', base: 'stretch' }} gap={3}>
                      <FormControl w={{ base: 'full', md: '440px' }}>
                        <FormLabel fontSize="md" color="#2D2D2D">
                          {t('ui.search')}
                        </FormLabel>
                        <Input
                          value={query}
                          onChange={(event) => setQuery(event.target.value)}
                          placeholder="Search invoices..."
                          bg="white"
                        />
                      </FormControl>

                      <FormControl w={{ base: 'full', md: '260px' }}>
                        <FormLabel fontSize="md" color="#2D2D2D">
                          Filter By Status
                        </FormLabel>
                        <MultiCheckSelect
                          selectedValues={selectedStatusGroupValues}
                          setSelectedValues={(values) => setStatusFilter(statusFilterFromGroupValues(values))}
                          allItems={contractorStatusFilterOptions}
                          placeholder="All statuses"
                          menuListMinW="360px"
                        />
                      </FormControl>

                      <FormControl w={{ base: 'full', md: '260px' }}>
                        <FormLabel fontSize="md" color="#2D2D2D">
                          Sort
                        </FormLabel>
                        <Select value={sort} onChange={(event) => setSort(event.target.value)} bg="white">
                          <option value="updated_at:desc">Last Updated - Newest First</option>
                          <option value="updated_at:asc">Last Updated - Oldest First</option>
                          <option value="status_completion:most">Status Most Complete</option>
                          <option value="status_completion:least">Status Least Complete</option>
                        </Select>
                      </FormControl>

                      <Button
                        variant="secondary"
                        bg="greys.white"
                        color="#2D2D2D"
                        borderColor="#2D2D2D"
                        onClick={() => {
                          setQuery('');
                          setStatusFilter(DEFAULT_CONTRACTOR_STATUS_FILTER);
                          setSort('updated_at:desc');
                        }}
                      >
                        Reset All
                      </Button>
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
