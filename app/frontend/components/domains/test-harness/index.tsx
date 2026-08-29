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
  Flex,
  FormControl,
  FormLabel,
  Grid,
  Heading,
  Input,
  Modal,
  ModalBody,
  ModalCloseButton,
  ModalContent,
  ModalFooter,
  ModalHeader,
  ModalOverlay,
  Select,
  Spinner,
  Stack,
  Table,
  Tbody,
  Td,
  Text,
  Th,
  Thead,
  Tooltip,
  Tr,
} from '@chakra-ui/react';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { RouterLink } from '../../shared/navigation/router-link';

const API = '/api/claims/admin/test_harness';

type DeploymentMap = {
  document_triage_deployment_name: string;
  supporting_document_extraction_deployment_name: string;
  upgrade_analysis_deployment_name: string;
  comparison_deployment_name?: string;
};

type SuiteCase = {
  id: string;
  testsuite_id: string;
  name: string;
  description?: string | null;
  baseline_invoice_version_id: string;
  baseline_ingest_run_id: string;
  invoice_reference_number?: string;
  original_filename?: string | null;
  deployments: DeploymentMap;
};

type Suite = {
  id: string;
  name: string;
  description?: string | null;
  case_count: number;
  has_runs?: boolean;
  cases?: SuiteCase[];
};

type Rule = {
  id: string;
  source_id?: string;
  rule_key: string;
  name?: string;
  prompt_text?: string;
  created_at?: string;
};
type Bootstrap = {
  deployments: DeploymentMap;
  deployment_options: string[];
  suites: Suite[];
  rules: Rule[];
  rule_histories: Rule[];
};

type EligibleVersion = {
  invoice_version_id: string;
  ingest_run_id: string;
  invoice_reference_number?: string;
  invoice_versionno?: number;
  original_filename?: string | null;
  deployments: DeploymentMap;
};

type HarnessCase = {
  id: string;
  name: string;
  status: string;
  failure_code?: string | null;
  baseline_invoice_version_id?: string;
  candidate_invoice_version_id?: string | null;
  invoice_version_id?: string | null;
  candidate_ingest_run_id?: string | null;
  ingest_run_id?: string | null;
  document_classification_comparison?: string | null;
  supporting_document_extraction_comparison?: string | null;
  upgrade_analysis_comparison?: string | null;
  rule_comparison?: string | null;
  result_summary?: string | null;
};

type HarnessRun = {
  id: string;
  testsuite_id: string;
  suite_name: string;
  status: string;
  case_count: number;
  completed_case_count: number;
  failed_case_count: number;
  created_at: string;
  cases?: HarnessCase[];
  [key: string]: any;
};

type Mode = 'model_compares' | 'rule_compares' | 'regressions';

async function request<T>(path: string, options?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    credentials: 'include',
    headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...(options?.headers || {}) },
    ...options,
  });
  if (!response.ok) {
    const payload = await response.json().catch(() => ({}));
    throw new Error(payload.error || `${response.status} ${response.statusText}`);
  }
  return response.status === 204 ? (undefined as T) : response.json();
}

function StatusBadge({ status }: { status: string }) {
  const color = status === 'completed' ? 'green' : status === 'failed' ? 'red' : status === 'draft' ? 'gray' : 'blue';
  return <Badge colorScheme={color}>{status.replace(/_/g, ' ')}</Badge>;
}

function ModelInput({
  label,
  value,
  onChange,
  options,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  options: string[];
}) {
  const listId = `models-${label.replace(/ /g, '-').toLowerCase()}`;
  return (
    <FormControl isRequired>
      <FormLabel fontSize="sm">{label}</FormLabel>
      <Input list={listId} value={value} onChange={(event) => onChange(event.target.value)} />
      <datalist id={listId}>
        {options.map((option) => (
          <option key={option} value={option} />
        ))}
      </datalist>
    </FormControl>
  );
}

