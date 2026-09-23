import {
  Box,
  Container,
  Flex,
  FormControl,
  FormHelperText,
  FormLabel,
  Heading,
  IconButton,
  Spinner,
  Stack,
  Switch,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
  Textarea,
  Tooltip,
  Input,
} from '@chakra-ui/react';
import { ArrowCounterClockwise, FloppyDiskBack } from '@phosphor-icons/react';
import React, { useEffect, useState } from 'react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';
import { AdminPdfViewerUxMode, normalizeAdminPdfViewerUxMode } from '../../shared/claims/admin-pdf-viewer-ux';

type ConfigDto = {
  id: string;
  system_record: string | null;
  document_triage_system_record: string | null;
  supporting_document_extraction_system_record: string | null;
  rule_audit_system_record: string | null;
  user_record0: string | null;
  admin_advice_intro: string | null;
  admin_advice_closing: string | null;
  admin_pdf_viewer_ux_mode: AdminPdfViewerUxMode;
  show_admin_field_revision_plus: boolean;
  document_triage_deployment_name: string | null;
  supporting_document_extraction_deployment_name: string | null;
  upgrade_analysis_deployment_name: string | null;
  comparison_deployment_name: string | null;
  hardcoded_prompts?: {
    case_comparison: string;
    model_summary: string;
    rule_summary: string;
  };
  updated_at?: string | null;
};

const hardcodedPromptTabs = [
  {
    key: 'case_comparison',
    label: 'Hardcoded - Case Comparison',
    description: 'Shared instructions for each case in model comparisons and rule comparisons.',
  },
  {
    key: 'model_summary',
    label: 'Hardcoded - Model Comparison Summary',
    description: 'Instructions for combining all model comparison case reports into the overall summary.',
  },
  {
    key: 'rule_summary',
    label: 'Hardcoded - Rule Comparison Summary',
    description: 'Instructions for combining all rule comparison case reports into the overall summary.',
  },
] as const;

