import {
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
  IconButton,
  Link,
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
  VStack,
  useDisclosure,
} from '@chakra-ui/react';
import { ArrowSquareOut, Info } from '@phosphor-icons/react';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Link as RouterLink, useParams } from 'react-router-dom';
import { formatClaimsReferenceNumber } from '../../../utils/format-claims-reference-number';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { REVISION_CLOSURE_LABELS } from '../../shared/claims/revision-closure-guidance';
import { buildImprovementActions } from './action-signals';
import { ActionSignalsOverview } from './action-signals-overview';
import { RuleImprovementProcess } from './improvement-process';
import { RulePackageAudits } from './package-audits';
import {
  BreakdownRow,
  COMPLAINT_LABELS,
  EvidenceRow,
  RuleBreakdowns,
  RuleMetrics,
  RuleRow,
  shortDate,
  titleize,
} from './types';

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
type EvidenceKind = 'complaints' | 'false_positives' | 'false_negatives' | 'contractor_follow_up' | 'closure_outcomes';

const EMPTY_BREAKDOWNS: RuleBreakdowns = {
  complaint_types: [],
  closure_types: [],
  admin_requests: [],
  contractor_responses: [],
  round_distribution: [],
};

const CLOSURE_LABELS: Record<string, string> = {
  pending_admin_review: 'Pending admin review',
  open: 'Open',
  ...REVISION_CLOSURE_LABELS,
};

const CLOSED_OUTCOME_LABELS = REVISION_CLOSURE_LABELS;

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
  const [rule, setRule] = useState<RuleRow | null>(null);
  const [timeline, setTimeline] = useState<Timeline | null>(null);
  const [breakdowns, setBreakdowns] = useState<RuleBreakdowns>(EMPTY_BREAKDOWNS);
  const [evidenceTab, setEvidenceTab] = useState(0);
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

  const isCodeRule = rule?.source_engine === 'code';
  const scopeLabel = isCodeRule ? 'this code implementation' : 'current rule version';
  const actions = useMemo(() => (rule ? buildImprovementActions(rule, breakdowns) : []), [rule, breakdowns]);

  return (
    <>
      <ThinBlueTitleBar
        title={rule ? `Rule Improvement Detail - ${rule.contractor_display_name}` : 'Rule Improvement Detail'}
      />
      <Container maxW="full" px={6} pb={4} pt={6}>
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
          <RuleImprovementProcess key={base} isCodeRule={isCodeRule} rule={rule} actions={actions}>
            <ActionSignalsOverview actions={actions} />
            <Tabs
              index={evidenceTab}
              onChange={setEvidenceTab}
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
              <TabList aria-label="Evidence details" overflowX="auto" overflowY="hidden">
                <Tab whiteSpace="nowrap">Rule history</Tab>
                <Tab whiteSpace="nowrap">Complaints</Tab>
                <Tab whiteSpace="nowrap">False-positives</Tab>
                <Tab whiteSpace="nowrap">False-negatives</Tab>
                <Tab whiteSpace="nowrap">Workflow management rounds</Tab>
                <Tab whiteSpace="nowrap">Requests and responses</Tab>
                <Tab whiteSpace="nowrap">Closure outcomes</Tab>
              </TabList>

              <TabPanels>
                <TabPanel p={3}>
                  <RuleHistoryTable periods={timeline?.periods ?? []} isCodeRule={isCodeRule} ruleKey={rule.rule_key} />
                </TabPanel>

                <TabPanel p={3}>
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
                      {breakdowns.complaint_types
                        .filter((row) => !Object.prototype.hasOwnProperty.call(COMPLAINT_LABELS, row.value))
                        .map((row) => (
                          <option key={row.value} value={row.value}>
                            {titleize(row.value)}
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
                  <Text fontSize="sm" fontWeight="semibold" mb={4}>
                    Total false-positives: {evidenceTotals.false_positives}
                  </Text>
                  <EvidenceTable
                    kind="false_positives"
                    rows={evidence.false_positives}
                    total={evidenceTotals.false_positives}
                    empty={`No false-positives are present for ${scopeLabel}.`}
                    onLoadMore={() => void loadMoreEvidence('false_positives')}
                  />
                </TabPanel>

                <TabPanel p={3}>
                  <Text fontSize="sm" fontWeight="semibold" mb={4}>
                    Total false-negatives: {evidenceTotals.false_negatives}
                  </Text>
                  <EvidenceTable
                    kind="false_negatives"
                    rows={evidence.false_negatives}
                    total={evidenceTotals.false_negatives}
                    empty={`No false-negatives are present for ${scopeLabel}.`}
                    onLoadMore={() => void loadMoreEvidence('false_negatives')}
                  />
                </TabPanel>

                <TabPanel p={3}>
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
            <RulePackageAudits rule={rule} evidenceUrl={apiUrl('/evidence')} auditUrl={apiUrl('/audit')} />
          </RuleImprovementProcess>
        )}
      </Container>
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
              <Th isNumeric>False-positives</Th>
              <Th isNumeric>False-negatives</Th>
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
  shortLabels?: Record<string, string>;
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
                  {shortLabels?.[row.value] || fullLabel}
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
