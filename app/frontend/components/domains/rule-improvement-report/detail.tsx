import {
  Accordion,
  AccordionButton,
  AccordionIcon,
  AccordionItem,
  AccordionPanel,
  Alert,
  AlertIcon,
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
  Link,
  ListItem,
  Select,
  SimpleGrid,
  Spinner,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Table,
  Tabs,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tr,
  Tooltip,
  UnorderedList,
  VStack,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowLeft, ArrowSquareOut, Info, PencilSimple, Question } from '@phosphor-icons/react';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Link as RouterLink, useLocation, useNavigate, useParams } from 'react-router-dom';
import { formatClaimsReferenceNumber } from '../../../utils/format-claims-reference-number';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { COMPLAINT_LABELS, EvidenceRow, RuleMetrics, RuleRow, shortDate, titleize } from './types';

type ChangedField = { field: string; label: string; before: unknown; after: unknown };
type Period = {
  sequence: number;
  label: string;
  period_start: string;
  period_end?: string | null;
  state: Record<string, unknown>;
  metrics: RuleMetrics;
};
type Timeline = {
  periods: Period[];
  milestones: Array<{ sequence: number; changed_at: string; label: string; changed_fields: ChangedField[] }>;
};
type BreakdownRow = { value: string; count: number };
type Breakdowns = {
  complaint_types: BreakdownRow[];
  closure_types: BreakdownRow[];
  admin_requests: BreakdownRow[];
  contractor_responses: BreakdownRow[];
  round_distribution: Array<{ rounds: number; count: number }>;
};
type EvidenceKind = 'complaints' | 'false_positives' | 'false_negatives' | 'contractor_follow_up' | 'closure_outcomes';

const EMPTY_BREAKDOWNS: Breakdowns = {
  complaint_types: [],
  closure_types: [],
  admin_requests: [],
  contractor_responses: [],
  round_distribution: [],
};

const CLOSURE_LABELS: Record<string, string> = {
  pending_admin_review: 'Pending admin review',
  open: 'Open',
  closed_no_contractor_action_required: 'No contractor action required',
  closed_via_corrected_documentation: 'Corrected documentation',
  closed_via_attestation: 'Contractor attestation',
  closed_via_exception: 'Approved exception',
  closed_as_withdrawn: 'Invoice withdrawn',
};

const CLOSED_OUTCOME_LABELS: Record<string, string> = {
  closed_no_contractor_action_required: 'No contractor action required',
  closed_via_corrected_documentation: 'Corrected documentation',
  closed_via_attestation: 'Contractor attestation',
  closed_via_exception: 'Approved exception',
  closed_as_withdrawn: 'Invoice withdrawn',
};

const COMMON_RULE_DETAIL_FIELDS = [
  ['contractor_display_name', 'Contractor-facing name'],
  ['definition_text', 'Rule definition'],
  ['enabled', 'Enabled'],
  ['source_quote', 'Source quote'],
  ['contractor_action', 'Contractor action'],
  ['contractor_visibility', 'Contractor visibility'],
  ['contractor_blocking_policy', 'Contractor blocking policy'],
  ['admin_workflow_policy', 'Admin workflow policy'],
] as const;

const CODE_RULE_DETAIL_FIELDS = [
  ['pass_admin_message', 'Pass message'],
  ['info_admin_message', 'Info message'],
  ['warn_admin_message', 'Warning message'],
  ['fail_admin_message', 'Failure message'],
  ['admin_notes', 'Admin notes'],
] as const;

function formatValue(value: unknown) {
  if (value === null || value === undefined || value === '') return 'Not set';
  if (typeof value === 'boolean') return value ? 'Yes' : 'No';
  return String(value);
}

function closureLabel(value?: string | null) {
  if (!value) return 'No closure recorded';
  return CLOSURE_LABELS[value] || titleize(value);
}