export default function RulesetConfigEditorScreen() {
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [config, setConfig] = useState<ConfigDto | null>(null);
  const [systemRecord, setSystemRecord] = useState<string>('');
  const [documentTriageSystemRecord, setDocumentTriageSystemRecord] = useState<string>('');
  const [supportingDocumentExtractionSystemRecord, setSupportingDocumentExtractionSystemRecord] = useState<string>('');
  const [ruleAuditSystemRecord, setRuleAuditSystemRecord] = useState('');
  const [userRecord0, setUserRecord0] = useState<string>('');
  const [adminAdviceIntro, setAdminAdviceIntro] = useState<string>('');
  const [adminAdviceClosing, setAdminAdviceClosing] = useState<string>('');
  const [adminPdfViewerUxMode, setAdminPdfViewerUxMode] = useState<AdminPdfViewerUxMode>('simple');
  const [showAdminFieldRevisionPlus, setShowAdminFieldRevisionPlus] = useState<boolean>(true);
  const [documentTriageDeploymentName, setDocumentTriageDeploymentName] = useState('');
  const [supportingDocumentExtractionDeploymentName, setSupportingDocumentExtractionDeploymentName] = useState('');
  const [upgradeAnalysisDeploymentName, setUpgradeAnalysisDeploymentName] = useState('');
  const [comparisonDeploymentName, setComparisonDeploymentName] = useState('');
  const [initialValues, setInitialValues] = useState({
    systemRecord: '',
    documentTriageSystemRecord: '',
    supportingDocumentExtractionSystemRecord: '',
    ruleAuditSystemRecord: '',
    userRecord0: '',
    adminAdviceIntro: '',
    adminAdviceClosing: '',
    adminPdfViewerUxMode: 'simple' as AdminPdfViewerUxMode,
    showAdminFieldRevisionPlus: true,
    documentTriageDeploymentName: '',
    supportingDocumentExtractionDeploymentName: '',
    upgradeAnalysisDeploymentName: '',
    comparisonDeploymentName: '',
  });

  const isDirty =
    systemRecord !== initialValues.systemRecord ||
    documentTriageSystemRecord !== initialValues.documentTriageSystemRecord ||
    supportingDocumentExtractionSystemRecord !== initialValues.supportingDocumentExtractionSystemRecord ||
    ruleAuditSystemRecord !== initialValues.ruleAuditSystemRecord ||
    userRecord0 !== initialValues.userRecord0 ||
    adminAdviceIntro !== initialValues.adminAdviceIntro ||
    adminAdviceClosing !== initialValues.adminAdviceClosing ||
    adminPdfViewerUxMode !== initialValues.adminPdfViewerUxMode ||
    showAdminFieldRevisionPlus !== initialValues.showAdminFieldRevisionPlus ||
    documentTriageDeploymentName !== initialValues.documentTriageDeploymentName ||
    supportingDocumentExtractionDeploymentName !== initialValues.supportingDocumentExtractionDeploymentName ||
    upgradeAnalysisDeploymentName !== initialValues.upgradeAnalysisDeploymentName ||
    comparisonDeploymentName !== initialValues.comparisonDeploymentName;

  function applyConfig(data: ConfigDto) {
    const values = {
      systemRecord: data.system_record ?? '',
      documentTriageSystemRecord: data.document_triage_system_record ?? '',
      supportingDocumentExtractionSystemRecord: data.supporting_document_extraction_system_record ?? '',
      ruleAuditSystemRecord: data.rule_audit_system_record ?? '',
      userRecord0: data.user_record0 ?? '',
      adminAdviceIntro: data.admin_advice_intro ?? '',
      adminAdviceClosing: data.admin_advice_closing ?? '',
      adminPdfViewerUxMode: normalizeAdminPdfViewerUxMode(data.admin_pdf_viewer_ux_mode),
      showAdminFieldRevisionPlus: data.show_admin_field_revision_plus !== false,
      documentTriageDeploymentName: data.document_triage_deployment_name ?? '',
      supportingDocumentExtractionDeploymentName: data.supporting_document_extraction_deployment_name ?? '',
      upgradeAnalysisDeploymentName: data.upgrade_analysis_deployment_name ?? '',
      comparisonDeploymentName: data.comparison_deployment_name ?? '',
    };

    setConfig(data);
    setSystemRecord(values.systemRecord);
    setDocumentTriageSystemRecord(values.documentTriageSystemRecord);
    setSupportingDocumentExtractionSystemRecord(values.supportingDocumentExtractionSystemRecord);
    setRuleAuditSystemRecord(values.ruleAuditSystemRecord);
    setUserRecord0(values.userRecord0);
    setAdminAdviceIntro(values.adminAdviceIntro);
    setAdminAdviceClosing(values.adminAdviceClosing);
    setAdminPdfViewerUxMode(values.adminPdfViewerUxMode);
    setShowAdminFieldRevisionPlus(values.showAdminFieldRevisionPlus);
    setDocumentTriageDeploymentName(values.documentTriageDeploymentName);
    setSupportingDocumentExtractionDeploymentName(values.supportingDocumentExtractionDeploymentName);
    setUpgradeAnalysisDeploymentName(values.upgradeAnalysisDeploymentName);
    setComparisonDeploymentName(values.comparisonDeploymentName);
    setInitialValues(values);
  }

  async function load() {
    setIsLoading(true);
    setError(null);

    try {
      const resp = await fetch('/api/claims/admin/validationgenai_config', {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: ConfigDto = await resp.json();
      applyConfig(data);
    } catch (e: any) {
      setError(e?.message ?? 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    setIsSaving(true);
    setError(null);

    try {
      const resp = await fetch('/api/claims/admin/validationgenai_config', {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          system_record: systemRecord,
          document_triage_system_record: documentTriageSystemRecord,
          supporting_document_extraction_system_record: supportingDocumentExtractionSystemRecord,
          ...(ruleAuditSystemRecord !== initialValues.ruleAuditSystemRecord
            ? { rule_audit_system_record: ruleAuditSystemRecord }
            : {}),
          user_record0: userRecord0,
          admin_advice_intro: adminAdviceIntro,
          admin_advice_closing: adminAdviceClosing,
          admin_pdf_viewer_ux_mode: adminPdfViewerUxMode,
          show_admin_field_revision_plus: showAdminFieldRevisionPlus,
          document_triage_deployment_name: documentTriageDeploymentName,
          supporting_document_extraction_deployment_name: supportingDocumentExtractionDeploymentName,
          upgrade_analysis_deployment_name: upgradeAnalysisDeploymentName,
          comparison_deployment_name: comparisonDeploymentName,
        }),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`PATCH failed (${resp.status}): ${txt}`);
      }

      const data: ConfigDto = await resp.json();
      applyConfig(data);
    } catch (e: any) {
      setError(e?.message ?? 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Box>
      <ThinBlueTitleBar title="System Config" />

      <Container maxW="full" py={6} px={{ base: 4, md: 6 }}>
        <Flex align="center" justify="space-between" mb={4}>
          <Box>
            <Heading size="md">System Config</Heading>
            <Text fontSize="sm" opacity={0.75} mt={1}>
              Shared validation prompt, PDF/image routing classifier prompts, support-document extraction prompts, admin
              advice framing.
            </Text>
          </Box>

          <Flex gap={2}>
            <Tooltip label="Reload latest saved values">
              <IconButton
                aria-label="Reload latest saved values"
                icon={<ArrowCounterClockwise size={18} />}
                variant="outline"
                onClick={load}
                isDisabled={isLoading || isSaving}
              />
            </Tooltip>
            <Tooltip label="Save system config">
              <IconButton
                aria-label="Save system config"
                icon={<FloppyDiskBack size={18} />}
                colorScheme="blue"
                onClick={save}
                isLoading={isSaving}
                isDisabled={!isDirty || isLoading}
              />
            </Tooltip>
          </Flex>
        </Flex>

        {isLoading && (
          <Flex align="center" gap={3} p={4}>
            <Spinner />
            <Text>Loading...</Text>
          </Flex>
        )}

        {error && (
          <Box p={4} borderWidth="1px" borderRadius="md" mb={4}>
            <Text fontWeight="bold">Error</Text>
            <Text whiteSpace="pre-wrap">{error}</Text>
          </Box>
        )}

        {!isLoading && !error && (
          <>
            <Tabs variant="line" colorScheme="gray">
              <TabList flexWrap="wrap">
                <Tab>Upgrade Analysis</Tab>
                <Tab>Document Classification</Tab>
                <Tab>Supporting Document Extraction</Tab>
                <Tab>OCR Guidance</Tab>
                <Tab>Advice Introduction</Tab>
                <Tab>Advice Closing</Tab>
                <Tab>PDF Viewer</Tab>
                <Tab>AI Models</Tab>
                <Tab>Rule Audit</Tab>
                {hardcodedPromptTabs.map((tab) => (
                  <Tab key={tab.key}>{tab.label}</Tab>
                ))}
              </TabList>
              <TabPanels>
                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Main validation instruction, output schema, and global guardrails.
                  </Text>
                  <Textarea value={systemRecord} onChange={(e) => setSystemRecord(e.target.value)} minH="520px" />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Document-routing prompt used by the classify_document step for PDFs and images. It identifies
                    invoice/supporting/unknown documents and leaves supporting-document evidence extraction to its
                    downstream step.
                  </Text>
                  <Textarea
                    value={documentTriageSystemRecord}
                    onChange={(e) => setDocumentTriageSystemRecord(e.target.value)}
                    minH="420px"
                  />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Extraction-only prompt for one already-classified supporting document type, with all files of that
                    type attached together.
                  </Text>
                  <Textarea
                    value={supportingDocumentExtractionSystemRecord}
                    onChange={(e) => setSupportingDocumentExtractionSystemRecord(e.target.value)}
                    minH="420px"
                  />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Shared user prompt loaded after the system record. Use this for Document Intelligence/OCR reading
                    guidance that applies to every ruleset call.
                  </Text>
                  <Textarea value={userRecord0} onChange={(e) => setUserRecord0(e.target.value)} minH="420px" />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Intro text prepended by Rails when combining section-level advice from common and upgrade-type
                    ruleset calls.
                  </Text>
                  <Textarea
                    value={adminAdviceIntro}
                    onChange={(e) => setAdminAdviceIntro(e.target.value)}
                    minH="220px"
                  />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Closing text appended by Rails after grouped ruleset advice sections.
                  </Text>
                  <Textarea
                    value={adminAdviceClosing}
                    onChange={(e) => setAdminAdviceClosing(e.target.value)}
                    minH="220px"
                  />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={4}>
                    Choose the workflow experience and field-level revision controls used by admins reviewing invoices.
                  </Text>
                  <Flex
                    align={{ base: 'flex-start', md: 'center' }}
                    justify="space-between"
                    direction={{ base: 'column', md: 'row' }}
                    gap={4}
                    borderWidth="1px"
                    borderRadius="md"
                    p={4}
                    mb={4}
                  >
                    <Box>
                      <Text fontSize="sm" fontWeight="semibold">
                        Admin PDF viewer experience
                      </Text>
                      <Text fontSize="sm" opacity={0.7} mt={1} maxW="680px">
                        Embedded handles revision requests directly beside the relevant invoice evidence, with a compact
                        summary for navigation and history. Centralized manages all revision requests in a dedicated
                        workspace with filtering, decision, and sending controls.
                      </Text>
                    </Box>
                    <Flex align="center" gap={3} whiteSpace="nowrap">
                      <Text
                        fontSize="sm"
                        fontWeight={adminPdfViewerUxMode === 'simple' ? '700' : '500'}
                        opacity={adminPdfViewerUxMode === 'simple' ? 1 : 0.65}
                      >
                        Embedded
                      </Text>
                      <Switch
                        aria-label="Use the centralized admin PDF viewer experience"
                        colorScheme="blue"
                        isChecked={adminPdfViewerUxMode === 'enterprise'}
                        onChange={(event) => setAdminPdfViewerUxMode(event.target.checked ? 'enterprise' : 'simple')}
                      />
                      <Text
                        fontSize="sm"
                        fontWeight={adminPdfViewerUxMode === 'enterprise' ? '700' : '500'}
                        opacity={adminPdfViewerUxMode === 'enterprise' ? 1 : 0.65}
                      >
                        Centralized
                      </Text>
                    </Flex>
                  </Flex>
                  <Flex align="center" justify="space-between" gap={4} borderWidth="1px" borderRadius="md" p={4}>
                    <Box>
                      <Text fontSize="sm" fontWeight="semibold">
                        Show field revision plus signs
                      </Text>
                      <Text fontSize="sm" opacity={0.7} mt={1}>
                        Allow admins to start a revision issue directly from an invoice or supporting-document field.
                      </Text>
                    </Box>
                    <Switch
                      aria-label="Show field revision plus signs"
                      colorScheme="blue"
                      isChecked={showAdminFieldRevisionPlus}
                      onChange={(event) => setShowAdminFieldRevisionPlus(event.target.checked)}
                    />
                  </Flex>
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={4}>
                    Deployment names are configuration, not credentials. New processing runs snapshot these values so
                    their exact model provenance remains inspectable after this screen changes.
                  </Text>
                  <Text fontWeight="bold" mb={4}>
                    Reasoning effort is not configurable here. GPT-6 Sol and GPT-6 Luna currently use their default of
                    medium. For future model changes, consider testing a lower-cost model with higher reasoning effort,
                    comparing accuracy, response time, and total cost before switching.
                  </Text>
                  <Stack spacing={5} maxW="760px">
                    <FormControl isRequired>
                      <FormLabel>Document classification model</FormLabel>
                      <Input
                        value={documentTriageDeploymentName}
                        onChange={(event) => setDocumentTriageDeploymentName(event.target.value)}
                      />
                      <FormHelperText>Used to classify invoice and supporting-document files.</FormHelperText>
                    </FormControl>
                    <FormControl isRequired>
                      <FormLabel>Supporting document extraction model</FormLabel>
                      <Input
                        value={supportingDocumentExtractionDeploymentName}
                        onChange={(event) => setSupportingDocumentExtractionDeploymentName(event.target.value)}
                      />
                      <FormHelperText>Used to extract configured evidence from supporting documents.</FormHelperText>
                    </FormControl>
                    <FormControl isRequired>
                      <FormLabel>Upgrade analysis model</FormLabel>
                      <Input
                        value={upgradeAnalysisDeploymentName}
                        onChange={(event) => setUpgradeAnalysisDeploymentName(event.target.value)}
                      />
                      <FormHelperText>Used for upgrade-type rules, findings, and advice.</FormHelperText>
                    </FormControl>
                    <FormControl isRequired>
                      <FormLabel>Comparison and rule audit model</FormLabel>
                      <Input
                        value={comparisonDeploymentName}
                        onChange={(event) => setComparisonDeploymentName(event.target.value)}
                      />
                      <FormHelperText>
                        Used by the test harness to compare results and by Rule Improvement Detail to audit a package.
                      </FormHelperText>
                    </FormControl>
                  </Stack>
                </TabPanel>
                <TabPanel px={0} pt={3}>
                  <FormControl>
                    <FormLabel htmlFor="rule-audit-system-record">Rule package audit system record</FormLabel>
                    <FormHelperText mb={3}>
                      Instructions for auditing one selected rule against an invoice package, its documents and history.
                      The human process guidance is supplied separately from the same guidance shown on Rule Improvement
                      Detail. Keep the four output field names unchanged; the advice text can use any useful structure.
                      Leaving this blank uses the application default. Suggested changes are not applied automatically.
                    </FormHelperText>
                    <Textarea
                      id="rule-audit-system-record"
                      value={ruleAuditSystemRecord}
                      onChange={(event) => setRuleAuditSystemRecord(event.target.value)}
                      maxLength={60000}
                      minH="520px"
                    />
                  </FormControl>
                </TabPanel>
                {hardcodedPromptTabs.map((tab) => (
                  <TabPanel key={tab.key} px={0} pt={3}>
                    <FormControl>
                      <FormLabel htmlFor={`hardcoded-${tab.key}`}>{tab.label}</FormLabel>
                      <FormHelperText mb={3}>
                        {tab.description} Read only. These instructions are defined in application code and cannot be
                        changed by saving this screen.
                      </FormHelperText>
                      <Textarea
                        id={`hardcoded-${tab.key}`}
                        value={config?.hardcoded_prompts?.[tab.key] ?? 'Prompt unavailable. Reload the configuration.'}
                        isReadOnly
                        minH="420px"
                        bg="gray.50"
                      />
                    </FormControl>
                  </TabPanel>
                ))}
              </TabPanels>
            </Tabs>

            <Flex justify="space-between" mt={2}>
              <Text fontSize="sm" opacity={0.8}>
                {isDirty ? 'Unsaved changes' : 'Saved'}
              </Text>
              <Text fontSize="sm" opacity={0.8}>
                {config?.updated_at ? `updated_at: ${config.updated_at}` : ''}
              </Text>
            </Flex>
          </>
        )}
      </Container>
    </Box>
  );
}
