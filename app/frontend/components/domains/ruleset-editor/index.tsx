import { Box, Button, Container, Flex, Heading, Input, Spinner, Text, Textarea } from '@chakra-ui/react';
import React, { useEffect, useMemo, useState } from 'react';
import { useLocation } from 'react-router-dom';
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
  const id = useQueryParam('id');

  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isSaving, setIsSaving] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  const [ruleset, setRuleset] = useState<RulesetDto | null>(null);

  // editable fields
  const [shortname, setShortname] = useState<string>('');
  const [systemRecord, setSystemRecord] = useState<string>('');
  const [userRecord1, setUserRecord1] = useState<string>('');

  const isDirty =
    ruleset != null &&
    (shortname !== (ruleset.ruleset_shortname ?? '') ||
      systemRecord !== (ruleset.system_record ?? '') ||
      userRecord1 !== (ruleset.user_record1 ?? ''));

  async function load() {
    if (!id) {
      setError('Missing query param: id');
      setIsLoading(false);
      return;
    }

    setIsLoading(true);
    setError(null);

    try {
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
    } catch (e: any) {
      setError(e?.message ?? 'Load failed');
    } finally {
      setIsLoading(false);
    }
  }

  async function save() {
    if (!id) return;
    setIsSaving(true);
    setError(null);

    try {
      const resp = await fetch(`/api/claims/admin/validationgenai_rulesets/${id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        credentials: 'include',
        body: JSON.stringify({
          ruleset_shortname: shortname,
          system_record: systemRecord,
          user_record1: userRecord1,
        }),
      });

      if (!resp.ok) {
        const txt = await resp.text();
        throw new Error(`PATCH failed (${resp.status}): ${txt}`);
      }

      const data: RulesetDto = await resp.json();
      setRuleset(data);
      setShortname(data.ruleset_shortname ?? '');
      setSystemRecord(data.system_record ?? '');
      setUserRecord1(data.user_record1 ?? '');
    } catch (e: any) {
      setError(e?.message ?? 'Save failed');
    } finally {
      setIsSaving(false);
    }
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  return (
    <Box>
      <BlueTitleBar title="Ruleset Editor" />

      <Container maxW="6xl" py={6}>
        {!id && (
          <Box p={4} borderWidth="1px" borderRadius="md">
            <Text fontWeight="bold">Missing id</Text>
            <Text>Use: /admin/ruleset-editor?id=&lt;uuid&gt;</Text>
          </Box>
        )}

        {id && (
          <Box>
            <Flex align="center" justify="space-between" mb={4}>
              <Heading size="md">Ruleset</Heading>

              <Flex gap={2}>
                <Button onClick={load} variant="outline" isDisabled={isLoading || isSaving}>
                  Reload
                </Button>
                <Button onClick={save} colorScheme="blue" isLoading={isSaving} isDisabled={!isDirty || isLoading}>
                  Save
                </Button>
              </Flex>
            </Flex>

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

                <Box mb={4}>
                  <Text fontWeight="bold" mb={1}>
                    system_record
                  </Text>
                  <Textarea value={systemRecord} onChange={(e) => setSystemRecord(e.target.value)} minH="240px" />
                </Box>

                <Box mb={4}>
                  <Text fontWeight="bold" mb={1}>
                    user_record1
                  </Text>
                  <Textarea value={userRecord1} onChange={(e) => setUserRecord1(e.target.value)} minH="240px" />
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