export default function RuleImprovementDetailScreen() {
  const { sourceEngine = '', ruleKey = '' } = useParams();
  const location = useLocation();
  const navigate = useNavigate();
  const help = useDisclosure();
  const [rule, setRule] = useState<RuleRow | null>(null);
  const [timeline, setTimeline] = useState<Timeline | null>(null);
  const [breakdowns, setBreakdowns] = useState<Breakdowns>(EMPTY_BREAKDOWNS);
  const [evidence, setEvidence] = useState<Record<EvidenceKind, EvidenceRow[]>>({
    complaints: [],
    false_positives: [],
    false_negatives: [],
    contractor_follow_up: [],
    closure_outcomes: [],
  });
  const [evidenceTotals, setEvidenceTotals] = useState<Record<EvidenceKind, number>>({
    complaints: 0,
    false_positives: 0,
    false_negatives: 0,
    contractor_follow_up: 0,
    closure_outcomes: 0,
  });
  const [evidenceLoading, setEvidenceLoading] = useState<Partial<Record<EvidenceKind, boolean>>>({});
  const [complaintTypeFilter, setComplaintTypeFilter] = useState('');
  const [minimumSentRounds, setMinimumSentRounds] = useState('');
  const [closureOutcomeFilter, setClosureOutcomeFilter] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const returnQuery = new URLSearchParams(location.search).get('return_query') ?? '';
  const encodedRule = encodeURIComponent(ruleKey);
  const encodedEngine = encodeURIComponent(sourceEngine);
  const base = `/api/claims/admin/reports/rule_improvement/${encodedEngine}/${encodedRule}`;
  const apiUrl = useCallback(
    (path = '', extras: Record<string, string> = {}) => {
      const params = new URLSearchParams(extras);
      return `${base}${path}${params.toString() ? `?${params}` : ''}`;
    },
    [base],
  );

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    const kinds: EvidenceKind[] = [
      'complaints',
      'false_positives',
      'false_negatives',
      'contractor_follow_up',
      'closure_outcomes',
    ];
    try {
      const [detailResponse, timelineResponse, ...evidenceResponses] = await Promise.all([
        fetch(apiUrl(), { credentials: 'include' }),
        fetch(apiUrl('/timeline'), { credentials: 'include' }),
        ...kinds.map((kind) =>
          fetch(apiUrl('/evidence', { evidence_type: kind, per: '25' }), { credentials: 'include' }),
        ),
      ]);
      const [detailData, timelineData, ...evidenceData] = await Promise.all([
        detailResponse.json(),
        timelineResponse.json(),
        ...evidenceResponses.map((response) => response.json()),
      ]);
      if (!detailResponse.ok || !timelineResponse.ok || evidenceResponses.some((response) => !response.ok)) {
        throw new Error(detailData.error || timelineData.error || 'Unable to load rule evidence.');
      }

      setRule(detailData.rule);
      setBreakdowns(detailData.breakdowns ?? EMPTY_BREAKDOWNS);
      setTimeline(timelineData);
      setEvidence(
        kinds.reduce(
          (result, kind, index) => ({ ...result, [kind]: evidenceData[index]?.rows ?? [] }),
          {} as Record<EvidenceKind, EvidenceRow[]>,
        ),
      );
      setEvidenceTotals(
        kinds.reduce(
          (result, kind, index) => ({ ...result, [kind]: evidenceData[index]?.meta?.total ?? 0 }),
          {} as Record<EvidenceKind, number>,
        ),
      );
    } catch (loadError: any) {
      setError(loadError?.message || 'Unable to load rule evidence.');
    } finally {
      setLoading(false);
    }
  }, [apiUrl]);

  useEffect(() => {
    if (!['genai', 'code'].includes(sourceEngine)) {
      setError('This report covers GenAI and code rules only.');
      setLoading(false);
      return;
    }
    void load();
  }, [load, sourceEngine]);

  const activeEvidenceFilters = (kind: EvidenceKind): Record<string, string> => {
    if (kind === 'complaints' && complaintTypeFilter) {
      return { evidence_complaint_code: complaintTypeFilter };
    }
    if (kind === 'contractor_follow_up' && minimumSentRounds) {
      return { minimum_sent_rounds: minimumSentRounds };
    }
    if (kind === 'closure_outcomes' && closureOutcomeFilter) {
      return { evidence_closure_outcome: closureOutcomeFilter };
    }
    return {};
  };

  const replaceEvidence = async (kind: EvidenceKind, filters: Record<string, string>) => {
    setEvidenceLoading((current) => ({ ...current, [kind]: true }));
    try {
      const response = await fetch(apiUrl('/evidence', { evidence_type: kind, per: '25', page: '1', ...filters }), {
        credentials: 'include',
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        setError(data.error || 'Unable to filter invoice evidence.');
        return;
      }
      setEvidence((current) => ({ ...current, [kind]: data.rows ?? [] }));
      setEvidenceTotals((current) => ({ ...current, [kind]: data.meta?.total ?? 0 }));
    } catch (loadError: any) {
      setError(loadError?.message || 'Unable to filter invoice evidence.');
    } finally {
      setEvidenceLoading((current) => ({ ...current, [kind]: false }));
    }
  };

  const applyComplaintTypeFilter = (value: string) => {
    setComplaintTypeFilter(value);
    void replaceEvidence('complaints', value ? { evidence_complaint_code: value } : {});
  };

  const applyMinimumSentRounds = (value: string) => {
    setMinimumSentRounds(value);
    void replaceEvidence('contractor_follow_up', value ? { minimum_sent_rounds: value } : {});
  };

  const applyClosureOutcomeFilter = (value: string) => {
    setClosureOutcomeFilter(value);
    if (value) void replaceEvidence('closure_outcomes', { evidence_closure_outcome: value });
  };

  const loadMoreEvidence = async (kind: EvidenceKind) => {
    const currentRows = evidence[kind];
    const nextPage = Math.floor(currentRows.length / 25) + 1;
    const response = await fetch(
      apiUrl('/evidence', {
        evidence_type: kind,
        per: '25',
        page: String(nextPage),
        ...activeEvidenceFilters(kind),
      }),
      { credentials: 'include' },
    );
    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      setError(data.error || 'Unable to load more invoice evidence.');
      return;
    }
    setEvidence((current) => ({ ...current, [kind]: [...current[kind], ...(data.rows ?? [])] }));
    setEvidenceTotals((current) => ({ ...current, [kind]: data.meta?.total ?? current[kind] }));
  };

  const editorLink = useMemo(() => {
    if (!rule) return '';
    const params = new URLSearchParams({ mode: 'edit', record_type: rule.record_type, record_id: rule.rule_id });
    const firstUpgradeTypeId = rule.upgrade_types[0]?.id;
    if (firstUpgradeTypeId) params.set('invoice_upgrade_type_id', firstUpgradeTypeId);
    return `/validation-rules-admin?${params}`;
  }, [rule]);

  const isCodeRule = rule?.source_engine === 'code';
  const scopeLabel = isCodeRule ? 'this code implementation' : 'current rule version';

  return (
    <>
      <ThinBlueTitleBar title="Rule Improvement Detail" />
      <Container maxW="full" px={6} pb={4} pt={6}>
        <Button
          leftIcon={<ArrowLeft />}
          variant="ghost"
          mb={4}
          onClick={() => navigate(`/reports-rule-improvement${returnQuery}`)}
        >
          Back to rules
        </Button>

        {error && (
          <Alert status="error" mb={5}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        {loading && (
          <Flex py={20} justify="center">
            <Spinner size="xl" />
          </Flex>
        )}

        {!loading && rule && (
          <>
            <Flex
              justify="space-between"
              align={{ base: 'start', md: 'center' }}
              direction={{ base: 'column', md: 'row' }}
              gap={4}
              mb={5}
            >
              <Box>
                <HStack mb={2}>
                  <Badge colorScheme={isCodeRule ? 'purple' : 'blue'}>{isCodeRule ? 'Code' : 'GenAI'}</Badge>
                  <Badge colorScheme={rule.enabled ? 'green' : 'gray'}>{rule.enabled ? 'Enabled' : 'Disabled'}</Badge>
                </HStack>
                <Text fontSize="2xl" fontWeight="bold">
                  {rule.contractor_display_name}
                </Text>
                <Text fontFamily="mono" fontSize="sm" color="gray.600">
                  {rule.rule_key}
                </Text>
              </Box>
              <HStack>
                <Button leftIcon={<Question />} variant="outline" onClick={help.onOpen}>
                  How to use this report
                </Button>
                <Button as={RouterLink} to={editorLink} leftIcon={<PencilSimple />} colorScheme="blue">
                  Edit rule
                </Button>
              </HStack>
            </Flex>

            <Tabs
              variant="line"
              isFitted
              colorScheme="gray"
              isLazy
              sx={{
                '.chakra-tabs__tablist': {
                  borderBottomWidth: '2px',
                  borderColor: 'gray.300',
                },
                '.chakra-tabs__tab[aria-selected=true]': {
                  borderBottomWidth: '4px',
                  borderColor: 'gray.800',
                },
              }}
            >
              <TabList overflowX="auto" overflowY="hidden">
                <Tab whiteSpace="nowrap">Rule history</Tab>
                <Tab whiteSpace="nowrap">Complaints</Tab>
                <Tab whiteSpace="nowrap">False-positive candidates</Tab>
                <Tab whiteSpace="nowrap">False-negative candidates</Tab>
                <Tab whiteSpace="nowrap">Workflow management rounds</Tab>
                <Tab whiteSpace="nowrap">Requests and responses</Tab>
                <Tab whiteSpace="nowrap">Closure outcomes</Tab>
              </TabList>

              <TabPanels>
                <TabPanel p={3}>
                  <CandidateNotice>
                    {isCodeRule
                      ? 'This tab shows one executable-code implementation period. Use the row information icon to inspect the complete database configuration for this record; it does not show the executable source code.'
                      : 'This history shows how the rule changed over time. Each row is one effective rule period; only the current period feeds the other tabs. Use a row information icon to see the complete rule values that applied during that version.'}
                  </CandidateNotice>
                  <RuleHistoryTable periods={timeline?.periods ?? []} isCodeRule={isCodeRule} ruleKey={rule.rule_key} />
                </TabPanel>

                <TabPanel p={3}>
                  <CandidateNotice>
                    Complaints concern the usefulness of the written reason, not necessarily whether the rule passed or
                    failed correctly. The finding may be accurate while its explanation, evidence, likely cause or
                    required action still needs improvement.
                  </CandidateNotice>
                  <ComplaintTypeChart
                    rows={breakdowns.complaint_types}
                    scopeLabel={scopeLabel}
                    selectedValue={complaintTypeFilter}
                    onSelect={applyComplaintTypeFilter}
                  />
                  <Box maxW="360px" mb={5}>
                    <Text as="label" htmlFor="complaint-type-filter" fontSize="sm" fontWeight="semibold" mb={1}>
                      Complaint type
                    </Text>
                    <Select
                      id="complaint-type-filter"
                      aria-label="Complaint type"
                      value={complaintTypeFilter}
                      onChange={(event) => applyComplaintTypeFilter(event.target.value)}
                      isDisabled={evidenceLoading.complaints}
                    >
                      <option value="">All complaint types</option>
                      {Object.entries(COMPLAINT_LABELS).map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </Select>
                  </Box>
                  <EvidenceTable
                    kind="complaints"
                    rows={evidence.complaints}
                    total={evidenceTotals.complaints}
                    empty={
                      complaintTypeFilter
                        ? `No ${COMPLAINT_LABELS[complaintTypeFilter]?.toLowerCase() ?? 'matching'} complaints are available for ${scopeLabel}.`
                        : `No complaint records are available for ${scopeLabel}.`
                    }
                    loading={Boolean(evidenceLoading.complaints)}
                    onLoadMore={() => void loadMoreEvidence('complaints')}
                  />
                </TabPanel>

                <TabPanel p={3}>
                  <CandidateNotice>
                    A warning or failure closed with no contractor action is worth reviewing, but it is not proof that
                    the rule was wrong.
                  </CandidateNotice>
                  <Text fontSize="sm" fontWeight="semibold" mb={4}>
                    Total false-positive candidates: {evidenceTotals.false_positives}
                  </Text>
                  <EvidenceTable
                    kind="false_positives"
                    rows={evidence.false_positives}
                    total={evidenceTotals.false_positives}
                    empty={`No false-positive candidates are present for ${scopeLabel}.`}
                    onLoadMore={() => void loadMoreEvidence('false_positives')}
                  />
                </TabPanel>

                <TabPanel p={3}>
                  <CandidateNotice>
                    A pass or informational result with a linked rule issue may indicate a miss, but it remains a
                    candidate rather than proof. Review whether the workflow required real corrective action.
                  </CandidateNotice>
                  <Text fontSize="sm" fontWeight="semibold" mb={4}>
                    Total false-negative candidates: {evidenceTotals.false_negatives}
                  </Text>
                  <EvidenceTable
                    kind="false_negatives"
                    rows={evidence.false_negatives}
                    total={evidenceTotals.false_negatives}
                    empty={`No false-negative candidates are present for ${scopeLabel}.`}
                    onLoadMore={() => void loadMoreEvidence('false_negatives')}
                  />
                </TabPanel>

                <TabPanel p={3}>
                  <CandidateNotice>
                    Several rounds are a signal of effort, not proof that contractor training is needed. Repeated
                    corrected-documentation closures for the same mistake may point to clearer guidance or training.
                    No-action or exception closures may instead expose a rule or policy problem. Open or pending cases
                    do not yet provide an outcome.
                  </CandidateNotice>
                  <SimpleGrid columns={{ base: 1, md: 3 }} spacing={3} mb={6}>
                    <SummaryValue label="Invoice versions with follow-up" value={rule.follow_up_invoice_count} />
                    <SummaryValue label="Total rounds" value={rule.total_round_count} />
                    <SummaryValue label="Average rounds" value={rule.average_rounds || '—'} />
                  </SimpleGrid>
                  <Box maxW="300px" mb={5}>
                    <Text as="label" htmlFor="minimum-sent-rounds-filter" fontSize="sm" fontWeight="semibold" mb={1}>
                      Minimum sent rounds
                    </Text>
                    <Select
                      id="minimum-sent-rounds-filter"
                      aria-label="Minimum sent rounds"
                      value={minimumSentRounds}
                      onChange={(event) => applyMinimumSentRounds(event.target.value)}
                      isDisabled={evidenceLoading.contractor_follow_up}
                    >
                      <option value="">All round counts</option>
                      {[1, 2, 3, 4, 5].map((rounds) => (
                        <option key={rounds} value={rounds}>
                          At least {rounds}
                        </option>
                      ))}
                    </Select>
                  </Box>
                  <EvidenceTable
                    kind="contractor_follow_up"
                    rows={evidence.contractor_follow_up}
                    total={evidenceTotals.contractor_follow_up}
                    empty={
                      minimumSentRounds
                        ? `No workflow records have at least ${minimumSentRounds} sent rounds for ${scopeLabel}.`
                        : `No workflow management round records are available for ${scopeLabel}.`
                    }
                    loading={Boolean(evidenceLoading.contractor_follow_up)}
                    onLoadMore={() => void loadMoreEvidence('contractor_follow_up')}
                  />
                </TabPanel>

                <TabPanel p={3}>
                  <CandidateNotice>
                    This tab counts pull-down selections in sent workflow rounds. It shows what administrators asked
                    contractors to do and how contractors responded before closure. Multiple rounds on one issue can
                    contribute multiple selections, so compare the patterns rather than treating the two charts as
                    one-to-one pairs.
                  </CandidateNotice>
                  <SimpleGrid columns={{ base: 1, xl: 2 }} spacing={5}>
                    <VerticalCategoryChart
                      title={`Admin requests — ${scopeLabel}`}
                      totalLabel="Request selections"
                      rows={breakdowns.admin_requests}
                      fullLabels={ADMIN_REQUEST_LABELS}
                      shortLabels={ADMIN_REQUEST_CHART_LABELS}
                      empty={`No admin request selections were sent for ${scopeLabel}.`}
                    />
                    <VerticalCategoryChart
                      title={`Contractor responses — ${scopeLabel}`}
                      totalLabel="Response selections"
                      rows={breakdowns.contractor_responses}
                      fullLabels={CONTRACTOR_RESPONSE_LABELS}
                      shortLabels={CONTRACTOR_RESPONSE_CHART_LABELS}
                      empty={`No contractor response selections were submitted for ${scopeLabel}.`}
                    />
                  </SimpleGrid>
                </TabPanel>

                <TabPanel p={3}>
                  <CandidateNotice>
                    This chart contains closed issues only. Open and pending issues are excluded because their outcomes
                    are not known yet. Repeated corrected-documentation outcomes may support clearer contractor
                    guidance, while repeated no-action outcomes may point to an over-broad rule. Exceptions can expose
                    recurring edge cases.
                  </CandidateNotice>
                  <ClosureOutcomeChart
                    rows={breakdowns.closure_types}
                    scopeLabel={scopeLabel}
                    selectedValue={closureOutcomeFilter}
                    onSelect={applyClosureOutcomeFilter}
                  />
                  <Box maxW="360px" mb={5}>
                    <Text as="label" htmlFor="closure-outcome-filter" fontSize="sm" fontWeight="semibold" mb={1}>
                      Outcome to inspect
                    </Text>
                    <Select
                      id="closure-outcome-filter"
                      aria-label="Outcome to inspect"
                      value={closureOutcomeFilter}
                      onChange={(event) => applyClosureOutcomeFilter(event.target.value)}
                      isDisabled={evidenceLoading.closure_outcomes}
                    >
                      <option value="">Choose an outcome</option>
                      {Object.entries(CLOSED_OUTCOME_LABELS).map(([value, label]) => (
                        <option key={value} value={value}>
                          {label}
                        </option>
                      ))}
                    </Select>
                  </Box>
                  {closureOutcomeFilter ? (
                    <EvidenceTable
                      kind="closure_outcomes"
                      rows={evidence.closure_outcomes}
                      total={evidenceTotals.closure_outcomes}
                      empty={`No ${CLOSED_OUTCOME_LABELS[closureOutcomeFilter]?.toLowerCase() ?? 'matching'} closure records are available for ${scopeLabel}.`}
                      loading={Boolean(evidenceLoading.closure_outcomes)}
                      onLoadMore={() => void loadMoreEvidence('closure_outcomes')}
                    />
                  ) : (
                    <Text color="gray.600" py={3}>
                      Choose an outcome above or select a chart bar to inspect its invoice records.
                    </Text>
                  )}
                </TabPanel>
              </TabPanels>
            </Tabs>
          </>
        )}
      </Container>

      <RuleImprovementHelp isOpen={help.isOpen} onClose={help.onClose} isCodeRule={isCodeRule} />
    </>
  );
}

function SummaryValue({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <Box borderWidth="1px" borderRadius="md" p={4}>
      <Text fontSize="2xl" fontWeight="bold">
        {value}
      </Text>
      <Text fontSize="sm" color="gray.600">
        {label}
      </Text>
    </Box>
  );
}

function CandidateNotice({ children }: React.PropsWithChildren) {
  return (
    <Alert status="info" variant="left-accent" mb={5} alignItems="start">
      <AlertIcon mt={1} />
      <Box flex="1">{children}</Box>
    </Alert>
  );
}

function RuleHistoryTable({
  periods,
  isCodeRule,
  ruleKey,
}: {
  periods: Period[];
  isCodeRule: boolean;
  ruleKey: string;
}) {
  const details = useDisclosure();
  const [selectedPeriod, setSelectedPeriod] = useState<Period | null>(null);
  const detailFields = isCodeRule
    ? [...COMMON_RULE_DETAIL_FIELDS, ...CODE_RULE_DETAIL_FIELDS]
    : COMMON_RULE_DETAIL_FIELDS;

  if (periods.length === 0) return <Text color="gray.500">No rule history is available.</Text>;

  return (
    <>
      <Box overflowX="auto">
        <Table size="sm">
          <Thead>
            <Tr>
              {!isCodeRule && <Th>Version</Th>}
              <Th>Effective period</Th>
              <Th isNumeric>Invoices</Th>
              <Th isNumeric>Complaints</Th>
              <Th isNumeric>FP candidates</Th>
              <Th isNumeric>FN candidates</Th>
              <Th isNumeric>Rounds</Th>
              <Th textAlign="center">Details</Th>
            </Tr>
          </Thead>
          <Tbody>
            {periods.map((period) => (
              <Tr key={period.sequence}>
                {!isCodeRule && <Td fontWeight="semibold">{period.sequence}</Td>}
                <Td whiteSpace="nowrap">
                  {shortDate(period.period_start)} – {period.period_end ? shortDate(period.period_end) : 'present'}
                </Td>
                <Td isNumeric>{period.metrics.invoice_count}</Td>
                <Td isNumeric>{period.metrics.complaint_count}</Td>
                <Td isNumeric>{period.metrics.candidate_false_positive_count}</Td>
                <Td isNumeric>{period.metrics.candidate_false_negative_count}</Td>
                <Td isNumeric>{period.metrics.total_round_count}</Td>
                <Td textAlign="center">
                  <Tooltip label={isCodeRule ? 'View code rule details' : `View version ${period.sequence} details`}>
                    <IconButton
                      aria-label={isCodeRule ? 'View code rule details' : `View version ${period.sequence} details`}
                      icon={<Info size={18} />}
                      size="sm"
                      variant="outline"
                      onClick={() => {
                        setSelectedPeriod(period);
                        details.onOpen();
                      }}
                    />
                  </Tooltip>
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>
      </Box>

      <Drawer isOpen={details.isOpen} placement="right" size="lg" onClose={details.onClose}>
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>
            {isCodeRule ? 'Code rule details' : `Version ${selectedPeriod?.sequence ?? ''} details`}
          </DrawerHeader>
          <DrawerBody pb={8}>
            {selectedPeriod && (
              <>
                <Box mb={4}>
                  <Text fontSize="sm" color="gray.600">
                    Rule key
                  </Text>
                  <Text fontFamily="mono" fontSize="sm">
                    {ruleKey}
                  </Text>
                </Box>
                <Box mb={5}>
                  <Text fontSize="sm" color="gray.600">
                    Effective period
                  </Text>
                  <Text>
                    {shortDate(selectedPeriod.period_start)} –{' '}
                    {selectedPeriod.period_end ? shortDate(selectedPeriod.period_end) : 'present'}
                  </Text>
                </Box>
              </>
            )}

            {isCodeRule && (
              <CandidateNotice>
                These are the complete database configuration values for this code-rule record. They do not show the
                executable source code.
              </CandidateNotice>
            )}

            {selectedPeriod && (
              <VStack align="stretch" spacing={4}>
                {detailFields.map(([field, label]) => (
                  <Box key={field} borderBottomWidth="1px" borderColor="gray.200" pb={4}>
                    <Text fontSize="sm" color="gray.600" mb={1}>
                      {label}
                    </Text>
                    <Text whiteSpace="pre-wrap">{formatValue(selectedPeriod.state[field])}</Text>
                  </Box>
                ))}
              </VStack>
            )}
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </>
  );
}

const COMPLAINT_CHART_LABELS: Record<string, string> = {
  unclear_or_confusing: 'Unclear',
  too_vague: 'Too vague',
  missing_evidence_explanation: 'Missing evidence',
  incorrect_evidence_or_reasoning: 'Incorrect evidence or reasoning',
  likely_causes_unhelpful: 'Unhelpful likely causes',
  required_action_unclear: 'Unclear required action',
  irrelevant_or_duplicative: 'Irrelevant or duplicate',
  too_verbose_or_repetitive: 'Too verbose',
  other: 'Other',
};

const CLOSURE_CHART_LABELS: Record<string, string> = {
  closed_no_contractor_action_required: 'No action required',
  closed_via_corrected_documentation: 'Corrected documentation',
  closed_via_attestation: 'Attestation',
  closed_via_exception: 'Exception',
  closed_as_withdrawn: 'Withdrawn',
};

const ADMIN_REQUEST_LABELS: Record<string, string> = {
  correct_and_reupload_invoice: 'Correct and re-upload invoice',
  upload_supporting_document: 'Upload supporting document',
  provide_attestation: 'Provide attestation',
  provide_explanation: 'Provide explanation',
};

const ADMIN_REQUEST_CHART_LABELS: Record<string, string> = {
  correct_and_reupload_invoice: 'Correct invoice',
  upload_supporting_document: 'Upload document',
  provide_attestation: 'Attestation',
  provide_explanation: 'Explanation',
};

const CONTRACTOR_RESPONSE_LABELS: Record<string, string> = {
  corrected_invoice_uploaded: 'Corrected invoice uploaded',
  supporting_document_uploaded: 'Supporting document uploaded',
  attestation_provided: 'Attestation provided',
  explanation_provided: 'Explanation provided',
  unable_to_resolve: 'Unable to resolve',
};

const CONTRACTOR_RESPONSE_CHART_LABELS: Record<string, string> = {
  corrected_invoice_uploaded: 'Corrected invoice',
  supporting_document_uploaded: 'Supporting document',
  attestation_provided: 'Attestation',
  explanation_provided: 'Explanation',
  unable_to_resolve: 'Unable to resolve',
};

function ComplaintTypeChart({
  rows,
  scopeLabel,
  selectedValue,
  onSelect,
}: {
  rows: BreakdownRow[];
  scopeLabel: string;
  selectedValue: string;
  onSelect: (value: string) => void;
}) {
  return (
    <VerticalCategoryChart
      title={`Complaints by type — ${scopeLabel}`}
      totalLabel="Total complaints"
      rows={rows}
      fullLabels={COMPLAINT_LABELS}
      shortLabels={COMPLAINT_CHART_LABELS}
      empty={`No reason complaints have been recorded for ${scopeLabel}.`}
      selectedValue={selectedValue}
      onSelect={onSelect}
    />
  );
}

function ClosureOutcomeChart({
  rows,
  scopeLabel,
  selectedValue,
  onSelect,
}: {
  rows: BreakdownRow[];
  scopeLabel: string;
  selectedValue: string;
  onSelect: (value: string) => void;
}) {
  return (
    <VerticalCategoryChart
      title="Closed issues by outcome"
      totalLabel="Total closed issues"
      rows={rows}
      fullLabels={CLOSED_OUTCOME_LABELS}
      shortLabels={CLOSURE_CHART_LABELS}
      empty={`No closed workflow issues are available for ${scopeLabel}.`}
      selectedValue={selectedValue}
      onSelect={onSelect}
    />
  );
}

function VerticalCategoryChart({
  title,
  totalLabel,
  rows,
  fullLabels,
  shortLabels,
  empty,
  selectedValue,
  onSelect,
}: {
  title: string;
  totalLabel: string;
  rows: BreakdownRow[];
  fullLabels: Record<string, string>;
  shortLabels: Record<string, string>;
  empty: string;
  selectedValue?: string;
  onSelect?: (value: string) => void;
}) {
  const counts = new Map(rows.map((row) => [row.value, row.count]));
  const chartRows = Object.keys(fullLabels).map((value) => ({
    value,
    count: counts.get(value) ?? 0,
  }));
  const total = chartRows.reduce((sum, row) => sum + row.count, 0);
  const max = Math.max(1, ...chartRows.map((row) => row.count));

  return (
    <Box borderWidth="1px" borderRadius="md" p={4} mb={6}>
      <Flex justify="space-between" align="baseline" gap={3} mb={4}>
        <Text fontWeight="bold">{title}</Text>
        <Text fontSize="sm" color="gray.600" whiteSpace="nowrap">
          {totalLabel}: {total}
        </Text>
      </Flex>
      <Box overflowX="auto" pb={2}>
        <SimpleGrid columns={chartRows.length} spacing={3} minW={`${chartRows.length * 100}px`}>
          {chartRows.map((row) => {
            const fullLabel = fullLabels[row.value] || titleize(row.value);
            const barHeight = row.count === 0 ? '3px' : `${Math.max(10, (row.count / max) * 150)}px`;
            const content = (
              <>
                <Flex h="185px" direction="column" justify="end" align="center" borderBottomWidth="1px">
                  <Text fontSize="sm" fontWeight="bold" mb={1}>
                    {row.count}
                  </Text>
                  <Box
                    role="img"
                    aria-label={`${fullLabel}: ${row.count}`}
                    title={`${fullLabel}: ${row.count}`}
                    w="56px"
                    maxW="80%"
                    h={barHeight}
                    bg={row.count === 0 ? 'gray.300' : 'blue.500'}
                    borderTopRadius="sm"
                  />
                </Flex>
                <Text fontSize="xs" textAlign="center" lineHeight="short" minH="48px" pt={2}>
                  {shortLabels[row.value] || fullLabel}
                </Text>
              </>
            );

            if (onSelect) {
              return (
                <Button
                  key={row.value}
                  aria-label={`Show ${fullLabel} examples`}
                  aria-pressed={selectedValue === row.value}
                  variant="ghost"
                  display="block"
                  h="auto"
                  minW={0}
                  p={1}
                  whiteSpace="normal"
                  borderWidth={selectedValue === row.value ? '2px' : '1px'}
                  borderColor={selectedValue === row.value ? 'blue.500' : 'transparent'}
                  bg={selectedValue === row.value ? 'blue.50' : undefined}
                  onClick={() => onSelect(row.value)}
                >
                  {content}
                </Button>
              );
            }

            return (
              <Box key={row.value} minW={0}>
                {content}
              </Box>
            );
          })}
        </SimpleGrid>
      </Box>
      {total === 0 && (
        <Text fontSize="sm" color="gray.500" mt={2}>
          {empty}
        </Text>
      )}
    </Box>
  );
}

function EvidenceTable({
  kind,
  rows,
  total,
  empty,
  loading = false,
  onLoadMore,
}: {
  kind: EvidenceKind;
  rows: EvidenceRow[];
  total: number;
  empty: string;
  loading?: boolean;
  onLoadMore: () => void;
}) {
  if (loading)
    return (
      <Flex py={10} justify="center">
        <Spinner />
      </Flex>
    );

  if (rows.length === 0)
    return (
      <Text py={8} textAlign="center" color="gray.500">
        {empty}
      </Text>
    );

  const showContextColumn = kind === 'complaints' || kind === 'contractor_follow_up';
  const contextHeading = kind === 'complaints' ? 'Admin complaint' : 'Sent rounds';
  const compactInvoiceIdentity =
    kind === 'complaints' ||
    kind === 'false_positives' ||
    kind === 'false_negatives' ||
    kind === 'contractor_follow_up' ||
    kind === 'closure_outcomes';

  return (
    <Box>
      <Box overflowX="auto">
        <Table size="sm">
          <Thead>
            <Tr>
              <Th>Date / invoice</Th>
              <Th>Rule result and reason</Th>
              {showContextColumn && <Th>{contextHeading}</Th>}
              <Th>Outcome</Th>
            </Tr>
          </Thead>
          <Tbody>
            {rows.map((row) => (
              <Tr key={row.rulecheck_id}>
                <Td minW="175px" verticalAlign="top">
                  <Text>{shortDate(row.rulecheck_created_at)}</Text>
                  {compactInvoiceIdentity ? (
                    <Link
                      as={RouterLink}
                      to={`/invoice-versions-by-version/${row.invoice_version_id}/read`}
                      color="blue.600"
                      fontSize="sm"
                      fontWeight="semibold"
                    >
                      {row.invoice_reference_number !== null && row.invoice_reference_number !== undefined
                        ? formatClaimsReferenceNumber(row.invoice_reference_number)
                        : `Version ${row.version_number}`}{' '}
                      <ArrowSquareOut display="inline" />
                    </Link>
                  ) : (
                    <>
                      {row.invoice_reference_number !== null && row.invoice_reference_number !== undefined && (
                        <Text fontWeight="semibold" fontSize="sm">
                          {formatClaimsReferenceNumber(row.invoice_reference_number)}
                        </Text>
                      )}
                      <Link
                        as={RouterLink}
                        to={`/invoice-versions-by-version/${row.invoice_version_id}/read`}
                        color="blue.600"
                        fontSize="sm"
                      >
                        Version {row.version_number} <ArrowSquareOut display="inline" />
                      </Link>
                      <Text fontSize="xs" color="gray.500">
                        {row.contractor_business_name}
                      </Text>
                    </>
                  )}
                </Td>
                <Td minW="320px" verticalAlign="top">
                  <Badge
                    colorScheme={row.rule_result === 'fail' ? 'red' : row.rule_result === 'warn' ? 'orange' : 'green'}
                  >
                    {row.rule_result}
                  </Badge>
                  <Text mt={2} fontSize="sm" whiteSpace="pre-wrap" noOfLines={5}>
                    {row.reason || 'No reason recorded.'}
                  </Text>
                </Td>
                {showContextColumn && (
                  <Td minW="270px" verticalAlign="top">
                    {kind === 'complaints' ? (
                      <>
                        <Text fontWeight="semibold" fontSize="sm">
                          {row.reason_complaint_code
                            ? COMPLAINT_LABELS[row.reason_complaint_code]
                            : 'No complaint category'}
                        </Text>
                        <Text mt={1} fontSize="sm" whiteSpace="pre-wrap">
                          {row.reason_complaint_text || 'No additional comment.'}
                        </Text>
                      </>
                    ) : (
                      <Text fontSize="2xl" fontWeight="bold">
                        {row.sent_round_count}
                      </Text>
                    )}
                  </Td>
                )}
                <Td minW="230px" verticalAlign="top">
                  <Text fontWeight="semibold" fontSize="sm">
                    {closureLabel(row.revision_issue_status)}
                  </Text>
                  {kind !== 'contractor_follow_up' && <Text fontSize="sm">Sent rounds: {row.sent_round_count}</Text>}
                  <Text mt={1} fontSize="sm" color="gray.600" whiteSpace="pre-wrap">
                    {row.disposition_comment || 'No disposition comment.'}
                  </Text>
                </Td>
              </Tr>
            ))}
          </Tbody>
        </Table>
      </Box>
      {rows.length < total && (
        <Flex justify="center" mt={4}>
          <Button variant="outline" size="sm" onClick={onLoadMore}>
            Load 25 more ({rows.length} of {total} shown)
          </Button>
        </Flex>
      )}
    </Box>
  );
}

function HelpSection({ title, children }: React.PropsWithChildren<{ title: string }>) {
  return (
    <AccordionItem borderWidth="1px" borderColor="gray.200" borderRadius="md" mb={3} overflow="hidden">
      <h3>
        <AccordionButton py={4} _expanded={{ bg: 'blue.50', color: 'blue.900' }}>
          <Text flex="1" textAlign="left" fontWeight="bold">
            {title}
          </Text>
          <AccordionIcon />
        </AccordionButton>
      </h3>
      <AccordionPanel pb={5} fontSize="sm" color="gray.700">
        {children}
      </AccordionPanel>
    </AccordionItem>
  );
}

function RuleImprovementHelp({
  isOpen,
  onClose,
  isCodeRule,
}: {
  isOpen: boolean;
  onClose: () => void;
  isCodeRule: boolean;
}) {
  return (
    <Drawer isOpen={isOpen} placement="right" onClose={onClose} size="lg">
      <DrawerOverlay />
      <DrawerContent>
        <DrawerCloseButton />
        <DrawerHeader>How to investigate a {isCodeRule ? 'code' : 'GenAI'} rule</DrawerHeader>
        <DrawerBody pb={8}>
          <Alert status="info" mb={4} alignItems="start">
            <AlertIcon mt={1} />
            <Text fontSize="sm">
              Use this report to choose one next step: tune the rule or its reason, improve contractor guidance or
              training, or keep observing. Start with a signal, inspect several underlying invoices, and act only when
              the evidence shows a repeatable pattern.
            </Text>
          </Alert>
          <Text fontSize="sm" color="gray.600" mb={4}>
            Open the section for the tab you are reviewing. All sections start collapsed so the guidance stays out of
            the way until you need it.
          </Text>

          <Accordion allowMultiple>
            <HelpSection title="Rule history">
              <Text mb={2}>
                Use this tab for more than identifying what changed. It connects each rule definition or implementation
                period to the results produced while it was effective, so you can judge whether a change actually
                improved the rule. Compare invoice volume, complaints, false-positive and false-negative candidates,
                follow-up and rounds between periods.
              </Text>
              {isCodeRule ? (
                <>
                  <Text mb={2}>
                    This table represents one executable-code implementation identified by its code-rule key. The row
                    information icon shows the complete database configuration—labels, messages, visibility and workflow
                    policy—but not the executable source code.
                  </Text>
                  <Text mb={2}>
                    When a code release changes the rule’s behaviour, development practice must create a new code-rule
                    key and database record. The application keeps keys unique and immutable, but cannot inspect source
                    code and enforce that release practice itself. A new record creates a clean measurement boundary so
                    the old and new implementations are not evaluated as if they were one rule.
                  </Text>
                </>
              ) : (
                <Text mb={2}>
                  Every saved GenAI rule change creates a new effective period. Use a row’s information icon to inspect
                  the complete rule values that applied during that period, including the prompt, messages, evidence
                  instructions and workflow settings. The other report tabs deliberately use only the current period;
                  this history table is where you compare it with earlier periods.
                </Text>
              )}
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Check sample size first:</strong> zero candidates across six assessed invoice versions is much
                  weaker evidence than zero across sixty comparable versions.
                </ListItem>
                <ListItem>
                  <strong>Compare rates as well as counts:</strong> five complaints after 200 checks may be an
                  improvement over four complaints after 20 checks. The table supplies counts and volume so you can make
                  that judgement rather than reading a raw total alone.
                </ListItem>
                <ListItem>
                  <strong>Check what changed:</strong> if false positives fall after narrowing applicability, that is a
                  plausible effect. If only contractor-facing wording changed, improved complaint and round patterns are
                  more meaningful than a change in detection accuracy.
                </ListItem>
                <ListItem>
                  <strong>Example:</strong> a prior period produced 12 false-positive candidates across 80 assessed
                  versions. The current period has none across only six. That is encouraging, but too early to conclude
                  that the change worked; keep observing until the current period has a credible sample and case mix.
                </ListItem>
                <ListItem>
                  <strong>Act on the comparison:</strong> retain a change when the intended measure improves without a
                  new adverse pattern. Investigate or reverse it when results worsen. Keep observing when volume is too
                  small or the invoice mix is not comparable.
                </ListItem>
              </UnorderedList>
            </HelpSection>

            <HelpSection title="Complaints">
              <Text mb={2}>
                Complaints concern the usefulness of the written reason, not necessarily the pass/fail result. The
                vertical chart always shows the full complaint vocabulary, including zeroes. The grid beneath it
                contains the exact reasons and comments behind the counts. Select a chart bar or use the complaint-type
                filter to narrow the grid while keeping the full distribution visible.
              </Text>
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Start with the distribution:</strong> one dominant complaint type usually gives a clearer next
                  step than an even mix. Then filter to that type and read several comments to confirm that
                  administrators used the pull-down consistently.
                </ListItem>
                <ListItem>
                  <strong>Separate correctness from helpfulness:</strong> if the rule correctly fails an invoice but the
                  reason does not say what is missing or how to fix it, improve the reason rather than weakening the
                  detection logic.
                </ListItem>
                <ListItem>
                  <strong>Possibly fine:</strong> an administrator prefers shorter wording, but the reason cites the
                  correct evidence and required action. A single stylistic complaint does not establish a pattern.
                </ListItem>
                <ListItem>
                  <strong>Likely needs improvement:</strong> repeated complaints say that the reason cites the wrong
                  document or never explains what the contractor must provide.
                </ListItem>
                <ListItem>
                  <strong>Useful interpretation:</strong> repeated <strong>Too verbose</strong> complaints usually
                  suggest a reason-writing change, while repeated <strong>Incorrect evidence or reasoning</strong>{' '}
                  complaints may require changes to evidence selection or the rule prompt.{' '}
                  <strong>Irrelevant or duplicate</strong> can expose an applicability or overlapping-rule problem.
                </ListItem>
                <ListItem>
                  <strong>Check concentration:</strong> complaints from one administrator may reflect a usage
                  difference; the same complaint across several administrators and contractors is stronger evidence of a
                  systemic problem.
                </ListItem>
                <ListItem>
                  <strong>Example action:</strong> when results are usually correct but administrators repeatedly select
                  <strong>Required action is unclear</strong>, rewrite the contractor-facing action and examples while
                  leaving the pass/fail logic alone. Review later periods to see whether that complaint declines.
                </ListItem>
              </UnorderedList>
            </HelpSection>

            <HelpSection title="False-positive candidates">
              <Text mb={2}>
                These began as warnings or failures and their rule issue closed with no contractor action required. That
                makes them candidates—not confirmed false positives.
              </Text>
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Review the complete chain:</strong> open the invoice version, read the original rule result
                  and evidence, then compare the workflow discussion and disposition comment. The closure label alone
                  cannot tell you why no contractor action was required.
                </ListItem>
                <ListItem>
                  <strong>Possibly fine:</strong> an administrator found acceptable evidence elsewhere, decided that no
                  action was needed for a legitimate case-specific reason, or used the no-action close type imprecisely.
                </ListItem>
                <ListItem>
                  <strong>Likely a rule problem:</strong> the same rule repeatedly fails invoices where the required
                  evidence is visibly present or the rule does not apply.
                </ListItem>
                <ListItem>
                  <strong>Example:</strong> 9 of 14 failures close with no action, and reviewers repeatedly state that
                  the model number was present on page two. That pattern supports narrowing the rule or improving how it
                  locates the evidence.
                </ListItem>
                <ListItem>
                  <strong>Use the denominator:</strong> three candidates across five assessed versions is a different
                  signal from three across five hundred. Confirm that the affected invoices were actually eligible for
                  the rule before treating the ratio as meaningful.
                </ListItem>
                <ListItem>
                  <strong>Look for a shared cause:</strong> repeated acceptable evidence in the same document location
                  suggests an evidence-search change; repeated inapplicability suggests a scope condition; inconsistent
                  no-action closures may instead require administrator guidance.
                </ListItem>
                <ListItem>
                  <strong>Choose the smallest action:</strong> tune rule logic only when the records show a repeatable
                  incorrect trigger. Improve the reason if detection is correct but the explanation caused confusion, or
                  keep observing when the cases do not share a cause.
                </ListItem>
              </UnorderedList>
            </HelpSection>

            <HelpSection title="False-negative candidates">
              <Text mb={2}>
                These checks passed or returned information, but a workflow issue is linked to that exact rulecheck.
                That link is why the row is a candidate: it suggests an administrator may have identified a problem the
                rule did not. It is still not proof of a false negative; review the original result, the workflow
                activity and the outcome together.
              </Text>
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Confirm the issue matches the rule:</strong> read the passing or informational result and the
                  linked workflow record. Treat it as a miss only when the later corrective request concerns the same
                  requirement this rule was meant to assess.
                </ListItem>
                <ListItem>
                  <strong>Possibly fine:</strong> the issue was created automatically by an all-results workflow policy,
                  remained pending without human follow-up, was opened as a precaution, or was linked to the wrong
                  source by an administrator.
                </ListItem>
                <ListItem>
                  <strong>Likely a rule problem:</strong> administrators repeatedly open issues for the exact defect
                  that the rule was designed to catch.
                </ListItem>
                <ListItem>
                  <strong>Example:</strong> the rule passes because an invoice mentions a permit, but administrators
                  repeatedly request the missing permit document itself. That suggests the rule is checking for the word
                  rather than the required evidence.
                </ListItem>
                <ListItem>
                  <strong>Distinguish severity from frequency:</strong> a rare miss involving a high-value or mandatory
                  requirement may still justify action. Several low-impact candidates may first warrant closer
                  monitoring or a targeted test case.
                </ListItem>
                <ListItem>
                  <strong>Look for what was missed:</strong> recurring missing attachments may require evidence-presence
                  logic; recurring wrong values may require a validation change; issues unrelated to the rule should be
                  corrected in workflow linkage or administrator practice instead.
                </ListItem>
                <ListItem>
                  <strong>After a change:</strong> add the confirmed examples to rule testing, then monitor the new
                  period for fewer equivalent misses without creating new false positives.
                </ListItem>
              </UnorderedList>
            </HelpSection>

            <HelpSection title="Workflow management rounds">
              <Text mb={2}>
                This tab measures operational effort, not blame. Compare how many invoice versions required follow-up
                with the total and average sent rounds, then inspect the grid to see what contractors were asked to
                correct. Use the minimum-round filter to start with the cases that required the most exchanges.
              </Text>
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Read the measures correctly:</strong> invoice versions with follow-up are distinct assessed
                  versions that produced a rule issue. Total rounds count sent administrator-to-contractor exchanges;
                  internal drafts do not count. Average rounds is calculated across issues with at least one sent round.
                </ListItem>
                <ListItem>
                  <strong>Start with the outliers:</strong> raise the minimum-round filter to find the invoices
                  requiring the most back-and-forth. Read their requests, responses and final disposition before
                  assuming that the contractor misunderstood the rule.
                </ListItem>
                <ListItem>
                  <strong>Likely straightforward:</strong> 30 invoice versions require follow-up, with 32 total rounds
                  and a 1.1 average. Most requests appear to be understood and resolved in one exchange.
                </ListItem>
                <ListItem>
                  <strong>Possible guidance or training problem:</strong> 8 versions require 21 rounds, and the records
                  show repeated omissions of the same equipment-specification page. Add a submission example or train
                  contractors on that requirement.
                </ListItem>
                <ListItem>
                  <strong>Target the response:</strong> if one contractor accounts for most repeated rounds, targeted
                  coaching may be appropriate. If many contractors make the same mistake, the program’s written
                  instructions or form design may be the real problem.
                </ListItem>
                <ListItem>
                  <strong>Do not equate rounds with rule accuracy:</strong> a correct rule can generate many rounds when
                  submission instructions are poor, and an incorrect rule can close in one round through an exception.
                  Use Complaints, Requests and responses, and Closure outcomes to identify the cause.
                </ListItem>
                <ListItem>
                  <strong>Example action:</strong> if many contractors repeatedly omit the same specification page, add
                  a checklist example or pre-submission instruction. If the same rule request itself changes from round
                  to round, improve administrator guidance or the rule’s required-action text.
                </ListItem>
              </UnorderedList>
            </HelpSection>

            <HelpSection title="Requests and responses">
              <Text mb={2}>
                These charts describe how the rule was used during the workflow before closure: the action
                administrators selected when sending a round and the response method contractors selected when replying.
                Every selection in a sent round is counted during the current measurement period, so an issue with
                several exchanges can be counted several times. The two totals need not match and the columns are not
                one-to-one pairings.
              </Text>
              <Text fontWeight="bold" mb={2}>
                What a recurring pattern can suggest
              </Text>
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Use the charts as a workflow map:</strong> first identify the most common administrator
                  request, then compare the response distribution and closure outcomes. Because the charts are
                  aggregates, open representative workflow records on the rounds or closure tabs before concluding that
                  two selections belonged to the same exchange.
                </ListItem>
                <ListItem>
                  <strong>Likely contractor guidance opportunity:</strong> admins repeatedly request a supporting
                  document, contractors then upload it, and the issues close through corrected documentation. The rule
                  may be working correctly, while the submission checklist or examples need improvement.
                </ListItem>
                <ListItem>
                  <strong>Possible requirement or rule problem:</strong> admins repeatedly request explanations, but
                  contractors frequently select <strong>Unable to resolve</strong>. Inspect the comments to learn
                  whether the evidence is unavailable, the requirement is unclear, or the rule is asking for something
                  unreasonable.
                </ListItem>
                <ListItem>
                  <strong>Possible communication mismatch:</strong> admins usually request a corrected invoice, while
                  contractors usually provide an explanation. The admin request wording, contractor instructions, or
                  workflow choices may not be expressing the intended next step clearly.
                </ListItem>
                <ListItem>
                  <strong>Healthy expected path:</strong> attestation requests are normally answered with attestations
                  and close through the attestation outcome. A stable matching pattern may require no change.
                </ListItem>
                <ListItem>
                  <strong>Watch for pull-down misuse:</strong> broad or inconsistent selections can obscure the real
                  pattern. If comments describe document requests while administrators select explanation, clarify the
                  pull-down definitions or train users before changing the rule.
                </ListItem>
                <ListItem>
                  <strong>Separate local and systemic patterns:</strong> one contractor repeatedly choosing Unable to
                  resolve may need direct support. The same response across contractors may mean that required evidence
                  is unavailable, the instruction is unclear, or the rule demands something the program cannot
                  reasonably substantiate.
                </ListItem>
              </UnorderedList>
            </HelpSection>

            <HelpSection title="Closure outcomes">
              <Text mb={2}>
                This chart contains only terminal closure outcomes. <strong>Pending admin review</strong> and{' '}
                <strong>Open</strong> are workflow states, not outcomes, so they are excluded from the chart and
                evidence total. Each bar counts closed issues, not invoices or rounds. Select a chart bar or choose an
                outcome to inspect the underlying invoice records and disposition comments.
              </Text>
              <UnorderedList spacing={2}>
                <ListItem>
                  <strong>Start with the dominant outcome:</strong> select its bar or filter, then sample the
                  disposition comments. Confirm that administrators are using the closure type consistently before
                  treating the chart as evidence about the rule.
                </ListItem>
                <ListItem>
                  <strong>Corrected documentation:</strong> the request was actionable; repeated occurrences may justify
                  clearer examples or training. Example: contractors repeatedly resubmit the same form with the missing
                  signature added.
                </ListItem>
                <ListItem>
                  <strong>Contractor attestation:</strong> the requirement may rely on information that is difficult to
                  document. Example: the contractor confirms an installation condition that photographs cannot
                  establish.
                </ListItem>
                <ListItem>
                  <strong>Approved exception:</strong> a legitimate case falls outside the ordinary rule. Repeated
                  similar exceptions may justify an explicit rule exception or policy clarification.
                </ListItem>
                <ListItem>
                  <strong>No contractor action required:</strong> investigate possible over-triggering or inconsistent
                  administration. A concentration here strengthens the false-positive signal but still requires record
                  review.
                </ListItem>
                <ListItem>
                  <strong>Invoice withdrawn:</strong> the invoice left the process. This is operational context, not
                  evidence by itself that either the rule or contractor was wrong.
                </ListItem>
                <ListItem>
                  <strong>Compare with other tabs:</strong> no-action closures strengthen the false-positive signal;
                  corrected-documentation closures plus repeated rounds suggest a submission-guidance problem; approved
                  exceptions concentrated around one scenario may justify an explicit applicability exception.
                </ListItem>
                <ListItem>
                  <strong>Do not force an action from a small sample:</strong> one unusual closure can be legitimate.
                  Look for repeated reasoning across several invoices, then decide whether to tune the rule, clarify
                  policy, improve training or keep observing.
                </ListItem>
              </UnorderedList>
            </HelpSection>
          </Accordion>
        </DrawerBody>
      </DrawerContent>
    </Drawer>
  );
}
