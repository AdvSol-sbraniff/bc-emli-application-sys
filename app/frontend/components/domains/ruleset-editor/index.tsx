import {
  Box, Button, Container, Drawer, DrawerBody, DrawerCloseButton, DrawerContent, DrawerHeader, DrawerOverlay,
  Flex, Heading, IconButton, Input, Spinner, Text, Textarea, Tooltip, useDisclosure,
  Tabs, TabList, TabPanels, Tab, TabPanel
} from '@chakra-ui/react';

import React, { useEffect, useMemo, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { ArrowCounterClockwise, FloppyDiskBack, Question } from '@phosphor-icons/react';
import { ThinBlueTitleBar } from '../../shared/base/thin-blue-title-bar';

// If you already have an api helper (axios wrapper), swap fetch() for that.
// This is intentionally simple and browser-friendly.

type RulesetDto = {
  id: string;
  ruleset_shortname: string;
  system_record: string | null;
  user_record1: string | null;
  created_at?: string;
  updated_at?: string;
};

function useQueryParam(name: string): string | null {
  const { search } = useLocation();
  return useMemo(() => new URLSearchParams(search).get(name), [search, name]);
}

export default function RulesetEditorScreen() {
  const navigate = useNavigate();
  const id = useQueryParam('id');
  const mode = useQueryParam('mode');
  const duplicateFromId = useQueryParam('duplicate_from');
  const isCreateMode = mode === 'create';

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [infoMessage, setInfoMessage] = useState<string | null>(null);

  const [ruleset, setRuleset] = useState<RulesetDto | null>(null);

  const {
    isOpen: isHelpOpen,
    onOpen: onHelpOpen,
    onClose: onHelpClose,
  } = useDisclosure();

  // editable fields
  const [shortname, setShortname] = useState<string>('');
  const [systemRecord, setSystemRecord] = useState<string>('');
  const [userRecord1, setUserRecord1] = useState<string>('');
  const [initialValues, setInitialValues] = useState({
    shortname: '',
    systemRecord: '',
    userRecord1: '',
  });

  const isDirty =
    shortname !== initialValues.shortname ||
    systemRecord !== initialValues.systemRecord ||
    userRecord1 !== initialValues.userRecord1;

  function buildDuplicateShortname(originalShortname?: string | null): string {
    const base = (originalShortname || '').trim();
    if (!base) return 'changeme';
    return `${base}-changeme`;
  }

  async function load() {
    setIsLoading(true);
    setError(null);
    setInfoMessage(null);

    try {
      if (isCreateMode) {
        if (duplicateFromId) {
          const resp = await fetch(`/api/claims/admin/validationgenai_rulesets/${duplicateFromId}`, {
            method: 'GET',
            headers: { Accept: 'application/json' },
            credentials: 'include',
          });

          if (!resp.ok) {
            const txt = await resp.text();
            throw new Error(`GET failed (${resp.status}): ${txt}`);
          }

          const sourceData: RulesetDto = await resp.json();
          const duplicatedShortname = buildDuplicateShortname(sourceData.ruleset_shortname);

          setRuleset(null);
          setShortname(duplicatedShortname);
          setSystemRecord(sourceData.system_record ?? '');
          setUserRecord1(sourceData.user_record1 ?? '');
          setInitialValues({
            shortname: duplicatedShortname,
            systemRecord: sourceData.system_record ?? '',
            userRecord1: sourceData.user_record1 ?? '',
          });
          setInfoMessage(`Create mode from duplicate of ruleset: ${sourceData.id}`);
          return;
        }

        setRuleset(null);
        setShortname('changeme');
        setSystemRecord('');
        setUserRecord1('');
        setInitialValues({
          shortname: 'changeme',
          systemRecord: '',
          userRecord1: '',
        });
        setInfoMessage('Create mode: no database row is inserted until Save is clicked.');
        return;
      }

      if (!id) {
        setError('Missing query param: id');
        return;
      }

      const resp = await fetch(`/api/claims/admin/validationgenai_rulesets/${id}`, {
        method: 'GET',
        headers: { Accept: 'application/json' },
        credentials: 'include',
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`GET failed (${resp.status}): ${txt}`);
      }

      const data: RulesetDto = await resp.json();
      setRuleset(data);
      setShortname(data.ruleset_shortname ?? '');
      setSystemRecord(data.system_record ?? '');
      setUserRecord1(data.user_record1 ?? '');
      setInitialValues({
        shortname: data.ruleset_shortname ?? '',
        systemRecord: data.system_record ?? '',
        userRecord1: data.user_record1 ?? '',
      });
    } catch (e: any) {
      setError(e?.message ?? 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    if (!isCreateMode && !id) return;

    const trimmedShortname = shortname.trim();
    if (!trimmedShortname) {
      setError('ruleset_shortname is required');
      return;
    }

    setIsSaving(true);
    setError(null);
    setInfoMessage(null);

    try {
      const endpoint = isCreateMode
        ? '/api/claims/admin/validationgenai_rulesets'
        : `/api/claims/admin/validationgenai_rulesets/${id}`;

      const method = isCreateMode ? 'POST' : 'PATCH';

      const resp = await fetch(endpoint, {
        method,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          ruleset_shortname: trimmedShortname,
          system_record: systemRecord,
          user_record1: userRecord1,
        }),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`${method} failed (${resp.status}): ${txt}`);
      }

      const data: RulesetDto = await resp.json();
      setRuleset(data);
      setShortname(data.ruleset_shortname ?? '');
      setSystemRecord(data.system_record ?? '');
      setUserRecord1(data.user_record1 ?? '');
      setInitialValues({
        shortname: data.ruleset_shortname ?? '',
        systemRecord: data.system_record ?? '',
        userRecord1: data.user_record1 ?? '',
      });

      if (isCreateMode) {
        navigate(`/ruleset-editor?id=${encodeURIComponent(data.id)}`, { replace: true });
      }
    } catch (e: any) {
      setError(e?.message ?? 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, mode, duplicateFromId]);

  return (
    <Box>
      <ThinBlueTitleBar title="Ruleset Editor" />

      <Container maxW="6xl" py={6}>
        {!id && !isCreateMode && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">Missing id</Text>
            <Text>Use: /ruleset-editor?id=&lt;uuid&gt; or /ruleset-editor?mode=create</Text>
          </Box>
        )}

        {(id || isCreateMode) && (
          <Box>
            <Flex align="center" justify="space-between" mb={4}>
              <Heading size="md">{isCreateMode ? 'Ruleset (Create)' : 'Ruleset'}</Heading>

              <Flex gap={2}>
                <Tooltip label="Undo unsaved changes by reloading the latest saved values from the database.">
                  <IconButton
                    aria-label="Undo unsaved changes"
                    icon={<ArrowCounterClockwise size={18} />}
                    variant="outline"
                    onClick={load}
                    isDisabled={isLoading || isSaving}
                  />
                </Tooltip>
                <Tooltip label="Save ruleset changes">
                  <IconButton
                    aria-label="Save ruleset"
                    icon={<FloppyDiskBack size={18} />}
                    colorScheme="blue"
                    onClick={save}
                    isLoading={isSaving}
                    isDisabled={(!isDirty && !isCreateMode) || isLoading}
                  />
                </Tooltip>
                <Tooltip label="Help: context layers and output mapping">
                  <IconButton
                    aria-label="Open ruleset editor help"
                    icon={<Question size={18} />}
                    variant="outline"
                    onClick={onHelpOpen}
                  />
                </Tooltip>
              </Flex>
            </Flex>

            {infoMessage && (
              <Box p={3} borderWidth="1px" borderRadius="md" mb={4} bg="blue.50" borderColor="blue.200">
                <Text>{infoMessage}</Text>
              </Box>
            )}

            {isLoading && (
              <Flex align="center" gap={3} p={4}>
                <Spinner />
                <Text>Loading…</Text>
              </Flex>
            )}

            {error && (
              <Box p={4} borderWidth="1px" borderRadius="md" mb={4}>
                <Text fontWeight="bold">Error</Text>
                <Text whiteSpace="pre-wrap">{error}</Text>
              </Box>
            )}

            {!isLoading && !error && (
              <Box>
                <Box mb={4}>
                  <Text fontWeight="bold" mb={1}>
                    ruleset_shortname
                  </Text>
                  <Input value={shortname} onChange={(e) => setShortname(e.target.value)} />
                </Box>

                <Box
                  borderWidth="1px"
                  borderRadius="lg"
                  p={3}
                  mb={4}
                  bg="white"
                >
                  <Tabs
                    variant="line"
                    isFitted
                    colorScheme="gray"
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
                    <TabList>
                      <Tab>system_record</Tab>
                      <Tab>user_record1</Tab>
                    </TabList>

                    <TabPanels>
                      <TabPanel px={0} pt={3}>
                        <Textarea
                          value={systemRecord}
                          onChange={(e) => setSystemRecord(e.target.value)}
                          minH="360px"
                        />
                      </TabPanel>

                      <TabPanel px={0} pt={3}>
                        <Textarea
                          value={userRecord1}
                          onChange={(e) => setUserRecord1(e.target.value)}
                          minH="360px"
                        />
                      </TabPanel>
                    </TabPanels>
                  </Tabs>
                </Box>

                <Flex justify="space-between" mt={2}>
                  <Text fontSize="sm" opacity={0.8}>
                    {isDirty ? 'Unsaved changes' : 'Saved'}
                  </Text>
                  <Text fontSize="sm" opacity={0.8}>
                    {ruleset?.updated_at ? `updated_at: ${ruleset.updated_at}` : ''}
                  </Text>
                </Flex>
              </Box>
            )}
          </Box>
        )}
      </Container>

      <Drawer isOpen={isHelpOpen} placement="left" onClose={onHelpClose} size="xl">
        <DrawerOverlay />
        <DrawerContent>
          <DrawerCloseButton />
          <DrawerHeader>Ruleset Editor Help</DrawerHeader>
          <DrawerBody>
            <Flex direction="column" gap={4}>
              <Box>
                <Heading size="sm" mb={2}>Big Picture</Heading>
                <Text as="div" fontSize="sm">
                  This page lets you edit the two ruleset tabs: system_record and user_record1.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  These two tabs tell the AI what to do and how to format the answer.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  They are the stable instructions that stay mostly the same across many invoices.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Clear writing here helps the AI give cleaner and more useful results.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>What You Edit And What You Do Not Edit</Heading>
                <Text as="div" fontSize="sm">
                  On this screen, you edit system_record and user_record1.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  system_record is the main instruction and output format.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  user_record1 is the stable background and task list.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  user record 2 is not edited on this page.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  user record 2 is built automatically at run time by looking up existing database records and document-read results.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>How This Page Is Used During A Check</Heading>
                <Text as="div" fontSize="sm">
                  First, the AI reads system_record and user_record1 from this screen.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Next, the system builds user record 2 automatically with this invoice&apos;s details.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  That user record 2 information is pulled from existing database tables and document-read data.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  So this page controls system_record and user_record1, but not user record 2.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Last, the AI answers in the exact shape asked by system_record.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>How One Answer Is Split Into 3 Parts</Heading>
                <Text as="div" fontSize="sm">
                  The AI answer is split into 3 parts.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Part 1 is the report card: confidence, pass/fail summary, and advice text.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Part 2 is "found things": where important values were found on the invoice.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Part 3 is "rule checks": each rule and whether it passed.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  These parts are saved separately so admins can read them clearly.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>How The 3 Parts Show In The PDF Viewer</Heading>
                <Text as="div" fontSize="sm">
                  "Invoice Header Fields" shows top invoice facts like names, dates, and totals.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  "Line Items (OCR)" shows each invoice line like description, quantity, and amount.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  "GenAI Located Fields" shows extra things the helper found and pointed to.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  "Pre-existing info on file" shows already-known case info from your system.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  "GenAI Rulechecks" shows each rule result plus the overall summary and advice.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  So one answer is shown in several friendly sections instead of one giant wall of text.
                </Text>
              </Box>

              <Box>
                <Heading size="sm" mb={2}>Simple Editing Tips</Heading>
                <Text as="div" fontSize="sm">
                  Keep the boss note clear and strict.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Keep the always-true note focused on rules that almost never change.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  Keep the final ask short and direct.
                </Text>
                <Text as="div" fontSize="sm" mt={1}>
                  If results look messy, simplify the words and remove extra instructions.
                </Text>
              </Box>
            </Flex>
          </DrawerBody>
        </DrawerContent>
      </Drawer>
    </Box>
  );
}