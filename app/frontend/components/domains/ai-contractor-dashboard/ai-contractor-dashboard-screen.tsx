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
import { PencilIcon } from '@phosphor-icons/react';
import { observer } from 'mobx-react-lite';
import React, { useEffect, useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useMst, useServerAPI } from '../../../setup/root';
import { getRuntimeBooleanMetaValue } from '../../../utils/utility-functions';
import { PerPageSelect } from '../../shared/base/inputs/per-page-select';
import { Paginator } from '../../shared/base/inputs/paginator';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';
import { getInvoiceUpgradeTypeMeta, InvoiceUpgradeTypeTile } from '../../shared/claims/invoice-upgrade-type-visual';
import { GreenLineSmall } from '../../shared/base/decorative/green-line-small';
import { SharedSpinner } from '../../shared/base/shared-spinner';
import { RouterLinkButton } from '../../shared/navigation/router-link-button';
import { ContractorProgramResourcesScreen } from '../contractor-management/contractor-program-resources-screen';

type ContractorPortalRow = {
  invoiceId: string;
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

function contractorStatusLabel(status?: string | null) {
  const value = String(status || '').toLowerCase();

  if (value === 'genai_complete') return 'Draft';
  if (value === 'admin_review_inbox') return 'Submitted';
  if (value === 'contractor_revision_inbox') return 'Update needed';
  if (value === 'in_review') return 'In review';
  if (value === 'approved_pending') return 'Approved - pending';
  if (value === 'approved_paid') return 'Approved - paid';
  if (value === 'ineligible') return 'Ineligible';

  return value || 'Unknown';
}

function contractorStatusColor(status?: string | null) {
  const value = String(status || '').toLowerCase();

  if (value === 'genai_complete') return 'blue';
  if (value === 'admin_review_inbox' || value === 'in_review') return 'yellow';
  if (value === 'contractor_revision_inbox') return 'orange';
  if (value === 'approved_pending' || value === 'approved_paid') return 'green';
  if (value === 'ineligible' || value.endsWith('_failed')) return 'red';

  return 'gray';
}

function actionLabel(status?: string | null) {
  const value = String(status || '').toLowerCase();
  if (value === 'genai_complete' || value === 'contractor_revision_inbox') return 'Continue';
  return 'View';
}

function displayUpgradeTypeKeys(row: ContractorPortalRow) {
  const keys = Array.isArray(row.latestDetectedUpgradeTypeKeys)
    ? row.latestDetectedUpgradeTypeKeys.map((key) => String(key || '').trim()).filter(Boolean)
    : [];

  return [...new Set(keys)];
}

function upgradeTypeSummary(row: ContractorPortalRow) {
  const keys = displayUpgradeTypeKeys(row);
  if (!keys.length) return `Session ${row.sessionId.slice(0, 8)}`;
  return keys.map((key) => getInvoiceUpgradeTypeMeta(key).label).join(', ');
}

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
        return contractorStatusLabel(left.status).localeCompare(contractorStatusLabel(right.status));
      case 'status:desc':
        return contractorStatusLabel(right.status).localeCompare(contractorStatusLabel(left.status));
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
  const subtitle = upgradeTypeSummary(row);
  const upgradeTypeKeys = displayUpgradeTypeKeys(row);

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
        <Flex
          display={{ base: 'none', md: 'flex' }}
          direction="column"
          flex={{ base: 0, md: 1 }}
          maxW={{ base: '100%', md: '20%' }}
          justifyContent="center"
        >
          <Flex direction="column" gap={3}>
            <Text fontSize="xs" fontWeight="bold" textTransform="uppercase" letterSpacing="0.08em" color="greys.grey01">
              Upgrade types
            </Text>
            <Flex gap={2} wrap="wrap" align="center">
              {upgradeTypeKeys.length ? (
                upgradeTypeKeys.map((upgradeTypeKey) => {
                  const meta = getInvoiceUpgradeTypeMeta(upgradeTypeKey);

                  return (
                    <Tooltip key={`${row.invoiceId}-${upgradeTypeKey}`} label={meta.label}>
                      <Box>
                        <InvoiceUpgradeTypeTile upgradeTypeKey={upgradeTypeKey} description={meta.label} size={42} />
                      </Box>
                    </Tooltip>
                  );
                })
              ) : (
                <Tooltip label="Common invoice evidence">
                  <Box>
                    <InvoiceUpgradeTypeTile upgradeTypeKey="common" description="Common invoice evidence" size={42} />
                  </Box>
                </Tooltip>
              )}
            </Flex>
          </Flex>
        </Flex>

        <Show below="md">
          <Flex justify="space-between" alignItems="flex-start" gap={4}>
            <Flex gap={2} wrap="wrap" flex={1}>
              {upgradeTypeKeys.length ? (
                upgradeTypeKeys.map((upgradeTypeKey) => {
                  const meta = getInvoiceUpgradeTypeMeta(upgradeTypeKey);

                  return (
                    <Tooltip key={`${row.invoiceId}-${upgradeTypeKey}-mobile`} label={meta.label}>
                      <Box>
                        <InvoiceUpgradeTypeTile upgradeTypeKey={upgradeTypeKey} description={meta.label} size={34} />
                      </Box>
                    </Tooltip>
                  );
                })
              ) : (
                <Tooltip label="Common invoice evidence">
                  <Box>
                    <InvoiceUpgradeTypeTile upgradeTypeKey="common" description="Common invoice evidence" size={34} />
                  </Box>
                </Tooltip>
              )}
            </Flex>
            <Badge colorScheme={contractorStatusColor(row.status)} borderRadius="full" px={3} py={1} flexShrink={0}>
              {contractorStatusLabel(row.status)}
            </Badge>
          </Flex>
        </Show>

        <Flex direction="column" gap={2} flex={{ base: 0, md: 5 }} maxW={{ base: '100%', md: '75%' }}>
          <Flex direction="column" flex={1} gap={2}>
            <Text color="text.link" fontSize="lg" fontWeight="bold">
              {title}
            </Text>
            <Text color="text.link" fontSize="lg" fontWeight="bold" flex="1">
              {subtitle}
            </Text>

            <Show below="md">
              <Text>
                <Text as="span" fontWeight={700} mr="1">
                  Session:
                </Text>
                {row.sessionId}
              </Text>
            </Show>

            <Box flex="1" alignContent="center">
              <GreenLineSmall />
            </Box>

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

        <Flex direction="column" align="flex-end" gap={4} flex={{ base: 0, md: 1 }} maxW={{ base: '100%', md: '25%' }}>
          <Show above="md">
            <Badge colorScheme={contractorStatusColor(row.status)} borderRadius="full" px={3} py={1}>
              {contractorStatusLabel(row.status)}
            </Badge>
            <Box>
              <Text align="right" variant="tiny_uppercase">
                Claims status
              </Text>
              <Text align="right">{row.status}</Text>
            </Box>
          </Show>

          <RouterLinkButton
            to={`/sessions/${row.sessionId}/invoices/${row.invoiceId}/read`}
            variant="secondary"
            w={{ base: 'full', md: 'fit-content' }}
            aria-label={`${actionLabel(row.status)} invoice submission for ${title}`}
            leftIcon={<PencilIcon />}
          >
            {actionLabel(row.status)}
          </RouterLinkButton>
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
  const [statusFilter, setStatusFilter] = useState('');
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
      if (statusFilter && row.status !== statusFilter) return false;

      if (!normalizedQuery) return true;

      const haystack = [
        row.latestOriginalFilename,
        row.invoiceId,
        row.sessionId,
        row.status,
        contractorStatusLabel(row.status),
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
                    to={'/new-invoice'}
                    variant="primary"
                    w={{ base: 'full', md: 'fit-content' }}
                    aria-label={
                      isSubmitInvoiceDisabled
                        ? t('contractor.suspended.buttonDisabled')
                        : `${t('landing.contractor.dashboard.submitInvoice')} - ${t('energySavingsApplication.newInvoiceSubmission')}`
                    }
                    isDisabled={isSubmitInvoiceDisabled}
                  >
                    {t('landing.contractor.dashboard.submitInvoice')}
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

                      <FormControl w={{ base: 'full', md: '220px' }}>
                        <FormLabel>Status</FormLabel>
                        <Select
                          value={statusFilter}
                          onChange={(event) => setStatusFilter(event.target.value)}
                          bg="white"
                        >
                          <option value="">All statuses</option>
                          <option value="genai_complete">Draft</option>
                          <option value="admin_review_inbox">Submitted</option>
                          <option value="contractor_revision_inbox">Update needed</option>
                          <option value="in_review">In review</option>
                          <option value="approved_pending">Approved - pending</option>
                          <option value="approved_paid">Approved - paid</option>
                          <option value="ineligible">Ineligible</option>
                        </Select>
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

                      {(query || statusFilter || sort !== 'updated_at:desc') && (
                        <Button
                          variant="link"
                          mb={{ base: 0, md: 2 }}
                          onClick={() => {
                            setQuery('');
                            setStatusFilter('');
                            setSort('updated_at:desc');
                          }}
                        >
                          {t('ui.resetFilters')}
                        </Button>
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