export function TestSuitesScreen() {
  const [suites, setSuites] = useState<Suite[]>([]);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  async function load() {
    setLoading(true);
    setError(null);
    try {
      const suiteData = await request<{ rows: Suite[] }>('/suites');
      setSuites(suiteData.rows);
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, []);

  async function createSuite() {
    try {
      await request('/suites', { method: 'POST', body: JSON.stringify({ name, description }) });
      setName('');
      setDescription('');
      await load();
    } catch (reason: any) {
      setError(reason.message);
    }
  }

  async function updateSuite(suite: Suite) {
    const nextName = window.prompt('Suite name', suite.name);
    if (!nextName) return;
    const nextDescription = window.prompt('Description', suite.description || '') ?? suite.description;
    try {
      await request(`/suites/${suite.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ name: nextName, description: nextDescription }),
      });
      await load();
    } catch (reason: any) {
      setError(reason.message);
    }
  }

  async function deleteSuite(suite: Suite) {
    if (!window.confirm(`Delete test suite “${suite.name}”?`)) return;
    try {
      await request(`/suites/${suite.id}`, { method: 'DELETE' });
      await load();
    } catch (reason: any) {
      setError(reason.message);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Test Suites" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Box borderWidth="1px" borderRadius="lg" p={4} mb={6} bg="white">
          <Heading size="sm" mb={4}>
            Add Test Suite
          </Heading>
          <Grid templateColumns={{ base: '1fr', md: '1fr 2fr auto' }} gap={4} alignItems="end">
            <FormControl isRequired>
              <FormLabel fontSize="sm">Name</FormLabel>
              <Input value={name} onChange={(event) => setName(event.target.value)} />
            </FormControl>
            <FormControl>
              <FormLabel fontSize="sm">Description</FormLabel>
              <Input value={description} onChange={(event) => setDescription(event.target.value)} />
            </FormControl>
            <Button colorScheme="blue" onClick={createSuite} isDisabled={!name.trim()}>
              Add
            </Button>
          </Grid>
        </Box>
        {loading ? (
          <Spinner />
        ) : (
          <Box borderWidth="1px" borderRadius="lg" bg="white" overflowX="auto">
            <Table>
              <Thead>
                <Tr>
                  <Th>Name</Th>
                  <Th>Description</Th>
                  <Th isNumeric>Cases</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {suites.map((suite) => (
                  <Tr key={suite.id}>
                    <Td fontWeight="600">{suite.name}</Td>
                    <Td>{suite.description || '—'}</Td>
                    <Td isNumeric>{suite.case_count}</Td>
                    <Td>
                      <Flex gap={2} justify="flex-end">
                        <Button
                          as={RouterLink}
                          to={`/test-harness/suites/${suite.id}/cases`}
                          size="sm"
                          variant="outline"
                        >
                          Edit/View Cases
                        </Button>
                        <Button size="sm" variant="outline" onClick={() => updateSuite(suite)}>
                          Edit
                        </Button>
                        <Tooltip
                          label="This test suite cannot be deleted because it has been used by one or more test runs."
                          isDisabled={!suite.has_runs}
                        >
                          <Box as="span" display="inline-block">
                            <Button
                              size="sm"
                              variant="outline"
                              colorScheme="red"
                              onClick={() => deleteSuite(suite)}
                              isDisabled={suite.has_runs}
                            >
                              Delete
                            </Button>
                          </Box>
                        </Tooltip>
                      </Flex>
                    </Td>
                  </Tr>
                ))}
              </Tbody>
            </Table>
          </Box>
        )}
      </Container>
    </Box>
  );
}

export function TestSuiteCasesScreen() {
  const { testsuiteId = '' } = useParams<{ testsuiteId: string }>();
  const [suite, setSuite] = useState<Suite | null>(null);
  const [versions, setVersions] = useState<EligibleVersion[]>([]);
  const [selectedVersion, setSelectedVersion] = useState<EligibleVersion | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [versionQuery, setVersionQuery] = useState('');
  const [isAddOpen, setIsAddOpen] = useState(false);
  const [hasSearched, setHasSearched] = useState(false);
  const [searching, setSearching] = useState(false);
  const [adding, setAdding] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const suiteData = await request<Suite>(`/suites/${testsuiteId}`);
      setSuite(suiteData);
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setLoading(false);
    }
  }, [testsuiteId]);

  useEffect(() => {
    load();
  }, [load]);

  async function searchVersions() {
    setSearching(true);
    try {
      const data = await request<{ rows: EligibleVersion[] }>(
        `/invoice_versions${versionQuery.trim() ? `?q=${encodeURIComponent(versionQuery.trim())}` : ''}`,
      );
      setVersions(data.rows);
      setHasSearched(true);
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setSearching(false);
    }
  }

  async function createCase() {
    if (!testsuiteId || !name.trim() || !selectedVersion) return;
    setAdding(true);
    try {
      await request(`/suites/${testsuiteId}/cases`, {
        method: 'POST',
        body: JSON.stringify({
          name,
          description,
          baseline_invoice_version_id: selectedVersion.invoice_version_id,
          baseline_ingest_run_id: selectedVersion.ingest_run_id,
        }),
      });
      closeAddModal();
      await load();
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setAdding(false);
    }
  }

  function openAddModal() {
    setVersions([]);
    setVersionQuery('');
    setHasSearched(false);
    setSelectedVersion(null);
    setName('');
    setDescription('');
    setIsAddOpen(true);
  }

  function closeAddModal() {
    setIsAddOpen(false);
    setSelectedVersion(null);
    setName('');
    setDescription('');
  }

  async function updateCase(testCase: SuiteCase) {
    const nextName = window.prompt('Name', testCase.name);
    if (!nextName) return;
    const nextDescription = window.prompt('Description', testCase.description || '') ?? testCase.description;
    try {
      await request(`/suite_cases/${testCase.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ name: nextName, description: nextDescription }),
      });
      await load();
    } catch (reason: any) {
      setError(reason.message);
    }
  }

  async function deleteCase(testCase: SuiteCase) {
    if (!window.confirm(`Remove test suite case “${testCase.name}”?`)) return;
    try {
      await request(`/suite_cases/${testCase.id}`, { method: 'DELETE' });
      await load();
    } catch (reason: any) {
      setError(reason.message);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Test Suite Cases" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        {suite && (
          <Flex mb={5} justify="space-between" align="end" gap={4}>
            <Box>
              <Heading size="md">{suite.name}</Heading>
              {suite.description && <Text color="gray.600">{suite.description}</Text>}
            </Box>
            <Button colorScheme="blue" onClick={openAddModal}>
              Add Cases
            </Button>
          </Flex>
        )}

        {loading ? (
          <Spinner />
        ) : (
          <Box borderWidth="1px" borderRadius="lg" bg="white" overflowX="auto">
            <Table>
              <Thead>
                <Tr>
                  <Th>Name</Th>
                  <Th>Description</Th>
                  <Th>Baseline Invoice Version</Th>
                  <Th>Baseline Ingest Run</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {(suite?.cases || []).map((testCase) => (
                  <Tr key={testCase.id}>
                    <Td fontWeight="600">{testCase.name}</Td>
                    <Td>{testCase.description || '—'}</Td>
                    <Td>
                      <RouterLink
                        to={`/invoice-versions-by-version/${testCase.baseline_invoice_version_id}/read`}
                        color="blue.600"
                        fontWeight="600"
                      >
                        {testCase.invoice_reference_number
                          ? `#${testCase.invoice_reference_number}`
                          : testCase.baseline_invoice_version_id}
                      </RouterLink>
                    </Td>
                    <Td fontSize="xs">{testCase.baseline_ingest_run_id}</Td>
                    <Td>
                      <Flex gap={2} justify="flex-end">
                        <Button size="sm" variant="outline" onClick={() => updateCase(testCase)}>
                          Edit
                        </Button>
                        <Button size="sm" variant="outline" colorScheme="red" onClick={() => deleteCase(testCase)}>
                          Delete
                        </Button>
                      </Flex>
                    </Td>
                  </Tr>
                ))}
              </Tbody>
            </Table>
          </Box>
        )}

        <Modal isOpen={isAddOpen} onClose={closeAddModal} size="6xl" isCentered>
          <ModalOverlay />
          <ModalContent>
            <ModalHeader>{selectedVersion ? 'Add Test Suite Case' : 'Find Invoice Version'}</ModalHeader>
            <ModalCloseButton />
            <ModalBody>
              {selectedVersion ? (
                <Stack spacing={5}>
                  <Box borderWidth="1px" borderRadius="md" p={4} bg="gray.50">
                    <Text fontWeight="700">
                      {selectedVersion.invoice_reference_number
                        ? `Invoice #${selectedVersion.invoice_reference_number}`
                        : 'Invoice version'}{' '}
                      · Version {selectedVersion.invoice_versionno}
                    </Text>
                    <Text>{selectedVersion.original_filename || selectedVersion.invoice_version_id}</Text>
                    <Text fontSize="xs" color="gray.600" mt={2}>
                      Ingest run: {selectedVersion.ingest_run_id}
                    </Text>
                  </Box>
                  <FormControl isRequired>
                    <FormLabel>Name</FormLabel>
                    <Input value={name} onChange={(event) => setName(event.target.value)} />
                  </FormControl>
                  <FormControl>
                    <FormLabel>Description</FormLabel>
                    <Input value={description} onChange={(event) => setDescription(event.target.value)} />
                  </FormControl>
                </Stack>
              ) : (
                <Stack spacing={4}>
                  <Flex gap={3} align="end">
                    <FormControl>
                      <FormLabel>Invoice Version Search</FormLabel>
                      <Input
                        placeholder="Reference number, file name, or invoice version UUID"
                        value={versionQuery}
                        onChange={(event) => setVersionQuery(event.target.value)}
                        onKeyDown={(event) => event.key === 'Enter' && searchVersions()}
                      />
                    </FormControl>
                    <Button variant="outline" onClick={searchVersions} isLoading={searching}>
                      Search
                    </Button>
                  </Flex>
                  {hasSearched && (
                    <Box borderWidth="1px" borderRadius="md" overflowX="auto">
                      <Table size="sm">
                        <Thead>
                          <Tr>
                            <Th>Invoice</Th>
                            <Th>Version</Th>
                            <Th>Original File Name</Th>
                            <Th>Baseline Models</Th>
                            <Th />
                          </Tr>
                        </Thead>
                        <Tbody>
                          {versions.map((version) => {
                            const alreadyAdded = (suite?.cases || []).some(
                              (testCase) => testCase.baseline_invoice_version_id === version.invoice_version_id,
                            );
                            return (
                              <Tr key={`${version.invoice_version_id}-${version.ingest_run_id}`}>
                                <Td>
                                  {version.invoice_reference_number ? `#${version.invoice_reference_number}` : '—'}
                                </Td>
                                <Td>{version.invoice_versionno}</Td>
                                <Td>{version.original_filename || '—'}</Td>
                                <Td fontSize="xs">
                                  {Object.values(version.deployments).filter(Boolean).join(' · ') || 'Missing'}
                                </Td>
                                <Td textAlign="right">
                                  <Button
                                    size="sm"
                                    variant="outline"
                                    onClick={() => setSelectedVersion(version)}
                                    isDisabled={alreadyAdded}
                                  >
                                    {alreadyAdded ? 'Added' : 'Add'}
                                  </Button>
                                </Td>
                              </Tr>
                            );
                          })}
                          {versions.length === 0 && (
                            <Tr>
                              <Td colSpan={5} textAlign="center" color="gray.600" py={6}>
                                No accepted invoice versions matched the search.
                              </Td>
                            </Tr>
                          )}
                        </Tbody>
                      </Table>
                    </Box>
                  )}
                </Stack>
              )}
            </ModalBody>
            <ModalFooter gap={3}>
              {selectedVersion ? (
                <>
                  <Button variant="outline" onClick={() => setSelectedVersion(null)}>
                    Back
                  </Button>
                  <Button colorScheme="blue" onClick={createCase} isDisabled={!name.trim()} isLoading={adding}>
                    Add Case
                  </Button>
                </>
              ) : (
                <Button variant="outline" onClick={closeAddModal}>
                  Close
                </Button>
              )}
            </ModalFooter>
          </ModalContent>
        </Modal>
      </Container>
    </Box>
  );
}

