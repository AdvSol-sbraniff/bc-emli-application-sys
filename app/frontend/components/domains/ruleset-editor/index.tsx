import {
  Box, Button, Container, Flex, Heading, Input, Spinner, Text, Textarea,
  Tabs, TabList, TabPanels, Tab, TabPanel
} from '@chakra-ui/react';

import React, { useEffect, useMemo, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { BlueTitleBar } from '../../shared/base/blue-title-bar';

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
      <BlueTitleBar title="Ruleset Editor" />

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
                <Button onClick={load} variant="outline" isDisabled={isLoading || isSaving}>
                  Reload
                </Button>
                <Button
                  onClick={save}
                  colorScheme="blue"
                  isLoading={isSaving}
                  isDisabled={(!isDirty && !isCreateMode) || isLoading}
                >
                  Save
                </Button>
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
    </Box>
  );
}