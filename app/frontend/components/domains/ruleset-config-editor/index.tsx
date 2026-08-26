import {
  Box,
  Container,
  Flex,
  Heading,
  IconButton,
  Spinner,
  Switch,
  Tab,
  TabList,
  TabPanel,
  TabPanels,
  Tabs,
  Text,
  Textarea,
  Tooltip,
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
  user_record0: string | null;
  admin_advice_intro: string | null;
  admin_advice_closing: string | null;
  admin_pdf_viewer_ux_mode: AdminPdfViewerUxMode;
  show_admin_field_revision_plus: boolean;
  updated_at?: string | null;
};

export default function RulesetConfigEditorScreen() {
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [config, setConfig] = useState<ConfigDto | null>(null);
  const [systemRecord, setSystemRecord] = useState<string>('');
  const [documentTriageSystemRecord, setDocumentTriageSystemRecord] = useState<string>('');
  const [supportingDocumentExtractionSystemRecord, setSupportingDocumentExtractionSystemRecord] = useState<string>('');
  const [userRecord0, setUserRecord0] = useState<string>('');
  const [adminAdviceIntro, setAdminAdviceIntro] = useState<string>('');
  const [adminAdviceClosing, setAdminAdviceClosing] = useState<string>('');
  const [adminPdfViewerUxMode, setAdminPdfViewerUxMode] = useState<AdminPdfViewerUxMode>('simple');
  const [showAdminFieldRevisionPlus, setShowAdminFieldRevisionPlus] = useState<boolean>(true);
  const [initialValues, setInitialValues] = useState({
    systemRecord: '',
    documentTriageSystemRecord: '',
    supportingDocumentExtractionSystemRecord: '',
    userRecord0: '',
    adminAdviceIntro: '',
    adminAdviceClosing: '',
    adminPdfViewerUxMode: 'simple' as AdminPdfViewerUxMode,
    showAdminFieldRevisionPlus: true,
  });

  const isDirty =
    systemRecord !== initialValues.systemRecord ||
    documentTriageSystemRecord !== initialValues.documentTriageSystemRecord ||
    supportingDocumentExtractionSystemRecord !== initialValues.supportingDocumentExtractionSystemRecord ||
    userRecord0 !== initialValues.userRecord0 ||
    adminAdviceIntro !== initialValues.adminAdviceIntro ||
    adminAdviceClosing !== initialValues.adminAdviceClosing ||
    adminPdfViewerUxMode !== initialValues.adminPdfViewerUxMode ||
    showAdminFieldRevisionPlus !== initialValues.showAdminFieldRevisionPlus;

  function applyConfig(data: ConfigDto) {
    const values = {
      systemRecord: data.system_record ?? '',
      documentTriageSystemRecord: data.document_triage_system_record ?? '',
      supportingDocumentExtractionSystemRecord: data.supporting_document_extraction_system_record ?? '',
      userRecord0: data.user_record0 ?? '',
      adminAdviceIntro: data.admin_advice_intro ?? '',
      adminAdviceClosing: data.admin_advice_closing ?? '',
      adminPdfViewerUxMode: normalizeAdminPdfViewerUxMode(data.admin_pdf_viewer_ux_mode),
      showAdminFieldRevisionPlus: data.show_admin_field_revision_plus !== false,
    };

    setConfig(data);
    setSystemRecord(values.systemRecord);
    setDocumentTriageSystemRecord(values.documentTriageSystemRecord);
    setSupportingDocumentExtractionSystemRecord(values.supportingDocumentExtractionSystemRecord);
    setUserRecord0(values.userRecord0);
    setAdminAdviceIntro(values.adminAdviceIntro);
    setAdminAdviceClosing(values.adminAdviceClosing);
    setAdminPdfViewerUxMode(values.adminPdfViewerUxMode);
    setShowAdminFieldRevisionPlus(values.showAdminFieldRevisionPlus);
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
          user_record0: userRecord0,
          admin_advice_intro: adminAdviceIntro,
          admin_advice_closing: adminAdviceClosing,
          admin_pdf_viewer_ux_mode: adminPdfViewerUxMode,
          show_admin_field_revision_plus: showAdminFieldRevisionPlus,
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

      <Container maxW="6xl" py={6}>
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
          <Box borderWidth="1px" borderRadius="lg" p={3} bg="white">
            <Tabs variant="line" isFitted colorScheme="gray">
              <TabList>
                <Tab>Main</Tab>
                <Tab>Document Triage</Tab>
                <Tab>Support Extract</Tab>
                <Tab>DI Guidance</Tab>
                <Tab>Advice Intro</Tab>
                <Tab>Advice Close</Tab>
                <Tab>Admin PDF Viewer</Tab>
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
          </Box>
        )}
      </Container>
    </Box>
  );
}