function RunDetail({ mode, run, onRun, busy }: { mode: Mode; run: HarnessRun; onRun: () => void; busy: boolean }) {
  const overall =
    mode === 'model_compares'
      ? [
          ['Document classification', run.overall_document_classification_comparison],
          ['Supporting document extraction', run.overall_supporting_document_extraction_comparison],
          ['Upgrade analysis', run.overall_upgrade_analysis_comparison],
        ]
      : mode === 'rule_compares'
        ? [['Overall rule comparison', run.overall_rule_comparison]]
        : [];
  const configuration =
    mode === 'model_compares'
      ? [
          [
            'Document classification',
            `${run.baseline_document_triage_deployment_name} → ${run.candidate_document_triage_deployment_name}`,
          ],
          [
            'Supporting extraction',
            `${run.baseline_supporting_document_extraction_deployment_name} → ${run.candidate_supporting_document_extraction_deployment_name}`,
          ],
          [
            'Upgrade analysis',
            `${run.baseline_upgrade_analysis_deployment_name} → ${run.candidate_upgrade_analysis_deployment_name}`,
          ],
          ['Comparison model', run.comparison_deployment_name],
        ]
      : mode === 'rule_compares'
        ? [
            ['Rule', run.rule_key],
            [
              'Baseline definition',
              run.baseline_rule_history_created_at
                ? new Date(run.baseline_rule_history_created_at).toLocaleString()
                : run.baseline_genai_rule_history_id,
            ],
            ['Candidate rule', run.candidate_rule_name || run.candidate_genai_rule_id],
            ['Comparison model', run.comparison_deployment_name],
          ]
        : [
            ['Document classification', run.document_triage_deployment_name],
            ['Supporting extraction', run.supporting_document_extraction_deployment_name],
            ['Upgrade analysis', run.upgrade_analysis_deployment_name],
          ];
  return (
    <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
      <Flex justify="space-between" align="center" mb={4}>
        <Box>
          <Heading size="sm">{run.suite_name}</Heading>
          <Text fontSize="xs" color="gray.500">
            {run.id}
          </Text>
        </Box>
        <Flex gap={2} align="center">
          <StatusBadge status={run.status} />
          {run.status === 'draft' && (
            <Button colorScheme="blue" onClick={onRun} isLoading={busy}>
              Run now
            </Button>
          )}
        </Flex>
      </Flex>
      <Box borderWidth="1px" borderRadius="md" mb={5} overflow="hidden">
        <Table size="sm">
          <Tbody>
            {configuration.map(([label, value]) => (
              <Tr key={label}>
                <Td fontWeight="700" width="38%">
                  {label}
                </Td>
                <Td wordBreak="break-word">{value || 'Not configured'}</Td>
              </Tr>
            ))}
          </Tbody>
        </Table>
      </Box>
      {overall.some(([, value]) => value) && (
        <Stack spacing={3} mb={5}>
          {overall.map(
            ([label, value]) =>
              value && (
                <Box key={label} borderLeftWidth="4px" borderColor="blue.500" pl={3}>
                  <Text fontWeight="700">{label}</Text>
                  <Text whiteSpace="pre-wrap">{value}</Text>
                </Box>
              ),
          )}
        </Stack>
      )}
      {['queued', 'running'].includes(run.status) && (
        <Flex align="center" gap={3} mb={4}>
          <Spinner size="sm" />
          <Text>Cases are processing. This detail refreshes automatically.</Text>
        </Flex>
      )}
      <Accordion allowMultiple>
        {(run.cases || []).map((testCase) => (
          <AccordionItem key={testCase.id}>
            <AccordionButton>
              <Box flex="1" textAlign="left">
                <Flex align="center" gap={3}>
                  <Text fontWeight="600">{testCase.name}</Text>
                  <StatusBadge status={testCase.status} />
                  {testCase.failure_code && (
                    <Text color="red.600" fontSize="sm">
                      {testCase.failure_code}
                    </Text>
                  )}
                </Flex>
              </Box>
              <AccordionIcon />
            </AccordionButton>
            <AccordionPanel>
              <CaseResult mode={mode} testCase={testCase} />
            </AccordionPanel>
          </AccordionItem>
        ))}
      </Accordion>
    </Box>
  );
}

