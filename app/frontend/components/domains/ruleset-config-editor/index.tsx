import {
  Box,
  Container,
  Flex,
  Heading,
  IconButton,
  Spinner,
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

type ConfigDto = {
  id: string;
  system_record: string | null;
  classifier_system_record: string | null;
  supporting_document_extraction_system_record: string | null;
  supporting_document_group_extraction_system_record: string | null;
  user_record0: string | null;
  admin_advice_intro: string | null;
  admin_advice_closing: string | null;
  updated_at?: string | null;
};

export default function RulesetConfigEditorScreen() {
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [config, setConfig] = useState<ConfigDto | null>(null);
  const [systemRecord, setSystemRecord] = useState<string>('');
  const [classifierSystemRecord, setClassifierSystemRecord] = useState<string>('');
  const [supportingDocumentExtractionSystemRecord, setSupportingDocumentExtractionSystemRecord] = useState<string>('');
  const [supportingDocumentGroupExtractionSystemRecord, setSupportingDocumentGroupExtractionSystemRecord] =
    useState<string>('');
  const [userRecord0, setUserRecord0] = useState<string>('');
  const [adminAdviceIntro, setAdminAdviceIntro] = useState<string>('');
  const [adminAdviceClosing, setAdminAdviceClosing] = useState<string>('');
  const [initialValues, setInitialValues] = useState({
    systemRecord: '',
    classifierSystemRecord: '',
    supportingDocumentExtractionSystemRecord: '',
    supportingDocumentGroupExtractionSystemRecord: '',
    userRecord0: '',
    adminAdviceIntro: '',
    adminAdviceClosing: '',
  });

  const isDirty =
    systemRecord !== initialValues.systemRecord ||
    classifierSystemRecord !== initialValues.classifierSystemRecord ||
    supportingDocumentExtractionSystemRecord !== initialValues.supportingDocumentExtractionSystemRecord ||
    supportingDocumentGroupExtractionSystemRecord !== initialValues.supportingDocumentGroupExtractionSystemRecord ||
    userRecord0 !== initialValues.userRecord0 ||
    adminAdviceIntro !== initialValues.adminAdviceIntro ||
    adminAdviceClosing !== initialValues.adminAdviceClosing;

  function applyConfig(data: ConfigDto) {
    const values = {
      systemRecord: data.system_record ?? '',
      classifierSystemRecord: data.classifier_system_record ?? '',
      supportingDocumentExtractionSystemRecord: data.supporting_document_extraction_system_record ?? '',
      supportingDocumentGroupExtractionSystemRecord: data.supporting_document_group_extraction_system_record ?? '',
      userRecord0: data.user_record0 ?? '',
      adminAdviceIntro: data.admin_advice_intro ?? '',
      adminAdviceClosing: data.admin_advice_closing ?? '',
    };

    setConfig(data);
    setSystemRecord(values.systemRecord);
    setClassifierSystemRecord(values.classifierSystemRecord);
    setSupportingDocumentExtractionSystemRecord(values.supportingDocumentExtractionSystemRecord);
    setSupportingDocumentGroupExtractionSystemRecord(values.supportingDocumentGroupExtractionSystemRecord);
    setUserRecord0(values.userRecord0);
    setAdminAdviceIntro(values.adminAdviceIntro);
    setAdminAdviceClosing(values.adminAdviceClosing);
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
          classifier_system_record: classifierSystemRecord,
          supporting_document_extraction_system_record: supportingDocumentExtractionSystemRecord,
          supporting_document_group_extraction_system_record: supportingDocumentGroupExtractionSystemRecord,
          user_record0: userRecord0,
          admin_advice_intro: adminAdviceIntro,
          admin_advice_closing: adminAdviceClosing,
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
      <ThinBlueTitleBar title="Validation Prompt Config" />

      <Container maxW="6xl" py={6}>
        <Flex align="center" justify="space-between" mb={4}>
          <Box>
            <Heading size="md">Validation Prompt Config</Heading>
            <Text fontSize="sm" opacity={0.75} mt={1}>
              Shared validation prompt, routing classifier prompt, support-document extraction prompt, and admin advice
              framing.
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
            <Tooltip label="Save AI system config">
              <IconButton
                aria-label="Save AI system config"
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
                <Tab>Classifier</Tab>
                <Tab>Support Extract</Tab>
                <Tab>Group Extract</Tab>
                <Tab>DI Guidance</Tab>
                <Tab>Advice Intro</Tab>
                <Tab>Advice Close</Tab>
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
                    Routing-only classifier prompt. It identifies invoice/supporting/unknown documents and leaves all
                    supporting-document located fields to the separate extraction call.
                  </Text>
                  <Textarea
                    value={classifierSystemRecord}
                    onChange={(e) => setClassifierSystemRecord(e.target.value)}
                    minH="420px"
                  />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Extraction-only prompt for one already-classified supporting document type.
                  </Text>
                  <Textarea
                    value={supportingDocumentExtractionSystemRecord}
                    onChange={(e) => setSupportingDocumentExtractionSystemRecord(e.target.value)}
                    minH="420px"
                  />
                </TabPanel>

                <TabPanel px={0} pt={3}>
                  <Text fontSize="sm" opacity={0.75} mb={3}>
                    Extraction-only prompt for one supporting-document group, such as a before/after photo set.
                  </Text>
                  <Textarea
                    value={supportingDocumentGroupExtractionSystemRecord}
                    onChange={(e) => setSupportingDocumentGroupExtractionSystemRecord(e.target.value)}
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