function CaseResult({ mode, testCase }: { mode: Mode; testCase: HarnessCase }) {
  const generatedVersionId = testCase.candidate_invoice_version_id || testCase.invoice_version_id;
  const results =
    mode === 'model_compares'
      ? [
          ['Document classification', testCase.document_classification_comparison],
          ['Supporting document extraction', testCase.supporting_document_extraction_comparison],
          ['Upgrade analysis', testCase.upgrade_analysis_comparison],
        ]
      : mode === 'rule_compares'
        ? [['Rule comparison', testCase.rule_comparison]]
        : [['Regression result', testCase.result_summary]];
  return (
    <Stack spacing={3}>
      {results.map(([label, value]) => (
        <Box key={label}>
          <Text fontWeight="700" fontSize="sm">
            {label}
          </Text>
          <Text whiteSpace="pre-wrap" color={value ? 'inherit' : 'gray.500'}>
            {value || 'Not available yet.'}
          </Text>
        </Box>
      ))}
      <Text fontSize="xs" color="gray.500">
        Generated invoice version:{' '}
        {generatedVersionId ? (
          <RouterLink to={`/invoice-versions-by-version/${generatedVersionId}/read`} color="blue.600" fontWeight="600">
            {generatedVersionId}
          </RouterLink>
        ) : (
          'pending'
        )}
        <br />
        Generated ingest run: {testCase.candidate_ingest_run_id || testCase.ingest_run_id || 'pending'}
      </Text>
    </Stack>
  );
}

export function ModelComparisonsScreen() {
  const [runs, setRuns] = useState<HarnessRun[]>([]);
  const [searchInput, setSearchInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [suiteId, setSuiteId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  useEffect(() => {
    request<{ rows: HarnessRun[] }>('/model_compares')
      .then((data) => setRuns(data.rows))
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const suites = useMemo(
    () => Array.from(new Map(runs.map((run) => [run.testsuite_id, run.suite_name])).entries()),
    [runs],
  );
  const normalizedSearchQuery = searchQuery.trim().toLowerCase();
  const visibleRuns = runs.filter((run) => {
    const matchesSearch =
      !normalizedSearchQuery ||
      [run.suite_name, run.id, run.status.replace(/_/g, ' ')].some((value) =>
        value.toLowerCase().includes(normalizedSearchQuery),
      );

    return matchesSearch && (!suiteId || run.testsuite_id === suiteId);
  });

  const submitSearch = (event: React.FormEvent<HTMLDivElement>) => {
    event.preventDefault();
    setSearchQuery(searchInput);
  };

  async function deleteRun(run: HarnessRun) {
    if (!window.confirm(`Delete model comparison run for “${run.suite_name}”?`)) return;
    setDeletingId(run.id);
    setError(null);
    try {
      await request(`/model_compares/${run.id}`, { method: 'DELETE' });
      setRuns((current) => current.filter((item) => item.id !== run.id));
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Model Comparison Runs" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Flex justify="space-between" align="center" mb={5}>
          <Heading size="md">Model Comparison Runs</Heading>
          <Button as={RouterLink} to="/test-harness/model-comparisons/new" colorScheme="blue">
            New Model Comparison
          </Button>
        </Flex>
        <Flex as="form" onSubmit={submitSearch} gap={3} mb={4} wrap="wrap">
          <Input
            maxW="320px"
            value={searchInput}
            onChange={(event) => setSearchInput(event.target.value)}
            placeholder="Search suite name or comparison ID"
            aria-label="Search model comparisons"
          />
          <Button type="submit" colorScheme="blue">
            Search
          </Button>
          <Select
            maxW="320px"
            value={suiteId}
            onChange={(event) => setSuiteId(event.target.value)}
            aria-label="Filter by test suite"
          >
            <option value="">All test suites</option>
            {suites.map(([id, suiteName]) => (
              <option key={id} value={id}>
                {suiteName}
              </option>
            ))}
          </Select>
        </Flex>
        {loading ? (
          <Spinner />
        ) : (
          <Box borderWidth="1px" borderRadius="lg" overflowX="auto" bg="white">
            <Table>
              <Thead>
                <Tr>
                  <Th>Test Suite</Th>
                  <Th>Status</Th>
                  <Th>Created</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {visibleRuns.map((run) => (
                  <Tr key={run.id}>
                    <Td fontWeight="600">{run.suite_name}</Td>
                    <Td>
                      <StatusBadge status={run.status} />
                    </Td>
                    <Td>{new Date(run.created_at).toLocaleString()}</Td>
                    <Td textAlign="right">
                      <Flex gap={2} justify="flex-end">
                        <Button
                          as={RouterLink}
                          to={`/test-harness/model-comparisons/${run.id}`}
                          size="sm"
                          variant="outline"
                        >
                          View
                        </Button>
                        <Button
                          size="sm"
                          colorScheme="red"
                          variant="outline"
                          onClick={() => deleteRun(run)}
                          isLoading={deletingId === run.id}
                          isDisabled={['queued', 'running'].includes(run.status)}
                          title={
                            ['queued', 'running'].includes(run.status)
                              ? 'Queued or running test runs cannot be deleted.'
                              : undefined
                          }
                        >
                          Delete
                        </Button>
                      </Flex>
                    </Td>
                  </Tr>
                ))}
                {visibleRuns.length === 0 && (
                  <Tr>
                    <Td colSpan={4} textAlign="center" color="gray.600" py={8}>
                      No model comparison runs found.
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
        )}
      </Container>
    </Box>
  );
}

export function NewModelComparisonScreen() {
  const navigate = useNavigate();
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null);
  const [suiteId, setSuiteId] = useState('');
  const [selectedSuite, setSelectedSuite] = useState<Suite | null>(null);
  const [models, setModels] = useState<DeploymentMap>({
    document_triage_deployment_name: '',
    supporting_document_extraction_deployment_name: '',
    upgrade_analysis_deployment_name: '',
    comparison_deployment_name: '',
  });
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingSuite, setLoadingSuite] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    request<Bootstrap>('/bootstrap')
      .then((data) => {
        setBootstrap(data);
        setModels(data.deployments);
      })
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    if (!suiteId) {
      setSelectedSuite(null);
      return;
    }
    setLoadingSuite(true);
    request<Suite>(`/suites/${suiteId}`)
      .then(setSelectedSuite)
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoadingSuite(false));
  }, [suiteId]);

  const baseline = selectedSuite?.cases?.[0]?.deployments;
  const canCreate =
    suiteId &&
    selectedSuite?.case_count &&
    models.document_triage_deployment_name.trim() &&
    models.supporting_document_extraction_deployment_name.trim() &&
    models.upgrade_analysis_deployment_name.trim() &&
    models.comparison_deployment_name?.trim();

  async function createRun() {
    setBusy(true);
    setError(null);
    try {
      const row = await request<HarnessRun>('/model_compares', {
        method: 'POST',
        body: JSON.stringify({
          testsuite_id: suiteId,
          candidate_document_triage_deployment_name: models.document_triage_deployment_name,
          candidate_supporting_document_extraction_deployment_name:
            models.supporting_document_extraction_deployment_name,
          candidate_upgrade_analysis_deployment_name: models.upgrade_analysis_deployment_name,
          comparison_deployment_name: models.comparison_deployment_name,
        }),
      });
      navigate(`/test-harness/model-comparisons/${row.id}`);
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="New Model Comparison" />
      <Container maxW="5xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Heading size="md" mb={5}>
          New Model Comparison
        </Heading>
        {loading ? (
          <Spinner />
        ) : (
          <Stack spacing={6}>
            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <FormControl isRequired>
                <FormLabel>Test Suite</FormLabel>
                <Select value={suiteId} onChange={(event) => setSuiteId(event.target.value)}>
                  <option value="">Select a test suite</option>
                  {bootstrap?.suites.map((suite) => (
                    <option key={suite.id} value={suite.id}>
                      {suite.name} ({suite.case_count} cases)
                    </option>
                  ))}
                </Select>
              </FormControl>
            </Box>

            {suiteId && (
              <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
                <Heading size="sm" mb={4}>
                  Baseline Models
                </Heading>
                {loadingSuite ? (
                  <Spinner size="sm" />
                ) : selectedSuite?.case_count ? (
                  <Table size="sm">
                    <Tbody>
                      <Tr>
                        <Td fontWeight="700">Document classification</Td>
                        <Td>{baseline?.document_triage_deployment_name || 'Missing'}</Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="700">Supporting document extraction</Td>
                        <Td>{baseline?.supporting_document_extraction_deployment_name || 'Missing'}</Td>
                      </Tr>
                      <Tr>
                        <Td fontWeight="700">Upgrade analysis</Td>
                        <Td>{baseline?.upgrade_analysis_deployment_name || 'Missing'}</Td>
                      </Tr>
                    </Tbody>
                  </Table>
                ) : (
                  <Alert status="warning">
                    <AlertIcon />
                    This test suite has no cases.
                  </Alert>
                )}
              </Box>
            )}

            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <Heading size="sm" mb={4}>
                Candidate and Comparison Models
              </Heading>
              <Stack spacing={4}>
                <ModelInput
                  label="Document classification model"
                  value={models.document_triage_deployment_name}
                  onChange={(value) => setModels({ ...models, document_triage_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
                <ModelInput
                  label="Supporting extraction model"
                  value={models.supporting_document_extraction_deployment_name}
                  onChange={(value) => setModels({ ...models, supporting_document_extraction_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
                <ModelInput
                  label="Upgrade analysis model"
                  value={models.upgrade_analysis_deployment_name}
                  onChange={(value) => setModels({ ...models, upgrade_analysis_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
                <ModelInput
                  label="Comparison model"
                  value={models.comparison_deployment_name || ''}
                  onChange={(value) => setModels({ ...models, comparison_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
              </Stack>
            </Box>
            <Flex justify="flex-end" gap={3}>
              <Button as={RouterLink} to="/test-harness/model-comparisons" variant="outline">
                Cancel
              </Button>
              <Button colorScheme="blue" onClick={createRun} isDisabled={!canCreate} isLoading={busy}>
                Create Draft
              </Button>
            </Flex>
          </Stack>
        )}
      </Container>
    </Box>
  );
}

export function ModelComparisonResultsScreen() {
  const { modelComparisonId = '' } = useParams<{ modelComparisonId: string }>();
  const [run, setRun] = useState<HarnessRun | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setRun(await request<HarnessRun>(`/model_compares/${modelComparisonId}`));
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setLoading(false);
    }
  }, [modelComparisonId]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!run || !['queued', 'running'].includes(run.status)) return;
    const timer = window.setInterval(load, 5000);
    return () => window.clearInterval(timer);
  }, [load, run]);

  async function submitRun() {
    if (!run) return;
    setBusy(true);
    setError(null);
    try {
      setRun(
        await request<HarnessRun>(`/model_compares/${run.id}/submit`, {
          method: 'POST',
          body: '{}',
        }),
      );
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Model Comparison Results" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Flex justify="space-between" align="center" mb={5}>
          <Heading size="md">Model Comparison Results</Heading>
          <Button as={RouterLink} to="/test-harness/model-comparisons" variant="outline">
            Back to Model Comparison Runs
          </Button>
        </Flex>
        {loading ? (
          <Spinner />
        ) : run ? (
          <RunDetail mode="model_compares" run={run} onRun={submitRun} busy={busy} />
        ) : null}
      </Container>
    </Box>
  );
}

export function RuleComparisonsScreen() {
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null);
  const [runs, setRuns] = useState<HarnessRun[]>([]);
  const [searchInput, setSearchInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [suiteId, setSuiteId] = useState('');
  const [ruleId, setRuleId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  useEffect(() => {
    Promise.all([request<Bootstrap>('/bootstrap'), request<{ rows: HarnessRun[] }>('/rule_compares')])
      .then(([bootstrapData, runData]) => {
        setBootstrap(bootstrapData);
        setRuns(runData.rows);
      })
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const normalizedSearchQuery = searchQuery.trim().toLowerCase();
  const visibleRuns = runs.filter((run) => {
    const matchesSearch =
      !normalizedSearchQuery ||
      [run.suite_name, run.id, run.rule_key, run.candidate_rule_name, run.status]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(normalizedSearchQuery));

    return (
      matchesSearch && (!suiteId || run.testsuite_id === suiteId) && (!ruleId || run.candidate_genai_rule_id === ruleId)
    );
  });

  const submitSearch = (event: React.FormEvent<HTMLDivElement>) => {
    event.preventDefault();
    setSearchQuery(searchInput);
  };

  async function deleteRun(run: HarnessRun) {
    if (!window.confirm(`Delete rule comparison run for “${run.rule_key}” in “${run.suite_name}”?`)) return;
    setDeletingId(run.id);
    setError(null);
    try {
      await request(`/rule_compares/${run.id}`, { method: 'DELETE' });
      setRuns((current) => current.filter((item) => item.id !== run.id));
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Rule Comparison Runs" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Flex justify="space-between" align="center" mb={5}>
          <Heading size="md">Rule Comparison Runs</Heading>
          <Button as={RouterLink} to="/test-harness/rule-comparisons/new" colorScheme="blue">
            New Rule Comparison
          </Button>
        </Flex>
        <Flex as="form" onSubmit={submitSearch} gap={3} mb={4} wrap="wrap">
          <Input
            maxW="320px"
            value={searchInput}
            onChange={(event) => setSearchInput(event.target.value)}
            placeholder="Search suite, rule, or comparison ID"
            aria-label="Search rule comparisons"
          />
          <Button type="submit" colorScheme="blue">
            Search
          </Button>
          <Select
            maxW="320px"
            value={suiteId}
            onChange={(event) => setSuiteId(event.target.value)}
            aria-label="Filter by test suite"
          >
            <option value="">All test suites</option>
            {bootstrap?.suites.map((suite) => (
              <option key={suite.id} value={suite.id}>
                {suite.name}
              </option>
            ))}
          </Select>
          <Select
            maxW="320px"
            value={ruleId}
            onChange={(event) => setRuleId(event.target.value)}
            aria-label="Filter by rule"
          >
            <option value="">All rules</option>
            {bootstrap?.rules.map((rule) => (
              <option key={rule.id} value={rule.id}>
                {rule.rule_key} — {rule.name}
              </option>
            ))}
          </Select>
        </Flex>
        {loading ? (
          <Spinner />
        ) : (
          <Box borderWidth="1px" borderRadius="lg" overflowX="auto" bg="white">
            <Table>
              <Thead>
                <Tr>
                  <Th>Test Suite</Th>
                  <Th>Rule</Th>
                  <Th>Status</Th>
                  <Th>Progress</Th>
                  <Th>Created</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {visibleRuns.map((run) => (
                  <Tr key={run.id}>
                    <Td fontWeight="600">{run.suite_name}</Td>
                    <Td>
                      <Text fontWeight="600">{run.rule_key}</Text>
                      <Text fontSize="xs" color="gray.600">
                        {run.candidate_rule_name}
                      </Text>
                    </Td>
                    <Td>
                      <StatusBadge status={run.status} />
                    </Td>
                    <Td>
                      {run.completed_case_count}/{run.case_count}
                      {run.failed_case_count ? ` · ${run.failed_case_count} failed` : ''}
                    </Td>
                    <Td>{new Date(run.created_at).toLocaleString()}</Td>
                    <Td textAlign="right">
                      <Flex gap={2} justify="flex-end">
                        <Button
                          as={RouterLink}
                          to={`/test-harness/rule-comparisons/${run.id}`}
                          size="sm"
                          variant="outline"
                        >
                          View
                        </Button>
                        <Button
                          size="sm"
                          colorScheme="red"
                          variant="outline"
                          onClick={() => deleteRun(run)}
                          isLoading={deletingId === run.id}
                          isDisabled={['queued', 'running'].includes(run.status)}
                          title={
                            ['queued', 'running'].includes(run.status)
                              ? 'Queued or running test runs cannot be deleted.'
                              : undefined
                          }
                        >
                          Delete
                        </Button>
                      </Flex>
                    </Td>
                  </Tr>
                ))}
                {visibleRuns.length === 0 && (
                  <Tr>
                    <Td colSpan={6} textAlign="center" color="gray.600" py={8}>
                      No rule comparison runs found.
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
        )}
      </Container>
    </Box>
  );
}

export function NewRuleComparisonScreen() {
  const navigate = useNavigate();
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null);
  const [suiteId, setSuiteId] = useState('');
  const [candidateRuleId, setCandidateRuleId] = useState('');
  const [historyId, setHistoryId] = useState('');
  const [comparisonDeploymentName, setComparisonDeploymentName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    request<Bootstrap>('/bootstrap')
      .then((data) => {
        setBootstrap(data);
        setComparisonDeploymentName(data.deployments.comparison_deployment_name || '');
      })
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const selectedSuite = bootstrap?.suites.find((suite) => suite.id === suiteId);
  const selectedRule = bootstrap?.rules.find((rule) => rule.id === candidateRuleId);
  const validHistories = useMemo(
    () => bootstrap?.rule_histories.filter((history) => history.source_id === candidateRuleId) || [],
    [bootstrap, candidateRuleId],
  );
  const selectedHistory = validHistories.find((history) => history.id === historyId);
  const canCreate = Boolean(
    suiteId && selectedSuite?.case_count && candidateRuleId && historyId && comparisonDeploymentName.trim(),
  );

  async function createRun() {
    setBusy(true);
    setError(null);
    try {
      const row = await request<HarnessRun>('/rule_compares', {
        method: 'POST',
        body: JSON.stringify({
          testsuite_id: suiteId,
          baseline_genai_rule_history_id: historyId,
          candidate_genai_rule_id: candidateRuleId,
          comparison_deployment_name: comparisonDeploymentName,
        }),
      });
      navigate(`/test-harness/rule-comparisons/${row.id}`);
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="New Rule Comparison" />
      <Container maxW="5xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Heading size="md" mb={5}>
          New Rule Comparison
        </Heading>
        {loading ? (
          <Spinner />
        ) : (
          <Stack spacing={6}>
            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <FormControl isRequired>
                <FormLabel>Test Suite</FormLabel>
                <Select value={suiteId} onChange={(event) => setSuiteId(event.target.value)}>
                  <option value="">Select a test suite</option>
                  {bootstrap?.suites.map((suite) => (
                    <option key={suite.id} value={suite.id}>
                      {suite.name} ({suite.case_count} cases)
                    </option>
                  ))}
                </Select>
              </FormControl>
              {selectedSuite && !selectedSuite.case_count && (
                <Alert status="warning" mt={4}>
                  <AlertIcon />
                  This test suite has no cases.
                </Alert>
              )}
            </Box>

            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <Heading size="sm" mb={4}>
                Rule Definitions
              </Heading>
              <Grid templateColumns={{ base: '1fr', lg: '1fr 1fr' }} gap={4}>
                <FormControl isRequired>
                  <FormLabel>Current Candidate Rule</FormLabel>
                  <Select
                    value={candidateRuleId}
                    onChange={(event) => {
                      setCandidateRuleId(event.target.value);
                      setHistoryId('');
                    }}
                  >
                    <option value="">Select a rule</option>
                    {bootstrap?.rules.map((rule) => (
                      <option key={rule.id} value={rule.id}>
                        {rule.rule_key} — {rule.name}
                      </option>
                    ))}
                  </Select>
                </FormControl>
                <FormControl isRequired isDisabled={!candidateRuleId}>
                  <FormLabel>Historical Baseline Definition</FormLabel>
                  <Select value={historyId} onChange={(event) => setHistoryId(event.target.value)}>
                    <option value="">Select a prior definition</option>
                    {validHistories.map((history) => (
                      <option key={history.id} value={history.id}>
                        {history.created_at ? new Date(history.created_at).toLocaleString() : history.id}
                      </option>
                    ))}
                  </Select>
                </FormControl>
              </Grid>
              {candidateRuleId && validHistories.length === 0 && (
                <Alert status="warning" mt={4}>
                  <AlertIcon />
                  This rule has no historical definitions available for comparison.
                </Alert>
              )}
              {(selectedRule || selectedHistory) && (
                <Grid templateColumns={{ base: '1fr', lg: '1fr 1fr' }} gap={4} mt={5}>
                  <Box borderWidth="1px" borderRadius="md" p={4}>
                    <Text fontWeight="700" mb={2}>
                      Candidate Prompt
                    </Text>
                    <Text
                      whiteSpace="pre-wrap"
                      fontSize="sm"
                      color={selectedRule?.prompt_text ? 'inherit' : 'gray.500'}
                    >
                      {selectedRule?.prompt_text || 'Not available.'}
                    </Text>
                  </Box>
                  <Box borderWidth="1px" borderRadius="md" p={4}>
                    <Text fontWeight="700" mb={2}>
                      Baseline Prompt
                    </Text>
                    <Text
                      whiteSpace="pre-wrap"
                      fontSize="sm"
                      color={selectedHistory?.prompt_text ? 'inherit' : 'gray.500'}
                    >
                      {selectedHistory?.prompt_text || 'Select a historical definition.'}
                    </Text>
                  </Box>
                </Grid>
              )}
            </Box>

            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <Heading size="sm" mb={4}>
                Comparison Model
              </Heading>
              <ModelInput
                label="Comparison model"
                value={comparisonDeploymentName}
                onChange={setComparisonDeploymentName}
                options={bootstrap?.deployment_options || []}
              />
            </Box>

            <Flex justify="flex-end" gap={3}>
              <Button as={RouterLink} to="/test-harness/rule-comparisons" variant="outline">
                Cancel
              </Button>
              <Button colorScheme="blue" onClick={createRun} isDisabled={!canCreate} isLoading={busy}>
                Create Draft
              </Button>
            </Flex>
          </Stack>
        )}
      </Container>
    </Box>
  );
}

export function RuleComparisonResultsScreen() {
  const { ruleComparisonId = '' } = useParams<{ ruleComparisonId: string }>();
  const [run, setRun] = useState<HarnessRun | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setRun(await request<HarnessRun>(`/rule_compares/${ruleComparisonId}`));
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setLoading(false);
    }
  }, [ruleComparisonId]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!run || !['queued', 'running'].includes(run.status)) return;
    const timer = window.setInterval(load, 5000);
    return () => window.clearInterval(timer);
  }, [load, run]);

  async function submitRun() {
    if (!run) return;
    setBusy(true);
    setError(null);
    try {
      setRun(
        await request<HarnessRun>(`/rule_compares/${run.id}/submit`, {
          method: 'POST',
          body: '{}',
        }),
      );
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Rule Comparison Results" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Flex justify="space-between" align="center" mb={5}>
          <Heading size="md">Rule Comparison Results</Heading>
          <Button as={RouterLink} to="/test-harness/rule-comparisons" variant="outline">
            Back to Rule Comparison Runs
          </Button>
        </Flex>
        {loading ? (
          <Spinner />
        ) : run ? (
          <RunDetail mode="rule_compares" run={run} onRun={submitRun} busy={busy} />
        ) : null}
      </Container>
    </Box>
  );
}

export function RegressionRunsScreen() {
  const [runs, setRuns] = useState<HarnessRun[]>([]);
  const [searchInput, setSearchInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const [suiteId, setSuiteId] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [deletingId, setDeletingId] = useState<string | null>(null);

  useEffect(() => {
    request<{ rows: HarnessRun[] }>('/regressions')
      .then((data) => setRuns(data.rows))
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const suites = useMemo(
    () => Array.from(new Map(runs.map((run) => [run.testsuite_id, run.suite_name])).entries()),
    [runs],
  );
  const normalizedSearchQuery = searchQuery.trim().toLowerCase();
  const visibleRuns = runs.filter((run) => {
    const matchesSearch =
      !normalizedSearchQuery ||
      [
        run.suite_name,
        run.id,
        run.status,
        run.document_triage_deployment_name,
        run.supporting_document_extraction_deployment_name,
        run.upgrade_analysis_deployment_name,
      ]
        .filter(Boolean)
        .some((value) => String(value).toLowerCase().includes(normalizedSearchQuery));

    return matchesSearch && (!suiteId || run.testsuite_id === suiteId);
  });

  const submitSearch = (event: React.FormEvent<HTMLDivElement>) => {
    event.preventDefault();
    setSearchQuery(searchInput);
  };

  async function deleteRun(run: HarnessRun) {
    if (!window.confirm(`Delete regression run for “${run.suite_name}”?`)) return;
    setDeletingId(run.id);
    setError(null);
    try {
      await request(`/regressions/${run.id}`, { method: 'DELETE' });
      setRuns((current) => current.filter((item) => item.id !== run.id));
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setDeletingId(null);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Regression Runs" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Flex justify="space-between" align="center" mb={5}>
          <Heading size="md">Regression Runs</Heading>
          <Button as={RouterLink} to="/test-harness/regressions/new" colorScheme="blue">
            New Regression Run
          </Button>
        </Flex>
        <Flex as="form" onSubmit={submitSearch} gap={3} mb={4} wrap="wrap">
          <Input
            maxW="320px"
            value={searchInput}
            onChange={(event) => setSearchInput(event.target.value)}
            placeholder="Search suite, model, or regression ID"
            aria-label="Search regression runs"
          />
          <Button type="submit" colorScheme="blue">
            Search
          </Button>
          <Select
            maxW="320px"
            value={suiteId}
            onChange={(event) => setSuiteId(event.target.value)}
            aria-label="Filter by test suite"
          >
            <option value="">All test suites</option>
            {suites.map(([id, suiteName]) => (
              <option key={id} value={id}>
                {suiteName}
              </option>
            ))}
          </Select>
        </Flex>
        {loading ? (
          <Spinner />
        ) : (
          <Box borderWidth="1px" borderRadius="lg" overflowX="auto" bg="white">
            <Table>
              <Thead>
                <Tr>
                  <Th>Test Suite</Th>
                  <Th>Status</Th>
                  <Th>Progress</Th>
                  <Th>Created</Th>
                  <Th />
                </Tr>
              </Thead>
              <Tbody>
                {visibleRuns.map((run) => (
                  <Tr key={run.id}>
                    <Td fontWeight="600">{run.suite_name}</Td>
                    <Td>
                      <StatusBadge status={run.status} />
                    </Td>
                    <Td>
                      {run.completed_case_count}/{run.case_count}
                      {run.failed_case_count ? ` · ${run.failed_case_count} failed` : ''}
                    </Td>
                    <Td>{new Date(run.created_at).toLocaleString()}</Td>
                    <Td textAlign="right">
                      <Flex gap={2} justify="flex-end">
                        <Button as={RouterLink} to={`/test-harness/regressions/${run.id}`} size="sm" variant="outline">
                          View
                        </Button>
                        <Button
                          size="sm"
                          colorScheme="red"
                          variant="outline"
                          onClick={() => deleteRun(run)}
                          isLoading={deletingId === run.id}
                          isDisabled={['queued', 'running'].includes(run.status)}
                          title={
                            ['queued', 'running'].includes(run.status)
                              ? 'Queued or running test runs cannot be deleted.'
                              : undefined
                          }
                        >
                          Delete
                        </Button>
                      </Flex>
                    </Td>
                  </Tr>
                ))}
                {visibleRuns.length === 0 && (
                  <Tr>
                    <Td colSpan={5} textAlign="center" color="gray.600" py={8}>
                      No regression runs found.
                    </Td>
                  </Tr>
                )}
              </Tbody>
            </Table>
          </Box>
        )}
      </Container>
    </Box>
  );
}

export function NewRegressionRunScreen() {
  const navigate = useNavigate();
  const [bootstrap, setBootstrap] = useState<Bootstrap | null>(null);
  const [suiteId, setSuiteId] = useState('');
  const [models, setModels] = useState<DeploymentMap>({
    document_triage_deployment_name: '',
    supporting_document_extraction_deployment_name: '',
    upgrade_analysis_deployment_name: '',
  });
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    request<Bootstrap>('/bootstrap')
      .then((data) => {
        setBootstrap(data);
        setModels(data.deployments);
      })
      .catch((reason: any) => setError(reason.message))
      .finally(() => setLoading(false));
  }, []);

  const selectedSuite = bootstrap?.suites.find((suite) => suite.id === suiteId);
  const canCreate = Boolean(
    suiteId &&
      selectedSuite?.case_count &&
      models.document_triage_deployment_name.trim() &&
      models.supporting_document_extraction_deployment_name.trim() &&
      models.upgrade_analysis_deployment_name.trim(),
  );

  async function createRun() {
    setBusy(true);
    setError(null);
    try {
      const row = await request<HarnessRun>('/regressions', {
        method: 'POST',
        body: JSON.stringify({
          testsuite_id: suiteId,
          document_triage_deployment_name: models.document_triage_deployment_name,
          supporting_document_extraction_deployment_name: models.supporting_document_extraction_deployment_name,
          upgrade_analysis_deployment_name: models.upgrade_analysis_deployment_name,
        }),
      });
      navigate(`/test-harness/regressions/${row.id}`);
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="New Regression Run" />
      <Container maxW="5xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Heading size="md" mb={5}>
          New Regression Run
        </Heading>
        {loading ? (
          <Spinner />
        ) : (
          <Stack spacing={6}>
            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <FormControl isRequired>
                <FormLabel>Test Suite</FormLabel>
                <Select value={suiteId} onChange={(event) => setSuiteId(event.target.value)}>
                  <option value="">Select a test suite</option>
                  {bootstrap?.suites.map((suite) => (
                    <option key={suite.id} value={suite.id}>
                      {suite.name} ({suite.case_count} cases)
                    </option>
                  ))}
                </Select>
              </FormControl>
              {selectedSuite && !selectedSuite.case_count && (
                <Alert status="warning" mt={4}>
                  <AlertIcon />
                  This test suite has no cases.
                </Alert>
              )}
            </Box>

            <Box borderWidth="1px" borderRadius="lg" p={5} bg="white">
              <Heading size="sm" mb={4}>
                Processing Models
              </Heading>
              <Stack spacing={4}>
                <ModelInput
                  label="Document classification model"
                  value={models.document_triage_deployment_name}
                  onChange={(value) => setModels({ ...models, document_triage_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
                <ModelInput
                  label="Supporting extraction model"
                  value={models.supporting_document_extraction_deployment_name}
                  onChange={(value) => setModels({ ...models, supporting_document_extraction_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
                <ModelInput
                  label="Upgrade analysis model"
                  value={models.upgrade_analysis_deployment_name}
                  onChange={(value) => setModels({ ...models, upgrade_analysis_deployment_name: value })}
                  options={bootstrap?.deployment_options || []}
                />
              </Stack>
            </Box>

            <Flex justify="flex-end" gap={3}>
              <Button as={RouterLink} to="/test-harness/regressions" variant="outline">
                Cancel
              </Button>
              <Button colorScheme="blue" onClick={createRun} isDisabled={!canCreate} isLoading={busy}>
                Create Draft
              </Button>
            </Flex>
          </Stack>
        )}
      </Container>
    </Box>
  );
}

export function RegressionRunResultsScreen() {
  const { regressionRunId = '' } = useParams<{ regressionRunId: string }>();
  const [run, setRun] = useState<HarnessRun | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async () => {
    try {
      setRun(await request<HarnessRun>(`/regressions/${regressionRunId}`));
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setLoading(false);
    }
  }, [regressionRunId]);

  useEffect(() => {
    load();
  }, [load]);

  useEffect(() => {
    if (!run || !['queued', 'running'].includes(run.status)) return;
    const timer = window.setInterval(load, 5000);
    return () => window.clearInterval(timer);
  }, [load, run]);

  async function submitRun() {
    if (!run) return;
    setBusy(true);
    setError(null);
    try {
      setRun(
        await request<HarnessRun>(`/regressions/${run.id}/submit`, {
          method: 'POST',
          body: '{}',
        }),
      );
    } catch (reason: any) {
      setError(reason.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Box>
      <ThinBlueTitleBar title="Regression Run Results" />
      <Container maxW="7xl" py={6}>
        {error && (
          <Alert status="error" mb={4}>
            <AlertIcon />
            {error}
          </Alert>
        )}
        <Flex justify="space-between" align="center" mb={5}>
          <Heading size="md">Regression Run Results</Heading>
          <Button as={RouterLink} to="/test-harness/regressions" variant="outline">
            Back to Regression Runs
          </Button>
        </Flex>
        {loading ? <Spinner /> : run ? <RunDetail mode="regressions" run={run} onRun={submitRun} busy={busy} /> : null}
      </Container>
    </Box>
  );
}
